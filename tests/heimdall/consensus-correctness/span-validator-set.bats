#!/usr/bin/env bats
# bats file_tags=heimdall,span,correctness

# Span / Validator-Set Correctness
# =================================
# Verifies that Heimdall's span assignments are internally consistent and that
# Bor is actually using the Heimdall-approved producer set to sign blocks.
#
# A span is Heimdall's declaration of which validators produce blocks for a
# contiguous range of Bor block numbers.  Errors here cause Bor to pick the
# wrong block producer at a sprint boundary, resulting in a silent chain split
# that is extremely hard to diagnose after the fact.
#
# The suite checks four properties:
#
#   1. Span contiguity     — span[i].start_block == span[i-1].end_block + 1
#                            (no gaps, no overlaps in the span schedule)
#   2. Producer membership — every address in selected_producers is also in
#                            validator_set (producers must be active validators)
#   3. Producer count      — 1 <= len(selected_producers) <= len(validator_set)
#   4. Bor cross-check     — bor_getAuthor(block) ∈ span.selected_producers for
#                            3 blocks sampled from inside the current span.
#                            This is the oracle test: it catches a span that is
#                            internally consistent but not what Bor is using.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL
#   - At least 2 spans have been committed (to check contiguity)
#
# RUN: bats tests/heimdall/consensus-correctness/span-validator-set.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # Quick reachability probe — if Heimdall is not up yet, skip the whole file.
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

    # Use BATS_FILE_TMPDIR for cross-subshell communication (exported vars from
    # setup_file do not propagate to setup() in BATS 1.x).
    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall REST API not reachable at ${L2_CL_API_URL} — all span tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_unavailable"
    else
        echo "Heimdall REST API reachable; latest span id=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall REST API not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

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

# Extract signer addresses from a span's validator_set field.
# $1 = span JSON object (full span, not just selected_producers)
# Prints a newline-separated list of lowercase signer addresses, or returns 1.
_get_span_validator_signers() {
    local span_json="$1"
    local signers
    signers=$(printf '%s' "${span_json}" \
        | jq -r '.validator_set.validators[]?.signer // empty' 2>/dev/null || true)
    if [[ -z "${signers}" ]]; then
        return 1
    fi
    # Normalise to lowercase for case-insensitive comparison.
    printf '%s\n' "${signers}" | tr '[:upper:]' '[:lower:]' | grep -v '^$'
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
    printf '%d\n' "${hex}"
}

# Call bor_getAuthor for a given block number (decimal).  Prints the lowercase
# author address on stdout, or an empty string if the call fails / returns null.
_bor_get_author() {
    local block_dec="$1"
    local block_hex
    block_hex=$(printf '0x%x' "${block_dec}")
    curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"bor_getAuthor\",\"params\":[\"${block_hex}\"],\"id\":1}" \
        | jq -r '.result // empty' \
        | tr '[:upper:]' '[:lower:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=span,correctness
@test "heimdall span: latest span is well-formed (id, start_block, end_block, selected_producers present)" {
    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL} — API may be down or chain has not started"
    fi

    local span_id start_block end_block n_producers
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')
    n_producers=$(printf '%s' "${span}" | jq -r '(.selected_producers // []) | length')

    echo "  span_id=${span_id} start_block=${start_block} end_block=${end_block} n_producers=${n_producers}" >&3

    if [[ -z "${span_id}" || "${span_id}" == "null" ]]; then
        echo "FAIL: latest span response has no 'id' field — raw span: ${span}" >&2
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
    if [[ "${end_block}" -le "${start_block}" ]]; then
        echo "FAIL: span ${span_id} has end_block (${end_block}) <= start_block (${start_block}) — invalid span range" >&2
        return 1
    fi
    if [[ "${n_producers}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} has an empty selected_producers list — no validator can produce blocks in this span" >&2
        return 1
    fi
}

# bats test_tags=span,correctness
@test "heimdall span: contiguity — span[i].start_block == span[i-1].end_block + 1 for latest 5 spans" {
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
    local failures=0

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

        local hi_start lo_end
        hi_start=$(printf '%s' "${hi_span}" | jq -r '.start_block')
        lo_end=$(printf '%s' "${lo_span}" | jq -r '.end_block')

        local expected_start=$(( lo_end + 1 ))
        echo "  span ${lo_id}: end_block=${lo_end}  →  span ${hi_id}: start_block=${hi_start}  (expected ${expected_start})" >&3

        if [[ "${hi_start}" -ne "${expected_start}" ]]; then
            echo "FAIL: span contiguity violated between span ${lo_id} and span ${hi_id}:" >&2
            echo "  span ${lo_id} end_block   = ${lo_end}" >&2
            echo "  span ${hi_id} start_block = ${hi_start}  (expected ${expected_start})" >&2
            if [[ "${hi_start}" -gt "${expected_start}" ]]; then
                echo "  There is a GAP of $(( hi_start - expected_start )) blocks with no assigned span." >&2
                echo "  Bor nodes will have no valid producer for blocks ${expected_start}–$(( hi_start - 1 ))." >&2
            else
                echo "  Spans OVERLAP: blocks ${hi_start}–$(( expected_start - 1 )) are assigned to both spans." >&2
                echo "  Bor nodes may disagree on which producer is authoritative in that range." >&2
            fi
            failures=$(( failures + 1 ))
        fi

        hi_id="${lo_id}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} span contiguity violation(s) detected — see messages above" >&2
        return 1
    fi
}

# bats test_tags=span,correctness
@test "heimdall span: producer membership — every selected_producer is in validator_set" {
    local latest_span
    if ! latest_span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id
    span_id=$(printf '%s' "${latest_span}" | jq -r '.id // empty')

    # Collect selected_producers signers (lowercase).
    local -a producers
    mapfile -t producers < <(printf '%s' "${latest_span}" \
        | jq -r '.selected_producers[]?.signer // empty' \
        | tr '[:upper:]' '[:lower:]' | grep -v '^$')

    if [[ "${#producers[@]}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers list is empty — no producer can sign blocks in this span" >&2
        return 1
    fi

    # Use the span's own validator_set (recorded at commit time), not the live
    # endpoint, to avoid false positives from validators who joined/left after
    # the span was committed.
    local signer_output
    if ! signer_output=$(_get_span_validator_signers "${latest_span}"); then
        skip "span ${span_id} has no validator_set field — cannot perform membership check"
    fi
    local -a validators
    mapfile -t validators <<< "${signer_output}"
    if [[ "${#validators[@]}" -eq 0 ]]; then
        skip "span ${span_id} validator_set is empty — chain may not have started staking yet"
    fi

    echo "  span ${span_id}: ${#producers[@]} producer(s), ${#validators[@]} active validator(s)" >&3

    # Build a lookup set from the validator array.
    local -A val_set=()
    local v
    for v in "${validators[@]}"; do
        val_set["${v}"]=1
    done

    local failures=0
    local p
    for p in "${producers[@]}"; do
        if [[ -z "${val_set[${p}]:-}" ]]; then
            echo "FAIL: span ${span_id} selected_producer ${p} is NOT in the active validator_set" >&2
            echo "  This means Heimdall assigned a non-validator as a block producer, which breaks" >&2
            echo "  the PoA invariant: only staked validators should produce blocks." >&2
            failures=$(( failures + 1 ))
        else
            echo "  OK producer ${p} is in validator_set" >&3
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} producer(s) in span ${span_id} are not in the active validator set" >&2
        return 1
    fi
}

# bats test_tags=span,correctness
@test "heimdall span: producer count — 1 <= len(selected_producers) <= len(validator_set)" {
    local latest_span
    if ! latest_span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id n_producers
    span_id=$(printf '%s' "${latest_span}" | jq -r '.id // empty')
    n_producers=$(printf '%s' "${latest_span}" | jq -r '(.selected_producers // []) | length')

    local signer_output_count
    if ! signer_output_count=$(_get_span_validator_signers "${latest_span}"); then
        skip "span ${span_id} has no validator_set field — skipping count bounds check"
    fi
    local -a validators
    mapfile -t validators <<< "${signer_output_count}"
    local n_validators="${#validators[@]}"

    echo "  span ${span_id}: selected_producers=${n_producers}, active validators=${n_validators}" >&3

    if [[ "${n_producers}" -lt 1 ]]; then
        echo "FAIL: span ${span_id} has 0 selected_producers — at least 1 producer is required for the chain to progress" >&2
        return 1
    fi

    if [[ "${n_validators}" -gt 0 && "${n_producers}" -gt "${n_validators}" ]]; then
        echo "FAIL: span ${span_id} has more selected_producers (${n_producers}) than active validators (${n_validators})" >&2
        echo "  selected_producers must be a subset of validator_set — this is a Heimdall assignment bug." >&2
        return 1
    fi

    echo "  OK: ${n_producers} producer(s) within bounds [1, ${n_validators}]" >&3
}

# bats test_tags=span,correctness
@test "heimdall span: bor cross-check — bor_getAuthor(block) is in current span's selected_producers" {
    # This is the oracle test.  It verifies that the address Bor ecrecovers from
    # block extra-data actually appears in the Heimdall-approved producer set for
    # the current span.  An internally-consistent span that doesn't match what
    # Bor uses indicates a critical span delivery or parsing bug.

    local latest_span
    if ! latest_span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${latest_span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${latest_span}" | jq -r '.start_block')
    end_block=$(printf '%s' "${latest_span}" | jq -r '.end_block')

    # Collect selected_producers as a lookup set (lowercase signer addresses).
    local -A producer_set=()
    local -a producers
    mapfile -t producers < <(printf '%s' "${latest_span}" \
        | jq -r '.selected_producers[]?.signer // empty' \
        | tr '[:upper:]' '[:lower:]')

    if [[ "${#producers[@]}" -eq 0 ]]; then
        skip "span ${span_id} has no selected_producers — cannot perform cross-check"
    fi

    local p
    for p in "${producers[@]}"; do
        producer_set["${p}"]=1
    done

    echo "  span ${span_id}: blocks ${start_block}–${end_block}, ${#producers[@]} producer(s)" >&3
    echo "  producers: ${producers[*]}" >&3

    # Determine current Bor chain tip to avoid sampling unproduced blocks.
    local current_block
    if ! current_block=$(_bor_block_number 2>/dev/null); then
        skip "Could not read current block number from Bor at ${L2_RPC_URL}"
    fi
    if [[ -z "${current_block}" || "${current_block}" -eq 0 ]]; then
        skip "Bor reports block 0 — chain has not started producing blocks yet"
    fi

    echo "  Bor current block: ${current_block}" >&3

    # Span may not have started yet (e.g. future span).
    if [[ "${current_block}" -lt "${start_block}" ]]; then
        skip "Current Bor block (${current_block}) has not reached span ${span_id} start_block (${start_block}) yet"
    fi

    # Compute 3 sample points within [start_block, end_block] ∩ [0, current_block].
    # Use start+1, midpoint, end-1 per spec (avoids sprint-boundary edge blocks).
    local sample_max=$(( current_block < end_block ? current_block : end_block ))
    local mid=$(( (start_block + sample_max) / 2 ))
    local -a candidates=(
        $(( start_block + 1 ))
        "${mid}"
        $(( sample_max - 1 ))
    )

    # Deduplicate and filter to blocks that exist (>= start_block, <= sample_max).
    local -A seen=()
    local -a sample_blocks=()
    local b
    for b in "${candidates[@]}"; do
        if [[ "${b}" -ge "${start_block}" && "${b}" -le "${sample_max}" && -z "${seen[${b}]:-}" ]]; then
            sample_blocks+=("${b}")
            seen["${b}"]=1
        fi
    done

    if [[ "${#sample_blocks[@]}" -eq 0 ]]; then
        skip "No valid sample blocks in span ${span_id} range [${start_block}, ${sample_max}] — span window too narrow"
    fi

    echo "  Sampling blocks: ${sample_blocks[*]}" >&3

    local failures=0
    for b in "${sample_blocks[@]}"; do
        local author
        author=$(_bor_get_author "${b}")

        if [[ -z "${author}" || "${author}" == "null" ]]; then
            echo "  WARN: bor_getAuthor returned empty for block ${b} — block may not be available yet, skipping" >&3
            continue
        fi

        echo "  block ${b}: author=${author}" >&3

        if [[ -z "${producer_set[${author}]:-}" ]]; then
            echo "FAIL: bor_getAuthor at block ${b} returned ${author} which is NOT in span ${span_id} selected_producers" >&2
            echo "  Bor is producing blocks with a producer not in the Heimdall-approved set." >&2
            echo "  This indicates a span delivery or parsing bug between Heimdall and Bor." >&2
            echo "  span ${span_id} selected_producers: ${producers[*]}" >&2
            echo "  To investigate: compare Bor's internal span cache with Heimdall's /bor/spans/${span_id}" >&2
            failures=$(( failures + 1 ))
        else
            echo "  OK block ${b}: author ${author} is in span ${span_id} selected_producers" >&3
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} block(s) authored by a validator outside the Heimdall span — see messages above" >&2
        return 1
    fi
}
