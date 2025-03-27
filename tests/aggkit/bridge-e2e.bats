setup() {
    load '../../core/helpers/common-setup'

    _common_setup

    local combined_json_file="/opt/zkevm/combined.json"
    combined_json_output=$($CONTRACTS_SERVICE_WRAPPER "cat $combined_json_file")
    bridge_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVMBridgeAddress)
    echo "Bridge address=$bridge_addr" >&3

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    readonly sender_addr="$(cast wallet address --private-key $sender_private_key)"
    destination_net=${DESTINATION_NET:-"1"}
    destination_addr=${DESTINATION_ADDRESS:-"0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"}
    ether_value=${ETHER_VALUE:-"0.0200000054"}
    amount=$(cast to-wei $ether_value ether)
    readonly native_token_addr=${NATIVE_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}
    readonly rollup_params_file=/opt/zkevm/create_rollup_parameters.json
    run bash -c "$CONTRACTS_SERVICE_WRAPPER 'cat $rollup_params_file' | tail -n +2 | jq -r '.gasTokenAddress'"
    assert_success
    assert_output --regexp "0x[a-fA-F0-9]{40}"
    gas_token_addr=$output
    readonly is_forced=${IS_FORCED:-"true"}
    meta_bytes=${META_BYTES:-"0x1234"}

    readonly l1_rpc_url=${L1_ETH_RPC_URL:-"$(kurtosis port print $ENCLAVE el-1-geth-lighthouse rpc)"}
    readonly aggkit_node_url=${AGGKIT_NODE_URL:-"$(kurtosis port print $ENCLAVE cdk-node-001 rpc)"}

    readonly dry_run=${DRY_RUN:-"false"}
    readonly l1_rpc_network_id=$(cast call --rpc-url $l1_rpc_url $bridge_addr 'networkID() (uint32)')
    readonly l2_rpc_network_id=$(cast call --rpc-url $L2_RPC_URL $bridge_addr 'networkID() (uint32)')
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    readonly erc20_artifact_path="core/contracts/erc20mock/ERC20Mock.json"
}

@test "Native gas token deposit to WETH" {
    destination_addr=$sender_addr
    run cast call --rpc-url $L2_RPC_URL $bridge_addr 'WETHToken() (address)'
    assert_success
    readonly weth_token_addr=$output

    local initial_receiver_balance=$(cast call --rpc-url "$L2_RPC_URL" "$weth_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance" >&3

    echo "=== Running LxLy deposit on L1 to network: $l2_rpc_network_id native_token: $native_token_addr" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url"
    assert_success
    local bridge_tx_hash=$output

    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 10 3 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 10 5 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 10 20 "$aggkit_node_url"
    assert_success
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 5 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 10 "$l1_rpc_network_id"
    assert_success

    echo "=== Running LxLy WETH ($weth_token_addr) deposit on L2 to L1 network" >&3
    destination_addr=$sender_addr
    destination_net=0
    run bridge_asset "$weth_token_addr" "$L2_RPC_URL"
    assert_success
    local bridge_tx_hash=$output
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
    run send_tx "$l1_rpc_url" "$sender_private_key" "$gas_token_addr" "$APPROVE_FN_SIG" "$bridge_addr" "$deposit_ether_value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$wei_amount
    meta_bytes="0x"
    run bridge_asset "$gas_token_addr" "$l1_rpc_url"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 10 3 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 10 5 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 10 20 "$aggkit_node_url"
    assert_success
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 5 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 10 "$l1_rpc_network_id"
    assert_success
    local claim_global_index="$output"

    # Validate the bridge_getClaims API
    echo "------- bridge_getClaims API testcase --------"
    run get_claim "$l2_rpc_network_id" "$claim_global_index" 10 3 "$aggkit_node_url"
    assert_success

    local origin_network="$(echo "$output" | jq -r '.origin_network')"
    local destination_network="$(echo "$output" | jq -r '.destination_network')"
    assert_equal "$l1_rpc_network_id" "$origin_network"
    assert_equal "$l2_rpc_network_id" "$destination_network"
    echo "🚀🚀 bridge_getClaims API testcase passed" >&3

    # Validate that the native token of receiver on L2 has increased by the bridge tokens amount
    run verify_balance "$L2_RPC_URL" "$native_token_addr" "$receiver" "$initial_receiver_balance" "$tokens_amount"
    assert_success
}

@test "Custom gas token withdrawal L2 -> L1" {
    echo "Custom gas token withdrawal (gas token addr: $gas_token_addr, L1 RPC: $l1_rpc_url, L2 RPC: $L2_RPC_URL)" >&3

    local initial_receiver_balance=$(cast call --rpc-url "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Receiver balance of gas token on L1 $initial_receiver_balance" >&3

    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL"
    assert_success
    local bridge_tx_hash=$output

    # Claim withdrawals (settle them on the L1)
    run get_bridge "$l2_rpc_network_id" "$bridge_tx_hash" 10 3 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l2_rpc_network_id" "$deposit_count" 10 5 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l1_rpc_network_id" "$l1_info_tree_index" 10 20 "$aggkit_node_url"
    assert_success
    run generate_claim_proof "$l2_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 5 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l1_rpc_url" 10 10 "$l2_rpc_network_id"
    assert_success

    # Validate that the token of receiver on L1 has increased by the bridge tokens amount
    run verify_balance "$l1_rpc_url" "$gas_token_addr" "$destination_addr" "$initial_receiver_balance" "$ether_value"
    if [ $status -eq 0 ]; then
        break
    fi
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
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_erc20_addr" "$APPROVE_FN_SIG" "$bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT ON L1
    local receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 10 3 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 10 5 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 10 20 "$aggkit_node_url"
    assert_success
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 5 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 10 "$l1_rpc_network_id"
    assert_success

    run wait_for_expected_token "$l1_erc20_addr" 10 2 "$aggkit_node_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.tokenMappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.tokenMappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success
}
