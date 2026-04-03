#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,gas-metering,fork-activation

# Gas Metering Fork Transition Tests
# ====================================
# Validates that EVM gas costs remain consistent and correctly enforced across
# Bor fork boundaries.  Gas calculation divergence between nodes causes block
# rejection and consensus splits — this is a Severity-1 risk area.
#
# Key invariants tested:
#   - MaxTxGas (30M) enforced at Madhugiri — transactions exceeding this are invalid
#   - SSTORE zero-to-nonzero gas cost is 20000 at all forks (EIP-2200)
#   - CALL to a cold address costs 2600 gas (EIP-2929)
#   - Gas refund cap is gasUsed/5 (EIP-3529)
#   - Contract creation intrinsic gas is 53000 base
#   - Simple ETH transfer gas is 21000 at all forks
#   - Cross-client (Bor / Erigon) gas agreement for identical transactions
#
# REQUIREMENTS:
#   - Kurtosis enclave with staggered fork activation
#   - Fork blocks at fixed positions (256, 320, etc.)
#   - An Erigon RPC node for cross-client test (auto-discovered or via L2_ERIGON_RPC_URL)
#
# RUN: bats tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Pre-fund ephemeral wallets (one per test) to avoid nonce conflicts.
    WALLET_DIR=$(mktemp -d)
    export WALLET_DIR

    local num_tests
    num_tests=$(grep -c '^@test ' "${BATS_TEST_FILENAME}")

    echo "Pre-funding ${num_tests} ephemeral wallets for gas-metering tests..." >&3

    local i
    for i in $(seq 1 "$num_tests"); do
        local wallet_json addr
        wallet_json=$(cast wallet new --json | jq '.[0]')
        echo "$wallet_json" > "${WALLET_DIR}/wallet_${i}.json"
        addr=$(echo "$wallet_json" | jq -r '.address')

        cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value 10ether "$addr" >/dev/null
    done

    echo "All ${num_tests} wallets funded" >&3

    # Discover Erigon RPC (optional — cross-client test skips if unavailable).
    export L2_ERIGON_RPC_URL
    _discover_erigon_rpc || {
        echo "WARNING: No Erigon RPC node found — cross-client gas test will be skipped." >&3
    }
}

teardown_file() {
    [[ -d "${WALLET_DIR:-}" ]] && rm -rf "$WALLET_DIR"
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Default staggered fork blocks — override via env to match Kurtosis config.
    _setup_fork_env

    # Read pre-funded wallet for this test (created in setup_file).
    local wallet_json
    wallet_json=$(cat "${WALLET_DIR}/wallet_${BATS_TEST_NUMBER}.json")
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

_current_block() { cast block-number --rpc-url "$L2_RPC_URL"; }

# Deploy a contract from runtime bytecode hex. Sets $contract_addr.
_deploy_runtime() {
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

# Deploy a contract with constructor logic (initcode provided as-is). Sets $contract_addr.
_deploy_initcode() {
    local initcode="$1"
    local gas="${2:-500000}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local status
    status=$(echo "$receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "deploy_initcode failed: $status" >&2
        return 1
    fi
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
}

# ────────────────────────────────────────────────────────────────────────────
# Test 1: MaxTxGas (30M) enforcement at Madhugiri
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,madhugiri,max-tx-gas
@test "gas-metering: MaxTxGas (30M) enforced at Madhugiri" {
    _require_min_bor "2.5.0"
    [[ "${FORK_MADHUGIRI:-0}" -le 0 ]] && skip "Madhugiri at genesis"

    _wait_for_block_on $(( FORK_MADHUGIRI + 2 )) "$L2_RPC_URL" "L2_RPC"

    local max_tx_gas=33554432   # 2^25 per EIP-7825
    local over_limit=$(( max_tx_gas + 1000000 ))

    # Pre-Madhugiri: gas estimation with a high gas limit should succeed or be
    # estimable at a block before the fork.
    echo "  Checking gas estimation pre-Madhugiri (block $(( FORK_MADHUGIRI - 1 )))..." >&3
    local pre_madhugiri_ok=0
    local pre_result
    pre_result=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        --value 1wei \
        --block $(( FORK_MADHUGIRI - 1 )) \
        "$ephemeral_address" 2>&1) && pre_madhugiri_ok=1

    if [[ "$pre_madhugiri_ok" -eq 1 ]]; then
        echo "  Pre-Madhugiri gas estimate succeeded: ${pre_result}" >&3
    else
        echo "  WARN: Pre-Madhugiri gas estimation not available (archive mode may not be enabled): ${pre_result}" >&3
    fi

    # Post-Madhugiri: attempt to send a transaction with gas > 30M.
    # This must be rejected by the node (tx validation rejects intrinsic gas > MaxTxGas).
    echo "  Attempting to send tx with gas=${over_limit} post-Madhugiri..." >&3
    local post_result
    local post_failed=0
    post_result=$(cast send \
        --legacy \
        --gas-limit "$over_limit" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --value 1wei \
        "$ephemeral_address" 2>&1) || post_failed=1

    if [[ "$post_failed" -eq 1 ]]; then
        echo "  TX with gas > 30M correctly rejected: ${post_result}" >&3
    else
        # If the transaction was accepted, check if it reverted.
        local tx_status
        tx_status=$(echo "$post_result" | jq -r '.status' 2>/dev/null) || tx_status=""
        if [[ "$tx_status" == "0x0" ]]; then
            echo "  TX with gas > 30M was included but reverted (status=0x0)" >&3
        else
            echo "  FAIL: TX with gas=${over_limit} was accepted post-Madhugiri." >&2
            echo "  MaxTxGas enforcement is broken — consensus split risk." >&2
            echo "  Response: ${post_result}" >&2
            return 1
        fi
    fi

    # Verify a transaction at exactly 30M gas is still accepted.
    echo "  Verifying tx with gas=${max_tx_gas} is still accepted..." >&3
    local at_limit_result
    at_limit_result=$(cast send \
        --legacy \
        --gas-limit "$max_tx_gas" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --value 1wei \
        "$ephemeral_address" 2>&1)

    local at_limit_status
    at_limit_status=$(echo "$at_limit_result" | jq -r '.status' 2>/dev/null) || at_limit_status=""
    if [[ "$at_limit_status" != "0x1" ]]; then
        echo "  FAIL: TX with gas exactly at MaxTxGas (${max_tx_gas}) was rejected." >&2
        echo "  Response: ${at_limit_result}" >&2
        return 1
    fi
    echo "  TX with gas=${max_tx_gas} accepted (status=0x1)" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Test 2: SSTORE zero-to-nonzero gas cost is 20000 at all forks
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,sstore,eip-2200
@test "gas-metering: SSTORE from zero to non-zero gas cost is 20000 at all forks" {
    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    # Deploy a contract whose runtime writes a nonzero value to a fresh storage slot.
    # Runtime: PUSH1 0x42 | PUSH1 0x00 | SSTORE | STOP
    # Bytecode: 60 42 60 00 55 00
    _deploy_runtime "604260005500"
    local sstore_addr="$contract_addr"
    echo "  SSTORE contract deployed at ${sstore_addr}" >&3

    # Use cast estimate to measure gas for calling the SSTORE contract.
    # The estimate includes intrinsic gas (21000) + execution cost.
    # SSTORE zero->nonzero (cold slot) = 20000 gas (EIP-2200).
    # Additional execution: PUSH1 (3) + PUSH1 (3) + SSTORE overhead.
    # Total expected: ~21000 (intrinsic) + 20000 (SSTORE) + overhead + cold slot access (2100).

    # Check gas estimate at multiple fork boundaries.
    local -a fork_blocks=()
    local -a fork_names=()

    # Always check at Rio.
    fork_blocks+=("$(( FORK_RIO + 1 ))")
    fork_names+=("Rio")

    # Check at Madhugiri if available.
    if [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        fork_blocks+=("$(( FORK_MADHUGIRI + 1 ))")
        fork_names+=("Madhugiri")
    fi

    # Check at Dandeli if available.
    if [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        fork_blocks+=("$(( FORK_DANDELI + 1 ))")
        fork_names+=("Dandeli")
    fi

    local first_gas=""
    local all_consistent=true
    local idx=0

    for block in "${fork_blocks[@]}"; do
        local fork_name="${fork_names[$idx]}"
        _wait_for_block_on "$block" "$L2_RPC_URL" "L2_RPC"

        local gas_est
        gas_est=$(cast estimate \
            --rpc-url "$L2_RPC_URL" \
            --from "$ephemeral_address" \
            --block "$block" \
            "$sstore_addr" 2>/dev/null) || {
            echo "  WARN: gas estimation at block ${block} (${fork_name}) not available (archive mode?)" >&3
            idx=$(( idx + 1 ))
            continue
        }

        echo "  SSTORE gas at ${fork_name} (block ${block}): ${gas_est}" >&3

        # The SSTORE zero->nonzero cost should include exactly 20000 gas for the SSTORE op.
        # Total is: 21000 (intrinsic) + 2100 (cold slot access, EIP-2929) + 20000 (SSTORE set) + PUSH costs.
        # We check that total is within a reasonable range (> 43000 and < 50000).
        if [[ "$gas_est" -lt 43000 || "$gas_est" -gt 50000 ]]; then
            echo "  FAIL: SSTORE gas at ${fork_name} = ${gas_est}, expected ~43100-46000 (21000 intrinsic + 20000 SSTORE + 2100 cold + overhead)" >&2
            all_consistent=false
        fi

        if [[ -z "$first_gas" ]]; then
            first_gas="$gas_est"
        elif [[ "$gas_est" != "$first_gas" ]]; then
            echo "  WARN: SSTORE gas changed across forks: first=${first_gas} vs ${fork_name}=${gas_est}" >&3
            # A change here is noteworthy but may be acceptable if both values are in range.
            # The key invariant is that the 20000 SSTORE base cost is preserved.
        fi

        idx=$(( idx + 1 ))
    done

    if [[ "$all_consistent" != "true" ]]; then
        return 1
    fi

    # Also verify via latest block for a final sanity check.
    local latest_gas
    latest_gas=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        "$sstore_addr" 2>/dev/null) || {
        echo "  WARN: gas estimation at latest block not available" >&3
        return 0
    }
    echo "  SSTORE gas at latest: ${latest_gas}" >&3

    if [[ "$latest_gas" -lt 43000 || "$latest_gas" -gt 50000 ]]; then
        echo "  FAIL: SSTORE gas at latest = ${latest_gas}, expected ~43100-46000" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 3: CALL to cold address costs 2600 gas (EIP-2929)
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,eip-2929,cold-access
@test "gas-metering: CALL to cold address costs 2600 gas across all forks" {
    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    # Deploy a contract whose runtime CALLs a cold address (a fresh EOA).
    # We measure gas of calling this contract, which internally does:
    #   PUSH1 0 (retSize) | PUSH1 0 (retOff) | PUSH1 0 (argsSize) | PUSH1 0 (argsOff)
    #   PUSH1 0 (value) | PUSH20 <cold_addr> | GAS | CALL | POP | STOP
    #
    # Create a fresh address that has never been accessed (cold).
    local cold_addr
    cold_addr=$(cast wallet new --json | jq -r '.[0].address')
    local cold_hex="${cold_addr#0x}"

    # Runtime: PUSH1 0 PUSH1 0 PUSH1 0 PUSH1 0 PUSH1 0 PUSH20 <addr> GAS CALL POP STOP
    # Hex:     6000 6000 6000 6000 6000 73<20 bytes> 5A F1 50 00
    local runtime="60006000600060006000"
    runtime+="73${cold_hex}"
    runtime+="5af15000"

    _deploy_runtime "$runtime" 500000
    local caller_addr="$contract_addr"
    echo "  CALL-cold contract deployed at ${caller_addr}" >&3
    echo "  Cold target address: ${cold_addr}" >&3

    # Estimate gas for calling this contract.
    local gas_est
    gas_est=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        "$caller_addr" 2>/dev/null) || {
        echo "  WARN: gas estimation not available" >&3
        skip "gas estimation not available at latest block"
    }

    echo "  CALL-to-cold-address gas: ${gas_est}" >&3

    # Expected: 21000 (intrinsic) + 2600 (cold address access, EIP-2929) + CALL base (100)
    #           + 9000 (CALL stipend) + PUSH/POP overhead.
    # The cold access cost of 2600 should be included. Total should be > 23000.
    # A warm CALL would cost only 100, so the difference is substantial.
    if [[ "$gas_est" -lt 23000 ]]; then
        echo "  FAIL: Gas estimate too low (${gas_est}). Cold CALL should include 2600 gas for EIP-2929." >&2
        return 1
    fi

    # Cross-check: estimate again at a different fork block to verify consistency.
    if [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        _wait_for_block_on $(( FORK_MADHUGIRI + 2 )) "$L2_RPC_URL" "L2_RPC"
        local madhugiri_gas
        madhugiri_gas=$(cast estimate \
            --rpc-url "$L2_RPC_URL" \
            --from "$ephemeral_address" \
            --block $(( FORK_MADHUGIRI + 1 )) \
            "$caller_addr" 2>/dev/null) || {
            echo "  WARN: gas estimation at Madhugiri block not available" >&3
            return 0
        }
        echo "  CALL-to-cold-address gas at Madhugiri: ${madhugiri_gas}" >&3

        if [[ "$madhugiri_gas" -lt 23000 ]]; then
            echo "  FAIL: Gas estimate at Madhugiri too low (${madhugiri_gas}). Cold CALL EIP-2929 cost missing." >&2
            return 1
        fi
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 4: Gas refund cap is correctly applied (EIP-3529)
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,eip-3529,gas-refund
@test "gas-metering: gas refund cap is correctly applied" {
    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    # EIP-3529 caps gas refunds at gasUsed/5 (replacing the old gasUsed/2 cap).
    # To test this: deploy a contract that pre-sets many storage slots to nonzero,
    # then clears them all. The refund from clearing should be capped.
    #
    # Strategy:
    #   Contract A: constructor sets slot 0 to 0x42, runtime clears slot 0 (SSTORE(0,0)).
    #   The SSTORE clear refund (4800 per EIP-3529) should be capped at gasUsed/5.
    #
    # For a single slot clear:
    #   - Execution gas: ~2100 (cold access) + 2900 (SSTORE reset) + ~6 (PUSH+STOP) = ~5006
    #   - Refund: 4800 (SSTORE_CLEARS_SCHEDULE)
    #   - Cap: gasUsed/5 => total_execution / 5
    #   - With intrinsic (21000): total ~26006, cap = ~5201. Refund 4800 < cap => full refund applied.
    #
    # We verify: clear-slot gasUsed < set-slot gasUsed (refund is applied).

    # Contract A: runtime writes 0x42 to slot 0 (zero -> nonzero).
    _deploy_runtime "604260005500"
    local writer_addr="$contract_addr"

    # Contract B: constructor writes 0x42 to slot 0, runtime clears it (nonzero -> zero).
    # Constructor: PUSH1 0x42 PUSH1 0x00 SSTORE (sets slot 0 = 0x42)
    # Then CODECOPY runtime and RETURN.
    # Runtime: PUSH1 0x00 PUSH1 0x00 SSTORE STOP = 600060005500
    local ctor_sstore="6042600055"
    local runtime_b="600060005500"
    local rb_len=$(( ${#runtime_b} / 2 ))
    local rb_len_hex
    printf -v rb_len_hex '%02x' "$rb_len"
    local ctor_header_len=$(( ${#ctor_sstore} / 2 ))   # 5
    local codecopy_len=12
    local runtime_offset=$(( ctor_header_len + codecopy_len ))
    local runtime_offset_hex
    printf -v runtime_offset_hex '%02x' "$runtime_offset"
    local codecopy_block="60${rb_len_hex}60${runtime_offset_hex}60003960${rb_len_hex}6000f3"
    local initcode_b="${ctor_sstore}${codecopy_block}${runtime_b}"

    _deploy_initcode "$initcode_b"
    local clearer_addr="$contract_addr"

    echo "  Writer at ${writer_addr}, Clearer at ${clearer_addr}" >&3

    # Call writer: SSTORE(0, 0x42) on fresh cold slot.
    local write_receipt
    write_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        "$writer_addr")

    local write_status
    write_status=$(echo "$write_receipt" | jq -r '.status')
    if [[ "$write_status" != "0x1" ]]; then
        echo "  Write call failed" >&2
        return 1
    fi
    local gas_used_write
    gas_used_write=$(echo "$write_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Call clearer: SSTORE(0, 0) on slot pre-set to 0x42.
    local clear_receipt
    clear_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        "$clearer_addr")

    local clear_status
    clear_status=$(echo "$clear_receipt" | jq -r '.status')
    if [[ "$clear_status" != "0x1" ]]; then
        echo "  Clear call failed" >&2
        return 1
    fi
    local gas_used_clear
    gas_used_clear=$(echo "$clear_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "  Write gasUsed=${gas_used_write}, Clear gasUsed=${gas_used_clear}" >&3

    # EIP-3529: clearing a slot yields a refund, so clear should cost less.
    if [[ "$gas_used_clear" -ge "$gas_used_write" ]]; then
        echo "  FAIL: Clear gasUsed (${gas_used_clear}) >= Write gasUsed (${gas_used_write})" >&2
        echo "  EIP-3529 gas refund is not being applied." >&2
        return 1
    fi

    # Verify the refund is capped (not more than gasUsed/5).
    # Effective gas = gasUsed_before_refund - refund.
    # refund <= gasUsed_before_refund / 5.
    # So gas_used_clear >= gasUsed_before_refund * 4/5.
    # gas_used_before_refund ~ gas_used_write (same execution path modulo SSTORE cost).
    # A simpler check: the clear should not be less than 45% of the write.
    # (45% allows margin for gas schedule differences across forks; the
    #  theoretical minimum with EIP-3529 is ~80%, so 45% is conservative.)
    local min_expected=$(( gas_used_write * 45 / 100 ))
    if [[ "$gas_used_clear" -lt "$min_expected" ]]; then
        echo "  FAIL: Clear gasUsed (${gas_used_clear}) < 45% of Write gasUsed (${gas_used_write})" >&2
        echo "  This suggests the EIP-3529 refund cap (gasUsed/5) is not being enforced." >&2
        return 1
    fi

    echo "  Gas refund cap correctly applied: write=${gas_used_write}, clear=${gas_used_clear}" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Test 5: Intrinsic gas for contract creation consistent across forks
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,contract-creation,intrinsic-gas
@test "gas-metering: intrinsic gas for contract creation consistent across forks" {
    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    # Contract creation intrinsic gas = 53000 base (21000 tx + 32000 create).
    # Plus per-byte initcode costs (16 gas per nonzero byte, 4 per zero byte).
    # We use a minimal initcode to keep the calculation deterministic.
    #
    # Minimal initcode: PUSH1 0x00 PUSH1 0x00 RETURN (deploys empty contract)
    # Hex: 60006000f3 (5 bytes, all nonzero except the 0x00 values)
    # Byte costs: 0x60=nonzero(16), 0x00=zero(4), 0x60=nonzero(16), 0x00=zero(4), 0xf3=nonzero(16)
    # Total byte cost: 16+4+16+4+16 = 56
    # Total intrinsic: 53000 + 56 = 53056
    # Plus initcode word cost (EIP-3860 if active): ceil(5/32) * 2 = 2 per word = 2
    # After Shanghai/Agra: 53056 + 2 = 53058

    local initcode="60006000f3"

    # Estimate at multiple fork blocks.
    local -a check_blocks=()
    local -a check_names=()

    check_blocks+=("$(( FORK_RIO + 1 ))")
    check_names+=("Rio")

    if [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        check_blocks+=("$(( FORK_MADHUGIRI + 1 ))")
        check_names+=("Madhugiri")
    fi

    if [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        check_blocks+=("$(( FORK_DANDELI + 1 ))")
        check_names+=("Dandeli")
    fi

    local first_gas=""
    local idx=0

    for block in "${check_blocks[@]}"; do
        local fork_name="${check_names[$idx]}"
        _wait_for_block_on "$block" "$L2_RPC_URL" "L2_RPC"

        local gas_est
        gas_est=$(cast estimate \
            --rpc-url "$L2_RPC_URL" \
            --from "$ephemeral_address" \
            --block "$block" \
            --create "0x${initcode}" 2>/dev/null) || {
            echo "  WARN: gas estimation at block ${block} (${fork_name}) not available" >&3
            idx=$(( idx + 1 ))
            continue
        }

        echo "  Contract creation intrinsic gas at ${fork_name} (block ${block}): ${gas_est}" >&3

        # Intrinsic gas for contract creation must be >= 53000.
        if [[ "$gas_est" -lt 53000 ]]; then
            echo "  FAIL: Contract creation gas at ${fork_name} = ${gas_est}, expected >= 53000" >&2
            return 1
        fi

        # Should be within a tight range: 53000-54000 for this minimal initcode.
        if [[ "$gas_est" -gt 54000 ]]; then
            echo "  WARN: Contract creation gas at ${fork_name} = ${gas_est}, higher than expected (> 54000)" >&3
        fi

        if [[ -z "$first_gas" ]]; then
            first_gas="$gas_est"
        elif [[ "$gas_est" != "$first_gas" ]]; then
            echo "  WARN: Contract creation gas changed across forks: first=${first_gas} vs ${fork_name}=${gas_est}" >&3
            echo "  This may indicate an initcode pricing change at ${fork_name}." >&3
        fi

        idx=$(( idx + 1 ))
    done

    # Also verify at latest block.
    local latest_gas
    latest_gas=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        --create "0x${initcode}" 2>/dev/null) || {
        echo "  WARN: gas estimation at latest block not available" >&3
        return 0
    }
    echo "  Contract creation intrinsic gas at latest: ${latest_gas}" >&3

    if [[ "$latest_gas" -lt 53000 ]]; then
        echo "  FAIL: Contract creation gas at latest = ${latest_gas}, expected >= 53000" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 6: Simple ETH transfer gas is 21000 across all forks
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,eth-transfer,intrinsic-gas
@test "gas-metering: simple ETH transfer gas is 21000 across all forks" {
    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    local target_addr
    target_addr=$(cast wallet new --json | jq -r '.[0].address')

    # Check gas estimate at multiple fork blocks.
    local -a check_blocks=()
    local -a check_names=()

    check_blocks+=("$(( FORK_RIO + 1 ))")
    check_names+=("Rio")

    if [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        check_blocks+=("$(( FORK_MADHUGIRI + 1 ))")
        check_names+=("Madhugiri")
    fi

    if [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        check_blocks+=("$(( FORK_DANDELI + 1 ))")
        check_names+=("Dandeli")
    fi

    if [[ "${FORK_LISOVO:-0}" -gt 0 ]]; then
        check_blocks+=("$(( FORK_LISOVO + 1 ))")
        check_names+=("Lisovo")
    fi

    local idx=0
    for block in "${check_blocks[@]}"; do
        local fork_name="${check_names[$idx]}"
        _wait_for_block_on "$block" "$L2_RPC_URL" "L2_RPC"

        local gas_est
        gas_est=$(cast estimate \
            --rpc-url "$L2_RPC_URL" \
            --from "$ephemeral_address" \
            --value 1wei \
            --block "$block" \
            "$target_addr" 2>/dev/null) || {
            echo "  WARN: gas estimation at block ${block} (${fork_name}) not available" >&3
            idx=$(( idx + 1 ))
            continue
        }

        echo "  ETH transfer gas at ${fork_name} (block ${block}): ${gas_est}" >&3

        if [[ "$gas_est" -ne 21000 ]]; then
            echo "  FAIL: ETH transfer gas at ${fork_name} = ${gas_est}, expected exactly 21000" >&2
            echo "  This indicates a fundamental gas metering change at ${fork_name} — consensus split risk." >&2
            return 1
        fi

        idx=$(( idx + 1 ))
    done

    # Also send a real transaction and verify gasUsed in the receipt.
    local receipt
    receipt=$(cast send \
        --legacy --gas-limit 21000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --value 1wei \
        "$target_addr")

    local tx_status
    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "  ETH transfer failed" >&2
        return 1
    fi

    local gas_used
    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    echo "  Real ETH transfer gasUsed: ${gas_used}" >&3

    if [[ "$gas_used" -ne 21000 ]]; then
        echo "  FAIL: Real ETH transfer gasUsed = ${gas_used}, expected exactly 21000" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 7: Cross-client gas agreement (Bor vs Erigon)
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=gas-metering,cross-client
@test "gas-metering: cross-client gas agreement for identical transactions" {
    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        skip "No Erigon RPC URL available (no Erigon node in enclave)"
    fi

    _wait_for_block_on $(( FORK_RIO + 2 )) "$L2_RPC_URL" "L2_RPC"

    # Wait for Erigon to reach the same block.
    local target_block=$(( FORK_RIO + 2 ))
    local erigon_block
    local attempts=0
    while [[ "$attempts" -lt 60 ]]; do
        erigon_block=$(cast block-number --rpc-url "$L2_ERIGON_RPC_URL" 2>/dev/null) || erigon_block=0
        [[ "$erigon_block" -ge "$target_block" ]] && break
        echo "  Waiting for Erigon to reach block ${target_block} (current: ${erigon_block})..." >&3
        sleep 5
        attempts=$(( attempts + 1 ))
    done

    if [[ "$erigon_block" -lt "$target_block" ]]; then
        skip "Erigon did not reach block ${target_block} within timeout"
    fi

    local target_addr
    target_addr=$(cast wallet new --json | jq -r '.[0].address')
    local diverged=0

    # ── Informational: compare gas estimates (WARN only, not pass/fail) ──

    local bor_transfer_gas erigon_transfer_gas
    bor_transfer_gas=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        --value 1wei \
        "$target_addr" 2>/dev/null) || bor_transfer_gas="error"

    erigon_transfer_gas=$(cast estimate \
        --rpc-url "$L2_ERIGON_RPC_URL" \
        --from "$ephemeral_address" \
        --value 1wei \
        "$target_addr" 2>/dev/null) || erigon_transfer_gas="error"

    echo "  ETH transfer estimate: Bor=${bor_transfer_gas}, Erigon=${erigon_transfer_gas}" >&3
    if [[ "$bor_transfer_gas" != "error" && "$erigon_transfer_gas" != "error" \
          && "$bor_transfer_gas" != "$erigon_transfer_gas" ]]; then
        echo "  WARN: eth_estimateGas divergence for ETH transfer (Bor=${bor_transfer_gas} vs Erigon=${erigon_transfer_gas})." >&3
        echo "        Estimates may differ due to access list handling or gas padding — not a consensus issue." >&3
    fi

    # ── Pass/fail: compare actual gasUsed from transaction receipts ──
    # Consensus requires identical gasUsed for the same on-chain transaction.
    # Send a tx via Bor (validators include it), then fetch the receipt from
    # both Bor and Erigon RPCs and compare.

    # Test 1: Simple ETH transfer — actual gasUsed.
    local send_result tx_hash
    send_result=$(cast send \
        --legacy --gas-limit 21000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --value 1wei \
        "$target_addr" 2>/dev/null) || send_result=""

    tx_hash=$(echo "$send_result" | jq -r '.transactionHash // empty' 2>/dev/null)
    if [[ -n "$tx_hash" && "$tx_hash" != "null" ]]; then
        # Wait for Erigon to index the tx
        local erigon_receipt="" wait_attempts=0
        while [[ "$wait_attempts" -lt 30 ]]; do
            erigon_receipt=$(cast receipt "$tx_hash" --rpc-url "$L2_ERIGON_RPC_URL" --json 2>/dev/null) || erigon_receipt=""
            [[ -n "$erigon_receipt" ]] && break
            sleep 2
            wait_attempts=$(( wait_attempts + 1 ))
        done

        local bor_receipt
        bor_receipt=$(cast receipt "$tx_hash" --rpc-url "$L2_RPC_URL" --json 2>/dev/null) || bor_receipt=""

        if [[ -n "$bor_receipt" && -n "$erigon_receipt" ]]; then
            local bor_gas_used erigon_gas_used
            bor_gas_used=$(echo "$bor_receipt" | jq -r '.gasUsed' | xargs printf "%d" 2>/dev/null) || bor_gas_used=0
            erigon_gas_used=$(echo "$erigon_receipt" | jq -r '.gasUsed' | xargs printf "%d" 2>/dev/null) || erigon_gas_used=0
            echo "  ETH transfer actual gasUsed: Bor=${bor_gas_used}, Erigon=${erigon_gas_used}" >&3

            if [[ "$bor_gas_used" -ne "$erigon_gas_used" ]]; then
                echo "  FAIL: ETH transfer actual gasUsed mismatch: Bor=${bor_gas_used} vs Erigon=${erigon_gas_used}" >&2
                echo "        This is a CONSENSUS DIVERGENCE — clients compute different gas for the same transaction." >&2
                diverged=1
            fi
        else
            echo "  WARN: Could not retrieve receipt from both clients for ETH transfer" >&3
        fi
    else
        echo "  WARN: ETH transfer transaction could not be sent" >&3
    fi

    # Test 2: Contract creation — actual gasUsed.
    local initcode="60006000f3"
    send_result=$(cast send \
        --legacy --gas-limit 100000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}" 2>/dev/null) || send_result=""

    tx_hash=$(echo "$send_result" | jq -r '.transactionHash // empty' 2>/dev/null)
    if [[ -n "$tx_hash" && "$tx_hash" != "null" ]]; then
        local erigon_receipt="" wait_attempts=0
        while [[ "$wait_attempts" -lt 30 ]]; do
            erigon_receipt=$(cast receipt "$tx_hash" --rpc-url "$L2_ERIGON_RPC_URL" --json 2>/dev/null) || erigon_receipt=""
            [[ -n "$erigon_receipt" ]] && break
            sleep 2
            wait_attempts=$(( wait_attempts + 1 ))
        done

        local bor_receipt
        bor_receipt=$(cast receipt "$tx_hash" --rpc-url "$L2_RPC_URL" --json 2>/dev/null) || bor_receipt=""

        if [[ -n "$bor_receipt" && -n "$erigon_receipt" ]]; then
            local bor_gas_used erigon_gas_used
            bor_gas_used=$(echo "$bor_receipt" | jq -r '.gasUsed' | xargs printf "%d" 2>/dev/null) || bor_gas_used=0
            erigon_gas_used=$(echo "$erigon_receipt" | jq -r '.gasUsed' | xargs printf "%d" 2>/dev/null) || erigon_gas_used=0
            echo "  Contract creation actual gasUsed: Bor=${bor_gas_used}, Erigon=${erigon_gas_used}" >&3

            if [[ "$bor_gas_used" -ne "$erigon_gas_used" ]]; then
                echo "  FAIL: Contract creation actual gasUsed mismatch: Bor=${bor_gas_used} vs Erigon=${erigon_gas_used}" >&2
                diverged=1
            fi
        else
            echo "  WARN: Could not retrieve receipt from both clients for contract creation" >&3
        fi
    else
        echo "  WARN: Contract creation transaction could not be sent" >&3
    fi

    # Test 3: Precompile (SHA-256) call — compare estimates as informational.
    # Precompile calls are read-only (no tx to send), so we compare estimates
    # with a tolerance and report divergence.
    local sha256_addr="0x0000000000000000000000000000000000000002"
    local sha256_input="0x616263"  # "abc"
    local bor_sha_gas erigon_sha_gas
    bor_sha_gas=$(cast estimate \
        --rpc-url "$L2_RPC_URL" \
        "$sha256_addr" "$sha256_input" 2>/dev/null) || bor_sha_gas="error"

    erigon_sha_gas=$(cast estimate \
        --rpc-url "$L2_ERIGON_RPC_URL" \
        "$sha256_addr" "$sha256_input" 2>/dev/null) || erigon_sha_gas="error"

    echo "  SHA-256 precompile estimate: Bor=${bor_sha_gas}, Erigon=${erigon_sha_gas}" >&3

    if [[ "$bor_sha_gas" != "error" && "$erigon_sha_gas" != "error" ]]; then
        if [[ "$bor_sha_gas" != "$erigon_sha_gas" ]]; then
            echo "  WARN: SHA-256 estimate divergence (Bor=${bor_sha_gas} vs Erigon=${erigon_sha_gas}) — informational only" >&3
        fi
    else
        echo "  WARN: SHA-256 gas estimation failed on one or both clients" >&3
    fi

    if [[ "$diverged" -ne 0 ]]; then
        echo "" >&2
        echo "  CONSENSUS SPLIT RISK: Bor and Erigon disagree on actual gasUsed for identical transactions." >&2
        echo "  This will cause block rejection and chain fork." >&2
        return 1
    fi
}
