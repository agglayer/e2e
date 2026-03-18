#!/bin/bash
# Settlement monitoring helpers for fast-settlement tests.
# Provides functions to track certificate lifecycle timing, epoch-based
# settlement counts, and height progression across multiple certificates.

set -euo pipefail

# get_epoch_configuration
# Fetches the epoch configuration from the agglayer RPC.
# Outputs JSON with epoch_duration and genesis_block fields.
#
# Usage: get_epoch_configuration "$agglayer_rpc_url"
function get_epoch_configuration() {
    local rpc_url="$1"
    cast rpc --rpc-url "$rpc_url" interop_getEpochConfiguration
}

# get_current_epoch_number
# Computes the current epoch number from the L1 block number and epoch config.
#
# Usage: get_current_epoch_number "$agglayer_rpc_url" "$l1_rpc_url"
function get_current_epoch_number() {
    local agglayer_rpc_url="$1"
    local l1_rpc_url="$2"

    local epoch_config
    epoch_config=$(get_epoch_configuration "$agglayer_rpc_url")

    local epoch_duration genesis_block current_block
    epoch_duration=$(echo "$epoch_config" | jq -r '.epoch_duration')
    genesis_block=$(echo "$epoch_config" | jq -r '.genesis_block')
    current_block=$(cast bn --rpc-url "$l1_rpc_url")

    echo $(( (current_block - genesis_block) / epoch_duration ))
}

# get_settled_cert_header
# Fetches the latest settled certificate header for a given network.
#
# Usage: get_settled_cert_header "$agglayer_rpc_url" "$network_id"
function get_settled_cert_header() {
    local rpc_url="$1"
    local network_id="$2"
    cast rpc --rpc-url "$rpc_url" interop_getLatestSettledCertificateHeader "$network_id"
}

# get_pending_cert_header
# Fetches the latest pending certificate header for a given network.
#
# Usage: get_pending_cert_header "$agglayer_rpc_url" "$network_id"
function get_pending_cert_header() {
    local rpc_url="$1"
    local network_id="$2"
    cast rpc --rpc-url "$rpc_url" interop_getLatestPendingCertificateHeader "$network_id"
}

# get_known_cert_header
# Fetches the latest known certificate header for a given network.
#
# Usage: get_known_cert_header "$agglayer_rpc_url" "$network_id"
function get_known_cert_header() {
    local rpc_url="$1"
    local network_id="$2"
    cast rpc --rpc-url "$rpc_url" interop_getLatestKnownCertificateHeader "$network_id"
}

# get_cert_header_by_id
# Fetches a certificate header by its certificate ID.
#
# Usage: get_cert_header_by_id "$agglayer_rpc_url" "$cert_id"
function get_cert_header_by_id() {
    local rpc_url="$1"
    local cert_id="$2"
    cast rpc --rpc-url "$rpc_url" interop_getCertificateHeader "$cert_id"
}

# wait_for_settled_height_increase
# Waits until the settled certificate height increases beyond a given baseline.
# Returns the new settled certificate header JSON on success.
#
# Usage: wait_for_settled_height_increase "$agglayer_rpc_url" "$network_id" "$baseline_height" "$timeout" "$interval"
function wait_for_settled_height_increase() {
    local rpc_url="$1"
    local network_id="$2"
    local baseline_height="$3"
    local timeout="${4:-300}"
    local interval="${5:-10}"

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while true; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "Error: Timed out ($timeout s) waiting for settled height to exceed $baseline_height" >&2
            return 1
        fi

        local header
        header=$(get_settled_cert_header "$rpc_url" "$network_id")

        if [[ -n "$header" && "$header" != "null" ]]; then
            local current_height
            current_height=$(echo "$header" | jq -r '.height')
            if [[ "$current_height" != "null" && "$current_height" -gt "$baseline_height" ]]; then
                echo "$header"
                return 0
            fi
            echo "Current settled height: $current_height, waiting for > $baseline_height..." >&2
        fi

        sleep "$interval"
    done
}

# collect_settled_certs_during_window
# Polls for settled certificates during a time window and collects unique
# certificate IDs along with their heights and epoch numbers.
# Outputs one JSON object per line for each unique settled cert observed.
#
# Usage: collect_settled_certs_during_window "$agglayer_rpc_url" "$network_id" "$duration" "$poll_interval"
function collect_settled_certs_during_window() {
    local rpc_url="$1"
    local network_id="$2"
    local duration="${3:-300}"
    local poll_interval="${4:-5}"

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))

    local -a seen_cert_ids=()

    while [[ $(date +%s) -lt $end_time ]]; do
        local header
        header=$(get_settled_cert_header "$rpc_url" "$network_id" 2>/dev/null || echo "null")

        if [[ -n "$header" && "$header" != "null" ]]; then
            local cert_id
            cert_id=$(echo "$header" | jq -r '.certificate_id')

            if [[ -n "$cert_id" && "$cert_id" != "null" ]]; then
                local already_seen=0
                for seen in "${seen_cert_ids[@]+"${seen_cert_ids[@]}"}"; do
                    if [[ "$seen" == "$cert_id" ]]; then
                        already_seen=1
                        break
                    fi
                done

                if [[ "$already_seen" -eq 0 ]]; then
                    seen_cert_ids+=("$cert_id")
                    local height epoch_number
                    height=$(echo "$header" | jq -r '.height')
                    epoch_number=$(echo "$header" | jq -r '.epoch_number')
                    echo "{\"certificate_id\":\"$cert_id\",\"height\":$height,\"epoch_number\":$epoch_number}"
                fi
            fi
        fi

        sleep "$poll_interval"
    done
}

# wait_for_n_settled_certs
# Waits until N distinct certificates have settled beyond a baseline height.
# Returns a newline-delimited list of JSON objects for each settled cert.
#
# Usage: wait_for_n_settled_certs "$agglayer_rpc_url" "$network_id" "$n" "$baseline_height" "$timeout" "$poll_interval"
function wait_for_n_settled_certs() {
    local rpc_url="$1"
    local network_id="$2"
    local n="$3"
    local baseline_height="$4"
    local timeout="${5:-600}"
    local poll_interval="${6:-5}"

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    local -a seen_cert_ids=()
    local results=""

    while [[ ${#seen_cert_ids[@]} -lt $n ]]; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "Error: Timed out ($timeout s) waiting for $n settled certs (got ${#seen_cert_ids[@]})" >&2
            return 1
        fi

        local header
        header=$(get_settled_cert_header "$rpc_url" "$network_id" 2>/dev/null || echo "null")

        if [[ -n "$header" && "$header" != "null" ]]; then
            local cert_id height
            cert_id=$(echo "$header" | jq -r '.certificate_id')
            height=$(echo "$header" | jq -r '.height')

            if [[ -n "$cert_id" && "$cert_id" != "null" && "$height" -gt "$baseline_height" ]]; then
                local already_seen=0
                for seen in "${seen_cert_ids[@]+"${seen_cert_ids[@]}"}"; do
                    if [[ "$seen" == "$cert_id" ]]; then
                        already_seen=1
                        break
                    fi
                done

                if [[ "$already_seen" -eq 0 ]]; then
                    seen_cert_ids+=("$cert_id")
                    local epoch_number
                    epoch_number=$(echo "$header" | jq -r '.epoch_number')
                    results+="{\"certificate_id\":\"$cert_id\",\"height\":$height,\"epoch_number\":$epoch_number}"$'\n'
                    echo "Collected cert ${#seen_cert_ids[@]}/$n: height=$height epoch=$epoch_number id=$cert_id" >&2
                fi
            fi
        fi

        sleep "$poll_interval"
    done

    echo -n "$results"
}

# measure_settlement_time
# Measures the time between a certificate appearing as pending and becoming settled.
# Returns the elapsed time in seconds.
#
# Usage: measure_settlement_time "$agglayer_rpc_url" "$cert_id" "$timeout"
function measure_settlement_time() {
    local rpc_url="$1"
    local cert_id="$2"
    local timeout="${3:-300}"

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while true; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "Error: Timed out ($timeout s) waiting for cert $cert_id to settle" >&2
            return 1
        fi

        local header
        header=$(get_cert_header_by_id "$rpc_url" "$cert_id" 2>/dev/null || echo "null")

        if [[ -n "$header" && "$header" != "null" ]]; then
            local status
            status=$(echo "$header" | jq -r '.status')
            if [[ "$status" == "Settled" ]]; then
                local elapsed=$(( $(date +%s) - start_time ))
                echo "$elapsed"
                return 0
            fi
        fi

        sleep 2
    done
}

# verify_heights_monotonic
# Given newline-delimited JSON cert records, verifies heights are strictly increasing.
# Returns 0 if monotonic, 1 otherwise.
#
# Usage: echo "$cert_records" | verify_heights_monotonic
function verify_heights_monotonic() {
    local prev_height=-1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local height
        height=$(echo "$line" | jq -r '.height')
        if [[ "$height" -le "$prev_height" ]]; then
            echo "Error: Height $height is not greater than previous $prev_height" >&2
            return 1
        fi
        prev_height=$height
    done
    return 0
}

# count_certs_in_epoch
# Given newline-delimited JSON cert records, counts how many share the same epoch number.
# Outputs: "epoch_number:count" lines.
#
# Usage: echo "$cert_records" | count_certs_in_epoch
function count_certs_in_epoch() {
    local -A epoch_counts
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local epoch
        epoch=$(echo "$line" | jq -r '.epoch_number')
        epoch_counts[$epoch]=$(( ${epoch_counts[$epoch]:-0} + 1 ))
    done

    for epoch in "${!epoch_counts[@]}"; do
        echo "$epoch:${epoch_counts[$epoch]}"
    done
}
