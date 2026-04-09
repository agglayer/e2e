#!/usr/bin/env bats
# bats file_tags=heimdall,bor,span,correctness

# Span / Sprint Boundary Safety
# ==============================
# This suite catches S1 risks from span/sprint boundary misalignment in Bor.
#
# Bor organises block production into spans (assigned by Heimdall) and sprints
# (fixed-length rotation windows within each span).  If span transitions
# misalign with sprint boundaries, or if producer selection is wrong at
# boundaries, the chain can stall or fork.
#
# The suite checks seven properties:
#
#   1. Current span has valid structure (start_block, end_block,
#      selected_producers, chain_id)
#   2. Span producer list matches Bor's getCurrentValidators
#   3. Block producer at span boundary is in span's producer list
#   4. All validators in current span have non-zero voting power
#   5. Span transitions have no block production gap (consecutive timestamps)
#   6. Consecutive spans are contiguous (span[i].end_block + 1 ==
#      span[i+1].start_block)
#   7. Current block height is within active span range
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL
#   - At least 1 span committed by Heimdall
#
# RUN: bats tests/pos/heimdall/bor/span-sprint-boundary-safety.bats

# ---------------------------------------------------------------------------
# File-level setup (runs once before all tests)
# ---------------------------------------------------------------------------

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Probe Heimdall span endpoint.  If not reachable, skip the whole file.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null \
        | jq -r '.span.id // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        # Try gRPC-gateway fallback path
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/bor/spans/latest" 2>/dev/null \
            | jq -r '.span.id // empty' 2>/dev/null || true)
    fi

    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall REST API not reachable at ${L2_CL_API_URL} — all span-sprint boundary tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_bor_unavailable"
    else
        echo "Heimdall REST API reachable; latest span id=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_bor_unavailable"
    fi

    # Probe Bor JSON-RPC separately — some tests require it.
    local bor_probe
    bor_probe=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null || true)

    if [[ -z "${bor_probe}" ]]; then
        echo "NOTE: Bor JSON-RPC not reachable at ${L2_RPC_URL} — some tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/bor_rpc_unavailable"
    else
        echo "Bor JSON-RPC reachable; current block=${bor_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/bor_rpc_unavailable"
    fi
}

# ---------------------------------------------------------------------------
# Per-test setup
# ---------------------------------------------------------------------------

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_bor_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall REST API not reachable at ${L2_CL_API_URL}"
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Fetch the latest span object from Heimdall.  Tries the standard path first,
# then the gRPC-gateway /v1beta1/ prefix.  Prints the raw JSON span object on
# stdout, or returns 1 if nothing could be fetched.
_get_latest_span() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null || true)
    local span
    span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        # Try gRPC-gateway fallback
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/bor/spans/latest" 2>/dev/null || true)
        span=$(printf '%s' "${raw}" | jq -r 'if .span then .span else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${span}" || "${span}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${span}"
}

# Fetch a specific span by numeric ID.  Prints the raw JSON span object on
# stdout, or returns 1 on failure.
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

# Get the miner (block producer) address for a given block number (decimal).
# Uses cast to fetch the block and extract the miner field.  Prints the
# lowercase address on stdout, or returns 1 on failure.
_get_block_miner() {
    local block_dec="$1"
    local miner
    miner=$(cast block "${block_dec}" --rpc-url "${L2_RPC_URL}" -j 2>/dev/null \
        | jq -r '.miner // empty' 2>/dev/null || true)
    if [[ -z "${miner}" || "${miner}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${miner}" | tr '[:upper:]' '[:lower:]'
}

# Get the timestamp (as decimal) for a given block number (decimal).
_get_block_timestamp() {
    local block_dec="$1"
    local ts
    ts=$(cast block "${block_dec}" --rpc-url "${L2_RPC_URL}" -j 2>/dev/null \
        | jq -r '.timestamp // empty' 2>/dev/null || true)
    if [[ -z "${ts}" || "${ts}" == "null" ]]; then
        return 1
    fi
    # Handle both hex (0x...) and decimal timestamp formats.
    if [[ "${ts}" =~ ^0x ]]; then
        printf '%d\n' "${ts}"
    else
        printf '%s\n' "${ts}"
    fi
}

# Require Bor RPC to be available; skip the test if not.
_require_bor_rpc() {
    if [[ "$(cat "${BATS_FILE_TMPDIR}/bor_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Bor RPC not available at ${L2_RPC_URL}"
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# bats test_tags=bor,span,correctness
@test "span-sprint: current span has valid structure" {
    # Fetch latest span from Heimdall and verify it contains all required
    # structural fields: start_block, end_block, selected_producers, chain_id.
    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL} — API may be down or chain has not started"
    fi

    local span_id start_block end_block chain_id n_producers
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')
    chain_id=$(printf '%s' "${span}" | jq -r '.bor_chain_id // .chain_id // empty')
    n_producers=$(printf '%s' "${span}" | jq -r '(.selected_producers // []) | length' 2>/dev/null || true)

    echo "  span_id=${span_id} start_block=${start_block} end_block=${end_block} chain_id=${chain_id} producers=${n_producers}" >&3

    # Validate id.
    if [[ -z "${span_id}" || "${span_id}" == "null" ]]; then
        echo "FAIL: latest span response has no 'id' field — raw span: ${span}" >&2
        return 1
    fi

    # Validate start_block.
    if [[ -z "${start_block}" || "${start_block}" == "null" ]]; then
        echo "FAIL: span ${span_id} has no 'start_block' field" >&2
        return 1
    fi
    if [[ ! "${start_block}" =~ ^[0-9]+$ ]]; then
        echo "FAIL: span ${span_id} start_block '${start_block}' is not a valid integer" >&2
        return 1
    fi

    # Validate end_block.
    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        echo "FAIL: span ${span_id} has no 'end_block' field" >&2
        return 1
    fi
    if [[ ! "${end_block}" =~ ^[0-9]+$ ]]; then
        echo "FAIL: span ${span_id} end_block '${end_block}' is not a valid integer" >&2
        return 1
    fi

    # start_block must be strictly less than end_block.
    if [[ "${start_block}" -ge "${end_block}" ]]; then
        echo "FAIL: span ${span_id} has start_block (${start_block}) >= end_block (${end_block}) — invalid span range" >&2
        return 1
    fi

    # Validate chain_id.
    if [[ -z "${chain_id}" || "${chain_id}" == "null" ]]; then
        echo "FAIL: span ${span_id} has no 'chain_id' field — span structure is incomplete" >&2
        return 1
    fi

    # Validate selected_producers is non-empty.
    [[ "${n_producers}" =~ ^[0-9]+$ ]] || n_producers=0
    if [[ "${n_producers}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} has an empty selected_producers list — no validator can produce blocks in this span" >&2
        return 1
    fi

    local duration=$(( end_block - start_block + 1 ))
    echo "  OK: span ${span_id} is well-formed — range=[${start_block}, ${end_block}] (${duration} blocks), chain_id=${chain_id}, ${n_producers} producer(s)" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: span producer list matches Bor validator set" {
    # Compare Heimdall's span selected_producers with Bor's getCurrentValidators.
    _require_bor_rpc

    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')

    # Collect Heimdall span producers (lowercase).
    local -a heimdall_producers
    mapfile -t heimdall_producers < <(printf '%s' "${span}" \
        | jq -r '.selected_producers[].signer // empty' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v '^$' || true)

    if [[ "${#heimdall_producers[@]}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers list is empty" >&2
        return 1
    fi

    echo "  span ${span_id}: ${#heimdall_producers[@]} Heimdall producer(s): ${heimdall_producers[*]}" >&3

    # Query Bor's getCurrentValidators via JSON-RPC.
    local bor_result
    bor_result=$(curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"bor_getCurrentValidators","params":[],"id":1}' \
        2>/dev/null || true)

    local bor_validators
    bor_validators=$(printf '%s' "${bor_result}" | jq -r '.result // empty' 2>/dev/null || true)

    if [[ -z "${bor_validators}" || "${bor_validators}" == "null" ]]; then
        skip "bor_getCurrentValidators returned empty — method may not be supported on this Bor version"
    fi

    # Extract Bor validator addresses (lowercase).
    local -a bor_addrs
    mapfile -t bor_addrs < <(printf '%s' "${bor_validators}" \
        | jq -r '.[].signer // empty' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v '^$' || true)

    if [[ "${#bor_addrs[@]}" -eq 0 ]]; then
        skip "bor_getCurrentValidators returned no validators — chain may still be initialising"
    fi

    echo "  Bor reports ${#bor_addrs[@]} validator(s): ${bor_addrs[*]}" >&3

    # Build lookup set from Bor validators.
    local -A bor_set=()
    local v
    for v in "${bor_addrs[@]}"; do
        bor_set["${v}"]=1
    done

    # Every Heimdall producer should appear in Bor's current validator set.
    local failures=0
    local p
    for p in "${heimdall_producers[@]}"; do
        if [[ -z "${bor_set[${p}]:-}" ]]; then
            echo "FAIL: Heimdall span ${span_id} producer ${p} is NOT in Bor's getCurrentValidators result" >&2
            echo "  Bor may not have ingested the latest span from Heimdall." >&2
            failures=$(( failures + 1 ))
        else
            echo "  OK: producer ${p} found in Bor validator set" >&3
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} span producer(s) missing from Bor's validator set — see messages above" >&2
        return 1
    fi

    echo "  OK: all ${#heimdall_producers[@]} Heimdall span producers are present in Bor's getCurrentValidators" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: block producer at span boundary is in span's producer list" {
    # Verify that the miner of the block at the span's start_block is one of the
    # span's selected_producers.  A mismatch here means Bor is using the wrong
    # producer set at the span boundary, which can cause a chain split.
    _require_bor_rpc

    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id start_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')

    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0

    echo "  span ${span_id}: checking block producer at start_block=${start_block}" >&3

    # Verify start_block has been produced.
    local current_block
    if ! current_block=$(_block_number_on "$L2_RPC_URL"); then
        skip "Bor RPC not available"
    fi

    if [[ "${current_block}" -lt "${start_block}" ]]; then
        skip "Current Bor block (${current_block}) has not reached span ${span_id} start_block (${start_block}) yet"
    fi

    # Get the miner at start_block.
    local miner
    if ! miner=$(_get_block_miner "${start_block}"); then
        skip "Could not fetch block ${start_block} from Bor — block may not be available"
    fi

    echo "  block ${start_block} miner: ${miner}" >&3

    # Build producer lookup set from span.
    local -A producer_set=()
    local -a producers
    mapfile -t producers < <(printf '%s' "${span}" \
        | jq -r '.selected_producers[].signer // empty' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v '^$' || true)

    if [[ "${#producers[@]}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} has no selected_producers — cannot verify boundary producer" >&2
        return 1
    fi

    local p
    for p in "${producers[@]}"; do
        producer_set["${p}"]=1
    done

    echo "  span ${span_id} producers: ${producers[*]}" >&3

    if [[ -z "${producer_set[${miner}]:-}" ]]; then
        echo "FAIL: block ${start_block} (span boundary) was produced by ${miner} which is NOT in span ${span_id} selected_producers" >&2
        echo "  Expected one of: ${producers[*]}" >&2
        echo "  This indicates a producer set mismatch at the span boundary — risk of chain split." >&2
        return 1
    fi

    echo "  OK: span boundary block ${start_block} producer ${miner} is in span ${span_id} selected_producers" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: all validators in current span have non-zero power" {
    # Every selected_producer in the span must have positive voting_power.
    # A producer with zero power cannot sign blocks, which would create a gap
    # when that producer's turn comes during a sprint.
    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')

    local n_producers
    n_producers=$(printf '%s' "${span}" | jq -r '(.selected_producers // []) | length' 2>/dev/null || true)
    [[ "${n_producers}" =~ ^[0-9]+$ ]] || n_producers=0

    if [[ "${n_producers}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers list is empty" >&2
        return 1
    fi

    echo "  span ${span_id}: checking voting_power for ${n_producers} producer(s)" >&3

    local failures=0
    local i
    for (( i = 0; i < n_producers; i++ )); do
        local signer power
        signer=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].signer // empty' 2>/dev/null || true)
        power=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].voting_power // .selected_producers[$idx].power // empty' 2>/dev/null || true)

        # Normalise: treat missing/null/non-integer as 0.
        if [[ -z "${power}" || "${power}" == "null" || ! "${power}" =~ ^[0-9]+$ ]]; then
            power=0
        fi

        echo "  producer[${i}]: signer=${signer} power=${power}" >&3

        if [[ "${power}" -le 0 ]]; then
            echo "FAIL: span ${span_id} producer[${i}] signer=${signer} has voting_power=${power} (must be > 0)" >&2
            echo "  A producer with zero power cannot sign blocks. When this producer's turn" >&2
            echo "  comes in the sprint rotation, the chain will stall." >&2
            failures=$(( failures + 1 ))
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} producer(s) in span ${span_id} have zero voting power — see messages above" >&2
        return 1
    fi

    echo "  OK: all ${n_producers} producers in span ${span_id} have non-zero voting power" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: span transitions have no block production gap" {
    # Verify that blocks at span.end_block and span.end_block+1 have consecutive
    # timestamps without a large gap.  A gap indicates that the chain stalled
    # during the span transition, which is a critical boundary failure.
    _require_bor_rpc

    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    # We need end_block+1 to exist (i.e. the next span must have started).
    local next_block=$(( end_block + 1 ))

    local current_block
    if ! current_block=$(_block_number_on "$L2_RPC_URL"); then
        skip "Bor RPC not available"
    fi

    if [[ "${current_block}" -lt "${next_block}" ]]; then
        skip "Current Bor block (${current_block}) has not reached span ${span_id} end_block+1 (${next_block}) — span transition has not happened yet"
    fi

    echo "  span ${span_id}: checking timestamp gap between blocks ${end_block} and ${next_block}" >&3

    local ts_end ts_next
    if ! ts_end=$(_get_block_timestamp "${end_block}"); then
        skip "Could not fetch timestamp for block ${end_block}"
    fi
    if ! ts_next=$(_get_block_timestamp "${next_block}"); then
        skip "Could not fetch timestamp for block ${next_block}"
    fi

    local gap=$(( ts_next - ts_end ))
    echo "  block ${end_block} timestamp=${ts_end}, block ${next_block} timestamp=${ts_next}, gap=${gap}s" >&3

    # In PoS Bor, the typical block time is 2 seconds.  A gap larger than 30
    # seconds at a span boundary strongly suggests the chain stalled during the
    # transition.  We use a generous threshold to avoid false positives from
    # normal network jitter.
    local max_gap=30
    if [[ "${gap}" -gt "${max_gap}" ]]; then
        echo "FAIL: span transition gap between block ${end_block} and ${next_block} is ${gap} seconds (threshold: ${max_gap}s)" >&2
        echo "  The chain appears to have stalled at the span boundary." >&2
        echo "  This usually indicates a sprint/span misalignment or a producer set" >&2
        echo "  disagreement between Heimdall and Bor at the transition point." >&2
        return 1
    fi

    if [[ "${gap}" -lt 0 ]]; then
        echo "FAIL: block ${next_block} has an earlier timestamp (${ts_next}) than block ${end_block} (${ts_end}) — timestamps went backwards" >&2
        return 1
    fi

    echo "  OK: span transition gap is ${gap}s (within ${max_gap}s threshold) — no stall detected" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: consecutive spans are contiguous" {
    # Verify that span[i].end_block + 1 == span[i+1].start_block for the latest
    # consecutive span pairs.  A gap means blocks exist with no assigned span
    # (no valid producer), and an overlap means two spans claim the same blocks.
    local latest_span latest_id
    if ! latest_span=$(_get_latest_span); then
        skip "Could not fetch latest span — Heimdall may not have committed spans yet"
    fi

    latest_id=$(printf '%s' "${latest_span}" | jq -r '.id // empty')
    if [[ -z "${latest_id}" || "${latest_id}" == "null" ]]; then
        skip "Latest span has no id — cannot perform contiguity check"
    fi
    if [[ "${latest_id}" -lt 1 ]]; then
        skip "Only span ${latest_id} exists — need at least 2 spans to check contiguity"
    fi

    # Walk back up to 5 consecutive span pairs.
    local check_count=$(( latest_id < 5 ? latest_id : 5 ))
    local hi_id=$(( latest_id ))
    local failures=0 stall_detected=0

    local i
    for (( i = 0; i < check_count; i++ )); do
        local lo_id=$(( hi_id - 1 ))
        local hi_span lo_span

        if ! hi_span=$(_get_span_by_id "${hi_id}"); then
            echo "  WARN: could not fetch span ${hi_id} — skipping pair (${lo_id}, ${hi_id})" >&3
            hi_id="${lo_id}"
            continue
        fi
        if ! lo_span=$(_get_span_by_id "${lo_id}"); then
            echo "  WARN: could not fetch span ${lo_id} — skipping pair (${lo_id}, ${hi_id})" >&3
            hi_id="${lo_id}"
            continue
        fi

        local hi_start hi_end lo_start lo_end
        hi_start=$(printf '%s' "${hi_span}" | jq -r '.start_block')
        hi_end=$(printf '%s'   "${hi_span}" | jq -r '.end_block')
        lo_start=$(printf '%s' "${lo_span}" | jq -r '.start_block')
        lo_end=$(printf '%s'   "${lo_span}" | jq -r '.end_block')

        local expected_start=$(( lo_end + 1 ))
        echo "  span ${lo_id}: [${lo_start}, ${lo_end}]  ->  span ${hi_id}: [${hi_start}, ${hi_end}]  (expected start ${expected_start})" >&3

        # Detect stall: consecutive spans covering identical block ranges.
        if [[ "${hi_start}" == "${lo_start}" && "${hi_end}" == "${lo_end}" ]]; then
            echo "  SKIP: spans ${lo_id} and ${hi_id} cover identical range [${lo_start}, ${lo_end}] — Heimdall span generation stalled" >&3
            stall_detected=1
            break
        fi

        if [[ "${hi_start}" -ne "${expected_start}" ]]; then
            echo "FAIL: span contiguity violated between span ${lo_id} and span ${hi_id}:" >&2
            echo "  span ${lo_id} end_block   = ${lo_end}" >&2
            echo "  span ${hi_id} start_block = ${hi_start}  (expected ${expected_start})" >&2
            if [[ "${hi_start}" -gt "${expected_start}" ]]; then
                echo "  There is a GAP of $(( hi_start - expected_start )) blocks with no assigned span." >&2
                echo "  Bor nodes will have no valid producer for blocks ${expected_start}-$(( hi_start - 1 ))." >&2
            else
                echo "  Spans OVERLAP: blocks ${hi_start}-$(( expected_start - 1 )) are assigned to both spans." >&2
                echo "  Bor nodes may disagree on which producer is authoritative in that range." >&2
            fi
            failures=$(( failures + 1 ))
        fi

        hi_id="${lo_id}"
    done

    if [[ "${stall_detected}" -eq 1 ]]; then
        skip "Heimdall span generation stalled — consecutive spans share identical block range (expected when a late fork is disabled in a mixed-version network)"
    fi

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} span contiguity violation(s) detected — see messages above" >&2
        return 1
    fi

    echo "  OK: ${check_count} consecutive span pair(s) are contiguous" >&3
}

# bats test_tags=bor,span,correctness
@test "span-sprint: current block height is within active span range" {
    # The latest Bor block must fall within the latest span's [start_block,
    # end_block] range.  If the block is past end_block, a new span should have
    # been proposed.  If it is before start_block, Bor is still in a prior span
    # (which is acceptable during span transitions but worth noting).
    _require_bor_rpc

    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0
    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    local current_block
    if ! current_block=$(_block_number_on "$L2_RPC_URL"); then
        skip "Bor RPC not available"
    fi

    echo "  span_id=${span_id} start_block=${start_block} end_block=${end_block} current_block=${current_block}" >&3

    if [[ "${current_block}" -gt "${end_block}" ]]; then
        echo "FAIL: current Bor block ${current_block} is past span ${span_id} end_block ${end_block}" >&2
        echo "  A new span should have been proposed by Heimdall. The chain may stall" >&2
        echo "  if Bor cannot determine the valid producer set for blocks beyond this span." >&2
        return 1
    fi

    if [[ "${current_block}" -lt "${start_block}" ]]; then
        # This is expected during span transitions — Heimdall prepares spans
        # in advance, so the latest span may be for a future block range.
        echo "  NOTE: Bor block ${current_block} is before latest span ${span_id} start ${start_block} — Bor is still in a prior span (expected during span transitions)" >&3
    else
        echo "  OK: Bor block ${current_block} is within span ${span_id} range [${start_block}, ${end_block}]" >&3
    fi
}
