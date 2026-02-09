#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    log_setup_test
    _agglayer_cdk_common_setup
}

# Get agglayer RPC URL
get_agglayer_rpc_url() {
    local enclave="${kurtosis_enclave_name:-$ENCLAVE_NAME}"
    if [[ -z "$enclave" ]]; then
        echo "Error: ENCLAVE_NAME not set" >&3
        return 1
    fi
    kurtosis port print "$enclave" agglayer aglr-readrpc
}

# Detect the configured TriggerCertMode from running config file
detect_trigger_mode() {
    local enclave="${kurtosis_enclave_name:-$ENCLAVE_NAME}"

    # Read TriggerCertMode from deployed config
    local mode
    mode=$(kurtosis service exec "$enclave" aggkit-001 'grep "^TriggerCertMode" /etc/aggkit/config.toml' 2>/dev/null | cut -d'"' -f2)

    if [[ -n "$mode" ]]; then
        echo "$mode"
    else
        echo "Unknown"
    fi
}

# Monitor certificate generation intervals
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
            break
        fi

        local response
        if response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$network_id" 2>&1); then
            local height
            height=$(echo "$response" | jq -r '.height')
            local status
            status=$(echo "$response" | jq -r '.status')
            current_timestamp=$(date +%s)

            # Track first appearance (generation time)
            if [[ "$height" != "$prev_height" ]]; then
                cert_count=$((cert_count + 1))
                echo "[$(date '+%H:%M:%S')] Cert #$cert_count: height=$height, status=$status" >&3

                if [[ -n "$prev_timestamp" ]]; then
                    local interval=$((current_timestamp - prev_timestamp))
                    intervals+=("$interval")
                    echo "  ⏱️  ${interval}s" >&3
                fi

                prev_height="$height"
                prev_timestamp="$current_timestamp"
            fi
        fi

        sleep 1
    done

    echo "Collected $cert_count certificates, ${#intervals[@]} intervals" >&3

    if [ ${#intervals[@]} -gt 0 ]; then
        printf '%s\n' "${intervals[@]}" | jq -Rs 'split("\n") | map(select(length > 0) | tonumber)'
    else
        echo "[]"
    fi
}

# Calculate statistics
calculate_stats() {
    local intervals_json="$1"

    if ! echo "$intervals_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        return 1
    fi

    local count min max avg variance
    count=$(echo "$intervals_json" | jq 'length')
    min=$(echo "$intervals_json" | jq 'min')
    max=$(echo "$intervals_json" | jq 'max')
    avg=$(echo "$intervals_json" | jq 'add / length')

    # Calculate variance
    variance=$(echo "$intervals_json" "$avg" | jq -s '
        .[0] as $intervals |
        .[1] as $avg |
        ($intervals | map(. - $avg | . * .) | add / length)
    ')

    jq -n \
        --argjson count "$count" \
        --argjson min "$min" \
        --argjson max "$max" \
        --argjson avg "$avg" \
        --argjson variance "$variance" \
        '{count: $count, min: $min, max: $max, avg: $avg, variance: $variance}'
}

# Certificate Generation Intervals (auto-detects mode by reading config file)
@test "Measure certificate generation intervals" {
    log_start_test

    # Detect configured mode
    local mode
    mode=$(detect_trigger_mode)
    echo "====== Detected TriggerCertMode: $mode :$LINENO" >&3

    # Show expected behavior based on mode
    case "$mode" in
        "ASAP")
            echo "Expected: Fast intervals controlled by MinimumNewCertificateInterval" >&3
            ;;
        "EpochBased")
            echo "Expected: Regular intervals at EpochNotificationPercentage of epoch" >&3
            ;;
        "NewBridge")
            echo "Expected: Certificates triggered by bridge events" >&3
            ;;
        "Auto")
            echo "Expected: Mode resolved based on AggsenderMode (see logs)" >&3
            ;;
        *)
            echo "Warning: Could not detect TriggerCertMode from logs" >&3
            ;;
    esac

    # Monitor certificate generation
    run monitor_certificate_intervals "$l2_rpc_network_id" 300
    assert_success

    local intervals_json="$output"

    # Calculate and display statistics
    if run calculate_stats "$intervals_json"; then
        local stats="$output"

        echo "" >&3
        echo "📊 Certificate Generation Statistics:" >&3
        echo "$stats" | jq -r '
            "   Count: \(.count) intervals",
            "   Min: \(.min)s",
            "   Max: \(.max)s",
            "   Avg: \(.avg)s",
            "   Variance: \(.variance)"
        ' >&3

        echo "" >&3
        echo "✅ Certificate generation intervals measured for $mode mode" >&3
    else
        echo "⚠️  No intervals collected - need more time or chain activity" >&3
        echo "   Try: longer monitoring duration or ensure bridge transactions are happening" >&3
    fi

    log_end_test
}
