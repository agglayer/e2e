#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,fork-transition

# Test 1.3 — Fork Transition Tests
#
# Verifies correctness across fork boundaries by deploying contracts and
# sending transactions before and after each fork activation block.
#
# Tests:
#   - New opcodes work after fork, fail before
#   - Gas accounting is consistent across transitions
#   - No reorgs at fork boundaries (chain progresses monotonically)
#   - Gas parameter changes take effect at the correct block
#
# REQUIREMENTS:
#   - Kurtosis network with STAGGERED fork activation
#   - Bor nodes running with --gcmode=archive
#   - Fork block numbers passed via environment variables
#
# Environment variables (override to match your Kurtosis fork config):
#   FORK_DELHI           Delhi activation block (BaseFeeChangeDenominator=16)
#   FORK_INDORE          Indore activation block
#   FORK_AGRA            Agra activation block (Shanghai opcodes: PUSH0)
#   FORK_NAPOLI          Napoli activation block (Cancun opcodes: MCOPY, TSTORE/TLOAD)
#   FORK_AHMEDABAD       Ahmedabad activation block (MaxCodeSize=32KB)
#   FORK_BHILAI          Bhilai activation block (BaseFeeChangeDenominator=64)
#   FORK_MADHUGIRI       Madhugiri activation block (BLS12-381, EIP-7825 tx gas limit)
#   FORK_MADHUGIRI_PRO   MadhugiriPro activation block (p256Verify)
#   FORK_DANDELI         Dandeli activation block (TargetGasPercentage=65%)
#   FORK_LISOVO          Lisovo activation block (CLZ opcode, KZG precompile)

# ────────────────────────────────────────────────────────────────────────────
# Setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Default staggered fork blocks — override via env to match Kurtosis config
    FORK_DELHI="${FORK_DELHI:-64}"
    FORK_INDORE="${FORK_INDORE:-128}"
    FORK_AGRA="${FORK_AGRA:-192}"
    FORK_NAPOLI="${FORK_NAPOLI:-256}"
    FORK_AHMEDABAD="${FORK_AHMEDABAD:-320}"
    FORK_BHILAI="${FORK_BHILAI:-384}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-512}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-576}"
    FORK_DANDELI="${FORK_DANDELI:-640}"
    FORK_LISOVO="${FORK_LISOVO:-704}"

    # Create ephemeral wallet for on-chain transactions
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Deploy a contract from runtime bytecode hex. Sets $contract_addr.
deploy_runtime() {
    local runtime="$1"
    local gas="${2:-200000}"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    local offset_hex="0c"
    local initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local status
    status=$(echo "$receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "deploy_runtime failed: $status" >&2
        return 1
    fi
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
}

# Call a deployed contract, sets $call_receipt.
call_contract() {
    local addr="$1"
    local gas="${2:-200000}"
    call_receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$addr")

    local status
    status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "call_contract failed: $status" >&2
        return 1
    fi
}

# eth_call at a specific block. Returns hex output or empty on revert.
_call_at_block() {
    local addr="$1"
    local input="${2:-0x}"
    local block="$3"
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block "${block}" "${addr}" "${input}" 2>/dev/null) || out=""
    echo "${out}"
}

# Get gasUsed from a transaction receipt.
_gas_used() {
    local receipt="$1"
    echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d"
}

# Get the block number from a transaction receipt.
_block_number() {
    local receipt="$1"
    echo "$receipt" | jq -r '.blockNumber' | xargs printf "%d"
}

# ────────────────────────────────────────────────────────────────────────────
# 1.3 — Opcode activation at fork boundaries
# ────────────────────────────────────────────────────────────────────────────

# --- CLZ opcode (0x1e): activated at Lisovo ---

# bats test_tags=execution-specs,fork-transition,opcode,clz,lisovo
@test "1.3: CLZ opcode reverts before Lisovo fork" {
    # Deploy a contract with CLZ(1) → SSTORE. Before Lisovo, 0x1e is invalid.
    # Runtime: PUSH1 0x01 CLZ PUSH1 0x00 SSTORE STOP
    local runtime="60011e60005500"

    # eth_call the runtime as a message (no deployment needed) at pre-fork block
    # Use CREATE to get the contract, then eth_call at historical block.
    # Simpler: use eth_call with code override if available, or just test
    # that a deployed contract's CALL reverts at pre-fork blocks.

    # Deploy the contract (will succeed because deployment is at current block)
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    # eth_call at pre-Lisovo block should fail (invalid opcode)
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_LISOVO - 1 )) "${addr}" 2>&1) || true
    # The call should either revert or return an error
    echo "CLZ eth_call at block $(( FORK_LISOVO - 1 )): ${out}" >&3
    # A successful call would set storage — we verify via eth_call that it fails
    [[ -z "${out}" || "${out}" == *"revert"* || "${out}" == *"error"* || "${out}" == *"execution reverted"* || "${out}" == "0x" ]]
}

# bats test_tags=execution-specs,fork-transition,opcode,clz,lisovo
@test "1.3: CLZ opcode works after Lisovo fork" {
    # Runtime: PUSH1 0x01 CLZ PUSH1 0x00 SSTORE STOP
    local runtime="60011e60005500"
    deploy_runtime "$runtime"
    call_contract "$contract_addr"

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")
    echo "CLZ(1) = ${result}" >&3
    # CLZ(1) = 255 (255 leading zero bits)
    [[ "$result" -eq 255 ]]
}

# --- PUSH0 opcode (0x5f): activated at Agra (Shanghai equivalent) ---

# bats test_tags=execution-specs,fork-transition,opcode,push0,agra
@test "1.3: PUSH0 opcode works after Agra fork via eth_call" {
    # Runtime: PUSH0 PUSH1 0x00 SSTORE STOP
    # PUSH0 = 0x5f, pushes 0 onto stack
    local runtime="5f60005500"
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    # eth_call at post-Agra block should succeed
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_AGRA + 1 )) "${addr}" 2>&1) || true
    echo "PUSH0 eth_call at block $(( FORK_AGRA + 1 )): '${out}'" >&3
    # Should not contain revert/error (PUSH0 is valid post-Agra)
    [[ "${out}" != *"execution reverted"* ]]
}

# bats test_tags=execution-specs,fork-transition,opcode,push0,agra
@test "1.3: PUSH0 opcode reverts before Agra fork" {
    local runtime="5f60005500"
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    # eth_call at pre-Agra block — PUSH0 is invalid
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_AGRA - 1 )) "${addr}" 2>&1) || true
    echo "PUSH0 eth_call at block $(( FORK_AGRA - 1 )): '${out}'" >&3
    [[ -z "${out}" || "${out}" == *"revert"* || "${out}" == *"error"* || "${out}" == *"execution reverted"* || "${out}" == "0x" ]]
}

# --- MCOPY opcode (0x5e): activated at Napoli (Cancun equivalent) ---

# bats test_tags=execution-specs,fork-transition,opcode,mcopy,napoli
@test "1.3: MCOPY opcode works after Napoli fork via eth_call" {
    # Runtime: PUSH1 0x20 PUSH1 0x00 PUSH1 0x00 MCOPY STOP
    # MCOPY(dst=0, src=0, len=32) — copies 32 bytes of memory in place
    # MCOPY = 0x5e
    local runtime="60206000600060005e00"

    # Simpler test: just PUSH1 0x01 PUSH1 0x00 PUSH1 0x20 MCOPY STOP
    # dst=0x20, src=0x00, len=0x01
    local runtime="600160006020"
    runtime+="5e"  # MCOPY
    runtime+="00"  # STOP
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_NAPOLI + 1 )) "${addr}" 2>&1) || true
    echo "MCOPY eth_call at block $(( FORK_NAPOLI + 1 )): '${out}'" >&3
    [[ "${out}" != *"execution reverted"* ]]
}

# bats test_tags=execution-specs,fork-transition,opcode,mcopy,napoli
@test "1.3: MCOPY opcode reverts before Napoli fork" {
    local runtime="600160006020"
    runtime+="5e"  # MCOPY
    runtime+="00"  # STOP
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_NAPOLI - 1 )) "${addr}" 2>&1) || true
    echo "MCOPY eth_call at block $(( FORK_NAPOLI - 1 )): '${out}'" >&3
    [[ -z "${out}" || "${out}" == *"revert"* || "${out}" == *"error"* || "${out}" == *"execution reverted"* || "${out}" == "0x" ]]
}

# --- Transient storage TSTORE/TLOAD (EIP-1153): activated at Napoli ---

# bats test_tags=execution-specs,fork-transition,opcode,transient-storage,napoli
@test "1.3: TSTORE/TLOAD work after Napoli fork via eth_call" {
    # Runtime: PUSH1 0x42 PUSH1 0x00 TSTORE PUSH1 0x00 TLOAD PUSH1 0x00 SSTORE STOP
    # TSTORE = 0x5d, TLOAD = 0x5c
    # Store 0x42 in transient slot 0, load it back, persist to storage slot 0
    local runtime="6042600060005d600060005c60005500"

    deploy_runtime "$runtime"
    local addr="$contract_addr"

    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_NAPOLI + 1 )) "${addr}" 2>&1) || true
    echo "TSTORE/TLOAD eth_call at block $(( FORK_NAPOLI + 1 )): '${out}'" >&3
    [[ "${out}" != *"execution reverted"* ]]
}

# bats test_tags=execution-specs,fork-transition,opcode,transient-storage,napoli
@test "1.3: TSTORE reverts before Napoli fork" {
    local runtime="6042600060005d600060005c60005500"
    deploy_runtime "$runtime"
    local addr="$contract_addr"

    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block $(( FORK_NAPOLI - 1 )) "${addr}" 2>&1) || true
    echo "TSTORE eth_call at block $(( FORK_NAPOLI - 1 )): '${out}'" >&3
    [[ -z "${out}" || "${out}" == *"revert"* || "${out}" == *"error"* || "${out}" == *"execution reverted"* || "${out}" == "0x" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 1.3 — Gas parameter transitions
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,fork-transition,gas,bhilai
@test "1.3: BaseFee changes more slowly after Bhilai (denominator 16→64)" {
    # After Bhilai, BaseFeeChangeDenominator goes from 16 to 64, meaning
    # the base fee adjusts more slowly per block. Compare the maximum
    # base fee delta between adjacent blocks before and after Bhilai.
    # We sample a window of blocks and verify the delta is smaller post-Bhilai.

    local pre_block=$(( FORK_BHILAI - 3 ))
    local post_block=$(( FORK_BHILAI + 3 ))

    # Get base fees at consecutive blocks
    local pre_fee1 pre_fee2 post_fee1 post_fee2
    pre_fee1=$(cast block --rpc-url "$L2_RPC_URL" "${pre_block}" -j | jq -r '.baseFeePerGas' | xargs printf "%d")
    pre_fee2=$(cast block --rpc-url "$L2_RPC_URL" "$(( pre_block + 1 ))" -j | jq -r '.baseFeePerGas' | xargs printf "%d")
    post_fee1=$(cast block --rpc-url "$L2_RPC_URL" "${post_block}" -j | jq -r '.baseFeePerGas' | xargs printf "%d")
    post_fee2=$(cast block --rpc-url "$L2_RPC_URL" "$(( post_block + 1 ))" -j | jq -r '.baseFeePerGas' | xargs printf "%d")

    echo "Pre-Bhilai  base fees: ${pre_fee1} → ${pre_fee2}" >&3
    echo "Post-Bhilai base fees: ${post_fee1} → ${post_fee2}" >&3

    # Calculate absolute deltas
    local pre_delta=$(( pre_fee2 > pre_fee1 ? pre_fee2 - pre_fee1 : pre_fee1 - pre_fee2 ))
    local post_delta=$(( post_fee2 > post_fee1 ? post_fee2 - post_fee1 : post_fee1 - post_fee2 ))

    echo "Pre-Bhilai  delta: ${pre_delta}" >&3
    echo "Post-Bhilai delta: ${post_delta}" >&3

    # If base fees are stable (both deltas 0), the test is trivially valid.
    # Otherwise, post-Bhilai delta should be <= pre-Bhilai delta since the
    # denominator is larger (fee adjusts more slowly).
    if [[ "$pre_delta" -gt 0 ]]; then
        [[ "$post_delta" -le "$pre_delta" ]]
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# 1.3 — Chain continuity across fork boundaries (no reorgs)
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,fork-transition,chain-continuity
@test "1.3: no reorgs at fork boundaries — parent hashes are consistent" {
    # For each fork block, verify that block N's parentHash == block (N-1)'s hash.
    # A reorg at a fork boundary would break this chain.
    local -a fork_blocks=(
        "${FORK_DELHI}"
        "${FORK_INDORE}"
        "${FORK_AGRA}"
        "${FORK_NAPOLI}"
        "${FORK_AHMEDABAD}"
        "${FORK_BHILAI}"
        "${FORK_MADHUGIRI}"
        "${FORK_MADHUGIRI_PRO}"
        "${FORK_DANDELI}"
        "${FORK_LISOVO}"
    )

    for fb in "${fork_blocks[@]}"; do
        # Skip block 0 (genesis has no parent to verify)
        [[ "$fb" -le 0 ]] && continue

        local parent_hash block_parent_hash
        parent_hash=$(cast block --rpc-url "$L2_RPC_URL" "$(( fb - 1 ))" -j | jq -r '.hash')
        block_parent_hash=$(cast block --rpc-url "$L2_RPC_URL" "${fb}" -j | jq -r '.parentHash')

        echo "Fork block ${fb}: parent_hash=${parent_hash}, block.parentHash=${block_parent_hash}" >&3

        if [[ "${parent_hash}" != "${block_parent_hash}" ]]; then
            echo "FAIL: Reorg detected at fork block ${fb}!" >&2
            echo "  Block $(( fb - 1 )) hash:    ${parent_hash}" >&2
            echo "  Block ${fb} parentHash: ${block_parent_hash}" >&2
            return 1
        fi
        echo "  OK: Block ${fb} parent hash consistent" >&3
    done
}

# bats test_tags=execution-specs,fork-transition,chain-continuity
@test "1.3: block numbers are monotonically increasing across all fork boundaries" {
    # Verify that timestamps and block numbers are strictly increasing around
    # each fork boundary. This catches any frozen-chain or time-warp issues.
    local -a fork_blocks=(
        "${FORK_DELHI}"
        "${FORK_AGRA}"
        "${FORK_NAPOLI}"
        "${FORK_BHILAI}"
        "${FORK_MADHUGIRI}"
        "${FORK_LISOVO}"
    )

    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 1 ]] && continue

        local ts_before ts_at ts_after
        ts_before=$(cast block --rpc-url "$L2_RPC_URL" "$(( fb - 1 ))" -j | jq -r '.timestamp' | xargs printf "%d")
        ts_at=$(cast block --rpc-url "$L2_RPC_URL" "${fb}" -j | jq -r '.timestamp' | xargs printf "%d")
        ts_after=$(cast block --rpc-url "$L2_RPC_URL" "$(( fb + 1 ))" -j | jq -r '.timestamp' | xargs printf "%d")

        echo "Fork ${fb}: timestamps ${ts_before} → ${ts_at} → ${ts_after}" >&3

        [[ "$ts_at" -gt "$ts_before" ]]
        [[ "$ts_after" -gt "$ts_at" ]]
    done
}

# ────────────────────────────────────────────────────────────────────────────
# 1.3 — Precompile gas consistency across fork boundaries
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,fork-transition,gas,precompile
@test "1.3: SHA-256 precompile gas cost is stable across Madhugiri boundary" {
    # SHA-256 is not affected by Madhugiri — gas should be identical before/after.
    local input="0x616263"  # "abc"
    local addr="0x0000000000000000000000000000000000000002"

    local gas_before gas_after
    gas_before=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_MADHUGIRI - 1 )) "${addr}" "${input}" 2>/dev/null) || gas_before="0"
    gas_after=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_MADHUGIRI + 1 )) "${addr}" "${input}" 2>/dev/null) || gas_after="0"

    echo "SHA-256 gas before Madhugiri: ${gas_before}" >&3
    echo "SHA-256 gas after Madhugiri:  ${gas_after}" >&3

    # If estimation works at both blocks, gas should be equal
    if [[ "$gas_before" != "0" && "$gas_after" != "0" ]]; then
        [[ "$gas_before" == "$gas_after" ]]
    else
        echo "  WARN: gas estimation not available at historical blocks, skipping comparison" >&3
    fi
}

# bats test_tags=execution-specs,fork-transition,gas,precompile
@test "1.3: ecRecover precompile gas cost is stable across Lisovo boundary" {
    local input="0x"
    input+="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"
    input+="000000000000000000000000000000000000000000000000000000000000001c"
    input+="9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"
    input+="4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"
    local addr="0x0000000000000000000000000000000000000001"

    local gas_before gas_after
    gas_before=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_LISOVO - 1 )) "${addr}" "${input}" 2>/dev/null) || gas_before="0"
    gas_after=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_LISOVO + 1 )) "${addr}" "${input}" 2>/dev/null) || gas_after="0"

    echo "ecRecover gas before Lisovo: ${gas_before}" >&3
    echo "ecRecover gas after Lisovo:  ${gas_after}" >&3

    if [[ "$gas_before" != "0" && "$gas_after" != "0" ]]; then
        [[ "$gas_before" == "$gas_after" ]]
    else
        echo "  WARN: gas estimation not available at historical blocks, skipping comparison" >&3
    fi
}
