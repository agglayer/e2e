

setup() {
    load '../../core/helpers/common-setup'

    _common_setup

    local combined_json_file="/opt/zkevm/combined.json"
    combined_json_output=$($CONTRACTS_SERVICE_WRAPPER "cat $combined_json_file" | tail -n +2)
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

    readonly weth_token_addr=$(cast call --rpc-url $L2_RPC_URL $bridge_addr 'WETHToken() (address)')
}

@test "Transfer message" {
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_message "$native_token_addr" "$l1_rpc_url"
    assert_success
    local bridge_tx_hash=$output

    echo "====== claimMessage (L2)" >&3
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 10 3 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 10 5 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 10 20 "$aggkit_node_url"
    assert_success
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 3 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 3 "$l1_rpc_network_id"
    assert_success

    echo "====== bridgeMessage L2 -> L1" >&3
    destination_net=0
    run bridge_message "$destination_addr" "$L2_RPC_URL"
    assert_success
}
