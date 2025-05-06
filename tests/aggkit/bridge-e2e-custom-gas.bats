

setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

@test "Custom gas token deposit L1 -> L2" {
    echo "Custom gas token deposit (gas token addr: $gas_token_addr, L1 RPC: $l1_rpc_url, L2 RPC: $L2_RPC_URL)" >&3

    # SETUP
    # Set receiver address and query for its initial native token balance on the L2
    receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    local initial_receiver_balance=$(cast balance "$receiver" --rpc-url "$L2_RPC_URL")
    echo "Initial receiver ($receiver) balance of native token on L2 $initial_receiver_balance" >&3

    local l1_minter_balance=$(cast balance "0x8943545177806ED17B9F23F0a21ee5948eCaa776" --rpc-url "$l1_rpc_url")
    echo "Initial minter balance on L1 $l1_minter_balance" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance" of gas token on L1 >&3

    # Mint gas token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    local minter_key=${MINTER_KEY:-"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"}
    run mint_erc20_tokens "$l1_rpc_url" "$gas_token_addr" "$minter_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of gas token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_final_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    local expected_balance=$(echo "$gas_token_init_sender_balance + $wei_amount" |
        bc |
        awk '{print $1}')

    echo "Sender balance ($sender_addr) (gas token L1): $gas_token_final_sender_balance" >&3
    assert_equal "$gas_token_final_sender_balance" "$expected_balance"

    # Send approve transaction to the gas token on L1
    deposit_ether_value="0.1ether"
    run send_tx "$l1_rpc_url" "$sender_private_key" "$gas_token_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$deposit_ether_value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$wei_amount
    meta_bytes="0x"
    run bridge_asset "$gas_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 50 10 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 50 10 "$l1_rpc_network_id" "$l2_bridge_addr"
    assert_success
    local claim_global_index="$output"

    # Validate the bridge_getClaims API
    run get_claim "$l2_rpc_network_id" "$claim_global_index" 50 10 "$aggkit_node_url"
    assert_success

    # Validate that the native token of receiver on L2 has increased by the bridge tokens amount
    run verify_balance "$L2_RPC_URL" "$native_token_addr" "$receiver" "$initial_receiver_balance" "$tokens_amount"
    assert_success
}

@test "Custom gas token withdrawal L2 -> L1" {
    echo "Custom gas token withdrawal (gas token addr: $gas_token_addr, L1 RPC: $l1_rpc_url, L2 RPC: $L2_RPC_URL)" >&3

    local initial_receiver_balance=$(cast call --rpc-url "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Receiver balance of gas token on L1 $initial_receiver_balance" >&3

    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim withdrawals (settle them on the L1)
    run get_bridge "$l2_rpc_network_id" "$bridge_tx_hash" 50 10 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l2_rpc_network_id" "$deposit_count" 50 10 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l1_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l2_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l1_rpc_url" 50 10 "$l2_rpc_network_id" "$l1_bridge_addr"
    assert_success

    # Validate that the token of receiver on L1 has increased by the bridge tokens amount
    run verify_balance "$l1_rpc_url" "$gas_token_addr" "$destination_addr" "$initial_receiver_balance" "$ether_value"
    if [ $status -eq 0 ]; then
        break
    fi
    assert_success
}
