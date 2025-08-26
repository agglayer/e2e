#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

# Helper function to manage aggkit-001 service
manage_aggkit() {
    local action="$1"  # start or stop
    local service="aggkit-001"
    local kurtosis_enclave_name=${ENCLAVE_NAME:-"aggkit"}

    if [[ "$action" == "stop" ]]; then
        if docker ps | grep "$service"; then
            echo "Stopping $service..." >&3
            kurtosis service stop "$kurtosis_enclave_name" "$service" || {
                echo "Error: Failed to stop $service" >&3
                return 1
            }
            echo "$service stopped." >&3
        else
            echo "Error: $service does not exist in enclave $kurtosis_enclave_name" >&3
            return 1
        fi
    elif [[ "$action" == "start" ]]; then
        echo "Starting $service..." >&3
        kurtosis service start "$kurtosis_enclave_name" "$service" || {
            echo "Error: Failed to start $service" >&3
            return 1
        }
        echo "$service started." >&3
    fi
}

@test "Aggoracle committee -> Stop all quorum nodes" {
    echo "=== 🧑‍💻 Running GER validation after claiming on L2" >&3

    echo "Step 1: Bridging and claiming asset on L2..." >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit "0.01ether" wei)

    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    # Get the latest GER from L1
    local l1_latest_ger
    l1_latest_ger=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" 'getLastGlobalExitRoot() (bytes32)')
    assert_success
    log "🔍 Latest L1 GER: $l1_latest_ger"

    echo "Step 2: Stopping aggkit-001 service..." >&3
    manage_aggkit "stop"

    echo "Step 3: Bridging asset from L1 to L2 (without claiming)..." >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    is_forced=false
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "Step 4: Checking L1 GER update propagation to L2 (should fail)..." >&3
    # Get the latest GER from L1
    local l1_latest_ger
    l1_latest_ger=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" 'getLastGlobalExitRoot() (bytes32)')
    assert_success
    log "🔍 Latest L1 GER: $l1_latest_ger"

    # Check initial status in the map for the L2 GER
    local initial_ger_status
    initial_ger_status=$(cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" 'globalExitRootMap(bytes32) (uint256)' "$l1_latest_ger")
    assert_success
    log "🔍 Initial GER status in L2 map for $l1_latest_ger: $initial_ger_status"
    assert_equal "$initial_ger_status" "0"

    log "⏳ Starting GER update monitoring for 2 minutes..."
    local start_time=$(date +%s)
    local end_time=$((start_time + 120))  # 2 minutes = 120 seconds
    local check_interval=10  # 10 seconds
    local check_count=0
    local ger_updated=false

    while [[ $(date +%s) -lt $end_time ]]; do
        check_count=$((check_count + 1))
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        log "🔍 Check $check_count: Elapsed time: ${elapsed}s"

        # Check current status in the map for the L1 GER
        local current_ger_status
        current_ger_status=$(cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" 'globalExitRootMap(bytes32) (uint256)' "$l1_latest_ger")
        assert_success

        log "🔍 L2 GER map status at check $check_count for $l1_latest_ger: $current_ger_status"

        # Check if the L1 GER has been added to the L2 map (status should change from 0 to non-zero)
        if [[ "$current_ger_status" != "0" && "$current_ger_status" != "$initial_ger_status" ]]; then
            ger_updated=true
            log "⚠️ L1 GER was added to L2 map with status: $current_ger_status"
            break
        fi

        log "⏳ L2 GER not yet updated. Waiting $check_interval seconds for next check..."
        sleep $check_interval
    done

    # Assert that GER was NOT updated in the map (this is the expected failure)
    if [[ "$ger_updated" == "true" ]]; then
        log "❌ Test FAILED: L1 GER was unexpectedly added to L2 map"
        log "L1 GER: $l1_latest_ger"
        log "L2 GER map status changed to: $current_ger_status"
        assert_failure "L1 GER should not have been added to L2 map during the monitoring period"
    else
        log "✅ Test PASSED: L1 GER was not added to L2 map during the 2-minute monitoring period"
        log "L1 GER: $l1_latest_ger"
        log "L2 GER map status remained at: $initial_ger_status"
        log "Expected behavior: L1 GER should not be added to L2 map when aggkit service is stopped"
    fi

    echo "Step 4: Starting aggkit-001 service..." >&3
    manage_aggkit "start"

    aggkit_bridge_url=$(_resolve_url_or_use_env "" \
        "aggkit-001" "rest" \
        "Failed to resolve aggkit bridge url from all fallback nodes" true)

    echo "Step 5: Attempting to claim the second bridge transaction..., should succeed" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    echo "=== ✅ GER validation test completed successfully" >&3
}
