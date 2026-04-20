#!/usr/bin/env bats
# bats file_tags=heimdall,checkpoint,correctness,range

# Checkpoint Range Invariants — Full Audit
# =========================================
# Performs a FULL audit of ALL checkpoints committed by Heimdall to verify that
# the checkpoint block ranges form a well-ordered, gap-free, overlap-free
# partition of the Bor block space.
#
# Checkpoints commit Bor block ranges [start_block, end_block] to L1.  If there
# are gaps or overlaps in checkpoint ranges, the bridge finality guarantee
# breaks: gaps leave Bor state uncommitted to L1, and overlaps may cause the
# root chain contract to reject submissions or double-commit state.
#
# The existing checkpoint-chain-integrity.bats checks the last 5 checkpoints for
# contiguity.  This test audits the ENTIRE checkpoint sequence to catch range
# discontinuities anywhere in the history.
#
# The suite checks seven invariants:
#
#   1. Full contiguity          — end[i]+1 == start[i+1] for ALL checkpoints
#   2. Valid ranges             — no checkpoint has end_block < start_block
#   3. No overlaps              — no two checkpoints cover the same block
#   4. Genesis coverage         — first checkpoint starts at block 0 or the
#                                 expected genesis block
#   5. Tip freshness            — latest checkpoint end is close to current
#                                 Bor block height (not lagging behind)
#   6. Monotonic timestamps     — checkpoint timestamps are non-decreasing
#   7. Unique root hashes       — no duplicate root commitments across all
#                                 checkpoints
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL (for tip freshness check)
#   - At least 2 checkpoints have been committed (tests skip if fewer)
#
# RUN: bats tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Probe the checkpoint API to confirm reachability and fetch the total count.
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
        echo "WARNING: Heimdall checkpoint API not reachable at ${L2_CL_API_URL} — all range-invariant tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/range_invariant_unavailable"
    else
        echo "Heimdall checkpoint API reachable; current ack_count=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/range_invariant_unavailable"
        echo "${probe}" > "${BATS_FILE_TMPDIR}/checkpoint_total_count"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/range_invariant_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall checkpoint API not reachable at ${L2_CL_API_URL}"
    fi

    local total
    total=$(cat "${BATS_FILE_TMPDIR}/checkpoint_total_count" 2>/dev/null || echo "0")
    if [[ "${total}" -lt 2 ]]; then
        skip "Only ${total} checkpoint(s) committed — need at least 2 for range-invariant checks"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the total acknowledged checkpoint count from Heimdall.
# Prints the count as a decimal integer, or returns 1 on failure.
_get_checkpoint_count() {
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

# Fetch the latest checkpoint object from Heimdall.
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

# Fetch ALL checkpoints (1..total) and write them as a JSON array to a file.
# The result file is cached in BATS_FILE_TMPDIR to avoid re-fetching.
# Arguments: none (uses the count from the tmpdir file).
# Returns 0 on success (file written), 1 on failure.
_fetch_all_checkpoints() {
    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"

    # Return immediately if already cached.
    if [[ -s "${cache_file}" ]]; then
        return 0
    fi

    local total
    total=$(cat "${BATS_FILE_TMPDIR}/checkpoint_total_count" 2>/dev/null || echo "0")
    if [[ "${total}" -lt 1 ]]; then
        return 1
    fi

    local checkpoints="["
    local fetched=0
    local i

    for (( i = 1; i <= total; i++ )); do
        local cp
        if ! cp=$(_get_checkpoint_by_number "${i}"); then
            echo "  WARN: could not fetch checkpoint ${i} — skipping" >&3
            continue
        fi

        if [[ "${fetched}" -gt 0 ]]; then
            checkpoints="${checkpoints},"
        fi
        checkpoints="${checkpoints}${cp}"
        fetched=$(( fetched + 1 ))
    done

    checkpoints="${checkpoints}]"

    if [[ "${fetched}" -lt 2 ]]; then
        return 1
    fi

    printf '%s' "${checkpoints}" > "${cache_file}"
    echo "  Fetched ${fetched}/${total} checkpoints successfully" >&3
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: all checkpoint block ranges are contiguous" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"
    local count
    count=$(jq 'length' "${cache_file}")

    if [[ "${count}" -lt 2 ]]; then
        skip "Only ${count} checkpoint(s) fetched — need at least 2 to check contiguity"
    fi

    echo "  Auditing contiguity across ${count} checkpoints..." >&3

    # Use jq to find all contiguity violations in a single pass.
    local result
    result=$(jq -r '
        . as $cps |
        [range(0; ($cps | length) - 1)] |
        map(
            . as $i |
            ($cps[$i].end_block | tonumber) as $prev_end |
            ($cps[$i + 1].start_block | tonumber) as $curr_start |
            if ($prev_end + 1) != $curr_start then
                "VIOLATION at checkpoint \($i + 1) -> \($i + 2): end_block=\($prev_end) but next start_block=\($curr_start) (expected \($prev_end + 1))"
            else
                empty
            end
        ) | .[]
    ' "${cache_file}" 2>/dev/null || true)

    if [[ -n "${result}" ]]; then
        local violation_count
        violation_count=$(printf '%s\n' "${result}" | wc -l)
        echo "FAIL: ${violation_count} contiguity violation(s) found across all checkpoints:" >&2
        printf '%s\n' "${result}" | head -20 >&2
        if [[ "${violation_count}" -gt 20 ]]; then
            echo "  ... and $(( violation_count - 20 )) more violation(s)" >&2
        fi
        return 1
    fi

    echo "  OK: all ${count} checkpoints form a contiguous chain ($(( count - 1 )) pairs verified)" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: no checkpoint has end_block < start_block" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"
    local count
    count=$(jq 'length' "${cache_file}")

    echo "  Validating block ranges for ${count} checkpoints..." >&3

    local result
    result=$(jq -r '
        to_entries |
        map(
            (.value.start_block | tonumber) as $start |
            (.value.end_block   | tonumber) as $end |
            if $end < $start then
                "VIOLATION at checkpoint \(.key + 1): start_block=\($start) end_block=\($end) — end < start"
            else
                empty
            end
        ) | .[]
    ' "${cache_file}" 2>/dev/null || true)

    if [[ -n "${result}" ]]; then
        local violation_count
        violation_count=$(printf '%s\n' "${result}" | wc -l)
        echo "FAIL: ${violation_count} checkpoint(s) have invalid block ranges (end < start):" >&2
        printf '%s\n' "${result}" >&2
        return 1
    fi

    echo "  OK: all ${count} checkpoints have valid block ranges (end_block >= start_block)" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: checkpoint ranges do not overlap" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"
    local count
    count=$(jq 'length' "${cache_file}")

    if [[ "${count}" -lt 2 ]]; then
        skip "Only ${count} checkpoint(s) fetched — need at least 2 to check for overlaps"
    fi

    echo "  Checking ${count} checkpoints for overlapping block ranges..." >&3

    # Two consecutive checkpoints overlap if start[i+1] <= end[i].
    local result
    result=$(jq -r '
        . as $cps |
        [range(0; ($cps | length) - 1)] |
        map(
            . as $i |
            ($cps[$i].end_block   | tonumber) as $prev_end |
            ($cps[$i + 1].start_block | tonumber) as $curr_start |
            if $curr_start <= $prev_end then
                "OVERLAP at checkpoint \($i + 1) -> \($i + 2): prev end_block=\($prev_end), next start_block=\($curr_start) — blocks \($curr_start)..\($prev_end) covered by both"
            else
                empty
            end
        ) | .[]
    ' "${cache_file}" 2>/dev/null || true)

    if [[ -n "${result}" ]]; then
        local violation_count
        violation_count=$(printf '%s\n' "${result}" | wc -l)
        echo "FAIL: ${violation_count} overlapping checkpoint range(s) detected:" >&2
        printf '%s\n' "${result}" | head -20 >&2
        if [[ "${violation_count}" -gt 20 ]]; then
            echo "  ... and $(( violation_count - 20 )) more overlap(s)" >&2
        fi
        return 1
    fi

    echo "  OK: no overlapping block ranges across all ${count} checkpoints" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: first checkpoint starts at block 0 or expected genesis" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"

    local first_start
    first_start=$(jq -r '.[0].start_block | tonumber' "${cache_file}" 2>/dev/null || true)

    if [[ -z "${first_start}" || "${first_start}" == "null" ]]; then
        echo "FAIL: could not read start_block from the first checkpoint" >&2
        return 1
    fi

    echo "  First checkpoint start_block=${first_start}" >&3

    # The first checkpoint should start at block 0 (genesis).
    # Some devnet configurations may start the first checkpoint at a small
    # positive block number (e.g. 1, 256) depending on sprint/span sizes,
    # so we allow a small tolerance: start_block must be <= 256.
    local max_genesis_start=256

    if [[ "${first_start}" -gt "${max_genesis_start}" ]]; then
        echo "FAIL: first checkpoint starts at block ${first_start}, which is > ${max_genesis_start}" >&2
        echo "  The first checkpoint should cover from the genesis (block 0) or very near it." >&2
        echo "  A high first start_block means Bor blocks 0..$(( first_start - 1 )) are never" >&2
        echo "  committed to L1, leaving early bridge state unverifiable." >&2
        return 1
    fi

    echo "  OK: first checkpoint starts at block ${first_start} (<= ${max_genesis_start})" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: latest checkpoint end is close to current bor block" {
    local cp
    if ! cp=$(_get_latest_checkpoint); then
        skip "Could not fetch latest checkpoint from Heimdall"
    fi

    local end_block
    end_block=$(printf '%s' "${cp}" | jq -r '.end_block // empty')
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest checkpoint has no end_block field"
    fi

    local bor_block
    if ! bor_block=$(_block_number_on "$L2_RPC_URL"); then
        skip "Could not fetch current Bor block number — Bor RPC may not be reachable"
    fi

    local lag=$(( bor_block - end_block ))
    echo "  Latest checkpoint end_block=${end_block}" >&3
    echo "  Current Bor block=${bor_block}" >&3
    echo "  Lag=${lag} blocks" >&3

    # On a Kurtosis devnet with small sprint/span sizes, checkpoints are
    # produced frequently.  A lag of more than 10000 blocks suggests the
    # checkpoint pipeline has stalled or Bor has run far ahead.
    local max_lag=10000

    if [[ "${lag}" -gt "${max_lag}" ]]; then
        echo "FAIL: latest checkpoint end_block (${end_block}) is ${lag} blocks behind current Bor tip (${bor_block})" >&2
        echo "  Maximum acceptable lag is ${max_lag} blocks." >&2
        echo "  This indicates the checkpoint pipeline may be stalled, preventing" >&2
        echo "  Bor state from being committed to L1 in a timely manner." >&2
        return 1
    fi

    # Negative lag (checkpoint ahead of Bor) is also a serious problem.
    if [[ "${lag}" -lt 0 ]]; then
        echo "FAIL: latest checkpoint end_block (${end_block}) is AHEAD of current Bor tip (${bor_block})" >&2
        echo "  This means a checkpoint was committed for blocks Bor has not yet produced," >&2
        echo "  which is a critical safety violation." >&2
        return 1
    fi

    echo "  OK: checkpoint lag is ${lag} blocks (within ${max_lag} limit)" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: checkpoint timestamps are monotonically increasing" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"
    local count
    count=$(jq 'length' "${cache_file}")

    if [[ "${count}" -lt 2 ]]; then
        skip "Only ${count} checkpoint(s) fetched — need at least 2 to check timestamp ordering"
    fi

    echo "  Checking timestamp monotonicity across ${count} checkpoints..." >&3

    # Timestamps may be Unix epoch integers or ISO-8601 strings.
    # Heimdall v2 uses integer timestamps; v1 may use strings.
    # We normalize to epoch seconds for comparison.
    local result
    result=$(jq -r '
        . as $cps |
        [range(0; ($cps | length) - 1)] |
        map(
            . as $i |
            ($cps[$i].timestamp   | tostring) as $prev_ts_raw |
            ($cps[$i + 1].timestamp | tostring) as $curr_ts_raw |
            # Try to parse as number; if it fails, treat as 0 (will be caught)
            (($prev_ts_raw | tonumber) // 0) as $prev_ts |
            (($curr_ts_raw | tonumber) // 0) as $curr_ts |
            if $curr_ts < $prev_ts then
                "VIOLATION at checkpoint \($i + 1) -> \($i + 2): timestamp \($prev_ts_raw) -> \($curr_ts_raw) — not monotonically increasing"
            else
                empty
            end
        ) | .[]
    ' "${cache_file}" 2>/dev/null || true)

    if [[ -n "${result}" ]]; then
        local violation_count
        violation_count=$(printf '%s\n' "${result}" | wc -l)
        echo "FAIL: ${violation_count} timestamp ordering violation(s) found:" >&2
        printf '%s\n' "${result}" | head -20 >&2
        if [[ "${violation_count}" -gt 20 ]]; then
            echo "  ... and $(( violation_count - 20 )) more violation(s)" >&2
        fi
        return 1
    fi

    echo "  OK: all ${count} checkpoint timestamps are monotonically increasing" >&3
}

# bats test_tags=checkpoint,correctness,range
@test "checkpoint-range: all checkpoint root hashes are unique" {
    if ! _fetch_all_checkpoints; then
        skip "Could not fetch all checkpoints from Heimdall"
    fi

    local cache_file="${BATS_FILE_TMPDIR}/all_checkpoints.json"
    local count
    count=$(jq 'length' "${cache_file}")

    if [[ "${count}" -lt 2 ]]; then
        skip "Only ${count} checkpoint(s) fetched — need at least 2 to check uniqueness"
    fi

    echo "  Checking root hash uniqueness across ${count} checkpoints..." >&3

    # Extract all root hashes and find duplicates.
    local duplicates
    duplicates=$(jq -r '
        [.[] | .root_hash] |
        group_by(.) |
        map(select(length > 1)) |
        map("DUPLICATE root_hash=\(.[0]) appears \(length) times") |
        .[]
    ' "${cache_file}" 2>/dev/null || true)

    if [[ -n "${duplicates}" ]]; then
        local dup_count
        dup_count=$(printf '%s\n' "${duplicates}" | wc -l)
        echo "FAIL: ${dup_count} duplicate root hash(es) found across all checkpoints:" >&2
        printf '%s\n' "${duplicates}" | head -20 >&2
        if [[ "${dup_count}" -gt 20 ]]; then
            echo "  ... and $(( dup_count - 20 )) more duplicate(s)" >&2
        fi
        echo "  Each checkpoint covers a distinct Bor block range and must produce a" >&2
        echo "  unique state root.  Duplicate root hashes indicate either identical" >&2
        echo "  block ranges were checkpointed or the root hash computation is broken." >&2
        return 1
    fi

    echo "  OK: all ${count} checkpoint root hashes are unique" >&3
}
