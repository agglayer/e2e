setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    local num_chain=2
    _agglayer_cdk_common_multi_setup $num_chain

    add_network_to_agglayer 2 "$l2_pp2_url"
    mint_pol_token "$l1_bridge_addr"
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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_pp1" "$l2_pp1_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_pp1_url"

    echo "=== Running LxLy claim L1 to L2(PP2) for $bridge_tx_hash_pp2" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_pp2" "$l2_pp2_network_id" "$l2_bridge_addr" "$aggkit_bridge_2_url" "$aggkit_bridge_2_url" "$l2_pp2_url"

    # reduce eth amount
    amount=1234567
    echo "=== Running LxLy bridge L2(PP2) to L2(PP1) amount:$amount" >&3
    destination_net=$l2_pp1_network_id
    meta_bytes="0xbeef"
    run bridge_asset "$native_token_addr" "$l2_pp2_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(PP2) to L2(PP1) for: $bridge_tx_hash" >&3
    process_bridge_claim "$l2_pp2_network_id" "$bridge_tx_hash" "$l2_pp1_network_id" "$l2_bridge_addr" "$aggkit_bridge_2_url" "$aggkit_bridge_1_url" "$l2_pp1_url"
    global_index_pp2_to_pp1=$output

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
    process_bridge_claim "$l2_pp1_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l1_rpc_url"

    if [[ "$ENCLAVE_NAME" == "aggkit" ]]; then
        echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_pp2_to_pp1 (PP1 network: $aggkit_pp1_rpc_url)"
        wait_to_settled_certificate_containing_global_index $aggkit_pp1_rpc_url $global_index_pp2_to_pp1
    else
        echo "Waiting 10 minutes to get some verified batch...."
        run $PROJECT_ROOT/core/helpers/scripts/batch_verification_monitor.sh 0 600
        assert_success
    fi
}

@test "Transfer message L2 to L2" {
    echo "====== bridgeMessage L2(pp1) -> L2(pp2)" >&3
    destination_addr=$sender_addr
    destination_net=$l2_pp2_network_id

    # amount is 0 for now since we only want to bridge message
    amount=0
    run bridge_message "$native_token_addr" "$l2_pp1_url" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    log "Bridge transaction hash: $bridge_tx_hash"

    echo "====== claimMessage (L2 pp2)" >&3
    process_bridge_claim "$l2_pp1_network_id" "$bridge_tx_hash" "$l2_pp2_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_2_url" "$l2_pp2_url"
    claim_global_index=$output
    log "Claim global index: $claim_global_index"

    # verify the message is bridged correctly
    run get_claim "$l2_pp2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local claim_metadata=$(echo "$output" | jq -r '.metadata')
    log "Claim metadata: $claim_metadata"
    assert_equal "$claim_metadata" "$meta_bytes"
}
