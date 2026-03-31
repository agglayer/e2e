#!/usr/bin/env bats
# bats file_tags=heimdall,milestone,correctness

# Milestone Finality Correctness
# ===============================
# Verifies that Heimdall's milestone-based fast finality mechanism is correct
# and that the block hash recorded in each milestone matches what Bor produced.
#
# Milestones are Heimdall's fast finality layer: validators vote on 2/3+
# majority agreement for a range of Bor blocks [start_block, end_block].
# The milestone's `hash` field is the block hash of `end_block` on Bor.
# If a milestone records the wrong block hash, Bor nodes accepting that
# milestone as finalized will diverge from the canonical chain.
#
# The suite checks four properties:
#
#   1. Well-formed             — latest milestone has proposer, start_block,
#                                end_block, and hash fields
#   2. Hash matches Bor        — milestone.hash == eth_getBlockByNumber(end_block).hash
#                                This is the oracle test: a Heimdall bug producing
#                                the wrong hash would silently finalize the wrong
#                                chain tip without triggering any other alarm
#   3. Chain contiguity        — milestone[i].start_block ==
#                                milestone[i-1].end_block + 1 for the last 5
#   4. Milestone behind chain  — milestone.end_block <= current Bor block number
#                                (finality cannot be ahead of block production)
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL
#   - At least 1 milestone has been committed (for hash check)
#   - At least 2 milestones for contiguity check
#
# RUN: bats tests/heimdall/consensus-correctness/milestone-finality.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/latest" 2>/dev/null \
        | jq -r '.milestone.start_block // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/latest" 2>/dev/null \
            | jq -r '.milestone.start_block // empty' 2>/dev/null || true)
    fi

    # Use BATS_FILE_TMPDIR for cross-subshell communication (exported vars from
    # setup_file do not propagate to setup() in BATS 1.x).
    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall milestone API not reachable at ${L2_CL_API_URL} — all milestone tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    else
        echo "Heimdall milestone API reachable; latest milestone start_block=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall milestone API not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the latest milestone object from Heimdall.
# Tries standard path first, then gRPC-gateway /v1beta1/ prefix.
# Prints the raw JSON milestone object on stdout, or returns 1 on failure.
_get_latest_milestone() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/latest" 2>/dev/null || true)
    local ms
    ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/latest" 2>/dev/null || true)
        ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${ms}"
}

# Fetch the total milestone count.
# Prints the count as a decimal integer, or returns 1 on failure.
_get_milestone_count() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/count" 2>/dev/null || true)
    local count
    count=$(printf '%s' "${raw}" | jq -r '.count // empty' 2>/dev/null || true)
    if [[ -z "${count}" || "${count}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/count" 2>/dev/null || true)
        count=$(printf '%s' "${raw}" | jq -r '.count // empty' 2>/dev/null || true)
    fi
    if [[ -z "${count}" || "${count}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${count}"
}

# Fetch a milestone by its sequence number.
# Prints the raw JSON milestone object on stdout, or returns 1 on failure.
_get_milestone_by_number() {
    local number="$1"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/${number}" 2>/dev/null || true)
    local ms
    ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/${number}" 2>/dev/null || true)
        ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${ms}"
}

# Return the current Bor block number as a decimal integer.
_bor_block_number() {
    local hex
    hex=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -r '.result // empty')
    if [[ -z "${hex}" ]]; then
        return 1
    fi
    printf '%d' "${hex}"
}

# Query a block field from Bor RPC.
# $1 = block number (decimal), $2 = field name
_bor_block_field() {
    local block_dec="$1" field="$2"
    local block_hex
    block_hex=$(printf '0x%x' "${block_dec}")
    curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

# Decode a base64 or hex hash into lowercase 0x-prefixed hex.
# Heimdall may encode the hash as base64 bytes (proto JSON) or 0x-prefixed hex.
# Returns 1 if input is empty/null; otherwise prints the canonical hex string.
_decode_hash() {
    local raw="$1"
    if [[ -z "${raw}" || "${raw}" == "null" ]]; then
        return 1
    fi
    # If it looks like 0x-prefixed hex, return as-is (lowercased).
    if [[ "${raw}" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    # Try base64 decode → hex (proto JSON encodes bytes as base64).
    # Use od (POSIX) instead of xxd to avoid a non-standard dependency.
    local hex_decoded
    hex_decoded=$(printf '%s' "${raw}" | base64 -d 2>/dev/null \
        | od -A n -t x1 2>/dev/null | tr -d ' \n' || true)
    if [[ -n "${hex_decoded}" ]]; then
        printf '0x%s' "${hex_decoded}"
        return 0
    fi
    # Return raw value unchanged if we cannot decode it.
    printf '%s' "${raw}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=milestone,correctness
@test "heimdall milestone: latest milestone is well-formed (proposer, start_block, end_block, hash present)" {
    local ms
    if ! ms=$(_get_latest_milestone); then
        fail "Could not fetch latest milestone from Heimdall at ${L2_CL_API_URL} — API may be down or no milestones committed yet"
    fi

    local proposer start_block end_block hash
    proposer=$(printf '%s' "${ms}" | jq -r '.proposer // empty')
    start_block=$(printf '%s' "${ms}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    hash=$(printf '%s' "${ms}" | jq -r '.hash // empty')

    echo "  proposer=${proposer} start_block=${start_block} end_block=${end_block}" >&3
    echo "  hash=${hash}" >&3

    if [[ -z "${proposer}" || "${proposer}" == "null" ]]; then
        echo "FAIL: latest milestone has no 'proposer' field" >&2
        return 1
    fi
    if [[ -z "${start_block}" || "${start_block}" == "null" ]]; then
        echo "FAIL: latest milestone has no 'start_block' field" >&2
        return 1
    fi
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        echo "FAIL: latest milestone has no 'end_block' field" >&2
        return 1
    fi
    if [[ "${end_block}" -le "${start_block}" ]]; then
        echo "FAIL: milestone end_block (${end_block}) <= start_block (${start_block}) — invalid range" >&2
        return 1
    fi
    if [[ -z "${hash}" || "${hash}" == "null" ]]; then
        echo "FAIL: latest milestone has no 'hash' field" >&2
        return 1
    fi
}

# bats test_tags=milestone,correctness
@test "heimdall milestone: hash matches Bor block hash at end_block (oracle test)" {
    # This is the critical oracle test.
    # milestone.hash must equal eth_getBlockByNumber(end_block).hash.
    # A mismatch means Heimdall is finalizing a different chain tip than what
    # Bor actually produced — the fast finality layer is broken.

    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local end_block ms_hash_raw
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    ms_hash_raw=$(printf '%s' "${ms}" | jq -r '.hash // empty')

    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block — cannot perform oracle check"
    fi
    if [[ -z "${ms_hash_raw}" || "${ms_hash_raw}" == "null" ]]; then
        skip "Latest milestone has no hash — cannot perform oracle check"
    fi

    # Decode the Heimdall hash (may be base64 or hex).
    local ms_hash
    ms_hash=$(_decode_hash "${ms_hash_raw}")
    echo "  milestone end_block=${end_block}, milestone hash=${ms_hash}" >&3

    # Fetch the Bor block hash for that block.
    local bor_hash
    bor_hash=$(_bor_block_field "${end_block}" "hash")

    if [[ -z "${bor_hash}" || "${bor_hash}" == "null" ]]; then
        echo "FAIL: Bor does not have block ${end_block} (milestone end_block)" >&2
        echo "  Either the milestone references a future block, or Bor is behind the milestone." >&2
        return 1
    fi

    echo "  Bor block hash for ${end_block}:  ${bor_hash}" >&3

    # Normalise both to lowercase for comparison.
    local ms_hash_lower bor_hash_lower
    ms_hash_lower=$(printf '%s' "${ms_hash}" | tr '[:upper:]' '[:lower:]')
    bor_hash_lower=$(printf '%s' "${bor_hash}" | tr '[:upper:]' '[:lower:]')

    if [[ "${ms_hash_lower}" != "${bor_hash_lower}" ]]; then
        echo "FAIL: milestone hash DOES NOT match Bor block hash at end_block ${end_block}:" >&2
        echo "  Heimdall milestone hash: ${ms_hash_lower}" >&2
        echo "  Bor block hash:          ${bor_hash_lower}" >&2
        echo "" >&2
        echo "  This means Heimdall's fast finality is recording a different chain tip than" >&2
        echo "  what Bor actually produced. Nodes accepting this milestone will diverge." >&2
        return 1
    fi

    echo "  OK: milestone hash matches Bor block hash: ${bor_hash_lower}" >&3
}

# bats test_tags=milestone,correctness
@test "heimdall milestone: chain contiguity — milestone[i].start_block == milestone[i-1].end_block + 1 for latest 5" {
    local total
    if ! total=$(_get_milestone_count); then
        skip "Could not fetch milestone count from Heimdall — API may not be ready"
    fi

    if [[ -z "${total}" || "${total}" -lt 2 ]]; then
        skip "Only ${total:-0} milestone(s) committed — need at least 2 to check contiguity"
    fi

    local check_count=$(( total < 5 ? total : 5 ))
    local hi_num="${total}"
    local failures=0

    local i
    for (( i = 0; i < check_count - 1; i++ )); do
        local lo_num=$(( hi_num - 1 ))
        local hi_ms lo_ms

        if ! hi_ms=$(_get_milestone_by_number "${hi_num}"); then
            echo "  WARN: could not fetch milestone ${hi_num} — skipping pair (${lo_num}, ${hi_num})" >&3
            hi_num="${lo_num}"
            continue
        fi
        if ! lo_ms=$(_get_milestone_by_number "${lo_num}"); then
            echo "  WARN: could not fetch milestone ${lo_num} — skipping pair (${lo_num}, ${hi_num})" >&3
            hi_num="${lo_num}"
            continue
        fi

        local hi_start lo_end
        hi_start=$(printf '%s' "${hi_ms}" | jq -r '.start_block // empty')
        lo_end=$(printf '%s' "${lo_ms}" | jq -r '.end_block // empty')
        if [[ -z "${hi_start}" || -z "${lo_end}" ]]; then
            echo "  WARN: milestone ${hi_num} or ${lo_num} missing start_block/end_block — skipping pair" >&3
            hi_num="${lo_num}"
            continue
        fi

        local expected_start=$(( lo_end + 1 ))
        echo "  milestone ${lo_num}: end_block=${lo_end}  →  milestone ${hi_num}: start_block=${hi_start}  (expected ${expected_start})" >&3

        if [[ "${hi_start}" -ne "${expected_start}" ]]; then
            echo "FAIL: milestone contiguity violated between milestone ${lo_num} and milestone ${hi_num}:" >&2
            echo "  milestone ${lo_num} end_block   = ${lo_end}" >&2
            echo "  milestone ${hi_num} start_block = ${hi_start}  (expected ${expected_start})" >&2
            if [[ "${hi_start}" -gt "${expected_start}" ]]; then
                echo "  GAP: blocks ${expected_start}–$(( hi_start - 1 )) have no milestone coverage." >&2
                echo "  These blocks cannot be fast-finalized and may remain unprotected." >&2
            else
                echo "  OVERLAP: blocks ${hi_start}–$(( expected_start - 1 )) are covered by two milestones." >&2
            fi
            failures=$(( failures + 1 ))
        fi

        hi_num="${lo_num}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} milestone contiguity violation(s) detected" >&2
        return 1
    fi
}

# bats test_tags=milestone,correctness
@test "heimdall milestone: end_block is not ahead of current Bor chain tip" {
    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local end_block
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block"
    fi

    local current_block
    if ! current_block=$(_bor_block_number); then
        skip "Could not read current block number from Bor"
    fi

    echo "  milestone end_block=${end_block}, Bor current block=${current_block}" >&3

    if [[ "${end_block}" -gt "${current_block}" ]]; then
        echo "FAIL: milestone end_block (${end_block}) is AHEAD of current Bor block (${current_block})" >&2
        echo "  Heimdall is finalizing a block that Bor has not produced yet." >&2
        echo "  This is only possible if Heimdall's block source is incorrect." >&2
        return 1
    fi

    local lag=$(( current_block - end_block ))
    echo "  OK: milestone end_block (${end_block}) <= Bor tip (${current_block}), lag=${lag} blocks" >&3
}
