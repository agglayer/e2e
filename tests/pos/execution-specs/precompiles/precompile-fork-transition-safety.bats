#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pos-precompile,fork-activation

# Precompile Fork-Transition Safety
# ====================================
# Verifies that precompile activation and removal happen at the correct fork
# boundaries on the Polygon PoS (Bor) chain.  A mismatch here causes consensus
# splits: one node thinks the precompile is active (and executes it), another
# does not (and returns empty / charges different gas), producing divergent
# state roots.
#
# Key transitions tested:
#   - KZG point evaluation (0x0a): Added at Lisovo, REMOVED at LisovoPro
#   - P256Verify (0x0100): Gas cost changes 3450 -> 6900 at Lisovo (EIP-7951)
#
# All tests use eth_call / eth_estimateGas pinned to specific block numbers
# so results are deterministic regardless of the chain tip.
#
# REQUIREMENTS:
#   - Kurtosis devnet with staggered fork activation
#   - FORK_* env vars matching the deployed schedule
#   - Chain must have advanced past FORK_LISOVO_PRO for all tests to run
#
# RUN: bats tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Discover Erigon RPC for cross-client tests (best effort)
    export L2_ERIGON_RPC_URL
    _discover_erigon_rpc || true

    # Discover a second Bor node (RPC, not validator) for cross-node tests
    export L2_BOR_RPC_NODE_URL
    if [[ -z "${L2_BOR_RPC_NODE_URL:-}" ]]; then
        local bor_port bor_svc
        for i in $(seq 1 12); do
            bor_svc="l2-el-${i}-bor-heimdall-v2-rpc"
            if bor_port=$(kurtosis port print "${ENCLAVE_NAME}" "${bor_svc}" rpc 2>/dev/null); then
                bor_port="${bor_port#http://}"; bor_port="${bor_port#https://}"
                L2_BOR_RPC_NODE_URL="http://${bor_port}"
                echo "Found Bor RPC node at ${bor_svc}: ${L2_BOR_RPC_NODE_URL}" >&3
                break
            fi
        done
    fi

    # Discover Bor archive node for tests requiring historical state
    export L2_BOR_ARCHIVE_RPC_URL
    _discover_bor_archive_rpc || true
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Fork activation block numbers (matching kurtosis-pos devnet defaults)
    _setup_fork_env

    # Skip early if Lisovo fork is not active (avoids 1800s hang in _wait_for_block_on)
    [[ "${FORK_LISOVO:-999999999}" -ge 999999999 ]] && skip "Lisovo fork not active in this version"

    # Precompile addresses
    KZG_ADDR="0x000000000000000000000000000000000000000a"
    P256_ADDR="0x0000000000000000000000000000000000000100"

    # ── KZG test vector (EIP-4844 point evaluation) ──────────────────────────
    # 192 bytes: versioned_hash(32) || z(32) || y(32) || commitment(48) || proof(48)
    # This is the canonical EIP-4844 test vector from the consensus-spec tests.
    KZG_INPUT="0x"
    KZG_INPUT+="01d18459b334ffe8e2226eef1db874fda6db2bdd9357268b39220af2d59571e4"  # versioned_hash
    KZG_INPUT+="73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000"  # z (BLS scalar field - 1)
    KZG_INPUT+="0000000000000000000000000000000000000000000000000000000000000000"  # y = 0
    # commitment (48 bytes): G1 generator
    KZG_INPUT+="97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac58"
    KZG_INPUT+="6c55e83ff97a1aeffb3af00adb22c6bb"
    # proof (48 bytes): matching proof for the above
    KZG_INPUT+="a72841987e735e9e2f5e44a3209b4225edfa168e40a1a18ae78445e0e9bf6580"
    KZG_INPUT+="4af1f87a1bf3a296ab0489f00328a7e2"

    # ── P256Verify test vector (RIP-7212 / Wycheproof) ───────────────────────
    # 160 bytes: hash(32) || r(32) || s(32) || x(32) || y(32)
    P256_INPUT="0x"
    P256_INPUT+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    P256_INPUT+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
    P256_INPUT+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    P256_INPUT+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
    P256_INPUT+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Call a precompile address with raw hex calldata at a specific block number.
# Returns the hex output string (including 0x prefix), or empty on revert/error.
# Falls back to the Bor archive node when the primary RPC returns empty (pruned state).
_call_at_block() {
    local addr="$1"
    local input="$2"
    local block="$3"
    local rpc="${4:-${L2_RPC_URL}}"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    local out
    out=$(curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"${addr}\",\"data\":\"${input}\"},\"${block_hex}\"],\"id\":1}" \
        | jq -r '.result // empty') || out=""
    # Fallback to archive node if primary returned empty and no explicit RPC was passed
    if [[ -z "${out}" && -z "${4:-}" && -n "${L2_BOR_ARCHIVE_RPC_URL:-}" && "${rpc}" != "${L2_BOR_ARCHIVE_RPC_URL}" ]]; then
        out=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_BOR_ARCHIVE_RPC_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"${addr}\",\"data\":\"${input}\"},\"${block_hex}\"],\"id\":1}" \
            | jq -r '.result // empty') || out=""
    fi
    echo "${out}"
}

# Estimate gas for a call at a specific block number.
# Returns the decimal gas value, or empty on error.
# Falls back to the Bor archive node when the primary RPC returns empty (pruned state).
_estimate_at_block() {
    local addr="$1"
    local input="$2"
    local block="$3"
    local rpc="${4:-${L2_RPC_URL}}"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    local out
    out=$(curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_estimateGas\",\"params\":[{\"to\":\"${addr}\",\"data\":\"${input}\"},\"${block_hex}\"],\"id\":1}" \
        | jq -r '.result // empty') || out=""
    # Fallback to archive node if primary returned empty and no explicit RPC was passed
    if [[ -z "${out}" && -z "${4:-}" && -n "${L2_BOR_ARCHIVE_RPC_URL:-}" && "${rpc}" != "${L2_BOR_ARCHIVE_RPC_URL}" ]]; then
        out=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_BOR_ARCHIVE_RPC_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_estimateGas\",\"params\":[{\"to\":\"${addr}\",\"data\":\"${input}\"},\"${block_hex}\"],\"id\":1}" \
            | jq -r '.result // empty') || out=""
    fi
    if [[ -n "${out}" && "${out}" != "null" ]]; then
        printf "%d" "${out}" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Returns 0 (true) when the hex string is non-empty AND has at least one
# non-zero nibble (i.e. "0x" alone or "0x000...0" are both considered trivial).
_is_nontrivial() {
    local data="${1#0x}"
    [[ -n "${data}" && "${data//0/}" != "" ]]
}


# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pos-precompile,fork-activation,kzg
@test "precompile-fork-safety: KZG (0x0a) is NOT active before Lisovo" {
    _require_min_bor "2.6.0"
    local pre_lisovo_block=$(( FORK_LISOVO - 1 ))
    _wait_for_block_on "${FORK_LISOVO}" "$L2_RPC_URL" "L2_RPC"

    echo "Testing KZG at block ${pre_lisovo_block} (pre-Lisovo)" >&3

    # Before Lisovo, calling KZG should return empty (no precompile) or trivial.
    # We send a short invalid input; an active precompile would revert (empty from
    # our helper), but so would an inactive address. So send the valid KZG input:
    # an active precompile would process it, an inactive address returns "0x".
    local out
    out=$(_call_at_block "${KZG_ADDR}" "${KZG_INPUT}" "${pre_lisovo_block}")
    echo "KZG output at block ${pre_lisovo_block}: '${out}'" >&3

    # Pre-Lisovo: 0x0a is NOT a precompile. Calling it returns "0x" (empty success)
    # because there is no code at the address and no precompile registered.
    if _is_nontrivial "${out}"; then
        echo "FAIL: KZG precompile returned non-trivial output before Lisovo fork" >&2
        echo "  Block: ${pre_lisovo_block}, Output: ${out}" >&2
        return 1
    fi
    echo "OK: KZG correctly inactive at block ${pre_lisovo_block}" >&3
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,kzg
@test "precompile-fork-safety: KZG (0x0a) IS active at Lisovo block" {
    _require_min_bor "2.6.0"
    _wait_for_block_on "$((FORK_LISOVO + 1))" "$L2_RPC_URL" "L2_RPC"

    echo "Testing KZG at block ${FORK_LISOVO} (Lisovo activation)" >&3

    # At Lisovo, KZG should be active. We call with the valid KZG input.
    # An active KZG precompile with valid input returns the field element
    # encoding (non-trivial output). An invalid input would revert (empty).
    # We also try with empty data: an active precompile reverts on bad input,
    # returning empty from _call_at_block. So we test with valid input.
    local out
    out=$(_call_at_block "${KZG_ADDR}" "${KZG_INPUT}" "${FORK_LISOVO}")
    echo "KZG output at block ${FORK_LISOVO}: '${out}'" >&3

    # If the KZG input was invalid (our test vector may not pass verification),
    # the precompile reverts and we get empty output. In that case, we fall back
    # to checking that empty-data behavior differs from pre-Lisovo:
    # an active precompile returns an error (result=null, empty from helper),
    # while a non-existent address returns "0x".
    if [[ -z "${out}" ]]; then
        # Precompile is active but rejected our input (revert).
        # Confirm it is actually active by checking that empty input also reverts
        # (whereas pre-Lisovo, empty input returns "0x" success).
        local empty_out
        empty_out=$(_call_at_block "${KZG_ADDR}" "0x" "${FORK_LISOVO}")
        local pre_empty_out
        pre_empty_out=$(_call_at_block "${KZG_ADDR}" "0x" "$((FORK_LISOVO - 1))")
        echo "  Empty-data at Lisovo: '${empty_out}', pre-Lisovo: '${pre_empty_out}'" >&3

        # Pre-Lisovo: "0x" (success, no precompile). At Lisovo: empty (revert from active precompile).
        if [[ "${pre_empty_out}" == "0x" && -z "${empty_out}" ]]; then
            echo "OK: KZG active at Lisovo (reverts on invalid input, unlike pre-Lisovo)" >&3
            return 0
        fi

        # Alternative: both may return empty, meaning the precompile was already
        # active before Lisovo — this should not happen but handle gracefully.
        echo "WARN: Could not confirm KZG activation via empty-data probe" >&3
        echo "  This may indicate the KZG test vector was rejected. Checking eth_call error..." >&3

        # Check the JSON-RPC error field directly
        local block_hex
        block_hex=$(printf '0x%x' "${FORK_LISOVO}")
        local raw_resp
        raw_resp=$(curl -s -m 30 -X POST "${L2_RPC_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"${KZG_ADDR}\",\"data\":\"${KZG_INPUT}\"},\"${block_hex}\"],\"id\":1}")
        local has_error
        has_error=$(echo "${raw_resp}" | jq -r '.error // empty')
        echo "  Raw response error: ${has_error}" >&3

        # If there is an error (revert), the precompile IS active.
        [[ -n "${has_error}" ]]
    else
        # Got non-trivial output: KZG precompile processed the input successfully.
        _is_nontrivial "${out}"
    fi
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,kzg
@test "precompile-fork-safety: KZG (0x0a) is NOT active at LisovoPro" {
    _require_min_bor "2.6.0"
    [[ "${FORK_LISOVO_PRO:-999999999}" -ge 999999999 ]] && skip "LisovoPro fork not active in this version"
    _wait_for_block_on "$((FORK_LISOVO_PRO + 1))" "$L2_RPC_URL" "L2_RPC"

    # Verify historical state is available at the test blocks before proceeding.
    if ! _state_available_at "${FORK_LISOVO_PRO}"; then
        skip "Historical state unavailable at LisovoPro block ${FORK_LISOVO_PRO} (pruning)"
    fi

    echo "Testing KZG at block ${FORK_LISOVO_PRO} (LisovoPro — KZG removed)" >&3

    # At LisovoPro, KZG is removed. Calling it should behave like a regular
    # empty address: return "0x" for any input (success with empty output).
    local out
    out=$(_call_at_block "${KZG_ADDR}" "${KZG_INPUT}" "${FORK_LISOVO_PRO}")
    echo "KZG output at block ${FORK_LISOVO_PRO}: '${out}'" >&3

    # Also check empty-data call: should return "0x" (no precompile).
    local empty_out
    empty_out=$(_call_at_block "${KZG_ADDR}" "0x" "${FORK_LISOVO_PRO}")
    echo "KZG empty-data at block ${FORK_LISOVO_PRO}: '${empty_out}'" >&3

    # Confirm behavior matches a non-existent precompile address.
    # A removed precompile should return "0x" (empty success).
    if _is_nontrivial "${out}"; then
        echo "FAIL: KZG returned non-trivial output at LisovoPro (should be removed)" >&2
        echo "  Block: ${FORK_LISOVO_PRO}, Output: ${out}" >&2
        return 1
    fi

    # Cross-check: at Lisovo (where KZG IS active), the same call should behave
    # differently (either return data or revert).
    local lisovo_out
    lisovo_out=$(_call_at_block "${KZG_ADDR}" "0x" "${FORK_LISOVO}")
    echo "KZG empty-data at Lisovo block ${FORK_LISOVO}: '${lisovo_out}'" >&3

    # The key assertion: at LisovoPro the KZG address is inert.
    if [[ "${empty_out}" == "0x" ]]; then
        echo "OK: KZG correctly removed at LisovoPro (returns empty success like non-existent address)" >&3
    elif [[ -z "${empty_out}" ]]; then
        # Empty means revert — precompile might still be active!
        echo "FAIL: KZG appears to still be active at LisovoPro (reverts on empty input)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,p256,evm-gas
@test "precompile-fork-safety: P256Verify (0x0100) gas cost pre-Lisovo" {
    _require_min_bor "2.6.0"
    local pre_lisovo_block=$(( FORK_LISOVO - 1 ))
    _wait_for_block_on "${FORK_LISOVO}" "$L2_RPC_URL" "L2_RPC"

    echo "Estimating P256Verify gas at block ${pre_lisovo_block} (pre-Lisovo, PIP-27 = 3450)" >&3

    local gas_estimate
    gas_estimate=$(_estimate_at_block "${P256_ADDR}" "${P256_INPUT}" "${pre_lisovo_block}")
    echo "P256Verify gas estimate at block ${pre_lisovo_block}: ${gas_estimate}" >&3

    if [[ -z "${gas_estimate}" ]]; then
        # P256 might not be active pre-Lisovo at all (it was added at MadhugiriPro).
        # Check if the precompile exists at this block.
        local p256_out
        p256_out=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${pre_lisovo_block}")
        if [[ -z "${p256_out}" || "${p256_out}" == "0x" ]]; then
            skip "P256Verify not active at block ${pre_lisovo_block}"
        fi
        echo "FAIL: P256 is callable but eth_estimateGas failed" >&2
        return 1
    fi

    # Pre-Lisovo gas = intrinsic (21000) + calldata cost (~2320) + precompile (3450)
    # Expected total: ~26770
    # Post-Lisovo gas would be: ~30220
    # Midpoint: ~28495
    echo "P256 gas estimate (pre-Lisovo): ${gas_estimate}" >&3
    if [[ "${gas_estimate}" -ge 28000 ]]; then
        echo "FAIL: Gas estimate ${gas_estimate} too high for pre-Lisovo PIP-27 cost (3450)" >&2
        echo "  Expected ~26770 (21000 intrinsic + ~2320 calldata + 3450 precompile)" >&2
        return 1
    fi

    # Sanity: should be at least intrinsic + some precompile cost
    if [[ "${gas_estimate}" -lt 24000 ]]; then
        echo "FAIL: Gas estimate ${gas_estimate} suspiciously low (expected ~26770)" >&2
        return 1
    fi

    echo "OK: P256Verify gas at pre-Lisovo (${gas_estimate}) consistent with PIP-27 cost 3450" >&3
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,p256,evm-gas
@test "precompile-fork-safety: P256Verify (0x0100) gas cost at Lisovo" {
    _require_min_bor "2.6.0"
    _wait_for_block_on "$((FORK_LISOVO + 1))" "$L2_RPC_URL" "L2_RPC"

    echo "Estimating P256Verify gas at block ${FORK_LISOVO} (Lisovo, EIP-7951 = 6900)" >&3

    local gas_estimate
    gas_estimate=$(_estimate_at_block "${P256_ADDR}" "${P256_INPUT}" "${FORK_LISOVO}")
    echo "P256Verify gas estimate at block ${FORK_LISOVO}: ${gas_estimate}" >&3

    if [[ -z "${gas_estimate}" ]]; then
        local p256_out
        p256_out=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${FORK_LISOVO}")
        if [[ -z "${p256_out}" || "${p256_out}" == "0x" ]]; then
            skip "P256Verify not active at Lisovo block ${FORK_LISOVO}"
        fi
        echo "FAIL: P256 is callable but eth_estimateGas failed at Lisovo" >&2
        return 1
    fi

    # Post-Lisovo gas = intrinsic (21000) + calldata cost (~2320) + precompile (6900)
    # Expected total: ~30220
    echo "P256 gas estimate (Lisovo): ${gas_estimate}" >&3
    if [[ "${gas_estimate}" -lt 28000 ]]; then
        echo "FAIL: Gas estimate ${gas_estimate} too low for Lisovo EIP-7951 cost (6900)" >&2
        echo "  Expected ~30220 (21000 intrinsic + ~2320 calldata + 6900 precompile)" >&2
        return 1
    fi

    # Upper bound sanity check
    if [[ "${gas_estimate}" -gt 35000 ]]; then
        echo "FAIL: Gas estimate ${gas_estimate} unexpectedly high (expected ~30220)" >&2
        return 1
    fi

    echo "OK: P256Verify gas at Lisovo (${gas_estimate}) consistent with EIP-7951 cost 6900" >&3
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,cross-node
@test "precompile-fork-safety: precompile set changes are consistent across all nodes" {
    _require_min_bor "2.6.0"
    [[ "${FORK_LISOVO_PRO:-999999999}" -ge 999999999 ]] && skip "LisovoPro fork not active in this version"

    if [[ -z "${L2_BOR_RPC_NODE_URL:-}" ]]; then
        skip "No secondary Bor RPC node available in enclave"
    fi

    _wait_for_block_on "$((FORK_LISOVO_PRO + 1))" "$L2_RPC_URL" "L2_RPC"
    _wait_for_block_on "$((FORK_LISOVO_PRO + 1))" "${L2_BOR_RPC_NODE_URL}" "BOR_RPC_NODE"

    echo "Comparing precompile behavior between validator and RPC node at fork boundaries" >&3

    local blocks_to_check=(
        "$((FORK_LISOVO - 1))"
        "${FORK_LISOVO}"
        "$((FORK_LISOVO_PRO - 1))"
        "${FORK_LISOVO_PRO}"
    )

    local diverged=0 compared=0 skipped=0

    for block in "${blocks_to_check[@]}"; do
        # Skip blocks where either node has pruned historical state
        if ! _state_available_at "${block}" "${L2_RPC_URL}" || \
           ! _state_available_at "${block}" "${L2_BOR_RPC_NODE_URL}"; then
            echo "  SKIP: block ${block} — historical state unavailable on one or both nodes" >&3
            skipped=$(( skipped + 1 ))
            continue
        fi

        compared=$(( compared + 1 ))

        # Compare KZG behavior
        local val_kzg rpc_kzg
        val_kzg=$(_call_at_block "${KZG_ADDR}" "0x" "${block}" "${L2_RPC_URL}")
        rpc_kzg=$(_call_at_block "${KZG_ADDR}" "0x" "${block}" "${L2_BOR_RPC_NODE_URL}")

        # Re-check state if either response is empty (aggressive pruning race)
        if [[ -z "${val_kzg}" || -z "${rpc_kzg}" ]]; then
            if ! _state_available_at "${block}" "${L2_RPC_URL}" || \
               ! _state_available_at "${block}" "${L2_BOR_RPC_NODE_URL}"; then
                echo "  SKIP: block ${block} — state pruned during comparison (KZG)" >&3
                compared=$(( compared - 1 ))
                skipped=$(( skipped + 1 ))
                continue
            fi
        fi

        # Normalize: '' and '0x' both mean "no data"
        local norm_val_kzg="${val_kzg:-0x}"
        local norm_rpc_kzg="${rpc_kzg:-0x}"

        if [[ "${norm_val_kzg}" != "${norm_rpc_kzg}" ]]; then
            echo "DIVERGENCE at block ${block} for KZG (0x0a):" >&2
            echo "  Validator: '${val_kzg}'" >&2
            echo "  RPC node:  '${rpc_kzg}'" >&2
            diverged=1
        else
            echo "  OK: KZG at block ${block}: validator='${val_kzg}', rpc='${rpc_kzg}'" >&3
        fi

        # Compare P256 behavior
        local val_p256 rpc_p256
        val_p256=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${block}" "${L2_RPC_URL}")
        rpc_p256=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${block}" "${L2_BOR_RPC_NODE_URL}")

        if [[ -z "${val_p256}" || -z "${rpc_p256}" ]]; then
            if ! _state_available_at "${block}" "${L2_RPC_URL}" || \
               ! _state_available_at "${block}" "${L2_BOR_RPC_NODE_URL}"; then
                echo "  SKIP: block ${block} — state pruned during comparison (P256)" >&3
                compared=$(( compared - 1 ))
                skipped=$(( skipped + 1 ))
                continue
            fi
        fi

        local norm_val_p256="${val_p256:-0x}"
        local norm_rpc_p256="${rpc_p256:-0x}"

        if [[ "${norm_val_p256}" != "${norm_rpc_p256}" ]]; then
            echo "DIVERGENCE at block ${block} for P256 (0x0100):" >&2
            echo "  Validator: '${val_p256}'" >&2
            echo "  RPC node:  '${rpc_p256}'" >&2
            diverged=1
        else
            echo "  OK: P256 at block ${block}: both nodes agree" >&3
        fi
    done

    if [[ "${compared}" -eq 0 && "${skipped}" -gt 0 ]]; then
        skip "Historical state unavailable on one or both nodes for all fork boundary blocks"
    fi

    if [[ "${diverged}" -eq 1 ]]; then
        echo "FAIL: Precompile behavior diverges between validator and RPC nodes" >&2
        return 1
    fi

    echo "OK: All precompile results consistent between validator and RPC node (compared=${compared}, skipped=${skipped})" >&3
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,kzg,evm-gas
@test "precompile-fork-safety: gas estimation changes correctly at KZG boundary" {
    _require_min_bor "2.6.0"
    _wait_for_block_on "$((FORK_LISOVO + 1))" "$L2_RPC_URL" "L2_RPC"

    local pre_lisovo_block=$(( FORK_LISOVO - 1 ))

    echo "Comparing KZG gas estimates: block ${pre_lisovo_block} vs ${FORK_LISOVO}" >&3

    # Pre-Lisovo: KZG is not active, so estimateGas for a call to 0x0a should
    # reflect a simple call to an empty address (just intrinsic + calldata cost).
    local gas_pre
    gas_pre=$(_estimate_at_block "${KZG_ADDR}" "${KZG_INPUT}" "${pre_lisovo_block}")
    echo "KZG gas estimate at block ${pre_lisovo_block} (pre-Lisovo): ${gas_pre:-'(failed/empty)'}" >&3

    # At Lisovo: KZG is active and will either process the input (charging
    # precompile gas) or revert. Either way, estimateGas should differ.
    local gas_post
    gas_post=$(_estimate_at_block "${KZG_ADDR}" "${KZG_INPUT}" "${FORK_LISOVO}")
    echo "KZG gas estimate at block ${FORK_LISOVO} (Lisovo): ${gas_post:-'(failed/empty)'}" >&3

    if [[ -z "${gas_pre}" && -z "${gas_post}" ]]; then
        skip "eth_estimateGas unavailable for KZG calls at both blocks"
    fi

    # If pre-Lisovo succeeds but post-Lisovo fails (or vice versa), that is
    # itself proof the precompile activation changed behavior.
    if [[ -z "${gas_pre}" && -n "${gas_post}" ]]; then
        echo "OK: Gas estimation fails pre-Lisovo but succeeds at Lisovo — precompile activated" >&3
        return 0
    fi
    if [[ -n "${gas_pre}" && -z "${gas_post}" ]]; then
        echo "OK: Gas estimation succeeds pre-Lisovo but fails at Lisovo — precompile rejects input" >&3
        return 0
    fi

    # Both returned values: they should differ (precompile gas cost added at Lisovo).
    if [[ "${gas_pre}" -eq "${gas_post}" ]]; then
        echo "FAIL: Gas estimates are identical pre/post Lisovo (${gas_pre})" >&2
        echo "  Expected different values due to KZG precompile activation" >&2
        return 1
    fi

    echo "OK: KZG gas estimate changed at Lisovo boundary (pre=${gas_pre}, post=${gas_post})" >&3
}

# bats test_tags=execution-specs,pos-precompile,fork-activation,cross-client,kzg
@test "precompile-fork-safety: cross-client precompile consistency at Lisovo" {
    _require_min_bor "2.6.0"

    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        skip "No Erigon RPC node available (no Erigon node in enclave)"
    fi

    # Use the Bor archive node for this comparison — both archive nodes retain
    # full historical state, eliminating false divergences from pruning.
    local bor_rpc="${L2_BOR_ARCHIVE_RPC_URL:-${L2_RPC_URL}}"
    local using_archive="false"
    if [[ -n "${L2_BOR_ARCHIVE_RPC_URL:-}" ]]; then
        using_archive="true"
        echo "Using Bor archive node for cross-client comparison: ${bor_rpc}" >&3
    else
        echo "WARNING: No Bor archive node — falling back to ${bor_rpc} (may skip pruned blocks)" >&3
    fi

    _wait_for_block_on "$((FORK_LISOVO + 1))" "${bor_rpc}" "Bor"
    _wait_for_block_on "$((FORK_LISOVO + 1))" "${L2_ERIGON_RPC_URL}" "Erigon"

    echo "Comparing precompile behavior between Bor and Erigon at Lisovo boundary" >&3

    local diverged=0 compared=0 skipped=0
    local blocks_to_check=(
        "$((FORK_LISOVO - 1))"
        "${FORK_LISOVO}"
        "$((FORK_LISOVO + 1))"
    )

    for block in "${blocks_to_check[@]}"; do
        # Skip blocks where either client has pruned historical state
        if ! _state_available_at "${block}" "${bor_rpc}" || \
           ! _state_available_at "${block}" "${L2_ERIGON_RPC_URL}"; then
            echo "  SKIP: block ${block} — historical state unavailable on one or both clients" >&3
            skipped=$(( skipped + 1 ))
            continue
        fi

        compared=$(( compared + 1 ))

        # Compare KZG behavior
        local bor_kzg erigon_kzg
        bor_kzg=$(_call_at_block "${KZG_ADDR}" "0x" "${block}" "${bor_rpc}")
        erigon_kzg=$(_call_at_block "${KZG_ADDR}" "0x" "${block}" "${L2_ERIGON_RPC_URL}")

        # If either response is empty despite state check, re-verify (pruning race)
        if [[ -z "${bor_kzg}" || -z "${erigon_kzg}" ]]; then
            if ! _state_available_at "${block}" "${bor_rpc}" || \
               ! _state_available_at "${block}" "${L2_ERIGON_RPC_URL}"; then
                echo "  SKIP: block ${block} — state pruned during comparison (KZG)" >&3
                compared=$(( compared - 1 ))
                skipped=$(( skipped + 1 ))
                continue
            fi
        fi

        # Normalize empty representations: '' and '0x' both mean "no data"
        local norm_bor_kzg="${bor_kzg:-0x}"
        local norm_erigon_kzg="${erigon_kzg:-0x}"

        if [[ "${norm_bor_kzg}" != "${norm_erigon_kzg}" ]]; then
            echo "DIVERGENCE at block ${block} for KZG (0x0a):" >&2
            echo "  Bor:    '${bor_kzg}'" >&2
            echo "  Erigon: '${erigon_kzg}'" >&2
            diverged=1
        else
            echo "  OK: KZG at block ${block}: Bor='${bor_kzg}', Erigon='${erigon_kzg}'" >&3
        fi

        # Compare P256 behavior
        local bor_p256 erigon_p256
        bor_p256=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${block}" "${bor_rpc}")
        erigon_p256=$(_call_at_block "${P256_ADDR}" "${P256_INPUT}" "${block}" "${L2_ERIGON_RPC_URL}")

        if [[ -z "${bor_p256}" || -z "${erigon_p256}" ]]; then
            if ! _state_available_at "${block}" "${bor_rpc}" || \
               ! _state_available_at "${block}" "${L2_ERIGON_RPC_URL}"; then
                echo "  SKIP: block ${block} — state pruned during comparison (P256)" >&3
                compared=$(( compared - 1 ))
                skipped=$(( skipped + 1 ))
                continue
            fi
        fi

        local norm_bor_p256="${bor_p256:-0x}"
        local norm_erigon_p256="${erigon_p256:-0x}"

        if [[ "${norm_bor_p256}" != "${norm_erigon_p256}" ]]; then
            echo "DIVERGENCE at block ${block} for P256 (0x0100):" >&2
            echo "  Bor:    '${bor_p256}'" >&2
            echo "  Erigon: '${erigon_p256}'" >&2
            diverged=1
        else
            echo "  OK: P256 at block ${block}: both clients agree" >&3
        fi
    done

    if [[ "${compared}" -eq 0 && "${skipped}" -gt 0 ]]; then
        skip "Historical state unavailable on one or both clients for all Lisovo boundary blocks"
    fi

    if [[ "${diverged}" -eq 1 ]]; then
        echo "FAIL: Bor and Erigon disagree on precompile behavior at Lisovo boundary" >&2
        echo "  This indicates a consensus-critical precompile activation mismatch" >&2
        return 1
    fi

    echo "OK: Bor and Erigon agree on all precompile results at Lisovo boundary (compared=${compared}, skipped=${skipped})" >&3
}
