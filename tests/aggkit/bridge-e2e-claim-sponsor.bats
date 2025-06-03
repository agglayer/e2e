setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Native token transfer L1 -> L2 using claimSponsor" {
    destination_addr="0x1aE97aE9de91A31df9FA788E6fE00Ba226CF0332"
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    log "Initial receiver balance of native token on L2 "$initial_receiver_balance" eth"

    log "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)"
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof="$output"
    
    run claim_bridge_claimSponsor "$bridge" "$proof" "$aggkit_bridge_url" "$l1_rpc_network_id" 10 2 "$initial_receiver_balance"
    assert_success
}
