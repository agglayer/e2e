setup() {
    load '../../core/helpers/common-setup'
    load '../../core/helpers/common-multi_cdk-setup'
    _common_setup
    _common_multi_setup

    add_network2_to_agglayer
    fund_claim_tx_manager
    mint_pol_token "$l1_bridge_addr"
}

function add_network2_to_agglayer() {
    echo "=== Checking if network 2 is added to agglayer ===" >&3
    local _prev=$(kurtosis service exec $ENCLAVE agglayer "grep \"2 = \" /etc/zkevm/agglayer-config.toml || true" | kurtosis_filer_exec_method)
    if [ ! -z "$_prev" ]; then
        echo "Network 2 is already added to agglayer" >&3
        return
    fi
    echo "=== Adding network 2 to agglayer ===" >&3
    kurtosis service exec $ENCLAVE agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
    kurtosis service stop $ENCLAVE agglayer
    kurtosis service start $ENCLAVE agglayer
}

@test "Test L2 to L2 bridge" {
    echo "=== Running LxLy bridge eth L1 to L2(PP1) amount:$amount" >&3
    destination_net=$l2_pp1_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp1=$output

    echo "=== Running LxLy bridge eth L1 to L2(PP2) amount:$amount" >&3
    destination_net=$l2_pp2_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp2=$output

    echo "=== Running LxLy claim L1 to L2(PP1) for $bridge_tx_hash_pp1" >&3
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_pp1" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_l1_info_leaf "$l2_pp1_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l2_pp1_url" 50 10 "$l1_rpc_network_id" "$l2_bridge_addr"
    assert_success

    echo "=== Running LxLy claim L1 to L2(PP2) for $bridge_tx_hash_pp2" >&3
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_pp2" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_l1_info_leaf "$l2_pp2_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l2_pp2_url" 50 10 "$l1_rpc_network_id" "$l2_bridge_addr"
    assert_success

    # reduce eth amount
    amount=1234567
    echo "=== Running LxLy bridge L2(PP2) to L2(PP1) amount:$amount" >&3
    destination_net=$l2_pp1_network_id
    meta_bytes="0xbeef"
    run bridge_asset "$native_token_addr" "$l2_pp2_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(PP2) to L2(PP1) for: $bridge_tx_hash" >&3
    run get_bridge "$l2_pp2_network_id" "$bridge_tx_hash" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l2_pp2_network_id" "$deposit_count" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_l1_info_leaf "$l2_pp1_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l2_pp2_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l2_pp1_url" 50 10 "$l2_pp2_network_id" "$l2_bridge_addr"
    assert_success
    local global_index_pp2_to_pp1="$output"

    # Now we need to do a bridge on L2(PP1) to trigger a certificate to be sent to L1
    ether_value=${ETHER_VALUE:-"0.0100000054"}
    amount=$(cast to-wei $ether_value ether)
    echo "=== Running LxLy bridge eth L2(PP1) to L1 (trigger certificate sending on PP1) amount:$amount" >&3
    destination_net=$l1_rpc_network_id
    meta_bytes="0xabcd"
    run bridge_asset "$native_token_addr" "$l2_pp1_url" "$l2_bridge_addr"
    assert_success
    bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(PP1) to L1 for $bridge_tx_hash" >&3
    run get_bridge "$l2_pp1_network_id" "$bridge_tx_hash" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l2_pp1_network_id" "$deposit_count" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_l1_info_leaf "$l1_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l2_pp1_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_1_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$l1_rpc_url" 50 10 "$l2_pp1_network_id" "$l1_bridge_addr"
    assert_success

    if [[ "$ENCLAVE" == "aggkit" ]]; then
        echo "=== Waiting to settled certificate with imported bridge for global_index: $global_index_pp2_to_pp1"
        wait_to_settled_certificate_containing_global_index $aggkit_pp1_rpc_url $global_index_pp2_to_pp1
    fi
}

function fund_claim_tx_manager() {
    echo "=== Funding bridge auto-claim  ===" >&3
    cast send --legacy --value 100ether --rpc-url $l2_pp1_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
    cast send --legacy --value 100ether --rpc-url $l2_pp2_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05
}
