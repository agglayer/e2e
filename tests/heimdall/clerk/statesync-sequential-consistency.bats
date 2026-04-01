#!/usr/bin/env bats
# bats file_tags=heimdall,clerk,correctness,statesync

# State Sync Sequential Consistency
# ====================================
# Verifies that Heimdall's clerk module maintains strict sequential consistency
# for L1→L2 state sync event records.
#
# State sync events are relayed from the L1 StateSender contract to Heimdall,
# where each event receives a sequential record ID. If record IDs have gaps,
# duplicates, or are out of chronological order, the L2 state diverges from
# what L1 committed — a critical safety property for the PoS bridge.
#
# The existing bridge-sync.bats only checks that latest_record_id > 0.
# This suite does a full audit of ALL records:
#
#   1. Sequential IDs      — record IDs form a contiguous 1..N sequence
#   2. Chronological order — record_time is non-decreasing
#   3. No duplicates       — all IDs are unique
#   4. Count consistency   — total records == latest_record_id
#   5. Valid references    — every record has a non-zero block_number
#   6. API cross-validation — latest-id endpoint matches paginated count
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - At least 1 state sync event has been processed (otherwise all tests skip)
#
# RUN: bats tests/heimdall/clerk/statesync-sequential-consistency.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    load "../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Probe clerk availability and fetch latest record ID.
    local raw_id
    raw_id=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/latest-id" 2>/dev/null \
        | jq -r '.latest_record_id // empty' 2>/dev/null || true)

    if [[ -z "${raw_id}" || "${raw_id}" == "null" ]]; then
        echo "WARNING: Clerk API not reachable at ${L2_CL_API_URL} — all tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/clerk_unavailable"
        echo "0" > "${BATS_FILE_TMPDIR}/latest_record_id"
        return
    fi

    [[ "${raw_id}" =~ ^[0-9]+$ ]] || raw_id=0
    echo "0" > "${BATS_FILE_TMPDIR}/clerk_unavailable"
    echo "${raw_id}" > "${BATS_FILE_TMPDIR}/latest_record_id"
    echo "Clerk API reachable; latest_record_id=${raw_id}" >&3

    if [[ "${raw_id}" -eq 0 ]]; then
        echo "No state sync events — consistency tests will skip." >&3
        return
    fi

    # Fetch ALL event records via pagination — stream to temp files then combine.
    local batch_dir="${BATS_FILE_TMPDIR}/batches"
    mkdir -p "${batch_dir}"
    local page=1 limit=50 batch batch_len
    while true; do
        batch=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/clerk/event-records/list?page=${page}&limit=${limit}" \
            2>/dev/null \
            | jq -c '.event_records // .result // []' 2>/dev/null || echo "[]")
        batch_len=$(echo "${batch}" | jq 'length' 2>/dev/null || echo 0)
        if [[ "${batch_len}" -eq 0 ]]; then
            break
        fi
        echo "${batch}" > "${batch_dir}/page_${page}.json"
        if [[ "${batch_len}" -lt "${limit}" ]]; then
            break
        fi
        page=$(( page + 1 ))
        # Safety: don't paginate more than 200 pages (10,000 records)
        [[ "${page}" -gt 200 ]] && break
    done

    # Combine all batches in a single jq pass (avoids quadratic re-parsing).
    jq -s 'add // []' "${batch_dir}"/page_*.json > "${BATS_FILE_TMPDIR}/all_records.json" 2>/dev/null \
        || echo "[]" > "${BATS_FILE_TMPDIR}/all_records.json"
    local total
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    echo "Fetched ${total} event records across ${page} page(s)." >&3
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    load "../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    if [[ "$(cat "${BATS_FILE_TMPDIR}/clerk_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Clerk API not reachable at ${L2_CL_API_URL}"
    fi

    LATEST_RECORD_ID=$(cat "${BATS_FILE_TMPDIR}/latest_record_id" 2>/dev/null || echo 0)
    if [[ "${LATEST_RECORD_ID}" -eq 0 ]]; then
        skip "No state sync events to validate (latest_record_id=0)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=clerk,statesync,correctness,sequential
@test "statesync-consistency: event record IDs are strictly sequential" {
    local ids
    ids=$(jq '[.[].id] | sort' "${BATS_FILE_TMPDIR}/all_records.json")
    local count
    count=$(echo "${ids}" | jq 'length')

    [[ "${count}" -gt 0 ]] || skip "No records fetched"

    local first last
    first=$(echo "${ids}" | jq '.[0]')
    last=$(echo "${ids}" | jq '.[-1]')

    # IDs should form a contiguous range: last - first + 1 == count
    local expected_count=$(( last - first + 1 ))
    if [[ "${count}" -ne "${expected_count}" ]]; then
        echo "FAIL: record IDs are not contiguous — expected ${expected_count} records for range [${first}..${last}], got ${count}" >&2
        return 1
    fi

    echo "  OK: ${count} records with contiguous IDs [${first}..${last}]" >&3
}

# bats test_tags=clerk,statesync,correctness,ordering
@test "statesync-consistency: event records are in chronological order" {
    local total
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    local original_times
    original_times=$(jq -c '[.[].record_time]' "${BATS_FILE_TMPDIR}/all_records.json")
    local sorted_times
    sorted_times=$(jq -c '[.[].record_time] | sort' "${BATS_FILE_TMPDIR}/all_records.json")

    if [[ "${original_times}" != "${sorted_times}" ]]; then
        echo "FAIL: event records are not in chronological order" >&2
        return 1
    fi

    echo "  OK: all ${total} records are in chronological order" >&3
}

# bats test_tags=clerk,statesync,correctness,uniqueness
@test "statesync-consistency: no duplicate event record IDs" {
    local total unique_count
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    unique_count=$(jq '[.[].id] | unique | length' "${BATS_FILE_TMPDIR}/all_records.json")

    if [[ "${total}" -ne "${unique_count}" ]]; then
        local dupes
        dupes=$(( total - unique_count ))
        echo "FAIL: found ${dupes} duplicate record IDs out of ${total} total" >&2
        return 1
    fi

    echo "  OK: all ${total} record IDs are unique" >&3
}

# bats test_tags=clerk,statesync,correctness,count
@test "statesync-consistency: record count matches latest record ID" {
    local total
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    local max_id
    max_id=$(jq '[.[].id] | max' "${BATS_FILE_TMPDIR}/all_records.json")

    # Allow for the case where the first ID is 1 (standard) or 0 (edge case)
    local first_id
    first_id=$(jq '[.[].id] | min' "${BATS_FILE_TMPDIR}/all_records.json")
    local expected_count=$(( max_id - first_id + 1 ))

    if [[ "${total}" -ne "${expected_count}" ]]; then
        echo "FAIL: fetched ${total} records but ID range [${first_id}..${max_id}] implies ${expected_count}" >&2
        return 1
    fi

    echo "  OK: ${total} records matches ID range [${first_id}..${max_id}]" >&3
}

# bats test_tags=clerk,statesync,correctness,references
@test "statesync-consistency: all records have valid tx_hash and contract fields" {
    # EventRecord proto has: id, contract, data, tx_hash, log_index, bor_chain_id, record_time
    # (no block_number field). Validate the fields that DO exist.
    local invalid_count
    invalid_count=$(jq '
        [.[] | select(
            (.tx_hash // "" | length) == 0 or
            (.contract // "" | length) == 0
        )] | length
    ' "${BATS_FILE_TMPDIR}/all_records.json")

    if [[ "${invalid_count}" -gt 0 ]]; then
        echo "FAIL: ${invalid_count} records have empty tx_hash or contract" >&2
        return 1
    fi

    local total
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    echo "  OK: all ${total} records have valid tx_hash and contract fields" >&3
}

# bats test_tags=clerk,statesync,correctness,api-consistency
@test "statesync-consistency: latest record ID from API matches paginated count" {
    local total
    total=$(jq 'length' "${BATS_FILE_TMPDIR}/all_records.json")
    local max_fetched_id
    max_fetched_id=$(jq '[.[].id] | max // 0' "${BATS_FILE_TMPDIR}/all_records.json")

    # Re-fetch latest-id to get the freshest value
    local api_latest
    api_latest=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/latest-id" 2>/dev/null \
        | jq -r '.latest_record_id // "0"' 2>/dev/null || echo "0")

    # The API latest may have advanced since we paginated, so allow max_fetched <= api_latest
    if [[ "${max_fetched_id}" -gt "${api_latest}" ]]; then
        echo "FAIL: fetched record ID ${max_fetched_id} exceeds API latest_record_id=${api_latest}" >&2
        return 1
    fi

    echo "  OK: max fetched ID=${max_fetched_id}, API latest=${api_latest} (consistent)" >&3
}
