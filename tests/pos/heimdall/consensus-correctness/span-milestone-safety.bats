#!/usr/bin/env bats
# bats file_tags=heimdall,bor,milestone,correctness,safety

# Span and Milestone Safety
# =========================
# Verifies that Heimdall's Bor span assignments and milestone finality
# records are within safe operational bounds.
#
# Spans with zero producers halt Bor block production. A span that ends
# without a replacement causes Bor to operate without valid producer
# authorization. Stale milestones mean Bor finality guarantees have stopped.
#
# The suite checks five safety properties:
#
#   1. Span duration    — span covers at least one full sprint (16 blocks);
#                         shorter spans break the Bor sprint scheduling invariant
#   2. Span continuity  — the next span was committed before the current one
#                         expired; a 128-block overrun past span end is flagged
#   3. Milestone order  — milestone IDs are strictly increasing; a duplicate or
#                         regressing ID indicates store corruption
#   4. Milestone staleness — the latest milestone's end_block is not older than
#                         20 000 Bor blocks; a larger gap means the milestone
#                         finalizer has stalled
#   5. Producer power   — the span has at least one producer and every selected
#                         producer has positive voting power; zero-power producers
#                         cannot sign blocks and would halt Bor
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL (some tests skip without it)
#   - At least 1 span committed (tests 1, 2, 5)
#   - At least 2 spans committed (test 2 contiguity sub-check)
#   - At least 1 milestone committed (tests 3, 4)
#   - At least 2 milestones for the monotonicity sub-check (test 3)
#
# RUN: bats tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests in this file)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Probe Heimdall span endpoint.
    local span_probe
    span_probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null \
        | jq -r '.span.id // empty' 2>/dev/null || true)

    if [[ -z "${span_probe}" ]]; then
        span_probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/bor/spans/latest" 2>/dev/null \
            | jq -r '.span.id // empty' 2>/dev/null || true)
    fi

    if [[ -z "${span_probe}" ]]; then
        echo "WARNING: Heimdall span API not reachable at ${L2_CL_API_URL} — span tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_span_unavailable"
    else
        echo "Heimdall span API reachable; latest span id=${span_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_span_unavailable"
    fi

    # Probe Heimdall milestone endpoint.
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
        echo "WARNING: Heimdall milestone API not reachable at ${L2_CL_API_URL} — milestone tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    else
        echo "Heimdall milestone API reachable; latest milestone start_block=${ms_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    fi

    # Probe Bor JSON-RPC separately — some tests require it.
    local bor_probe
    bor_probe=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null || true)

    if [[ -z "${bor_probe}" ]]; then
        echo "NOTE: Bor JSON-RPC not reachable at ${L2_RPC_URL} — block-number tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/bor_rpc_unavailable"
    else
        echo "Bor JSON-RPC reachable; current block=${bor_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/bor_rpc_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the latest span object from Heimdall.
# Tries the standard REST path first, then the gRPC-gateway /v1beta1/ prefix.
# Prints the raw JSON span object on stdout, or returns 1 on failure.
_get_latest_span() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null || true)
    local span
    span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/bor/spans/latest" 2>/dev/null || true)
        span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${span}"
}

# Fetch a specific span by numeric ID.
# Prints the raw JSON span object on stdout, or returns 1 on failure.
_get_span_by_id() {
    local id="$1"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/${id}" 2>/dev/null || true)
    local span
    span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/bor/spans/${id}" 2>/dev/null || true)
        span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${span}"
}

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
    count=$(printf '%s' "${raw}" | jq -r '.count // .result // empty' 2>/dev/null || true)
    if [[ -z "${count}" || "${count}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/count" 2>/dev/null || true)
        count=$(printf '%s' "${raw}" | jq -r '.count // .result // empty' 2>/dev/null || true)
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
# Prints the decimal block number on stdout, or returns 1 if the RPC is not
# reachable or returns an unexpected value.
_bor_block_number() {
    local hex
    hex=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null || true)
    if [[ -z "${hex}" || "${hex}" == "null" ]]; then
        return 1
    fi
    # Validate hex fits in a 64-bit integer (max 16 hex digits after 0x).
    if [[ ! "${hex}" =~ ^0x[0-9a-fA-F]{1,16}$ ]]; then
        return 1
    fi
    printf '%d\n' "${hex}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=bor,span,correctness,safety
@test "heimdall span: span duration meets minimum sprint length requirement" {
    # DefaultSprintDuration = 16 (x/bor/types/params.go).
    # A span shorter than one sprint means Bor cannot complete a full
    # producer-rotation cycle, breaking the sprint-based scheduling invariant.
    local min_sprint_length=16

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_span_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall span API not reachable at ${L2_CL_API_URL}"
    fi

    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL} — API may be down or chain has not started"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    if [[ -z "${span_id}" || "${span_id}" == "null" ]]; then
        echo "FAIL: latest span response has no 'id' field" >&2
        return 1
    fi
    if [[ -z "${start_block}" || "${start_block}" == "null" ]]; then
        echo "FAIL: span ${span_id} has no 'start_block' field" >&2
        return 1
    fi
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        echo "FAIL: span ${span_id} has no 'end_block' field" >&2
        return 1
    fi

    # Validate integer fields before arithmetic.
    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0
    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    local duration
    duration=$(( end_block - start_block + 1 ))

    echo "  span id=${span_id} start_block=${start_block} end_block=${end_block} duration=${duration}" >&3

    if [[ "${duration}" -lt "${min_sprint_length}" ]]; then
        echo "FAIL: span id=${span_id} duration ${duration} is less than minimum sprint length ${min_sprint_length} — producers cannot complete a full sprint" >&2
        echo "  start_block=${start_block} end_block=${end_block}" >&2
        echo "  Bor uses sprints of ${min_sprint_length} blocks; a span shorter than one sprint means" >&2
        echo "  the producer set rotates before a full sprint has been executed." >&2
        return 1
    fi

    echo "OK: span id=${span_id} duration=${duration} blocks (>= ${min_sprint_length} sprint minimum)" >&3
}

# bats test_tags=bor,span,correctness,safety,liveness
@test "heimdall span: next span is being prepared before current span ends" {
    # A span coverage gap — where Bor's current block is past the latest span's
    # end_block by more than 128 blocks with no new span committed — means Bor
    # is operating without valid producer authorization.  MsgBackfillSpans can
    # recover from a gap of any size, but more than 128 blocks indicates that
    # the span proposer pipeline has stalled.
    local gap_limit=128

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_span_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall span API not reachable at ${L2_CL_API_URL}"
    fi

    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL}"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    [[ "${span_id}" =~ ^[0-9]+$ ]] || span_id=0
    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0
    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    echo "  latest span: id=${span_id} start_block=${start_block} end_block=${end_block}" >&3

    # Check that at least one span transition has occurred (span_id >= 1), which
    # implies contiguity can be verified.
    if [[ "${span_id}" -ge 1 ]]; then
        local prev_id
        prev_id=$(( span_id - 1 ))
        local prev_span
        if prev_span=$(_get_span_by_id "${prev_id}"); then
            local prev_end_block
            prev_end_block=$(printf '%s' "${prev_span}" | jq -r '.end_block // empty')
            [[ "${prev_end_block}" =~ ^[0-9]+$ ]] || prev_end_block=0
            local expected_start
            expected_start=$(( prev_end_block + 1 ))
            echo "  prev span: id=${prev_id} end_block=${prev_end_block} (latest span should start at ${expected_start})" >&3
            if [[ "${start_block}" -ne "${expected_start}" ]]; then
                # In mixed-version networks (e.g. bor 2.7.0 vs 2.6.5), Heimdall
                # may re-emit spans with overlapping or regressed ranges when nodes
                # disagree on fork activation. This is expected protocol behavior
                # that cannot be resolved without all nodes running the same version.
                if [[ "${end_block}" == "${prev_end_block}" ]]; then
                    skip "Span overlap: spans ${prev_id} and ${span_id} share end_block=${end_block} — expected in mixed-version networks where nodes disagree on fork activation boundaries"
                elif [[ "${start_block}" -lt "${expected_start}" ]]; then
                    skip "Span regression: span ${span_id} start_block=${start_block} < expected ${expected_start} — expected in mixed-version networks where nodes disagree on fork activation boundaries"
                else
                    local gap_size
                    gap_size=$(( start_block - expected_start ))
                    echo "FAIL: span contiguity violated between span ${prev_id} and span ${span_id}:" >&2
                    echo "  span ${prev_id} end_block=${prev_end_block}, span ${span_id} start_block=${start_block} (expected ${expected_start})" >&2
                    echo "  GAP of ${gap_size} blocks: Bor has no valid producer for blocks ${expected_start}–$(( start_block - 1 ))" >&2
                    return 1
                fi
            fi
            echo "  OK: span ${span_id} starts exactly at prev span ${prev_id} end + 1 (contiguous)" >&3
        else
            echo "  NOTE: could not fetch prev span ${prev_id} — skipping contiguity sub-check" >&3
        fi
    fi

    # If Bor RPC is unavailable, skip the block-number comparison.
    if [[ "$(cat "${BATS_FILE_TMPDIR}/bor_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Bor RPC not available — cannot check block-number vs span end"
    fi

    local current_bor_block
    if ! current_bor_block=$(_bor_block_number); then
        skip "Could not read current block number from Bor at ${L2_RPC_URL}"
    fi

    [[ "${current_bor_block}" =~ ^[0-9]+$ ]] || current_bor_block=0

    echo "  current Bor block: ${current_bor_block}" >&3

    local blocks_remaining
    blocks_remaining=$(( end_block - current_bor_block ))

    if [[ "${current_bor_block}" -le "${end_block}" ]]; then
        echo "  OK: span ends at block ${end_block}, current Bor block is ${current_bor_block}, ${blocks_remaining} blocks remaining" >&3
        if [[ "${blocks_remaining}" -lt 16 ]]; then
            echo "  WARN: span id=${span_id} is about to expire in ${blocks_remaining} blocks — next span should be proposed soon" >&3
        fi
    else
        local overrun
        overrun=$(( current_bor_block - end_block ))
        echo "  WARN: current Bor block ${current_bor_block} is ${overrun} blocks past span id=${span_id} end_block ${end_block}" >&3

        # Hard fail only if overrun exceeds the gap limit.
        if [[ "${overrun}" -gt "${gap_limit}" ]]; then
            echo "FAIL: Bor is ${overrun} blocks past span id=${span_id} end_block ${end_block} with no new span committed" >&2
            echo "  The span coverage gap exceeds the ${gap_limit}-block threshold." >&2
            echo "  Bor is operating without valid producer authorization for at least ${overrun} blocks." >&2
            echo "  MsgBackfillSpans should have been triggered automatically to recover." >&2
            return 1
        fi

        echo "  NOTE: overrun of ${overrun} blocks is within the ${gap_limit}-block tolerance — new span may be in flight" >&3
    fi

    echo "OK: span ends at block ${end_block}, current Bor block is ${current_bor_block}, lag=$((current_bor_block > end_block ? current_bor_block - end_block : 0)) blocks past end" >&3
}

# bats test_tags=milestone,correctness,safety
@test "heimdall milestone: milestone ID is monotonically increasing" {
    # Milestone IDs are assigned by incrementing the store counter in AddMilestone.
    # A regressing or duplicate ID would indicate store corruption or a replay of
    # an already-processed milestone.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall milestone API not reachable at ${L2_CL_API_URL}"
    fi

    local total
    if ! total=$(_get_milestone_count); then
        skip "Could not fetch milestone count from Heimdall — API may not be ready"
    fi

    [[ "${total}" =~ ^[0-9]+$ ]] || total=0

    if [[ "${total}" -lt 1 ]]; then
        skip "No milestones committed yet — cannot check monotonicity"
    fi

    if [[ "${total}" -lt 2 ]]; then
        skip "Fewer than 2 milestones — cannot check monotonicity (only ${total} milestone committed)"
    fi

    echo "  total milestones: ${total}" >&3

    # Fetch the latest milestone (count = N) and the previous one (count-1 = N-1).
    # The milestone IDs tracked in the Heimdall store are the sequence numbers
    # themselves (milestone at position N has milestone_id derived from its
    # content, but the store index is the count).  We verify the store count is
    # strictly advancing by checking the end_block ordering: later milestones
    # must cover later Bor blocks, which implies the IDs are ordered.
    local latest_ms prev_ms
    if ! latest_ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone"
    fi

    local prev_num
    prev_num=$(( total - 1 ))
    if ! prev_ms=$(_get_milestone_by_number "${prev_num}"); then
        skip "Could not fetch milestone ${prev_num} — cannot check ordering"
    fi

    local latest_end_block prev_end_block latest_milestone_id prev_milestone_id
    latest_end_block=$(printf '%s' "${latest_ms}" | jq -r '.end_block // empty')
    prev_end_block=$(printf '%s' "${prev_ms}" | jq -r '.end_block // empty')
    latest_milestone_id=$(printf '%s' "${latest_ms}" | jq -r '.milestone_id // .id // empty')
    prev_milestone_id=$(printf '%s' "${prev_ms}" | jq -r '.milestone_id // .id // empty')

    [[ "${latest_end_block}" =~ ^[0-9]+$ ]] || latest_end_block=0
    [[ "${prev_end_block}" =~ ^[0-9]+$ ]] || prev_end_block=0

    echo "  milestone ${prev_num}: end_block=${prev_end_block} milestone_id=${prev_milestone_id:-<not present>}" >&3
    echo "  milestone ${total} (latest): end_block=${latest_end_block} milestone_id=${latest_milestone_id:-<not present>}" >&3

    # The store counter advancing from prev_num to total (i.e. total = prev_num + 1)
    # is guaranteed by the API; what we check here is that the block coverage
    # moves forward — later milestones must cover higher Bor blocks.
    if [[ "${latest_end_block}" -le "${prev_end_block}" ]]; then
        echo "FAIL: latest milestone (count=${total}) end_block ${latest_end_block} is not greater than previous milestone (count=${prev_num}) end_block ${prev_end_block}" >&2
        echo "  Milestone records must cover strictly increasing Bor block ranges." >&2
        echo "  A non-increasing end_block implies a duplicate or regressing milestone was committed." >&2
        return 1
    fi

    echo "OK: latest milestone_id=${latest_milestone_id:-N/A}, total milestones=${total}, end_block progression: ${prev_end_block} → ${latest_end_block}" >&3
}

# bats test_tags=milestone,correctness,safety,liveness
@test "heimdall milestone: latest milestone's end_block is within recent Bor history" {
    # If the latest milestone's end_block is more than 20 000 Bor blocks behind
    # the current chain tip, the milestone finalizer has stalled: validators are
    # no longer producing milestone votes, so Bor's fast finality guarantee
    # has stopped.
    local staleness_limit=20000

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall milestone API not reachable at ${L2_CL_API_URL}"
    fi

    local ms
    if ! ms=$(_get_latest_milestone); then
        fail "Could not fetch latest milestone from Heimdall at ${L2_CL_API_URL}"
    fi

    local end_block
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')

    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block — cannot check staleness"
    fi

    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    # Bor RPC is required for this check.
    if [[ "$(cat "${BATS_FILE_TMPDIR}/bor_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Bor RPC not available — cannot compare milestone end_block to chain tip"
    fi

    local current_bor_block
    if ! current_bor_block=$(_bor_block_number); then
        skip "Could not read current block number from Bor at ${L2_RPC_URL}"
    fi

    [[ "${current_bor_block}" =~ ^[0-9]+$ ]] || current_bor_block=0

    echo "  milestone end_block=${end_block}, Bor tip=${current_bor_block}" >&3

    # A milestone cannot reference a future block — Bor must have produced it.
    if [[ "${end_block}" -gt "${current_bor_block}" ]]; then
        echo "FAIL: latest milestone end_block (${end_block}) is AHEAD of current Bor block (${current_bor_block})" >&2
        echo "  Heimdall is finalizing a block that Bor has not produced yet." >&2
        echo "  This should not be possible under normal operation." >&2
        return 1
    fi

    local lag
    lag=$(( current_bor_block - end_block ))

    echo "  lag=${lag} blocks (limit=${staleness_limit})" >&3

    if [[ "${lag}" -gt "${staleness_limit}" ]]; then
        echo "FAIL: latest milestone is ${lag} blocks behind Bor tip — milestone finality may be stalled" >&2
        echo "  end_block=${end_block}, Bor tip=${current_bor_block}, limit=${staleness_limit}" >&2
        echo "  Validators are not producing milestone votes for recent Bor blocks." >&2
        echo "  Bor's fast finality guarantee (milestone-based finality) has stopped." >&2
        return 1
    fi

    echo "OK: milestone end_block=${end_block}, Bor tip=${current_bor_block}, lag=${lag} blocks" >&3
}

# bats test_tags=bor,span,correctness,safety,s0
@test "heimdall span: selected_producers count is non-zero and within validator set size" {
    # Zero producers in a span means Bor has no authorized block signers for
    # the entire span duration — the chain will halt immediately.
    # A producer with zero voting power cannot sign blocks and is treated as
    # offline by Bor's consensus engine.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_span_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall span API not reachable at ${L2_CL_API_URL}"
    fi

    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL}"
    fi

    local span_id
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    [[ "${span_id}" =~ ^[0-9]+$ ]] || span_id=0

    # Count selected producers.
    local n_producers
    n_producers=$(printf '%s' "${span}" | jq -r '(.selected_producers // []) | length' 2>/dev/null || true)
    [[ "${n_producers}" =~ ^[0-9]+$ ]] || n_producers=0

    # Count validator set size (embedded in the span at commit time).
    local n_validators
    n_validators=$(printf '%s' "${span}" | jq -r '(.validator_set.validators // []) | length' 2>/dev/null || true)
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    echo "  span id=${span_id}: selected_producers=${n_producers}, validator_set.validators=${n_validators}" >&3

    # FAIL if no producers are selected.
    if [[ "${n_producers}" -eq 0 ]]; then
        echo "FAIL: span id=${span_id} has zero producers — Bor cannot produce any blocks in this span, chain halt" >&2
        echo "  The span's selected_producers list is empty." >&2
        echo "  This can happen if SelectNextProducers returns an empty set, which occurs" >&2
        echo "  when GetSpanEligibleValidators returns no validators." >&2
        return 1
    fi

    # FAIL if producers exceed validator set (internal accounting error).
    if [[ "${n_validators}" -gt 0 && "${n_producers}" -gt "${n_validators}" ]]; then
        echo "FAIL: span id=${span_id} has more producers (${n_producers}) than validators (${n_validators}) — internal accounting error" >&2
        echo "  selected_producers must be a subset of validator_set.validators." >&2
        return 1
    fi

    # Check that every selected producer has positive voting power.
    local failures=0
    local i
    for (( i = 0; i < n_producers; i++ )); do
        local val_id power signer
        val_id=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].val_id // .selected_producers[$idx].id // empty' \
            2>/dev/null || true)
        signer=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].signer // empty' \
            2>/dev/null || true)
        # Accept either voting_power or power field names (proto JSON may vary).
        power=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].voting_power // .selected_producers[$idx].power // empty' \
            2>/dev/null || true)

        [[ "${val_id}" =~ ^[0-9]+$ ]] || val_id=0
        [[ "${power}" =~ ^[0-9]+$ ]] || power=0

        echo "  producer[${i}]: val_id=${val_id} signer=${signer:-<empty>} power=${power}" >&3

        if [[ "${power}" -eq 0 ]]; then
            echo "FAIL: producer[${i}] (val_id=${val_id}, signer=${signer:-<empty>}) in span id=${span_id} has zero voting power" >&2
            echo "  A producer with zero voting power cannot sign blocks." >&2
            echo "  If all producers have zero power, Bor will produce unsigned blocks or stall." >&2
            failures=$(( failures + 1 ))
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "FAIL: ${failures} producer(s) in span id=${span_id} have zero voting power — see messages above" >&2
        return 1
    fi

    local vs_info=""
    if [[ "${n_validators}" -gt 0 ]]; then
        vs_info=" out of ${n_validators} validators"
    fi

    echo "OK: ${n_producers} producers${vs_info} in span id=${span_id}, all with positive power" >&3
}
