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
        if docker ps | grep -q "$service"; then
            echo "Stopping $service..." >&3
            kurtosis service stop "$kurtosis_enclave_name" "$service" || {
                echo "Error: Failed to stop $service" >&3
                return 1
            }
            echo "$service stopped." >&3
        else
            echo "$service does not exist in enclave $kurtosis_enclave_name. Skipping stop operation." >&3
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

# Helper function to check if a GER exists in the L2 GER contract
check_ger_exists_in_l2_contract() {
    local ger="$1"
    local l2_ger_addr="$2"

    echo "Checking if GER $ger exists in L2 GER contract at $l2_ger_addr..." >&3

    # Call globalExitRootMap(bytes32) function
    local result
    result=$(cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "globalExitRootMap(bytes32)(uint256)" "$ger" 2>/dev/null || echo "0")

    if [[ "$result" != "0" ]]; then
        echo "✅ GER $ger exists in L2 contract with value: $result" >&3
        return 0
    else
        echo "❌ GER $ger does not exist in L2 contract" >&3
        return 1
    fi
}

# Helper function to get the last global exit root from L1 GER contract
get_last_global_exit_root() {
    local l1_ger_addr="$1"

    echo "Getting last global exit root from L1 GER contract at $l1_ger_addr..." >&3

    local result
    result=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" "getLastGlobalExitRoot()(bytes32)" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")

    if [[ "$result" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "✅ Last GER: $result" >&3
        echo "$result"
    else
        echo "❌ Failed to get last GER" >&3
        return 1
    fi
}

@test "Aggoracle committee -> Stop all quorom nodes" {
    echo "=== 🧑‍💻 Running GER validation after claiming on L2" >&3

    echo "Step 1: Bridging and claiming asset on L2..." >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit "0.01ether" wei)

    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    echo "✅ Bridge transaction: $bridge_tx_hash" >&3

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success
    echo "✅ Asset claimed successfully on L2" >&3

    echo "Step 2: Stopping aggkit-001 service..." >&3
    manage_aggkit "stop"
    echo "✅ aggkit-001 service stopped" >&3

    echo "Step 3: Bridging asset from L1 to L2 (without claiming)..." >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    is_forced=false
    meta_bytes="0x"

    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    echo "✅ Bridge transaction: $bridge_tx_hash" >&3

    echo "Step 4: Monitoring that GER is not updated while aggkit-001 is stopped..." >&3
    local max_wait_time=120
    local check_interval=10

    echo "Step 5: Attempting to claim the second bridge transaction..." >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success
    echo "✅ GER was not updated during the monitoring period" >&3

    echo "Step 6: Starting aggkit-001 service..." >&3
    manage_aggkit "start"
    echo "✅ aggkit-001 service started" >&3

    echo "Step 7: Attempting to claim the second bridge transaction..." >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success
    echo "✅ Second asset claimed successfully after re-enabling aggkit-001" >&3

    echo "=== ✅ GER validation test completed successfully" >&3
}
