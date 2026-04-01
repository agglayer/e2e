#!/usr/bin/env bats
# bats file_tags=heimdall,checkpoint,correctness,safety

# Checkpoint Safety
# =================
# Verifies that Heimdall's checkpoint ledger is internally consistent
# and does not contain states that would cause panics or L1 submission failures.
#
# Checkpoints carry the Bor state root to L1. Incorrect proposers, wrong-length
# root hashes, or non-monotonic ACK counts indicate corruption that would either
# panic during side-tx signing or be rejected by the L1 root chain contract.
#
# The suite checks five safety properties:
#
#   1. Monotonic ACK count     — the checkpoint ACK counter must never decrease;
#                                a decrease means the checkpoint ledger is corrupt
#   2. Valid proposer address  — every checkpoint proposer must be a well-formed
#                                EVM address and an active validator;
#                                GetSideSignBytes panics on a malformed proposer
#   3. No numbering gaps       — the latest 10 checkpoints must have contiguous
#                                block ranges (extends chain-integrity to 10 pairs)
#   4. Root hash length        — each checkpoint root hash must be exactly 32 bytes;
#                                the L1 root chain contract rejects any other length
#   5. Distinct root hashes    — no two consecutive checkpoints may share a root
#                                hash, because disjoint Bor block ranges must have
#                                different state roots
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - At least 1 checkpoint has been committed (tests skip if none exist)
#
# RUN: bats tests/heimdall/consensus-correctness/checkpoint-safety.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # Probe the checkpoint count endpoint, which is the most fundamental API
    # used by the safety tests.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/count" 2>/dev/null \
        | jq -r '.ack_count // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/count" 2>/dev/null \
            | jq -r '.ack_count // empty' 2>/dev/null || true)
    fi

    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall checkpoint count API not reachable at ${L2_CL_API_URL} — all checkpoint safety tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/checkpoint_safety_unavailable"
    else
        echo "Heimdall checkpoint API reachable; current ack_count=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/checkpoint_safety_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/checkpoint_safety_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall checkpoint API not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the total acknowledged checkpoint count from Heimdall.
# Tries the canonical path then the /v1beta1/ prefix.
# Prints the raw integer on stdout, or returns 1 on failure.
_get_ack_count() {
    local raw count
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/count" 2>/dev/null || true)
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

# Fetch the latest checkpoint JSON object from Heimdall.
# Tries the canonical path then the /v1beta1/ prefix.
# Prints the raw JSON checkpoint object on stdout, or returns 1 on failure.
_get_latest_checkpoint() {
    local raw cp
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/latest" 2>/dev/null || true)
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

# Fetch a checkpoint by its 1-based sequence number from Heimdall.
# Prints the raw JSON checkpoint object on stdout, or returns 1 on failure.
_get_checkpoint_by_number() {
    local number="$1"
    local raw cp
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/${number}" 2>/dev/null || true)
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

# Fetch the active validator signers (hex addresses, lowercased) from Heimdall.
# Prints a newline-separated list on stdout, or returns 1 on failure.
_get_validator_signers() {
    local raw signers
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/stake/validators" 2>/dev/null || true)
    signers=$(printf '%s' "${raw}" \
        | jq -r '.validators[]?.signer // empty' 2>/dev/null || true)
    if [[ -z "${signers}" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/stake/validators" 2>/dev/null || true)
        signers=$(printf '%s' "${raw}" \
            | jq -r '.validators[]?.signer // empty' 2>/dev/null || true)
    fi
    if [[ -z "${signers}" ]]; then
        return 1
    fi
    printf '%s\n' "${signers}" | tr '[:upper:]' '[:lower:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=checkpoint,correctness,safety
@test "heimdall checkpoint: ACK count is monotonically increasing over time" {
    local count_first
    if ! count_first=$(_get_ack_count); then
        skip "Could not fetch checkpoint count from Heimdall — API may not be ready"
    fi

    # Validate: must be a non-negative integer
    [[ "${count_first}" =~ ^[0-9]+$ ]] || count_first=0

    echo "  Initial ack_count=${count_first}; waiting 30 seconds..." >&3
    echo "${count_first}" > "${BATS_FILE_TMPDIR}/ack_count_first"

    sleep 30

    local count_second
    if ! count_second=$(_get_ack_count); then
        skip "Could not fetch checkpoint count from Heimdall on second poll — API may not be ready"
    fi
    [[ "${count_second}" =~ ^[0-9]+$ ]] || count_second=0

    echo "  Second ack_count=${count_second}" >&3

    if [[ "${count_second}" -lt "${count_first}" ]]; then
        echo "FAIL: checkpoint ACK count decreased — checkpoint ledger may be corrupted" >&2
        echo "  first poll  : ack_count=${count_first}" >&2
        echo "  second poll : ack_count=${count_second}" >&2
        echo "  A decreasing ACK count means the keeper's ackCount item was overwritten" >&2
        echo "  with a smaller value, which would break checkpoint numbering." >&2
        return 1
    fi

    echo "OK: checkpoint ACK count advanced from ${count_first} to ${count_second}" >&3
}

# bats test_tags=checkpoint,correctness,safety
@test "heimdall checkpoint: proposer address is non-empty and well-formed" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall — API may be down or no checkpoints committed yet"
    fi

    local proposer
    proposer=$(printf '%s' "${cp}" | jq -r '.proposer // empty')

    echo "  proposer=${proposer}" >&3

    if [[ -z "${proposer}" || "${proposer}" == "null" ]]; then
        echo "FAIL: latest checkpoint has an empty or null proposer" >&2
        echo "  GetSideSignBytes would panic on this checkpoint:" >&2
        echo "  panic(errors.New(\"invalid proposer while getting side sign bytes for checkpoint msg\"))" >&2
        return 1
    fi

    # Validate EVM address format: 0x followed by exactly 40 hex characters
    if [[ ! "${proposer}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        echo "FAIL: checkpoint proposer '${proposer}' is malformed — not a valid EVM address" >&2
        echo "  Expected format: 0x followed by 40 hex characters (e.g. 0xAbCd...1234)" >&2
        echo "  GetSideSignBytes would panic on this checkpoint." >&2
        return 1
    fi

    # Also confirm the proposer is in the active validator set.
    local signer_output
    if ! signer_output=$(_get_validator_signers); then
        echo "  NOTE: could not fetch validator set — skipping active-set membership check" >&3
        echo "OK: checkpoint proposer ${proposer} is valid (active-set check skipped)" >&3
        return 0
    fi

    local -a validators
    mapfile -t validators <<< "${signer_output}"

    if [[ "${#validators[@]}" -eq 0 ]]; then
        echo "  NOTE: validator set is empty — skipping active-set membership check" >&3
        echo "OK: checkpoint proposer ${proposer} is valid (active-set check skipped)" >&3
        return 0
    fi

    local proposer_lower found
    proposer_lower=$(printf '%s' "${proposer}" | tr '[:upper:]' '[:lower:]')
    found=0

    local v
    for v in "${validators[@]}"; do
        if [[ "${v}" == "${proposer_lower}" ]]; then
            found=1
            break
        fi
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "FAIL: checkpoint proposer ${proposer} is NOT in the active validator set" >&2
        echo "  Only active staked validators should be able to propose checkpoints." >&2
        echo "  This may indicate a stake accounting bug or a rogue proposer." >&2
        return 1
    fi

    echo "OK: checkpoint proposer ${proposer} is valid and in active set" >&3
}

# bats test_tags=checkpoint,correctness,safety
@test "heimdall checkpoint: checkpoint sequence has no numbering gaps in latest 10" {
    local total
    if ! total=$(_get_ack_count); then
        skip "Could not fetch checkpoint count from Heimdall — API may not be ready"
    fi
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0

    if [[ "${total}" -lt 2 ]]; then
        skip "Only ${total} checkpoint(s) committed — need at least 2 to check sequence gaps"
    fi

    # Check up to the latest 10 checkpoints (requires 10 pairs → up to 10 fetches).
    local check_count
    check_count=$(( total < 10 ? total : 10 ))

    local hi_num="${total}"
    local failures=0
    local checked=0

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

        local hi_start lo_end hi_id lo_id
        hi_start=$(printf '%s' "${hi_cp}" | jq -r '.start_block // empty')
        lo_end=$(printf '%s'   "${lo_cp}" | jq -r '.end_block   // empty')
        hi_id=$(printf '%s'    "${hi_cp}" | jq -r '.id          // empty')
        lo_id=$(printf '%s'    "${lo_cp}" | jq -r '.id          // empty')

        [[ "${hi_start}" =~ ^[0-9]+$ ]] || hi_start=0
        [[ "${lo_end}"   =~ ^[0-9]+$ ]] || lo_end=0
        [[ "${hi_id}"    =~ ^[0-9]+$ ]] || hi_id=0
        [[ "${lo_id}"    =~ ^[0-9]+$ ]] || lo_id=0

        local expected_start=$(( lo_end + 1 ))
        echo "  checkpoint ${lo_num} (id=${lo_id}): end_block=${lo_end}  →  checkpoint ${hi_num} (id=${hi_id}): start_block=${hi_start}  (expected ${expected_start})" >&3

        # Check block range contiguity
        if [[ "${hi_start}" -ne "${expected_start}" ]]; then
            echo "FAIL: block range gap between checkpoint ${lo_num} and checkpoint ${hi_num}" >&2
            echo "  checkpoint ${lo_num} end_block   = ${lo_end}" >&2
            echo "  checkpoint ${hi_num} start_block = ${hi_start}  (expected ${expected_start})" >&2
            if [[ "${hi_start}" -gt "${expected_start}" ]]; then
                echo "  GAP: Bor blocks ${expected_start}–$(( hi_start - 1 )) have no checkpoint coverage." >&2
            else
                echo "  OVERLAP: Bor blocks ${hi_start}–$(( expected_start - 1 )) appear in two checkpoints." >&2
            fi
            failures=$(( failures + 1 ))
        fi

        # Check that checkpoint IDs are sequential (id at index N should equal N)
        if [[ "${hi_id}" -ne "${hi_num}" ]]; then
            echo "FAIL: checkpoint fetched at index ${hi_num} has id=${hi_id} (expected ${hi_num})" >&2
            failures=$(( failures + 1 ))
        fi
        if [[ "${lo_id}" -ne "${lo_num}" ]]; then
            echo "FAIL: checkpoint fetched at index ${lo_num} has id=${lo_id} (expected ${lo_num})" >&2
            failures=$(( failures + 1 ))
        fi

        checked=$(( checked + 1 ))
        hi_num="${lo_num}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} sequencing violation(s) detected in latest ${check_count} checkpoints" >&2
        return 1
    fi

    echo "OK: latest ${check_count} checkpoints have contiguous block ranges (${checked} pairs checked)" >&3
}

# bats test_tags=checkpoint,correctness,safety
@test "heimdall checkpoint: root hash length is exactly 32 bytes (66 hex chars with 0x)" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall — API may be down or no checkpoints committed yet"
    fi

    local root_hash
    root_hash=$(printf '%s' "${cp}" | jq -r '.root_hash // empty')

    if [[ -z "${root_hash}" || "${root_hash}" == "null" ]]; then
        echo "FAIL: latest checkpoint has no root_hash field" >&2
        return 1
    fi

    echo "  root_hash=${root_hash}" >&3

    local byte_count=0

    if [[ "${root_hash}" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Hex-encoded: strip the 0x prefix and count hex characters.
        # Two hex chars per byte, so byte_count = (len - 2) / 2.
        local stripped="${root_hash#0x}"
        local hex_len="${#stripped}"
        byte_count=$(( hex_len / 2 ))

        echo "  Detected hex encoding; hex chars (without 0x)=${hex_len}, byte_count=${byte_count}" >&3

        if [[ "${hex_len}" -ne 64 ]]; then
            echo "FAIL: checkpoint root hash has wrong length — L1 contract expects exactly 32 bytes" >&2
            echo "  root_hash : ${root_hash}" >&2
            echo "  hex chars : ${hex_len} (expected 64, i.e. 32 bytes)" >&2
            echo "  The Ethereum root chain contract calls abi.decode on the root hash as bytes32;" >&2
            echo "  a wrong-length value will cause the submission to revert." >&2
            return 1
        fi
    else
        # Assume base64 encoding (proto3 JSON encodes bytes as base64).
        local decoded_hex
        decoded_hex=$(printf '%s' "${root_hash}" \
            | base64 -d 2>/dev/null \
            | od -A n -t x1 2>/dev/null \
            | tr -d ' \n' || true)

        if [[ -z "${decoded_hex}" ]]; then
            echo "FAIL: root_hash '${root_hash}' is neither valid hex nor valid base64" >&2
            return 1
        fi

        byte_count=$(( ${#decoded_hex} / 2 ))
        echo "  Detected base64 encoding; decoded byte_count=${byte_count}" >&3

        if [[ "${byte_count}" -ne 32 ]]; then
            echo "FAIL: checkpoint root hash has wrong length — L1 contract expects exactly 32 bytes" >&2
            echo "  root_hash (base64) : ${root_hash}" >&2
            echo "  decoded bytes      : ${byte_count} (expected 32)" >&2
            echo "  The Ethereum root chain contract calls abi.decode on the root hash as bytes32;" >&2
            echo "  a wrong-length value will cause the submission to revert." >&2
            return 1
        fi
    fi

    echo "OK: root hash is ${byte_count}-byte value" >&3
}

# bats test_tags=checkpoint,correctness,safety
@test "heimdall checkpoint: no two consecutive checkpoints have the same root hash" {
    local total
    if ! total=$(_get_ack_count); then
        skip "Could not fetch checkpoint count from Heimdall — API may not be ready"
    fi
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0

    if [[ "${total}" -lt 2 ]]; then
        skip "Only ${total} checkpoint(s) committed — need at least 2 to compare root hashes"
    fi

    # Check the latest 5 checkpoints (up to 4 consecutive pairs).
    local check_count
    check_count=$(( total < 5 ? total : 5 ))

    local hi_num="${total}"
    local failures=0
    local checked=0

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

        local hi_root lo_root
        hi_root=$(printf '%s' "${hi_cp}" | jq -r '.root_hash // empty')
        lo_root=$(printf '%s' "${lo_cp}" | jq -r '.root_hash // empty')

        echo "  checkpoint ${lo_num}: root_hash=${lo_root}" >&3
        echo "  checkpoint ${hi_num}: root_hash=${hi_root}" >&3

        if [[ -z "${hi_root}" || "${hi_root}" == "null" || -z "${lo_root}" || "${lo_root}" == "null" ]]; then
            echo "  WARN: one or both root hashes are empty for pair (${lo_num}, ${hi_num}) — skipping comparison" >&3
            hi_num="${lo_num}"
            continue
        fi

        if [[ "${hi_root}" == "${lo_root}" ]]; then
            echo "FAIL: checkpoints ${lo_num} and ${hi_num} have identical root_hash: ${hi_root}" >&2
            echo "  Different Bor block ranges must produce different state roots." >&2
            echo "  Identical root hashes indicate that either the same block range was" >&2
            echo "  checkpointed twice, or the state root computation is incorrectly producing" >&2
            echo "  the same output for distinct inputs." >&2
            failures=$(( failures + 1 ))
        fi

        checked=$(( checked + 1 ))
        hi_num="${lo_num}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} consecutive root-hash collision(s) detected in latest ${check_count} checkpoints" >&2
        return 1
    fi

    echo "OK: latest ${check_count} checkpoints all have distinct root hashes (${checked} pairs checked)" >&3
}
