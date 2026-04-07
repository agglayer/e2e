#!/usr/bin/env bats
# bats file_tags=heimdall,checkpoint,correctness

# Checkpoint Chain Integrity
# ==========================
# Verifies that Heimdall's checkpoint chain is internally consistent and that
# the block data committed in each checkpoint matches what Bor produced.
#
# Checkpoints are Heimdall's merkle-root commitments of Bor block ranges to the
# Ethereum root chain.  A checkpoint contains a root_hash that commits the
# stateRoot of every block in [start_block, end_block].  If Heimdall commits
# the wrong root_hash, the L1 bridge accepts incorrect state — this is a
# critical safety property for the PoS bridge.
#
# The suite checks four properties:
#
#   1. Well-formed             — latest checkpoint has all required fields
#                                (proposer, start_block, end_block, root_hash)
#   2. Chain contiguity        — checkpoint[i].start_block ==
#                                checkpoint[i-1].end_block + 1 for the last 5
#                                (no gaps and no overlapping block ranges)
#   3. Root hash non-trivial   — root_hash is not the zero hash (a zero root
#                                would silently accept any Bor state as valid)
#   4. Proposer in validator set — the checkpoint proposer must be an active
#                                  staked validator (not a phantom address)
#   5. Bor consistency         — Bor has the end_block of the latest checkpoint
#                                and returns a non-null block hash for it
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL
#   - At least 2 checkpoints have been committed (to check contiguity)
#
# RUN: bats tests/heimdall/consensus-correctness/checkpoint-chain-integrity.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # Quick reachability probe
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/latest" 2>/dev/null \
        | jq -r '.checkpoint.start_block // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/latest" 2>/dev/null \
            | jq -r '.checkpoint.start_block // empty' 2>/dev/null || true)
    fi

    # Use BATS_FILE_TMPDIR for cross-subshell communication (exported vars from
    # setup_file do not propagate to setup() in BATS 1.x).
    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall checkpoint API not reachable at ${L2_CL_API_URL} — all checkpoint tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_checkpoint_unavailable"
    else
        echo "Heimdall checkpoint API reachable; latest checkpoint start_block=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_checkpoint_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_checkpoint_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall checkpoint API not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the latest checkpoint object from Heimdall.
# Tries standard path first, then gRPC-gateway /v1beta1/ prefix.
# Prints the raw JSON checkpoint object on stdout, or returns 1 on failure.
_get_latest_checkpoint() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/latest" 2>/dev/null || true)
    local cp
    cp=$(printf '%s' "${raw}" | jq -r 'if .checkpoint then .checkpoint else empty end' 2>/dev/null || true)
    if [[ -z "${cp}" || "${cp}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/latest" 2>/dev/null || true)
        cp=$(printf '%s' "${raw}" | jq -r 'if .checkpoint then .checkpoint else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${cp}" || "${cp}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${cp}"
}

# Fetch the total acknowledged checkpoint count.
# Prints the count as a decimal integer, or returns 1 on failure.
_get_checkpoint_count() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/count" 2>/dev/null || true)
    local count
    count=$(printf '%s' "${raw}" | jq -r '.ack_count // empty' 2>/dev/null || true)
    if [[ -z "${count}" || "${count}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/count" 2>/dev/null || true)
        count=$(printf '%s' "${raw}" | jq -r '.ack_count // empty' 2>/dev/null || true)
    fi
    if [[ -z "${count}" || "${count}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${count}"
}

# Fetch a checkpoint by its 1-based sequence number.
# Prints the raw JSON checkpoint object on stdout, or returns 1 on failure.
_get_checkpoint_by_number() {
    local number="$1"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/${number}" 2>/dev/null || true)
    local cp
    cp=$(printf '%s' "${raw}" | jq -r 'if .checkpoint then .checkpoint else empty end' 2>/dev/null || true)
    if [[ -z "${cp}" || "${cp}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/${number}" 2>/dev/null || true)
        cp=$(printf '%s' "${raw}" | jq -r 'if .checkpoint then .checkpoint else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${cp}" || "${cp}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${cp}"
}

# Fetch the active validator signers (lowercase) from Heimdall.
# Prints a newline-separated list of addresses, or returns 1 on failure.
#
# Strategy:
#   1. /stake/validators-set — available on heimdall-v2 (returns .validator_set.validators[].signer)
#   2. /stake/validators     — heimdall-v1 (returns .validators[].signer)
#   3. /bor/spans/latest     — fallback via span producers (returns .span.selected_producers[].signer)
_get_validator_signers() {
    local raw signers

    # Attempt 1: /stake/validators-set (heimdall-v2)
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/stake/validators-set" 2>/dev/null || true)
    signers=$(printf '%s' "${raw}" \
        | jq -r '.validator_set.validators[]?.signer // empty' 2>/dev/null || true)

    # Attempt 2: /stake/validators (heimdall-v1) or /v1beta1/ prefix
    if [[ -z "${signers}" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/stake/validators" 2>/dev/null || true)
        signers=$(printf '%s' "${raw}" \
            | jq -r '.validators[]?.signer // empty' 2>/dev/null || true)
    fi
    if [[ -z "${signers}" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/stake/validators" 2>/dev/null || true)
        signers=$(printf '%s' "${raw}" \
            | jq -r '.validators[]?.signer // empty' 2>/dev/null || true)
    fi

    # Attempt 3: span producers as a last resort
    if [[ -z "${signers}" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null || true)
        signers=$(printf '%s' "${raw}" \
            | jq -r '.span.selected_producers[]?.signer // empty' 2>/dev/null || true)
    fi

    if [[ -z "${signers}" ]]; then
        return 1
    fi
    printf '%s\n' "${signers}" | tr '[:upper:]' '[:lower:]'
}

# Query a block field from Bor RPC.
_bor_block_field() {
    local block_dec="$1" field="$2"
    local block_hex
    block_hex=$(printf '0x%x' "${block_dec}")
    curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=checkpoint,correctness
@test "heimdall checkpoint: latest checkpoint is well-formed (proposer, start_block, end_block, root_hash present)" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        fail "Could not fetch latest checkpoint from Heimdall at ${L2_CL_API_URL} — API may be down or no checkpoints committed yet"
    fi

    local proposer start_block end_block root_hash
    proposer=$(printf '%s' "${cp}" | jq -r '.proposer // empty')
    start_block=$(printf '%s' "${cp}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${cp}" | jq -r '.end_block // empty')
    root_hash=$(printf '%s' "${cp}" | jq -r '.root_hash // empty')

    echo "  proposer=${proposer} start_block=${start_block} end_block=${end_block}" >&3
    echo "  root_hash=${root_hash}" >&3

    if [[ -z "${proposer}" || "${proposer}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no 'proposer' field" >&2
        return 1
    fi
    if [[ -z "${start_block}" || "${start_block}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no 'start_block' field" >&2
        return 1
    fi
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no 'end_block' field" >&2
        return 1
    fi
    if [[ "${end_block}" -le "${start_block}" ]]; then
        echo "FAIL: checkpoint end_block (${end_block}) <= start_block (${start_block}) — invalid range" >&2
        return 1
    fi
    if [[ -z "${root_hash}" || "${root_hash}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no 'root_hash' field" >&2
        return 1
    fi
}

# bats test_tags=checkpoint,correctness
@test "heimdall checkpoint: chain contiguity — checkpoint[i].start_block == checkpoint[i-1].end_block + 1 for latest 5" {
    local total
    if ! total=$(_get_checkpoint_count); then
        skip "Could not fetch checkpoint count from Heimdall — API may not be ready"
    fi

    if [[ -z "${total}" || "${total}" -lt 2 ]]; then
        skip "Only ${total:-0} checkpoint(s) committed — need at least 2 to check contiguity"
    fi

    local check_count=$(( total < 5 ? total : 5 ))
    local hi_num="${total}"
    local failures=0

    local i
    for (( i = 0; i < check_count - 1; i++ )); do
        local lo_num=$(( hi_num - 1 ))
        local hi_cp lo_cp

        if ! hi_cp=$(_get_checkpoint_by_number "${hi_num}"); then
            echo "  WARN: could not fetch checkpoint ${hi_num} — skipping pair (${lo_num}, ${hi_num})" >&3
            hi_num="${lo_num}"
            continue
        fi
        if ! lo_cp=$(_get_checkpoint_by_number "${lo_num}"); then
            echo "  WARN: could not fetch checkpoint ${lo_num} — skipping pair (${lo_num}, ${hi_num})" >&3
            hi_num="${lo_num}"
            continue
        fi

        local hi_start lo_end
        hi_start=$(printf '%s' "${hi_cp}" | jq -r '.start_block')
        lo_end=$(printf '%s' "${lo_cp}" | jq -r '.end_block')

        local expected_start=$(( lo_end + 1 ))
        echo "  checkpoint ${lo_num}: end_block=${lo_end}  →  checkpoint ${hi_num}: start_block=${hi_start}  (expected ${expected_start})" >&3

        if [[ "${hi_start}" -ne "${expected_start}" ]]; then
            echo "FAIL: checkpoint contiguity violated between checkpoint ${lo_num} and checkpoint ${hi_num}:" >&2
            echo "  checkpoint ${lo_num} end_block   = ${lo_end}" >&2
            echo "  checkpoint ${hi_num} start_block = ${hi_start}  (expected ${expected_start})" >&2
            if [[ "${hi_start}" -gt "${expected_start}" ]]; then
                echo "  GAP of $(( hi_start - expected_start )) Bor blocks has no checkpoint coverage." >&2
                echo "  State for blocks ${expected_start}–$(( hi_start - 1 )) has NOT been committed to the root chain." >&2
            else
                echo "  OVERLAP: blocks ${hi_start}–$(( expected_start - 1 )) are covered by two checkpoints." >&2
                echo "  This may cause the root chain contract to reject the checkpoint submission." >&2
            fi
            failures=$(( failures + 1 ))
        fi

        hi_num="${lo_num}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} checkpoint contiguity violation(s) detected" >&2
        return 1
    fi
}

# bats test_tags=checkpoint,correctness
@test "heimdall checkpoint: root_hash is non-zero" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall"
    fi

    local root_hash
    root_hash=$(printf '%s' "${cp}" | jq -r '.root_hash // empty')

    if [[ -z "${root_hash}" || "${root_hash}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no root_hash" >&2
        return 1
    fi

    # root_hash may be 0x-prefixed hex or base64 (proto3 JSON encodes bytes as base64).
    # Check that it is not an all-zero value regardless of encoding.
    local is_zero=0
    local stripped="${root_hash#0x}"
    if [[ "${stripped}" =~ ^[0-9a-fA-F]+$ ]]; then
        # Hex-encoded: check for all-zero hex digits
        [[ "${stripped}" =~ ^0+$ ]] && is_zero=1
    else
        # Likely base64-encoded bytes: decode and check if all bytes are 0x00.
        # A 32-byte zero hash in base64 is AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
        local hex_decoded
        hex_decoded=$(printf '%s' "${stripped}" | base64 -d 2>/dev/null \
            | od -A n -t x1 2>/dev/null | tr -d ' \n' || true)
        if [[ -n "${hex_decoded}" && "${hex_decoded}" =~ ^0+$ ]]; then
            is_zero=1
        fi
    fi

    if [[ "${is_zero}" -eq 1 ]]; then
        echo "FAIL: latest checkpoint root_hash is all zeros: ${root_hash}" >&2
        echo "  A zero root_hash means the Ethereum root chain contract would accept" >&2
        echo "  any Bor state as valid, breaking the bridge's integrity guarantee." >&2
        return 1
    fi

    echo "  OK: root_hash is non-zero: ${root_hash}" >&3
}

# bats test_tags=checkpoint,correctness
@test "heimdall checkpoint: proposer is in active validator set" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall"
    fi

    local proposer
    proposer=$(printf '%s' "${cp}" | jq -r '.proposer // empty' | tr '[:upper:]' '[:lower:]')
    if [[ -z "${proposer}" || "${proposer}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no proposer" >&2
        return 1
    fi

    local signer_output
    if ! signer_output=$(_get_validator_signers); then
        skip "Could not fetch validator set from ${L2_CL_API_URL}/stake/validators — skipping proposer check"
    fi
    local -a validators
    mapfile -t validators <<< "${signer_output}"
    if [[ "${#validators[@]}" -eq 0 ]]; then
        skip "Validator set is empty — chain may not have started staking yet"
    fi

    echo "  checkpoint proposer: ${proposer}" >&3
    echo "  active validators: ${#validators[@]}" >&3

    local found=0
    local v
    for v in "${validators[@]}"; do
        if [[ "${v}" == "${proposer}" ]]; then
            found=1
            break
        fi
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "FAIL: checkpoint proposer ${proposer} is NOT in the active validator set" >&2
        echo "  A checkpoint committed by a non-validator could be fraudulent or indicate" >&2
        echo "  a stake accounting bug in Heimdall." >&2
        return 1
    fi

    echo "  OK: proposer ${proposer} is in the active validator set" >&3
}

# bats test_tags=checkpoint,correctness
@test "heimdall checkpoint: Bor has the end_block of the latest checkpoint" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall"
    fi

    local end_block
    end_block=$(printf '%s' "${cp}" | jq -r '.end_block // empty')
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest checkpoint has no end_block — cannot verify against Bor"
    fi

    echo "  Checking Bor has block ${end_block}..." >&3

    local block_hash
    block_hash=$(_bor_block_field "${end_block}" "hash")

    if [[ -z "${block_hash}" || "${block_hash}" == "null" ]]; then
        echo "FAIL: Bor does not have block ${end_block} (latest checkpoint end_block)" >&2
        echo "  Either the checkpoint references a future block Bor has not produced," >&2
        echo "  or Bor is stuck and has not reached the checkpoint boundary yet." >&2
        return 1
    fi

    echo "  OK: Bor has block ${end_block}: ${block_hash}" >&3
}
