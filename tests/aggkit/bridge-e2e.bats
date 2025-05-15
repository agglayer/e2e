setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

@test "Transfer message" {
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "====== claimMessage (L2)" >&3
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

    echo "====== bridgeMessage L2 -> L1" >&3
    destination_net=0
    run bridge_message "$destination_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "ERC20 token deposit L1 -> L2" {
    echo "Retrieving ERC20 contract artifact from $erc20_artifact_path" >&3

    run jq -r '.bytecode' "$erc20_artifact_path"
    assert_success
    local erc20_bytecode="$output"

    run cast send --rpc-url "$l1_rpc_url" --private-key "$sender_private_key" --legacy --create "$erc20_bytecode"
    assert_success
    local erc20_deploy_output=$output
    echo "Contract deployment $erc20_deploy_output"

    local l1_erc20_addr=$(echo "$erc20_deploy_output" |
        grep 'contractAddress' |
        awk '{print $2}' |
        tr '[:upper:]' '[:lower:]')
    echo "ERC20 contract address: $l1_erc20_addr" >&3

    # Mint gas token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of gas token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_erc20_token_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    echo "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]" >&3

    # Send approve transaction to the gas token on L1
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_erc20_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT ON L1
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
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

    run wait_for_expected_token "$l1_erc20_addr" 50 10 "$aggkit_node_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.tokenMappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.tokenMappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success
}

@test "Native token transfer L1 -> L2" {
    destination_addr=$sender_addr
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 "$initial_receiver_balance" eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
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

    echo "=== Running L2 gas token ($native_token_addr) deposit to L1 network" >&3
    destination_addr=$sender_addr
    destination_net=0
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "Test UpdateRemovalHashChainValue" {
    echo "=== 🧑‍💻 Running UpdateRemovalHashChainValue" >&3
    run update_removal_hash_chain_value "$L2_RPC_URL" "$l2_ger_addr" "$l2_sovereignadmin_private_key"
    assert_success "UpdateRemovalHashChainValue failed"
}

@test "Verify certificate settlement" {
    echo "Waiting 10 minutes to get some settle certificate...." >&3

    run $PROJECT_ROOT/core/helpers/scripts/agglayer_certificates_monitor.sh 1 600 $l2_rpc_network_id
    assert_success
}
