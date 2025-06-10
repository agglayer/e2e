setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    local num_chain=3
    _agglayer_cdk_common_multi_setup $num_chain

    add_network_to_agglayer 2 "$l2_pp2_url"
    add_network_to_agglayer 3 "$l2_pp3_url"
    mint_pol_token "$l1_bridge_addr"
}

@test "L1 → PP3 (native/WETH) → PP1" {
    run query_contract "$l2_pp1_url" "$weth_token_addr_pp1" "$BALANCE_OF_FN_SIG" "$destination_addr"
    assert_success
    local initial_weth_token_addr_pp1_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial destination addr balance $initial_weth_token_addr_pp1_balance of gas token on L1" >&3

    echo "=== Running LxLy bridge eth L1 to L2(PP3) amount:$amount" >&3
    destination_net=$l2_pp3_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp3=$output

    echo "=== Running LxLy claim L1 to L2(PP3) for $bridge_tx_hash_pp3" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_pp3" "$l2_pp3_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_3_url" "$l2_pp3_url"

    # reduce eth amount
    amount="0.01ether"
    local wei_amount=$(cast --to-unit $amount wei)
    echo "=== Running LxLy bridge L2(PP3) to L2(PP1) amount:$amount" >&3
    destination_net=$l2_pp1_network_id
    meta_bytes="0xbeef"
    run bridge_asset "$native_token_addr" "$l2_pp3_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(PP3) to L2(PP1) for: $bridge_tx_hash" >&3
    process_bridge_claim "$l2_pp3_network_id" "$bridge_tx_hash" "$l2_pp1_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_1_url" "$l2_pp1_url"
    global_index_pp3_to_pp1=$output

    # Verify final balance on PP1
    run query_contract "$l2_pp1_url" "$weth_token_addr_pp1" "$BALANCE_OF_FN_SIG" "$destination_addr"
    assert_success
    local weth_token_addr_pp1_final_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    local expected_balance=$(echo "$initial_weth_token_addr_pp1_balance + $wei_amount" |
        bc |
        awk '{print $1}')

    echo "$destination_addr balance on PP1: $weth_token_addr_pp1_final_balance" >&3
    assert_equal "$weth_token_addr_pp1_final_balance" "$expected_balance"
}
