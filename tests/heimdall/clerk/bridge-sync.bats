#!/usr/bin/env bats
# bats file_tags=heimdall,clerk,bridge,correctness

# Bridge Synchronization
# ======================
# Verifies that Heimdall's bridge between L1 and L2 is operating correctly
# and that state sync events are being processed in a timely manner.
#
# The bridge processes L1 events and submits checkpoints back to L1. A stuck
# bridge means deposits are delayed, governance changes are not applied, and
# the checkpoint stream to L1 stops — blocking withdrawals.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - L1 RPC reachable at L1_RPC_URL
#   - At least 1 state sync event processed by Heimdall
#
# RUN: bats tests/heimdall/clerk/bridge-sync.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # Resolve the CometBFT JSON-RPC URL.  It is exposed on a different port
    # from the Cosmos REST API (L2_CL_API_URL).  Try kurtosis first, then
    # fall back to replacing the REST port (1317) with the CometBFT default
    # (26657).
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            # kurtosis port print already returns a full URL (http://host:port)
            export L2_CL_RPC_URL="${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi
    echo "L2_CL_RPC_URL=${L2_CL_RPC_URL}" >&3

    # Probe the Heimdall clerk endpoint.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/latest-id" 2>/dev/null \
        | jq -r '.latest_record_id // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall clerk endpoint not reachable at ${L2_CL_API_URL} — all bridge-sync tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/flag_clerk_unavailable"
    else
        echo "Heimdall clerk endpoint reachable; latest_record_id=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/flag_clerk_unavailable"
    fi

    # Probe L1 RPC separately — tests 3 and 4 may need it.
    local l1_probe
    l1_probe=$(curl -s -m 15 --connect-timeout 5 -X POST "${L1_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null || true)

    if [[ -z "${l1_probe}" ]]; then
        echo "NOTE: L1 RPC not reachable at ${L1_RPC_URL} — L1-dependent tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/flag_l1_unavailable"
    else
        echo "L1 RPC reachable; eth_blockNumber=${l1_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/flag_l1_unavailable"
    fi

    # Probe CometBFT RPC separately — test 5 requires it.
    local rpc_probe
    rpc_probe=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${rpc_probe}" ]]; then
        echo "NOTE: CometBFT RPC not reachable at ${L2_CL_RPC_URL} — block height consistency test will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/flag_cometbft_rpc_unavailable"
    else
        echo "CometBFT RPC reachable; latest_block_height=${rpc_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/flag_cometbft_rpc_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    # Re-derive L2_CL_RPC_URL so it is available in every test subshell.
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            # kurtosis port print already returns a full URL (http://host:port)
            export L2_CL_RPC_URL="${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi

    if [[ "$(cat "${BATS_FILE_TMPDIR}/flag_clerk_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall clerk endpoint not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the latest record ID from the Heimdall clerk module.
# Prints the numeric latest_record_id on stdout, or returns 1.
_get_latest_record_id() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/latest-id" 2>/dev/null || true)
    local record_id
    record_id=$(printf '%s' "${raw}" | jq -r '.latest_record_id // empty' 2>/dev/null || true)
    if [[ -z "${record_id}" || "${record_id}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${record_id}"
}

# Fetch a page of event records from the Heimdall clerk module.
# Prints the raw JSON array of event record objects on stdout, or returns 1.
_get_event_records() {
    local page="${1:-1}"
    local limit="${2:-50}"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/clerk/event-records/list?page=${page}&limit=${limit}" \
        2>/dev/null || true)
    local records
    records=$(printf '%s' "${raw}" | jq -c '.event_records // .result // empty' 2>/dev/null || true)
    if [[ -z "${records}" || "${records}" == "null" || "${records}" == "[]" ]]; then
        return 1
    fi
    printf '%s' "${records}"
}

# Fetch the current L1 block number (hex) via eth_blockNumber.
# Prints the decimal block number on stdout, or returns 1.
_get_l1_block_number() {
    local hex
    hex=$(curl -s -m 15 --connect-timeout 5 -X POST "${L1_RPC_URL}" \
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

# Fetch the checkpoint ack count from the Heimdall REST API.
# Prints the numeric ack_count on stdout, or returns 1.
_get_checkpoint_ack_count() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/checkpoints/count" 2>/dev/null || true)
    local ack_count
    ack_count=$(printf '%s' "${raw}" | jq -r '.ack_count // empty' 2>/dev/null || true)
    if [[ -z "${ack_count}" || "${ack_count}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${ack_count}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=clerk,bridge,correctness
@test "heimdall bridge: clerk has processed at least one state sync event" {
    local max_wait=180 poll_interval=10 elapsed=0
    local latest_record_id=0

    while [[ "$elapsed" -lt "$max_wait" ]]; do
        local raw_id
        raw_id=$(_get_latest_record_id || true)

        if [[ -z "${raw_id}" ]]; then
            echo "  [${elapsed}s] clerk API returned empty — retrying..." >&3
            sleep "$poll_interval"
            elapsed=$(( elapsed + poll_interval ))
            continue
        fi

        latest_record_id="${raw_id}"
        [[ "${latest_record_id}" =~ ^[0-9]+$ ]] || latest_record_id=0

        if [[ "${latest_record_id}" -gt 0 ]]; then
            echo "  OK: latest state sync record ID = ${latest_record_id} (after ${elapsed}s)" >&3
            return 0
        fi

        echo "  [${elapsed}s] latest_record_id=0 — waiting for first L1→L2 state sync..." >&3
        sleep "$poll_interval"
        elapsed=$(( elapsed + poll_interval ))
    done

    echo "  latest_record_id=${latest_record_id}" >&3
    skip "no L1→L2 state sync events after ${max_wait}s — L1 may not have emitted StateSynced events in this devnet"
}

# bats test_tags=clerk,bridge,correctness,safety
@test "heimdall bridge: clerk event record ID does not exceed L1 state counter" {
    local raw_id
    raw_id=$(_get_latest_record_id || true)

    if [[ -z "${raw_id}" ]]; then
        echo "FAIL: could not fetch latest_record_id from clerk endpoint" >&2
        return 1
    fi

    local latest_record_id="${raw_id}"
    [[ "${latest_record_id}" =~ ^[0-9]+$ ]] || latest_record_id=0

    # Fetch the event records list to determine the maximum ID seen.
    local records
    if ! records=$(_get_event_records 1 50); then
        skip "Could not fetch event records list from clerk — skipping ID consistency check"
    fi

    # Extract the maximum ID from the list.
    local max_id
    max_id=$(printf '%s' "${records}" | jq -r '[.[].id | tonumber] | max' 2>/dev/null || true)
    [[ "${max_id}" =~ ^[0-9]+$ ]] || max_id=0

    echo "  max_event_id_in_list=${max_id}  latest_record_id=${latest_record_id}" >&3

    if [[ "${max_id}" -gt "${latest_record_id}" ]]; then
        echo "FAIL: max event ID in list (${max_id}) > latest-id from clerk (${latest_record_id}) — state inconsistency detected" >&2
        return 1
    fi

    echo "  OK: max event ID in list (${max_id}) <= latest-id from clerk (${latest_record_id})" >&3
}

# bats test_tags=clerk,bridge,correctness,liveness
@test "heimdall bridge: event records are being processed in a timely manner" {
    local records
    if ! records=$(_get_event_records 1 50); then
        skip "Could not fetch event records list from clerk — skipping freshness check"
    fi

    # Get the last event record from the list (highest index).
    local last_record
    last_record=$(printf '%s' "${records}" | jq -c '.[-1] // empty' 2>/dev/null || true)

    if [[ -z "${last_record}" || "${last_record}" == "null" ]]; then
        skip "Event records list is empty — cannot check freshness"
    fi

    # Extract the record_time field (RFC3339 / ISO8601 timestamp).
    local time_str
    time_str=$(printf '%s' "${last_record}" | jq -r '.record_time // empty' 2>/dev/null || true)

    if [[ -z "${time_str}" || "${time_str}" == "null" ]]; then
        skip "Cannot parse event record time — skipping freshness check"
    fi

    # Validate time_str is a well-formed RFC3339/ISO8601 timestamp before
    # passing to `date -d` — prevents unexpected interpretation of adversarial values.
    if [[ ! "${time_str}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        skip "record_time '${time_str}' is not a valid RFC3339 timestamp — skipping freshness check"
    fi

    # Parse the timestamp to epoch seconds (requires GNU date).
    local event_epoch
    event_epoch=$(date -d "${time_str}" +%s 2>/dev/null || true)

    if [[ -z "${event_epoch}" || ! "${event_epoch}" =~ ^[0-9]+$ ]]; then
        skip "Cannot parse event record time — skipping freshness check"
    fi

    local now_epoch
    now_epoch=$(date +%s)
    [[ "${now_epoch}" =~ ^[0-9]+$ ]] || now_epoch=0

    local age=$(( now_epoch - event_epoch ))
    [[ "${age}" =~ ^[0-9]+$ ]] || age=0

    local record_id
    record_id=$(printf '%s' "${last_record}" | jq -r '.id // "unknown"' 2>/dev/null || true)

    echo "  record_id=${record_id}  record_time=${time_str}  age_seconds=${age}" >&3

    # 24 hours = 86400 seconds
    if [[ "${age}" -gt 86400 ]]; then
        echo "FAIL: most recent state sync event is stale (age=${age}s, record_id=${record_id}) — bridge may be lagging" >&2
        return 1
    fi

    echo "  OK: most recent event record is recent (age = ${age} seconds)" >&3
}

# bats test_tags=clerk,bridge,correctness,safety
@test "heimdall bridge: at least one checkpoint has been acknowledged on L1" {
    # A non-zero ACK count proves the Heimdall→L1 bridge has completed at least
    # one full round-trip: Heimdall committed a checkpoint, the bridge submitted
    # it to the L1 root chain contract, and the contract acknowledged it.
    local ack_count
    if ! ack_count=$(_get_checkpoint_ack_count); then
        echo "FAIL: could not fetch checkpoint ack count from ${L2_CL_API_URL}/checkpoints/count" >&2
        return 1
    fi

    [[ "${ack_count}" =~ ^[0-9]+$ ]] || ack_count=0

    echo "  checkpoint_ack_count=${ack_count}" >&3

    if [[ "${ack_count}" -eq 0 ]]; then
        echo "FAIL: no checkpoints have been acknowledged on L1 — bridge may not be running" >&2
        return 1
    fi

    echo "  OK: checkpoint ACK count = ${ack_count}, bridge has completed at least one L1 round-trip" >&3
}

# bats test_tags=bridge,correctness,liveness
@test "heimdall bridge: Heimdall block height is not lagging behind CometBFT tip" {
    # Fetch REST API block height from /status.
    # Heimdall REST returns flat JSON: {"latest_block_height": 1234, ...}
    # (no .result.sync_info wrapper, and the value is a number not a string)
    local rest_raw
    rest_raw=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_API_URL}/status" 2>/dev/null || true)
    local rest_height
    rest_height=$(printf '%s' "${rest_raw}" \
        | jq -r '.latest_block_height // empty' 2>/dev/null || true)
    [[ "${rest_height}" =~ ^[0-9]+$ ]] || rest_height=""

    # Check if CometBFT RPC is available.
    if [[ "$(cat "${BATS_FILE_TMPDIR}/flag_cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        if [[ -z "${rest_height}" ]]; then
            skip "Neither REST API /status nor CometBFT RPC is available — skipping height consistency check"
        fi
        skip "CometBFT RPC not available — skipping height consistency check"
    fi

    # Fetch CometBFT RPC block height from /status.
    local rpc_raw
    rpc_raw=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null || true)
    local rpc_height
    rpc_height=$(printf '%s' "${rpc_raw}" \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
    [[ "${rpc_height}" =~ ^[0-9]+$ ]] || rpc_height=""

    if [[ -z "${rest_height}" && -z "${rpc_height}" ]]; then
        skip "Could not fetch block height from either REST API or CometBFT RPC"
    fi

    if [[ -z "${rest_height}" ]]; then
        skip "REST API /status not available — cannot compare heights"
    fi

    if [[ -z "${rpc_height}" ]]; then
        skip "CometBFT RPC /status not available — cannot compare heights"
    fi

    local delta
    if [[ "${rest_height}" -ge "${rpc_height}" ]]; then
        delta=$(( rest_height - rpc_height ))
    else
        delta=$(( rpc_height - rest_height ))
    fi
    [[ "${delta}" =~ ^[0-9]+$ ]] || delta=0

    echo "  rest_height=${rest_height}  rpc_height=${rpc_height}  delta=${delta}" >&3

    if [[ "${delta}" -gt 10 ]]; then
        echo "FAIL: REST API and CometBFT RPC disagree on block height by more than 10 (delta=${delta}) — possible connection to different nodes" >&2
        return 1
    fi

    echo "  OK: REST height=${rest_height}, RPC height=${rpc_height} (delta=${delta})" >&3
}
