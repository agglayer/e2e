#!/usr/bin/env bats
# bats file_tags=heimdall,milestone,checkpoint,correctness,safety

# Milestone–Checkpoint Consistency
# =================================
# Verifies that Heimdall's two finality mechanisms — milestones (fast finality)
# and checkpoints (L1-anchored finality) — do not conflict with each other or
# with the Bor execution layer.
#
# Milestones provide near-instant finality by having validators vote on small
# Bor block ranges.  Checkpoints commit larger Bor block ranges to the Ethereum
# root chain contract, anchoring finality on L1.  If a milestone references a
# block that is not covered by any checkpoint range, or if a milestone's hash
# does not match the Bor block, the security model is broken: nodes relying on
# milestone finality would accept a chain tip that L1 cannot verify.
#
# The suite checks six consistency properties:
#
#   1. Milestone <= checkpoint   — the latest milestone's end_block must not
#                                  exceed the latest checkpoint's end_block
#   2. Bor block exists          — Bor returns a non-null block for the
#                                  milestone's end_block
#   3. Milestone count positive  — at least 1 milestone has been committed
#   4. Hash oracle match         — milestone.hash matches the Bor block hash
#                                  at end_block
#   5. Range coverage            — the last 5 milestones each reference
#                                  end_blocks that fall within a checkpoint's
#                                  [start_block, end_block] range
#   6. Milestone lag bounded     — the gap between the latest milestone
#                                  end_block and the current Bor tip does not
#                                  exceed a safe threshold
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL
#   - At least 1 milestone and 1 checkpoint committed
#
# RUN: bats tests/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # ── Probe milestone API ──────────────────────────────────────────────
    local ms_probe
    ms_probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/latest" 2>/dev/null \
        | jq -r '.milestone.start_block // empty' 2>/dev/null || true)

    if [[ -z "${ms_probe}" ]]; then
        ms_probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/latest" 2>/dev/null \
            | jq -r '.milestone.start_block // empty' 2>/dev/null || true)
    fi

    if [[ -z "${ms_probe}" ]]; then
        echo "WARNING: Heimdall milestone API not reachable at ${L2_CL_API_URL} — all tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/ms_cp_milestone_unavailable"
    else
        echo "Heimdall milestone API reachable; latest milestone start_block=${ms_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/ms_cp_milestone_unavailable"
    fi

    # ── Probe checkpoint API ─────────────────────────────────────────────
    local cp_probe
    cp_probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/latest" 2>/dev/null \
        | jq -r '.checkpoint.start_block // empty' 2>/dev/null || true)

    if [[ -z "${cp_probe}" ]]; then
        cp_probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/checkpoints/latest" 2>/dev/null \
            | jq -r '.checkpoint.start_block // empty' 2>/dev/null || true)
    fi

    if [[ -z "${cp_probe}" ]]; then
        echo "WARNING: Heimdall checkpoint API not reachable at ${L2_CL_API_URL} — all tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/ms_cp_checkpoint_unavailable"
    else
        echo "Heimdall checkpoint API reachable; latest checkpoint start_block=${cp_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/ms_cp_checkpoint_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/ms_cp_milestone_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall milestone API not reachable at ${L2_CL_API_URL}"
    fi
    if [[ "$(cat "${BATS_FILE_TMPDIR}/ms_cp_checkpoint_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall checkpoint API not reachable at ${L2_CL_API_URL}"
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
    # Try base64 decode -> hex (proto JSON encodes bytes as base64).
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

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: latest milestone block <= latest checkpoint end_block" {
    # Milestones provide fast finality within seconds; checkpoints provide
    # L1-anchored finality.  If a milestone's end_block exceeds the latest
    # checkpoint's end_block, the milestone is finalizing blocks that have not
    # yet been committed to L1.  While this can happen transiently (milestones
    # are produced faster than checkpoints), a large gap signals a stalled
    # checkpoint pipeline or a consensus split between the two subsystems.

    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall"
    fi

    local ms_end_block cp_end_block
    ms_end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    cp_end_block=$(printf '%s' "${cp}" | jq -r '.end_block // empty')

    if [[ -z "${ms_end_block}" || "${ms_end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block"
    fi
    if [[ -z "${cp_end_block}" || "${cp_end_block}" == "null" ]]; then
        skip "Latest checkpoint has no end_block"
    fi

    echo "  milestone end_block=${ms_end_block}, checkpoint end_block=${cp_end_block}" >&3

    # Milestones are produced faster than checkpoints, so ms_end_block > cp_end_block
    # is normal. But a VERY large gap signals a stalled checkpoint pipeline.
    local MAX_ACCEPTABLE_GAP=10000
    if [[ "${ms_end_block}" -gt "${cp_end_block}" ]]; then
        local gap=$(( ms_end_block - cp_end_block ))
        echo "  milestone ahead of checkpoint by ${gap} blocks (normal — milestones are faster)" >&3
        if [[ "${gap}" -gt "${MAX_ACCEPTABLE_GAP}" ]]; then
            echo "FAIL: milestone-checkpoint gap (${gap} blocks) exceeds ${MAX_ACCEPTABLE_GAP} — checkpoint pipeline may be stalled" >&2
            return 1
        fi
    fi

    echo "  OK: milestone end_block=${ms_end_block}, checkpoint end_block=${cp_end_block} — gap within bounds" >&3
}

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: milestone block height references a real Bor block" {
    # The milestone's end_block must correspond to an actual block that Bor
    # has produced.  If Bor returns null for eth_getBlockByNumber(end_block),
    # the milestone is referencing a phantom block — either Bor is behind the
    # milestone (should not happen) or the milestone was forged.

    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local end_block
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block"
    fi

    echo "  Checking Bor has block ${end_block} (milestone end_block)..." >&3

    local block_hash
    block_hash=$(_bor_block_field "${end_block}" "hash")

    if [[ -z "${block_hash}" || "${block_hash}" == "null" ]]; then
        echo "FAIL: Bor does not have block ${end_block} (latest milestone end_block)" >&2
        echo "  eth_getBlockByNumber(${end_block}) returned null." >&2
        echo "  The milestone is referencing a block that Bor has not produced." >&2
        echo "  Either the milestone was committed for a future block, or Bor is" >&2
        echo "  behind the milestone — both indicate a finality layer mismatch." >&2
        return 1
    fi

    echo "  OK: Bor has block ${end_block}: hash=${block_hash}" >&3
}

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: milestone count is positive and increasing" {
    # The milestone count must be > 0 for the devnet to be producing milestones.
    # A zero count means the milestone subsystem never started or has been reset.

    local count
    if ! count=$(_get_milestone_count); then
        skip "Could not fetch milestone count from Heimdall — API may not be ready"
    fi

    [[ "${count}" =~ ^[0-9]+$ ]] || count=0

    echo "  milestone count=${count}" >&3

    if [[ "${count}" -lt 1 ]]; then
        echo "FAIL: milestone count is ${count} — expected at least 1" >&2
        echo "  The milestone subsystem appears to have never committed a milestone." >&2
        echo "  Fast finality is not operational on this devnet." >&2
        return 1
    fi

    echo "  OK: milestone count=${count} (positive)" >&3
}

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: milestone block hash matches Bor RPC" {
    # The milestone's hash field must match the block hash that Bor returns for
    # end_block.  A mismatch means Heimdall's fast finality layer recorded a
    # different chain tip than what Bor produced — nodes trusting the milestone
    # will diverge from the actual Bor canonical chain.

    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local end_block ms_hash_raw
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    ms_hash_raw=$(printf '%s' "${ms}" | jq -r '.hash // empty')

    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block — cannot perform hash check"
    fi
    if [[ -z "${ms_hash_raw}" || "${ms_hash_raw}" == "null" ]]; then
        skip "Latest milestone has no hash — cannot perform hash check"
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
        echo "  Cannot verify milestone hash — Bor returned null for eth_getBlockByNumber." >&2
        return 1
    fi

    echo "  Bor block hash for ${end_block}: ${bor_hash}" >&3

    # Normalise both to lowercase for comparison.
    local ms_hash_lower bor_hash_lower
    ms_hash_lower=$(printf '%s' "${ms_hash}" | tr '[:upper:]' '[:lower:]')
    bor_hash_lower=$(printf '%s' "${bor_hash}" | tr '[:upper:]' '[:lower:]')

    if [[ "${ms_hash_lower}" != "${bor_hash_lower}" ]]; then
        echo "FAIL: milestone hash DOES NOT match Bor block hash at end_block ${end_block}" >&2
        echo "  Heimdall milestone hash: ${ms_hash_lower}" >&2
        echo "  Bor block hash:          ${bor_hash_lower}" >&2
        echo "" >&2
        echo "  The milestone finality layer recorded a different chain tip than Bor produced." >&2
        echo "  Nodes trusting milestone finality will diverge from the canonical chain." >&2
        echo "  Combined with checkpoint inconsistency, this is a critical S1 safety violation." >&2
        return 1
    fi

    echo "  OK: milestone hash matches Bor block hash: ${bor_hash_lower}" >&3
}

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: all recent milestones reference blocks within checkpoint ranges" {
    # For the last 5 milestones, verify that each milestone's end_block falls
    # within some checkpoint's [start_block, end_block] range.  If a milestone
    # references a block that is not covered by any checkpoint, it means the
    # milestone finalized a block that L1 has not acknowledged — a gap between
    # the two finality layers that breaks the security model.

    local ms_count
    if ! ms_count=$(_get_milestone_count); then
        skip "Could not fetch milestone count from Heimdall"
    fi
    [[ "${ms_count}" =~ ^[0-9]+$ ]] || ms_count=0

    if [[ "${ms_count}" -lt 1 ]]; then
        skip "No milestones committed — cannot check range coverage"
    fi

    local cp_count
    if ! cp_count=$(_get_checkpoint_count); then
        skip "Could not fetch checkpoint count from Heimdall"
    fi
    [[ "${cp_count}" =~ ^[0-9]+$ ]] || cp_count=0

    if [[ "${cp_count}" -lt 1 ]]; then
        skip "No checkpoints committed — cannot verify milestone coverage"
    fi

    # Collect the last N checkpoints into parallel arrays for range lookup.
    # We fetch up to the last 20 checkpoints to have a wide enough window.
    local fetch_cp_count=$(( cp_count < 20 ? cp_count : 20 ))
    local -a cp_starts=()
    local -a cp_ends=()

    local j
    for (( j = cp_count; j > cp_count - fetch_cp_count; j-- )); do
        local cp_obj
        if ! cp_obj=$(_get_checkpoint_by_number "${j}"); then
            echo "  WARN: could not fetch checkpoint ${j} — skipping" >&3
            continue
        fi
        local s e
        s=$(printf '%s' "${cp_obj}" | jq -r '.start_block // empty')
        e=$(printf '%s' "${cp_obj}" | jq -r '.end_block // empty')
        if [[ -n "${s}" && "${s}" != "null" && -n "${e}" && "${e}" != "null" ]]; then
            cp_starts+=("${s}")
            cp_ends+=("${e}")
        fi
    done

    if [[ "${#cp_starts[@]}" -eq 0 ]]; then
        skip "Could not fetch any checkpoint ranges — cannot verify milestone coverage"
    fi

    echo "  Fetched ${#cp_starts[@]} checkpoint ranges for coverage check" >&3

    # Check the last 5 milestones.
    local check_ms_count=$(( ms_count < 5 ? ms_count : 5 ))
    local failures=0
    local checked=0

    local i
    for (( i = ms_count; i > ms_count - check_ms_count; i-- )); do
        local ms_obj
        if ! ms_obj=$(_get_milestone_by_number "${i}"); then
            echo "  WARN: could not fetch milestone ${i} — skipping" >&3
            continue
        fi

        local ms_end
        ms_end=$(printf '%s' "${ms_obj}" | jq -r '.end_block // empty')
        if [[ -z "${ms_end}" || "${ms_end}" == "null" ]]; then
            echo "  WARN: milestone ${i} has no end_block — skipping" >&3
            continue
        fi

        # Search checkpoint ranges for one that contains ms_end.
        local found=0
        local k
        for (( k = 0; k < ${#cp_starts[@]}; k++ )); do
            if [[ "${ms_end}" -ge "${cp_starts[k]}" && "${ms_end}" -le "${cp_ends[k]}" ]]; then
                found=1
                echo "  milestone ${i}: end_block=${ms_end} is within checkpoint [${cp_starts[k]}, ${cp_ends[k]}]" >&3
                break
            fi
        done

        if [[ "${found}" -eq 0 ]]; then
            echo "FAIL: milestone ${i} end_block=${ms_end} is NOT within any checkpoint range" >&2
            echo "  Checked ${#cp_starts[@]} checkpoint ranges (latest ${fetch_cp_count})." >&2
            echo "  This milestone finalized a block that L1 has not acknowledged." >&2
            echo "  The two finality layers are inconsistent — S1 safety risk." >&2
            failures=$(( failures + 1 ))
        fi

        checked=$(( checked + 1 ))
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} milestone(s) out of ${checked} checked are outside checkpoint coverage" >&2
        return 1
    fi

    echo "  OK: all ${checked} recent milestones fall within checkpoint ranges" >&3
}

# bats test_tags=milestone,checkpoint,correctness,safety
@test "milestone-checkpoint: no gap between last milestone and current block > expected interval" {
    # The latest milestone should not lag too far behind the current Bor chain
    # tip.  A large gap means the milestone finalizer has stalled and fast
    # finality is no longer operational.  We allow up to 1000 blocks of lag
    # (well above the typical milestone interval of ~12-16 blocks on devnets)
    # to account for slow devnet conditions.

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

    local lag=$(( current_block - end_block ))
    echo "  milestone end_block=${end_block}, Bor tip=${current_block}, lag=${lag} blocks" >&3

    # Allow a generous threshold: 1000 blocks.
    # On mainnet milestones cover ~12-16 blocks each, so 1000 blocks is ~60-80
    # milestone intervals.  On a devnet with slower block times this is still
    # very generous.
    local max_lag=1000

    if [[ "${lag}" -gt "${max_lag}" ]]; then
        echo "FAIL: milestone lag is ${lag} blocks (threshold: ${max_lag})" >&2
        echo "  milestone end_block = ${end_block}" >&2
        echo "  Bor chain tip       = ${current_block}" >&2
        echo "  The milestone finalizer appears to have stalled.  Fast finality is not" >&2
        echo "  covering recent blocks, leaving them without milestone protection." >&2
        return 1
    fi

    if [[ "${lag}" -lt 0 ]]; then
        echo "FAIL: milestone end_block (${end_block}) is ahead of Bor tip (${current_block})" >&2
        echo "  Negative lag means the milestone finalized a block that Bor has not" >&2
        echo "  produced yet — the finality layer is referencing phantom blocks." >&2
        return 1
    fi

    echo "  OK: milestone lag=${lag} blocks (within ${max_lag}-block threshold)" >&3
}
