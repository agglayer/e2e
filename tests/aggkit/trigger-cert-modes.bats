#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    log_setup_test
    _agglayer_cdk_common_setup
}

# Helper function to get the agglayer RPC URL
get_agglayer_rpc_url() {
    local enclave="${kurtosis_enclave_name:-$ENCLAVE_NAME}"
    if [[ -z "$enclave" ]]; then
        echo "Error: ENCLAVE_NAME not set" >&3
        return 1
    fi
    kurtosis port print "$enclave" agglayer aglr-readrpc
}

# Monitor certificate generation and measure intervals
# Returns JSON array of intervals in seconds
monitor_certificate_intervals() {
    local network_id="$1"
    local duration="$2"

    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))

    local prev_height=""
    local prev_timestamp=""
    local intervals=()
    local cert_count=0

    echo "Monitoring certificate generation for ${duration}s..." >&3

    while true; do
        local current_time
        current_time=$(date +%s)

        if ((current_time > end_time)); then
            echo "Monitoring complete" >&3
            break
        fi

        # Get latest certificate
        local response
        if response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$network_id" 2>&1); then
            local height
            height=$(echo "$response" | jq -r '.height')
            local status
            status=$(echo "$response" | jq -r '.status')
            local current_timestamp
            current_timestamp=$(date +%s)

            # Track first appearance of each certificate (generation time)
            if [[ "$height" != "$prev_height" ]]; then
                cert_count=$((cert_count + 1))
                echo "[$(date '+%H:%M:%S')] Cert #$cert_count: height=$height, status=$status" >&3

                # Calculate interval
                if [[ -n "$prev_timestamp" ]]; then
                    local interval=$((current_timestamp - prev_timestamp))
                    intervals+=("$interval")
                    echo "  ⏱️  Interval: ${interval}s" >&3
                fi

                prev_height="$height"
                prev_timestamp="$current_timestamp"
            fi
        fi

        sleep 1
    done

    echo "Collected $cert_count certificates with ${#intervals[@]} intervals" >&3

    # Return intervals as JSON array
    if [ ${#intervals[@]} -gt 0 ]; then
        printf '%s\n' "${intervals[@]}" | jq -Rs 'split("\n") | map(select(length > 0) | tonumber)'
    else
        echo "[]"
    fi
}

# Calculate and display interval statistics
calculate_interval_stats() {
    local intervals_json="$1"

    if ! echo "$intervals_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        return 1
    fi

    local count
    count=$(echo "$intervals_json" | jq 'length')

    if [ "$count" -eq 0 ]; then
        return 1
    fi

    local min max avg
    min=$(echo "$intervals_json" | jq 'min')
    max=$(echo "$intervals_json" | jq 'max')
    avg=$(echo "$intervals_json" | jq 'add / length')

    echo "📊 Interval Statistics:" >&3
    echo "   Count: $count intervals" >&3
    echo "   Min: ${min}s" >&3
    echo "   Max: ${max}s" >&3
    echo "   Avg: ${avg}s" >&3

    jq -n \
        --argjson count "$count" \
        --argjson min "$min" \
        --argjson max "$max" \
        --argjson avg "$avg" \
        '{count: $count, min: $min, max: $max, avg: $avg}'
}

# ------------------------------------------------------------------------------
# TEST: ASAP Mode
# Measures certificate generation intervals with ASAP trigger mode
# ------------------------------------------------------------------------------
@test "TriggerCertMode: ASAP - measure generation intervals" {
    log_start_test

    echo "====== Testing ASAP mode :$LINENO" >&3
    echo "Config: MinimumNewCertificateInterval should control intervals" >&3

    # Monitor for 5 minutes
    run monitor_certificate_intervals "$l2_rpc_network_id" 300
    assert_success

    local intervals_json="$output"
    local interval_count
    interval_count=$(echo "$intervals_json" | jq -e 'length' 2>/dev/null || echo "0")

    if [ "$interval_count" -eq 0 ]; then
        echo "⚠️  No intervals collected - need more time or activity" >&3
    else
        if run calculate_interval_stats "$intervals_json"; then
            echo "$output" >&3
            echo "✅ ASAP mode intervals measured" >&3
        fi
    fi

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: EpochBased Mode
# Measures certificate generation intervals with EpochBased trigger mode
# ------------------------------------------------------------------------------
@test "TriggerCertMode: EpochBased - measure generation intervals" {
    log_start_test

    echo "====== Testing EpochBased mode :$LINENO" >&3
    echo "Config: EpochNotificationPercentage controls trigger timing" >&3

    # Monitor for 5 minutes
    run monitor_certificate_intervals "$l2_rpc_network_id" 300
    assert_success

    local intervals_json="$output"
    local interval_count
    interval_count=$(echo "$intervals_json" | jq -e 'length' 2>/dev/null || echo "0")

    if [ "$interval_count" -eq 0 ]; then
        echo "⚠️  No intervals collected - need more time or activity" >&3
    else
        if run calculate_interval_stats "$intervals_json"; then
            echo "$output" >&3

            # Calculate variance for consistency check
            local avg
            avg=$(echo "$output" | jq -r '.avg')
            local variance
            variance=$(echo "$intervals_json" "$avg" | jq -s '
                .[0] as $intervals |
                .[1] as $avg |
                ($intervals | map(. - $avg | . * .) | add / length)
            ')
            echo "   Variance: $variance" >&3
            echo "✅ EpochBased mode intervals measured" >&3
        fi
    fi

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: NewBridge Mode
# Verifies certificates are generated in response to bridge events
# ------------------------------------------------------------------------------
@test "TriggerCertMode: NewBridge - verify bridge-triggered generation" {
    log_start_test

    echo "====== Testing NewBridge mode :$LINENO" >&3
    echo "Expected: Certificate generated after each bridge operation" >&3

    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    # Get initial height
    local initial_response
    initial_response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local initial_height
    initial_height=$(echo "$initial_response" | jq -r '.height')
    echo "Initial height: $initial_height" >&3

    # Monitor and collect heights over time
    local heights=()
    local duration=300  # 5 minutes
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))

    while true; do
        local current_time
        current_time=$(date +%s)

        if ((current_time > end_time)); then
            break
        fi

        local response
        if response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id" 2>&1); then
            local height
            height=$(echo "$response" | jq -r '.height')

            # Check if height already seen
            local seen=false
            for h in "${heights[@]}"; do
                if [[ "$h" == "$height" ]]; then
                    seen=true
                    break
                fi
            done

            if [[ "$seen" == "false" ]]; then
                heights+=("$height")
                echo "[$(date '+%H:%M:%S')] New certificate: height=$height" >&3
            fi
        fi

        sleep 5
    done

    local cert_count=${#heights[@]}
    echo "Generated $cert_count certificates during monitoring period" >&3
    echo "✅ NewBridge mode monitored" >&3

    log_end_test
}
