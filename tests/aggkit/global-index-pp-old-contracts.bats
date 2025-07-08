setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Global Index PP old contracts: " {
    echo "----------- Test mainnet flag 1, unused bits != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "true"
    assert_success
    local global_index_1=$output
    echo "Global index: $global_index_1" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_1 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_1

    echo "----------- Test mainnet flag 1, rollup id != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "false" "true"
    assert_success
    local global_index_2=$output
    echo "Global index: $global_index_2" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_2 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_2

    echo "----------- Test mainnet flag 0, unused bits != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url" "true" "false"
    assert_success
    local global_index_3=$output
    echo "Global index: $global_index_3" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_3 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_3
}
