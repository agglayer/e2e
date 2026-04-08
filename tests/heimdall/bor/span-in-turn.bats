#!/usr/bin/env bats
# bats file_tags=heimdall,bor,span,correctness

# Heimdall Bor Span In-Turn Validation
# =====================================
# This suite verifies that Heimdall's Bor span assignments are valid and that
# Bor is operating within the correct span:
#   - Span block ranges are non-zero (start < end)
#   - The current Bor block falls within the latest span's range
#   - Producers are not duplicated within a span
#   - All producer signer addresses are well-formed
#
# A span tells Bor which validators produce blocks for a given range of block
# numbers.  Errors here cause Bor to use incorrect block producers, which can
# lead to chain splits at sprint boundaries.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Bor JSON-RPC reachable at L2_RPC_URL (optional; some tests skip without it)
#   - At least 1 span committed by Heimdall
#
# RUN: bats tests/heimdall/bor/span-in-turn.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
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

    # Use BATS_FILE_TMPDIR for cross-subshell communication (exported vars from
    # setup_file do not propagate to setup() in BATS 1.x).
    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall REST API not reachable at ${L2_CL_API_URL} — all bor span tests will be skipped." >&3
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
        echo "NOTE: Bor JSON-RPC not reachable at ${L2_RPC_URL} — block-range test will be skipped." >&3
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
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_bor_unavailable" 2>/dev/null)" != "0" ]]; then
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

# bats test_tags=bor,span,correctness
@test "heimdall bor: latest span has a non-zero block range (start_block < end_block)" {
    local span
    if ! span=$(_get_latest_span); then
        fail "Could not fetch latest span from Heimdall at ${L2_CL_API_URL} — API may be down or chain has not started"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    echo "  span_id=${span_id} start_block=${start_block} end_block=${end_block}" >&3

    # Validate that fields are present and non-null.
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

    # Validate that both values are non-negative integers before arithmetic.
    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0
    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    # Reject the degenerate case where both fields are zero — this means the
    # span object was not properly populated.
    if [[ "${start_block}" -eq 0 && "${end_block}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} has start_block=0 and end_block=0 — span was not properly populated" >&2
        return 1
    fi

    if [[ "${start_block}" -ge "${end_block}" ]]; then
        echo "FAIL: span ${span_id} has start_block (${start_block}) >= end_block (${end_block}) — invalid span range" >&2
        return 1
    fi

    local duration=$(( end_block - start_block + 1 ))
    echo "  OK: span id=${span_id} start=${start_block} end=${end_block} duration=${duration} blocks" >&3
}

# bats test_tags=bor,span,correctness
@test "heimdall bor: current Bor block is within the latest span's block range" {
    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall — API may be down or chain has not started"
    fi

    local span_id start_block end_block
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')
    start_block=$(printf '%s' "${span}" | jq -r '.start_block // empty')
    end_block=$(printf '%s' "${span}" | jq -r '.end_block // empty')

    # Validate integer fields before arithmetic.
    [[ "${start_block}" =~ ^[0-9]+$ ]] || start_block=0
    [[ "${end_block}" =~ ^[0-9]+$ ]] || end_block=0

    # Skip if Bor RPC is not available.
    if [[ "$(cat "${BATS_FILE_TMPDIR}/bor_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Bor RPC not available"
    fi

    local bor_block
    if ! bor_block=$(_bor_block_number); then
        skip "Bor RPC not available"
    fi

    # Validate bor_block is a non-negative integer.
    [[ "${bor_block}" =~ ^[0-9]+$ ]] || bor_block=0

    echo "  span_id=${span_id} start_block=${start_block} end_block=${end_block} bor_block=${bor_block}" >&3

    if [[ "${bor_block}" -gt "${end_block}" ]]; then
        echo "FAIL: current Bor block ${bor_block} is past span end ${end_block} — a new span should have been proposed" >&2
        return 1
    fi

    # Heimdall prepares spans in advance, so the current Bor block may still be
    # in a previous span while the "latest" span has already been committed.
    # This is normal — we only flag a failure when Bor has *passed* the span.
    if [[ "${bor_block}" -lt "${start_block}" ]]; then
        echo "  NOTE: Bor block ${bor_block} is before latest span start ${start_block} — Bor is still in a prior span (this is expected during span transitions)" >&3
    else
        echo "  OK: Bor block ${bor_block} is within span [${start_block}, ${end_block}]" >&3
    fi
}

# bats test_tags=bor,span,correctness
@test "heimdall bor: span selected_producers have no duplicate signer addresses" {
    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall — API may be down or chain has not started"
    fi

    local span_id
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')

    # Collect selected_producers signer addresses (normalised to lowercase).
    local -a signers
    mapfile -t signers < <(printf '%s' "${span}" \
        | jq -r '.selected_producers[].signer // empty' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v '^$' || true)

    local n_signers="${#signers[@]}"

    if [[ "${n_signers}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers list is empty — cannot check for duplicates" >&2
        return 1
    fi

    echo "  span_id=${span_id} producers=${n_signers}" >&3

    # Build an associative array to detect duplicates.  For each signer address
    # track how many times it appears; increment a failure counter for any that
    # appear more than once.
    local -A seen=()
    local -a duplicates=()
    local s
    for s in "${signers[@]}"; do
        if [[ -n "${seen[${s}]:-}" ]]; then
            # Record duplicates without repeating the same address twice.
            if [[ "${seen[${s}]}" -eq 1 ]]; then
                duplicates+=("${s}")
            fi
            seen["${s}"]=$(( seen["${s}"] + 1 ))
        else
            seen["${s}"]=1
        fi
    done

    if [[ "${#duplicates[@]}" -gt 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers contains duplicate signer address(es):" >&2
        local d
        for d in "${duplicates[@]}"; do
            echo "  duplicate: ${d} (appears ${seen[${d}]} times)" >&2
        done
        return 1
    fi

    echo "  OK: ${n_signers} producers, all signer addresses are unique" >&3
}

# bats test_tags=bor,span,correctness
@test "heimdall bor: each span producer has a non-empty valid signer address" {
    local span
    if ! span=$(_get_latest_span); then
        skip "Could not fetch latest span from Heimdall — API may be down or chain has not started"
    fi

    local span_id
    span_id=$(printf '%s' "${span}" | jq -r '.id // empty')

    local n_producers
    n_producers=$(printf '%s' "${span}" | jq -r '(.selected_producers // []) | length' 2>/dev/null || true)
    [[ "${n_producers}" =~ ^[0-9]+$ ]] || n_producers=0

    if [[ "${n_producers}" -eq 0 ]]; then
        echo "FAIL: span ${span_id} selected_producers list is empty — at least 1 producer is required" >&2
        return 1
    fi

    echo "  span_id=${span_id} producers=${n_producers}" >&3

    local failures=0
    local i
    for (( i = 0; i < n_producers; i++ )); do
        local signer val_id
        signer=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].signer // empty' 2>/dev/null || true)
        val_id=$(printf '%s' "${span}" \
            | jq -r --argjson idx "${i}" '.selected_producers[$idx].val_id // empty' 2>/dev/null || true)

        # Validate that the signer field is non-empty and non-null.
        if [[ -z "${signer}" || "${signer}" == "null" ]]; then
            echo "FAIL: producer[${i}] has an empty or null signer address" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        # Validate that the signer address matches the expected hex format.
        if [[ ! "${signer}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            echo "FAIL: producer[${i}] signer '${signer}' does not match expected format 0x<40 hex chars>" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        # Validate that the validator ID is a positive integer.
        [[ "${val_id}" =~ ^[0-9]+$ ]] || val_id=0
        if [[ "${val_id}" -le 0 ]]; then
            echo "FAIL: producer[${i}] signer ${signer} has non-positive validator id=${val_id}" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        echo "  producer[${i}]: id=${val_id} signer=${signer} — OK" >&3
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} producer(s) in span ${span_id} failed signer address validation — see messages above" >&2
        return 1
    fi

    echo "  OK: all ${n_producers} producers have valid signer addresses" >&3
}
