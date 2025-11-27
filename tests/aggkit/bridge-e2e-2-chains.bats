#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    local num_chain=2
    _agglayer_cdk_common_multi_setup $num_chain

    add_network_to_agglayer 2 "$l2_rpc_url_2"
    mint_pol_token "$l1_bridge_addr"
    readonly aggoracle_private_key=${AGGORACLE_PRIVATE_KEY:-"6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919"}
    readonly insert_global_exit_root_func_sig="function insertGlobalExitRoot(bytes32)"
    readonly forceEmitDetailedClaimEvent_func_sig="function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])"
    readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
    readonly remove_global_exit_roots_func_sig="function removeGlobalExitRoots(bytes32[])"
    readonly global_exit_root_map_sig="function globalExitRootMap(bytes32) (uint256)"
}

@test "Test L2 to L2 bridge" {
    echo "=== Running LxLy bridge eth L1 to L2(Rollup 1) amount:$amount" >&3
    destination_net=$rollup_1_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp1=$output

    echo "=== Running LxLy bridge eth L1 to L2(Rollup 2) amount:$amount" >&3
    destination_net=$rollup_2_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp2=$output

    echo "=== Running LxLy claim L1 to L2(Rollup 1) for $bridge_tx_hash_pp1" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp1" "$rollup_1_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success

    echo "=== Running LxLy claim L1 to L2(Rollup 2) for $bridge_tx_hash_pp2" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp2" "$rollup_2_network_id" "$l2_bridge_addr" "$aggkit_bridge_2_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    assert_success

    # reduce eth amount
    amount=1234567
    echo "=== Running LxLy bridge L2(Rollup 2) to L2(Rollup 1) amount:$amount" >&3
    destination_net=$rollup_1_network_id
    meta_bytes="0xbeef"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_2" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(Rollup 2) to L2(Rollup 1) for: $bridge_tx_hash" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO"  "$rollup_2_network_id" "$bridge_tx_hash" "$rollup_1_network_id" "$l2_bridge_addr" "$aggkit_bridge_2_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success
    global_index_pp2_to_pp1=$output

    # Now we need to do a bridge on L2(Rollup 1) to trigger a certificate to be sent to L1
    ether_value=${ETHER_VALUE:-"0.0100000054"}
    amount=$(cast to-wei "$ether_value" ether)
    echo "=== Running LxLy bridge eth L2(Rollup 1) to L1 (trigger certificate sending on Rollup 1) amount:$amount" >&3
    destination_net=$l1_rpc_network_id
    meta_bytes="0xabcd"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_1" "$l2_bridge_addr"
    assert_success
    bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(Rollup 1) to L1 for $bridge_tx_hash" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO"  "$rollup_1_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l1_rpc_url"
    assert_success

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_pp2_to_pp1 (Rollup 1 rpc: $aggkit_rpc_url)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index_pp2_to_pp1"
}

@test "Transfer message L2 to L2" {
    echo "====== Bridge Message L2(Rollup 1) -> L2(Rollup 2)" >&3
    destination_addr=$sender_addr
    destination_net=$rollup_2_network_id

    # amount is 0 for now since we only want to bridge message
    amount=0
    run bridge_message "$native_token_addr" "$l2_rpc_url_1" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    log "Bridge transaction hash: $bridge_tx_hash"

    echo "====== Claim Message (L2 Rollup 2)" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$rollup_1_network_id" "$bridge_tx_hash" "$rollup_2_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    assert_success
    claim_global_index=$output
    log "Claim global index: $claim_global_index"

    # verify the message is bridged correctly
    run get_claim "$rollup_2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success
    local claim_metadata
    claim_metadata=$(echo "$output" | jq -r '.metadata')
    log "Claim metadata: $claim_metadata"
    assert_equal "$claim_metadata" "$meta_bytes"
}
