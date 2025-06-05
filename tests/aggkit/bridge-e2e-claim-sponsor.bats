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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    
    run claim_bridge_claimSponsor "$bridge" "$proof" "$aggkit_bridge_url" "$l1_rpc_network_id" 10 2 "$initial_receiver_balance"
    assert_success
}
