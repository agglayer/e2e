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

@test "L1 → PP1 (custom gas token) → PP2" {
    # Set receiver address and query for its initial native token addr balance on the PP1
    local initial_receiver_balance_pp1=$(cast balance "$receiver" --rpc-url "$l2_pp1_url")
    echo "Initial receiver ($receiver) balance of native token addr on PP1 $initial_receiver_balance_pp1" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_addr_pp1" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance_l1=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance_l1" of gas token on L1 >&3

    # Mint gas token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    local minter_key=${MINTER_KEY:-"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"}
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$gas_token_addr_pp1" "$minter_key" "$sender_addr" "$tokens_amount"
    assert_success

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$l2_pp1_network_id
    amount=$tokens_amount
    meta_bytes="0x"
    run bridge_asset "$gas_token_addr_pp1" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the PP1)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_pp1_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_pp1_url"
    local claim_global_index="$output"
    # Validate the bridge_getClaims API
    run get_claim "$l2_pp1_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_1_url"
    assert_success

    local final_receiver_balance_pp1=$(cast balance "$receiver" --rpc-url "$l2_pp1_url")
    echo "Final receiver ($receiver) balance of gas token addr on PP1 $final_receiver_balance_pp1" >&3

    echo "==== 💰 Verifying balance on PP1" >&3
    run verify_balance "$l2_pp1_url" "$native_token_addr" "$destination_addr" "$initial_receiver_balance_pp1" "$amount"
    assert_success

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$l2_pp2_network_id
    amount="0.01ether"
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l2_pp1_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the PP2)
    run process_bridge_claim "$l2_pp1_network_id" "$bridge_tx_hash" "$l2_pp2_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_2_url" "$l2_pp2_url"
    local claim_global_index="$output"
    # Validate the bridge_getClaims API
    run get_claim "$l2_pp2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success

    run wait_for_expected_token "$gas_token_addr_pp1" "$l2_pp2_network_id" 15 2 "$aggkit_bridge_2_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$gas_token_addr_pp1" "$origin_token_addr"

    local pp2_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 PP2 wrapped token address $pp2_wrapped_token_addr"

    echo "==== 💰 Verifying balance on PP2" >&3
    run verify_balance "$l2_pp2_url" "$pp2_wrapped_token_addr" "$destination_addr" 0 "$amount"
    assert_success
}
