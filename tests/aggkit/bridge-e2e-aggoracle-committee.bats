#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

# Helper function to manage aggkit-001 service
manage_aggkit_nodes() {
    local service="$1"
    local action="$2"  # start or stop
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

@test "Test Aggoracle committee" {
    echo "Step 1: Bridging and claiming asset on L2..." >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit "0.01ether" wei)
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "aggoracle_committee: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    echo "Step 2: Stopping aggkit-001-aggoracle-committee-001, aggkit-001-aggoracle-committee-002 service..." >&3
    manage_aggkit_nodes "aggkit-001-aggoracle-committee-001" "stop"
    manage_aggkit_nodes "aggkit-001-aggoracle-committee-002" "stop"

    echo "Step 3: Bridging asset from L1 to L2 (without claiming)..." >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    local l1_latest_ger
    l1_latest_ger=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" 'getLastGlobalExitRoot() (bytes32)')
    log "🔍 Latest L1 GER: $l1_latest_ger"

    echo "Step 4: Waiting for 2 minutes to check if GER is not added to L2 map..." >&3
    sleep 120

    local l2_ger_status
    l2_ger_status=$(cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" 'globalExitRootMap(bytes32) (uint256)' "$l1_latest_ger")
    assert_equal "$l2_ger_status" "0"

    echo "Step 5: Starting aggkit-001-aggoracle-committee-001, aggkit-001-aggoracle-committee-002 service..." >&3
    manage_aggkit_nodes "aggkit-001-aggoracle-committee-001" "start"
    manage_aggkit_nodes "aggkit-001-aggoracle-committee-002" "start"

    echo "Step 6: Attempting to claim the second bridge transaction..., should succeed" >&3
    run process_bridge_claim "aggoracle_committee: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    echo "=== ✅ GER validation test completed successfully" >&3
}
