#!/usr/bin/env bats
# bats file_tags=heimdall,statesync,clerk,correctness

# State Sync Event Ordering and Integrity
# ========================================
# Verifies that Heimdall's clerk module processes L1→L2 state sync events
# in the correct order and that each event record is internally consistent.
#
# State sync events are how the Ethereum root chain sends deposits, governance
# signals, and other state into the Bor execution layer.  Heimdall's clerk
# module receives these events, assigns sequential IDs, and Bor processes them
# in ID order during block finalization (the `Finalize` call in bor.go).
#
# A clerk ordering bug causes Bor to:
#   - Skip or re-process a deposit
#   - Apply a governance change out of order
#   - Diverge silently from other nodes that process events in the correct order
#
# The suite checks four properties:
#
#   1. Event list is ordered     — IDs in the list from /clerk/event-records/list
#                                  are strictly increasing (monotonically; gaps are
#                                  allowed since IDs come from the L1 state counter)
#   2. No duplicate IDs          — each event has a unique ID within the list
#   3. Fields non-empty          — each event has id, contract, and tx_hash
#   4. Latest-id is an upper bound — max ID in the list <= /clerk/event-records/latest-id
#                                    (the endpoint returns the L1 state counter, which
#                                    may be ahead of Heimdall's locally processed IDs)
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - At least 1 state sync event has been processed by Heimdall
#
# RUN: bats tests/heimdall/consensus-correctness/statesync-event-ordering.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # The clerk list endpoint requires page and limit params (page=0 or limit=0
    # returns an InvalidArgument error from the server). Use page=1&limit=1 for
    # the probe to minimize cost while checking reachability.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/list?page=1&limit=1" 2>/dev/null \
        | jq -r '(.event_records // []) | length' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/clerk/event-records/list?page=1&limit=1" 2>/dev/null \
            | jq -r '(.event_records // []) | length' 2>/dev/null || true)
    fi

    # Use BATS_FILE_TMPDIR for cross-subshell communication (exported vars from
    # setup_file do not propagate to setup() in BATS 1.x).
    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall clerk API not reachable at ${L2_CL_API_URL} — all clerk tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_clerk_unavailable"
    else
        echo "Heimdall clerk API reachable; event record count=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_clerk_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_clerk_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall clerk API not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the event record list from Heimdall clerk.
# The server requires page and limit params; defaults to page=1&limit=50.
# Prints the raw JSON array of event records on stdout, or returns 1 on failure.
# Accepts optional query params string, e.g. "?page=1&limit=50".
_get_event_records() {
    local query="${1:-?page=1&limit=50}"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/list${query}" 2>/dev/null || true)
    local records
    records=$(printf '%s' "${raw}" | jq -c '.event_records // empty' 2>/dev/null || true)
    if [[ -z "${records}" || "${records}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/clerk/event-records/list${query}" 2>/dev/null || true)
        records=$(printf '%s' "${raw}" | jq -c '.event_records // empty' 2>/dev/null || true)
    fi
    if [[ -z "${records}" || "${records}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${records}"
}

# Fetch the latest event record ID (L1 state counter).
# The response field is latest_record_id, which is the L1 counter of the most
# recent state sync event (may be ahead of Heimdall's locally processed IDs).
# Prints the ID as a decimal integer, or returns 1 on failure.
_get_latest_record_id() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/latest-id" 2>/dev/null || true)
    local id
    id=$(printf '%s' "${raw}" | jq -r '.latest_record_id // empty' 2>/dev/null || true)
    if [[ -z "${id}" || "${id}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/clerk/event-records/latest-id" 2>/dev/null || true)
        id=$(printf '%s' "${raw}" | jq -r '.latest_record_id // empty' 2>/dev/null || true)
    fi
    if [[ -z "${id}" || "${id}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${id}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=statesync,clerk,correctness
@test "heimdall clerk: event record list is sorted by ID in strictly ascending order" {
    local records
    if ! records=$(_get_event_records); then
        skip "Could not fetch event records from ${L2_CL_API_URL}/clerk/event-records/list — Heimdall may have no events yet"
    fi

    local n_records
    n_records=$(printf '%s' "${records}" | jq 'length')
    if [[ -z "${n_records}" || "${n_records}" -eq 0 ]]; then
        skip "No event records returned — L1→L2 state sync may not have started yet"
    fi

    echo "  ${n_records} event record(s) in list" >&3

    # Extract IDs as a newline-separated list.
    local -a ids
    mapfile -t ids < <(printf '%s' "${records}" | jq -r '.[].id')

    if [[ "${#ids[@]}" -lt 2 ]]; then
        echo "  Only 1 event record — ordering trivially satisfied" >&3
        return 0
    fi

    local failures=0
    local prev_id="${ids[0]}"
    local i
    for (( i = 1; i < ${#ids[@]}; i++ )); do
        local curr_id="${ids[$i]}"
        if [[ "${curr_id}" -le "${prev_id}" ]]; then
            echo "FAIL: event record ordering violation at position ${i}:" >&2
            echo "  record[$(( i - 1 ))].id = ${prev_id}" >&2
            echo "  record[${i}].id         = ${curr_id}  (expected > ${prev_id})" >&2
            echo "  Bor processes state sync events in ID order during Finalize()." >&2
            echo "  Out-of-order delivery means deposits/governance changes are mis-applied." >&2
            failures=$(( failures + 1 ))
        fi
        prev_id="${curr_id}"
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} ordering violation(s) in event record list" >&2
        return 1
    fi

    echo "  OK: all ${#ids[@]} event records are in strictly ascending ID order" >&3
}

# bats test_tags=statesync,clerk,correctness
@test "heimdall clerk: no duplicate IDs in event record list" {
    local records
    if ! records=$(_get_event_records); then
        skip "Could not fetch event records from ${L2_CL_API_URL}/clerk/event-records/list"
    fi

    local n_records
    n_records=$(printf '%s' "${records}" | jq 'length')
    if [[ -z "${n_records}" || "${n_records}" -eq 0 ]]; then
        skip "No event records returned"
    fi

    echo "  Checking ${n_records} event record(s) for duplicate IDs" >&3

    # Count unique IDs vs total.
    local unique_count total_count
    total_count=$(printf '%s' "${records}" | jq 'length')
    unique_count=$(printf '%s' "${records}" | jq '[.[].id] | unique | length')

    if [[ "${unique_count}" -ne "${total_count}" ]]; then
        local dup_count=$(( total_count - unique_count ))
        echo "FAIL: found ${dup_count} duplicate event record ID(s) in list" >&2
        echo "  total records: ${total_count}, unique IDs: ${unique_count}" >&2
        # Print duplicate IDs for diagnosis.
        printf '%s' "${records}" \
            | jq -r '[.[].id] | group_by(.) | map(select(length > 1)) | .[] | .[0]' \
            | while read -r dup_id; do
                echo "  duplicate ID: ${dup_id}" >&2
            done
        echo "  Duplicate event IDs mean Bor will process the same L1 event twice," >&2
        echo "  which can double-credit deposits or replay governance votes." >&2
        return 1
    fi

    echo "  OK: all ${total_count} event records have unique IDs" >&3
}

# bats test_tags=statesync,clerk,correctness
@test "heimdall clerk: each event record has required non-empty fields (id, contract, tx_hash)" {
    local records
    if ! records=$(_get_event_records); then
        skip "Could not fetch event records from ${L2_CL_API_URL}/clerk/event-records/list"
    fi

    local n_records
    n_records=$(printf '%s' "${records}" | jq 'length')
    if [[ -z "${n_records}" || "${n_records}" -eq 0 ]]; then
        skip "No event records returned"
    fi

    echo "  Checking required fields in ${n_records} event record(s)" >&3

    local failures=0
    local i
    for (( i = 0; i < n_records; i++ )); do
        local rec
        rec=$(printf '%s' "${records}" | jq -c ".[${i}]")

        local rec_id contract tx_hash
        rec_id=$(printf '%s' "${rec}" | jq -r '.id // empty')
        contract=$(printf '%s' "${rec}" | jq -r '.contract // empty')
        tx_hash=$(printf '%s' "${rec}" | jq -r '.tx_hash // empty')

        local field_ok=1
        if [[ -z "${rec_id}" || "${rec_id}" == "null" || "${rec_id}" == "0" ]]; then
            echo "FAIL: event record at index ${i} has missing or zero 'id'" >&2
            field_ok=0
        fi
        if [[ -z "${contract}" || "${contract}" == "null" ]]; then
            echo "FAIL: event record id=${rec_id:-?} has no 'contract' field" >&2
            echo "  The contract address identifies which L1 contract emitted this event." >&2
            field_ok=0
        fi
        if [[ -z "${tx_hash}" || "${tx_hash}" == "null" ]]; then
            echo "FAIL: event record id=${rec_id:-?} has no 'tx_hash' field" >&2
            echo "  Without a tx_hash the event cannot be verified against the L1 chain." >&2
            field_ok=0
        fi

        if [[ "${field_ok}" -eq 0 ]]; then
            failures=$(( failures + 1 ))
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} event record(s) are missing required fields" >&2
        return 1
    fi

    echo "  OK: all ${n_records} event records have id, contract, and tx_hash" >&3
}

# bats test_tags=statesync,clerk,correctness
@test "heimdall clerk: latest-id endpoint is consistent with event record list" {
    local records
    if ! records=$(_get_event_records); then
        skip "Could not fetch event records from ${L2_CL_API_URL}/clerk/event-records/list"
    fi

    local n_records
    n_records=$(printf '%s' "${records}" | jq 'length')
    if [[ -z "${n_records}" || "${n_records}" -eq 0 ]]; then
        skip "No event records in list — cannot check latest-id consistency"
    fi

    local latest_id_api
    if ! latest_id_api=$(_get_latest_record_id); then
        skip "Could not fetch latest-id from ${L2_CL_API_URL}/clerk/event-records/latest-id"
    fi

    # The max ID in the list must be <= the reported latest-id.
    # (The list may be paginated and not include all records, so max_in_list <= latest_id is the invariant.)
    local max_id_in_list
    max_id_in_list=$(printf '%s' "${records}" | jq '[.[].id] | max')

    echo "  latest-id API: ${latest_id_api}" >&3
    echo "  max ID in list: ${max_id_in_list}" >&3

    if [[ "${max_id_in_list}" -gt "${latest_id_api}" ]]; then
        echo "FAIL: max event record ID in list (${max_id_in_list}) exceeds latest-id from L1 counter (${latest_id_api})" >&2
        echo "  Heimdall has stored an event with an ID higher than the L1 state counter." >&2
        echo "  This indicates a fabricated or mis-numbered event in Heimdall's clerk module." >&2
        return 1
    fi

    echo "  OK: max ID in list (${max_id_in_list}) <= L1 latest-id (${latest_id_api})" >&3
}
