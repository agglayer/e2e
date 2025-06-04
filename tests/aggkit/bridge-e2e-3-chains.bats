setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    local num_chain=3
    _agglayer_cdk_common_multi_setup $num_chain

    add_network_to_agglayer 2 "$l2_pp2_url"
    add_network_to_agglayer 3 "$l2_pp3_url"
    fund_claim_tx_manager $num_chain
    mint_pol_token "$l1_bridge_addr"
}

@test "L1 → PP3 (native/WETH) → PP1" {
    # Get initial balance on PP1
    local initial_balance_pp1=$(get_token_balance "$l2_pp1_url" "$weth_token_addr_pp1" "$destination_addr")
    echo "Initial balance on PP1: $initial_balance_pp1" >&3

    echo "=== Running L1 native token deposit to PP3 network $l2_pp3_network_id (native_token: $native_token_addr)" >&3
    destination_addr=$sender_addr
    destination_net=$l2_pp3_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_l1_to_pp3=$output

    # Claim deposit on PP3
    echo "=== Running claim for L1 to PP3 bridge" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_l1_to_pp3" "$l2_pp3_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_3_url" "$l2_pp3_url"

    # Get balance on PP3 after first bridge
    local balance_pp3=$(get_token_balance "$l2_pp3_url" "$weth_token_addr_pp3" "$destination_addr")
    echo "Balance on PP3 after L1 bridge: $balance_pp3" >&3

    # Bridge from PP3 to PP1
    echo "=== Running PP3 native token deposit to PP1 network $l2_pp1_network_id" >&3
    destination_net=$l2_pp1_network_id
    run bridge_asset "$native_token_addr" "$l2_pp3_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash_pp3_to_pp1=$output

    # Claim deposit on PP1
    echo "=== Running claim for PP3 to PP1 bridge" >&3
    process_bridge_claim "$l2_pp3_network_id" "$bridge_tx_hash_pp3_to_pp1" "$l2_pp1_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_1_url" "$l2_pp1_url"

    # Verify final balance on PP1
    local final_balance_pp1=$(get_token_balance "$l2_pp1_url" "$weth_token_addr_pp1" "$destination_addr")
    echo "Final balance on PP1: $final_balance_pp1" >&3
}
