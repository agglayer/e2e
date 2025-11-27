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

@test "Inject LatestBlock-N GER - B1 case PP" {
    skip "This test should be run independently on a new setup as GER and claim proofs are hardcoded to create invalid GER and its claim proof"
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
    global_index_pp1=$output
    assert_success
    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_pp1 (Rollup 1 rpc: $aggkit_rpc_1_url)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_1_url" "$global_index_pp1"
    log "✅ Certificate settlement completed for global index: $global_index_pp1"
    echo "=== Running LxLy claim L1 to L2(Rollup 2) for $bridge_tx_hash_pp2" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp2" "$rollup_2_network_id" "$l2_bridge_addr" "$aggkit_bridge_2_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    global_index_pp2=$output
    assert_success
    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_pp2 (Rollup 2 rpc: $aggkit_rpc_2_url)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_2_url" "$global_index_pp2"
    log "✅ Certificate settlement completed for global index: $global_index_pp2"

    # Now we need to do a bridge on L2(Rollup 2) to trigger a certificate to be sent to L1
    ether_value=${ETHER_VALUE:-"0.0100000054"}
    amount=$(cast to-wei "$ether_value" ether)
    echo "=== Running LxLy bridge eth L2(Rollup 2) to L1 (trigger certificate sending on Rollup 1) amount:$amount" >&3
    destination_net=$l1_rpc_network_id
    meta_bytes="0xabcd"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_2" "$l2_bridge_addr"
    assert_success

    # wait for certificate to be sent to L1
    sleep 100

    echo "=== Running LxLy bridge eth L1 to L2(Rollup 1) amount:$amount" >&3
    destination_net=$rollup_1_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp3=$output

    local next_ger="0xdfd6763b3d9a85c280e3255126f97bec6131db2f09a9bab48c035f58f065c8a1"
    log "🔄 Inserting GER into map $next_ger"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$l2_rpc_url_1" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$next_ger" --json
    assert_success
    local insert_global_exit_root_tx_resp=$output
    log "insertGlobalExitRoot transaction details: $insert_global_exit_root_tx_resp"

    local in_merkle_proof="[0x0000000000000000000000000000000000000000000000000000000000000000,0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5,0xd4ab5623b8815d6d3e532789cf20c9ea0888b72a006b8c6e2e85a186954730a0,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
    local in_rollup_merkle_proof="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
    local in_global_index=18446744073709551620
    local in_main_exit_root="0xc8427ffeda6a80e0ad01723eda3d56fb86eac808f5d8e484c08a8474cb75b004"
    local in_rollup_exit_root="0x27ae5ba08d7291c96c8cbddcc148bf48a6d68c7974b94356f53754ef6171d757"
    local in_orig_net=0
    local in_orig_addr="0x0000000000000000000000000000000000000000"
    local in_dest_net=1
    local in_dest_addr="0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"
    local in_amount=20000005400000000
    local in_metadata="0x"

    run cast send --legacy --private-key "$aggoracle_private_key" \
        --rpc-url "$l2_rpc_url_1" \
        "$l2_bridge_addr" \
        "$CLAIM_ASSET_FN_SIG" \
        "$in_merkle_proof" \
        "$in_rollup_merkle_proof" \
        $in_global_index \
        $in_main_exit_root \
        $in_rollup_exit_root \
        $in_orig_net \
        $in_orig_addr \
        $in_dest_net \
        $in_dest_addr \
        $in_amount \
        $in_metadata
    assert_success
    local claim_tx_resp=$output
    log "🔍 Claim transaction details: $claim_tx_resp"

    log "🔄 Removing GER from map $next_ger"
    run cast send --legacy --rpc-url "$l2_rpc_url_1" --private-key "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$next_ger]"
    assert_success
    run query_contract "$l2_rpc_url_1" "$l2_ger_addr" "$global_exit_root_map_sig" "$next_ger"
    assert_success
    final_status="$output"
    assert_equal "$final_status" "0"
    log "✅ GER successfully removed"

    extract_claim_parameters_json "$bridge_tx_hash_pp3" "first"
    assert_success
    local claim_params_1="$output"
    log "🔍 Claim parameters: $claim_params_1"
    local proof_local_exit_root_1
    proof_local_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_1
    proof_rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_rollup_exit_root')
    local global_index_1
    global_index_1=$(echo "$claim_params_1" | jq -r '.global_index')
    local mainnet_exit_root_1
    mainnet_exit_root_1=$(echo "$claim_params_1" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_1
    rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.rollup_exit_root')
    local origin_network_1
    origin_network_1=$(echo "$claim_params_1" | jq -r '.origin_network')
    local origin_address_1
    origin_address_1=$(echo "$claim_params_1" | jq -r '.origin_address')
    local destination_network_1
    destination_network_1=$(echo "$claim_params_1" | jq -r '.destination_network')
    local destination_address_1
    destination_address_1=$(echo "$claim_params_1" | jq -r '.destination_address')
    local amount_1
    amount_1=$(echo "$claim_params_1" | jq -r '.amount')
    local metadata_1
    metadata_1=$(echo "$claim_params_1" | jq -r '.metadata')

    run cast send \
        --rpc-url "$l2_rpc_url_1" \
        --private-key "$l2_sovereign_admin_private_key" \
        "$l2_bridge_addr" \
        "function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])" \
        '[("$proof_local_exit_root_1","$proof_rollup_exit_root_1","$global_index_1","$mainnet_exit_root_1","$rollup_exit_root_1","0","$origin_network_1","$origin_address_1","$destination_network_1","$destination_address_1","$amount_1","$metadata_1")]'
    assert_success
    local force_emit_detailed_claim_event_tx_resp=$output
    log "🔍 Force emit detailed claim event transaction details: $force_emit_detailed_claim_event_tx_resp"

    echo "=== Running LxLy bridge eth L1 to L2(Rollup 1) amount:$amount" >&3
    destination_net=$rollup_1_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp1=$output
    echo "=== Running LxLy claim L1 to L2(Rollup 1) for $bridge_tx_hash_pp1" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp1" "$rollup_1_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    global_index_pp1=$output
    assert_success
    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_pp1 (Rollup 1 rpc: $aggkit_rpc_1_url)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_1_url" "$global_index_pp1"
    log "✅ Certificate settlement completed for global index: $global_index_pp1"
}
