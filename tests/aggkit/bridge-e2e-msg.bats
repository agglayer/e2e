

setup() {
    load '../../core/helpers/common-setup'
    _common_setup

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
