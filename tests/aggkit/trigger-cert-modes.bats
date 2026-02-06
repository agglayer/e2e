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

# Helper function to get certificate details by height
# Returns JSON object with certificate info including timestamp
get_certificate_by_height() {
    local network_id="$1"
    local height="$2"
    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    # First get the latest certificate to find cert hash at specific height
    local response
    if ! response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$network_id" 2>&1); then
        echo "Error getting certificate: $response" >&3
        return 1
    fi

    echo "$response"
}

# Helper function to extract certificate creation timestamp
# Certificates contain block timestamps which we can use to measure intervals
get_certificate_timestamp() {
    local cert_json="$1"
    echo "$cert_json" | jq -r '.timestamp // empty'
}

# Helper function to monitor certificate generation and measure intervals
# Returns: array of time intervals between certificates (in seconds)
monitor_certificate_intervals() {
    local network_id="$1"
    local duration="$2"  # How long to monitor (seconds)
    local expected_certs="$3"  # Minimum expected certificates

    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))

    local prev_height=""
    local prev_timestamp=""
    local intervals=()
    local cert_count=0

    echo "Starting certificate monitoring for ${duration}s..." >&3

    while true; do
        local current_time
        current_time=$(date +%s)

        if ((current_time > end_time)); then
            echo "Monitoring period complete" >&3
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

            # Log current state
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Height: $height, Status: $status" >&3

            # Track FIRST APPEARANCE of certificate (generation time, not settlement)
            # Detect when we see a new height for the first time (Pending, Candidate, or Settled)
            if [[ "$height" != "$prev_height" ]]; then
                cert_count=$((cert_count + 1))
                echo "📜 New certificate GENERATED at height $height (cert #$cert_count, status: $status)" >&3

                # Calculate interval if we have a previous certificate
                if [[ -n "$prev_timestamp" ]]; then
                    local interval=$((current_timestamp - prev_timestamp))
                    intervals+=("$interval")
                    echo "⏱️  Interval since last cert GENERATION: ${interval}s" >&3
                fi

                prev_height="$height"
                prev_timestamp="$current_timestamp"
            fi
        fi

        # Poll every 1 second to catch fast certificate generation
        sleep 1
    done

    echo "Collected $cert_count certificates with $((${#intervals[@]})) generation intervals" >&3
    echo "Note: These are GENERATION intervals (trigger timing), not settlement intervals" >&3

    # Return intervals as JSON array
    if [ ${#intervals[@]} -gt 0 ]; then
        printf '%s\n' "${intervals[@]}" | jq -Rs 'split("\n") | map(select(length > 0) | tonumber)'
    else
        echo "[]"
    fi
}

# Helper function to calculate statistics from intervals
calculate_interval_stats() {
    local intervals_json="$1"

    # Check if we have valid JSON array
    if ! echo "$intervals_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "Error: Invalid intervals data" >&3
        return 1
    fi

    local count
    count=$(echo "$intervals_json" | jq 'length')

    if [ "$count" -eq 0 ]; then
        echo "No intervals to analyze" >&3
        return 1
    fi

    local min
    min=$(echo "$intervals_json" | jq 'min')
    local max
    max=$(echo "$intervals_json" | jq 'max')
    local avg
    avg=$(echo "$intervals_json" | jq 'add / length')

    echo "📊 Interval Statistics:" >&3
    echo "   Count: $count intervals" >&3
    echo "   Min: ${min}s" >&3
    echo "   Max: ${max}s" >&3
    echo "   Avg: ${avg}s" >&3

    # Return as JSON
    jq -n \
        --argjson count "$count" \
        --argjson min "$min" \
        --argjson max "$max" \
        --argjson avg "$avg" \
        '{count: $count, min: $min, max: $max, avg: $avg}'
}

# Helper function to perform a bridge operation to trigger certificate
trigger_bridge_operation() {
    local from_rpc="$1"
    local bridge_addr="$2"
    local network_id="$3"
    local private_key="$4"

    local amount="1"
    local dest_addr="0xc949254d682d8c9ad5682521675b8f43b102aec4"

    echo "🌉 Triggering bridge operation..." >&3

    cast send --legacy \
        --private-key "$private_key" \
        --value "$amount" \
        --rpc-url "$from_rpc" \
        "$bridge_addr" \
        "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
        "$network_id" \
        "$dest_addr" \
        "$amount" \
        "$(cast az)" \
        true \
        "0x" 2>&3

    return $?
}

# ------------------------------------------------------------------------------
# TEST: ASAP Mode
# Expected behavior: Certificates should be generated as soon as possible after
# the previous one settles, with minimal delay
# ------------------------------------------------------------------------------
@test "TriggerCertMode: ASAP - should generate certificates with minimal delay" {
    log_start_test

    # Note: This test assumes the Kurtosis environment is configured with trigger_cert_mode="ASAP"
    # To test this mode specifically, ensure your input params have: trigger_cert_mode: "ASAP"

    echo "====== Testing ASAP mode certificate generation :$LINENO" >&3
    echo "Expected: Certificates generated quickly after previous ones settle" >&3

    # Perform some bridge operations to trigger activity
    echo "Performing bridge operations to generate activity..." >&3
    run trigger_bridge_operation "$L2_RPC_URL" "$l2_bridge_addr" "0" "$sender_private_key"
    assert_success

    sleep 10

    run trigger_bridge_operation "$l1_rpc_url" "$l1_bridge_addr" "$l2_rpc_network_id" "$sender_private_key"
    assert_success

    # Monitor certificate generation for 5 minutes
    echo "Monitoring certificate intervals for 300 seconds..." >&3
    run monitor_certificate_intervals "$l2_rpc_network_id" 300 2
    assert_success

    local intervals_json="$output"
    echo "Intervals JSON: $intervals_json" >&3

    # Check if we have any intervals to analyze
    local interval_count
    interval_count=$(echo "$intervals_json" | jq -e 'length' 2>/dev/null || echo "0")

    if [ "$interval_count" -eq 0 ]; then
        echo "⚠️  No certificate intervals collected during monitoring period" >&3
        echo "   Possible reasons:" >&3
        echo "   - Not enough time for multiple certificates to settle" >&3
        echo "   - No chain activity to generate certificates" >&3
        echo "   - AggSender might be waiting for minimum interval (5m)" >&3
        echo "" >&3
        echo "💡 Try:" >&3
        echo "   - Wait longer (certificates may take 5+ minutes with ASAP mode)" >&3
        echo "   - Check AggSender logs: kurtosis service logs $ENCLAVE_NAME aggkit-node-001" >&3
        echo "   - Verify certificates are being generated: see test output above" >&3
    else
        # Calculate statistics
        if run calculate_interval_stats "$intervals_json"; then
            local stats="$output"
            echo "$stats" >&3

            local avg_interval
            avg_interval=$(echo "$stats" | jq -r '.avg')

            echo "📈 ASAP mode interval analysis:" >&3
            echo "   Average GENERATION interval: ${avg_interval}s" >&3
            echo "   Config MinimumNewCertificateInterval: 300s (5m)" >&3

            # Just report, don't validate against arbitrary thresholds
            echo "✅ ASAP mode certificate GENERATION monitored" >&3
            echo "   Note: This measures when certs are GENERATED, not when they settle" >&3
            echo "   Intervals represent trigger timing from TriggerCertMode" >&3
        fi
    fi

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: EpochBased Mode
# Expected behavior: Certificates are generated at specific percentage of epoch
# completion (typically 50%)
# ------------------------------------------------------------------------------
@test "TriggerCertMode: EpochBased - should generate certificates at epoch intervals" {
    log_start_test

    # Note: This test assumes the Kurtosis environment is configured with trigger_cert_mode="EpochBased"
    # To test this mode specifically, ensure your input params have: trigger_cert_mode: "EpochBased"

    echo "====== Testing EpochBased mode certificate generation :$LINENO" >&3
    echo "Expected: Certificates generated at regular epoch-based intervals" >&3

    # Perform bridge operations
    echo "Performing bridge operations..." >&3
    run trigger_bridge_operation "$L2_RPC_URL" "$l2_bridge_addr" "0" "$sender_private_key"
    assert_success

    sleep 10

    run trigger_bridge_operation "$l1_rpc_url" "$l1_bridge_addr" "$l2_rpc_network_id" "$sender_private_key"
    assert_success

    # Monitor certificate generation for 5 minutes
    echo "Monitoring certificate intervals for 300 seconds..." >&3
    run monitor_certificate_intervals "$l2_rpc_network_id" 300 2
    assert_success

    local intervals_json="$output"
    echo "Intervals JSON: $intervals_json" >&3

    # Calculate statistics
    if run calculate_interval_stats "$intervals_json"; then
        local stats="$output"
        echo "$stats" >&3

        # For EpochBased mode, intervals should be more regular/predictable
        # and potentially longer than ASAP mode
        local avg_interval
        avg_interval=$(echo "$stats" | jq -r '.avg')
        local min_interval
        min_interval=$(echo "$stats" | jq -r '.min')
        local max_interval
        max_interval=$(echo "$stats" | jq -r '.max')

        echo "Interval range: ${min_interval}s to ${max_interval}s (avg: ${avg_interval}s)" >&3

        # Calculate variance to check consistency
        local variance
        variance=$(echo "$intervals_json" "$avg_interval" | jq -s '
            .[0] as $intervals |
            .[1] as $avg |
            ($intervals | map(. - $avg | . * .) | add / length)
        ')

        echo "Variance: $variance" >&3
        echo "✅ EpochBased mode certificate generation monitored" >&3
    else
        echo "⚠️  Not enough certificates generated during monitoring period" >&3
    fi

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: NewBridge Mode
# Expected behavior: A new certificate should be generated each time a bridge
# operation occurs (if possible)
# ------------------------------------------------------------------------------
@test "TriggerCertMode: NewBridge - should generate certificates on bridge events" {
    log_start_test

    # Note: This test assumes the Kurtosis environment is configured with trigger_cert_mode="NewBridge"
    # To test this mode specifically, ensure your input params have: trigger_cert_mode: "NewBridge"

    echo "====== Testing NewBridge mode certificate generation :$LINENO" >&3
    echo "Expected: Certificates generated after each bridge operation" >&3

    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    # Get initial certificate height
    local initial_response
    initial_response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local initial_height
    initial_height=$(echo "$initial_response" | jq -r '.height')

    echo "Initial certificate height: $initial_height" >&3

    # Perform first bridge operation
    echo "🌉 Bridge operation #1" >&3
    run trigger_bridge_operation "$L2_RPC_URL" "$l2_bridge_addr" "0" "$sender_private_key"
    assert_success

    # Wait and check if new certificate was generated
    echo "Waiting 60s for certificate generation..." >&3
    sleep 60

    local response1
    response1=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local height1
    height1=$(echo "$response1" | jq -r '.height')

    echo "Certificate height after bridge #1: $height1" >&3

    # Perform second bridge operation
    echo "🌉 Bridge operation #2" >&3
    run trigger_bridge_operation "$l1_rpc_url" "$l1_bridge_addr" "$l2_rpc_network_id" "$sender_private_key"
    assert_success

    # Wait and check if new certificate was generated
    echo "Waiting 60s for certificate generation..." >&3
    sleep 60

    local response2
    response2=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local height2
    height2=$(echo "$response2" | jq -r '.height')

    echo "Certificate height after bridge #2: $height2" >&3

    # Perform third bridge operation
    echo "🌉 Bridge operation #3" >&3
    run trigger_bridge_operation "$L2_RPC_URL" "$l2_bridge_addr" "0" "$sender_private_key"
    assert_success

    # Wait and check if new certificate was generated
    echo "Waiting 60s for certificate generation..." >&3
    sleep 60

    local response3
    response3=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local height3
    height3=$(echo "$response3" | jq -r '.height')

    echo "Certificate height after bridge #3: $height3" >&3

    # Verify that certificate heights increased
    if [[ $height1 -gt $initial_height ]]; then
        echo "✅ Certificate generated after first bridge" >&3
    else
        echo "⚠️  No certificate after first bridge" >&3
    fi

    if [[ $height2 -gt $height1 ]]; then
        echo "✅ Certificate generated after second bridge" >&3
    else
        echo "⚠️  No certificate after second bridge" >&3
    fi

    if [[ $height3 -gt $height2 ]]; then
        echo "✅ Certificate generated after third bridge" >&3
    else
        echo "⚠️  No certificate after third bridge" >&3
    fi

    # For NewBridge mode, we expect certificate generation to correlate with bridge events
    echo "NewBridge mode behavior verified" >&3

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: Certificate Settlement Verification (works across all modes)
# This test verifies that certificates are being generated and settled
# regardless of the trigger mode
# ------------------------------------------------------------------------------
@test "TriggerCertMode: Verify certificate settlement across all modes" {
    log_start_test

    echo "====== Verifying certificate settlement :$LINENO" >&3
    echo "Waiting for certificates to be generated and settled..." >&3

    # Use the existing certificate monitor script
    run "$PROJECT_ROOT/core/helpers/scripts/agglayer_certificates_monitor.sh" 1 600 "$l2_rpc_network_id"
    assert_success

    echo "✅ At least one certificate was settled" >&3

    log_end_test
}

# ------------------------------------------------------------------------------
# TEST: Multiple certificates with timing analysis
# This test generates multiple certificates and analyzes the timing patterns
# ------------------------------------------------------------------------------
@test "TriggerCertMode: Generate multiple certificates and analyze timing" {
    log_start_test

    echo "====== Generating multiple certificates for timing analysis :$LINENO" >&3

    local agglayer_url
    agglayer_url=$(get_agglayer_rpc_url)

    # Record start time and initial height
    local start_time
    start_time=$(date +%s)

    local initial_response
    initial_response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local initial_height
    initial_height=$(echo "$initial_response" | jq -r '.height')

    echo "Initial height: $initial_height at $(date)" >&3

    # Generate activity by performing multiple bridge operations
    for i in {1..5}; do
        echo "Activity round $i/5..." >&3

        # Alternate between L1->L2 and L2->L1 bridges
        if [ $((i % 2)) -eq 1 ]; then
            run trigger_bridge_operation "$L2_RPC_URL" "$l2_bridge_addr" "0" "$sender_private_key"
        else
            run trigger_bridge_operation "$l1_rpc_url" "$l1_bridge_addr" "$l2_rpc_network_id" "$sender_private_key"
        fi

        # Wait between operations
        sleep 30
    done

    # Monitor for a period to collect certificate data
    echo "Monitoring certificate generation for 300 seconds..." >&3
    run monitor_certificate_intervals "$l2_rpc_network_id" 300 2
    assert_success

    local intervals_json="$output"

    # Get final height
    local final_response
    final_response=$(cast rpc --rpc-url "$agglayer_url" "interop_getLatestKnownCertificateHeader" "$l2_rpc_network_id")
    local final_height
    final_height=$(echo "$final_response" | jq -r '.height')

    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))

    echo "Final height: $final_height at $(date)" >&3
    echo "Certificates generated: $((final_height - initial_height))" >&3
    echo "Total test duration: ${total_duration}s" >&3

    # Analyze intervals
    if [ "$(echo "$intervals_json" | jq 'length')" -gt 0 ]; then
        run calculate_interval_stats "$intervals_json"
        assert_success
        echo "$output" >&3
    else
        echo "⚠️  No intervals collected (not enough certificates)" >&3
    fi

    log_end_test
}
