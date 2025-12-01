#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
  load '../../core/helpers/agglayer-cdk-common-setup'
  _agglayer_cdk_common_setup

  readonly update_hash_chain_value_event_sig="event UpdateHashChainValue(bytes32, bytes32)"
  readonly set_sovereign_token_address_event_sig="event SetSovereignTokenAddress(uint32, address, address, bool)"
  readonly migrate_legacy_token_event_sig="event MigrateLegacyToken(address, address, address, uint256)"
  readonly remove_legacy_sovereign_token_addr_event_sig="event RemoveLegacySovereignTokenAddress(address)"

  readonly remove_global_exit_roots_func_sig="function removeGlobalExitRoots(bytes32[])"
  readonly global_exit_root_map_sig="function globalExitRootMap(bytes32) (uint256)"
  readonly set_multiple_sovereign_token_address_func_sig="function setMultipleSovereignTokenAddress(uint32[], address[], address[], bool[])"
  readonly grant_role_func_sig="function grantRole(bytes32, address)"
  readonly migrate_legacy_token_func_sig="function migrateLegacyToken(address, uint256, bytes)"
  readonly remove_legacy_sovereign_token_address_func_sig="function removeLegacySovereignTokenAddress(address)"
  readonly unset_multiple_claims_func_sig="function unsetMultipleClaims(uint256[])"
  readonly set_multiple_claims_func_sig="function setMultipleClaims(uint256[])"
  readonly insert_global_exit_root_func_sig="function insertGlobalExitRoot(bytes32)"
  readonly force_emit_detailed_claim_event_func_sig="function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])"

  readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
  readonly l2_sovereign_admin_public_key=$(cast wallet address --private-key "$l2_sovereign_admin_private_key")

  readonly aggoracle_private_key=${AGGORACLE_PRIVATE_KEY:-"6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919"}
}

@test "Test Case B2 PP mode" {
    # Bridge first native token from L1 to L2 with amount 0.0200000054 ether
    destination_addr=$receiver
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    run process_bridge_claim "claim L1: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    sender_balance_after_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after claim $sender_balance_after_claim eth" >&3

    # inject GER1 on L2 using aggoracle pvt key
    local ger1="0xeddc1e373486f80fe4ee28eecdb1cc92f0ec309c931712d546041817599e0bea"
    log "🔄 Inserting GER into map $ger1"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger1" --json
    assert_success
    local insert_global_exit_root_tx_resp1=$output
    log "insertGlobalExitRoot first transaction details: $insert_global_exit_root_tx_resp1"

    # inject GER2 on L2 using aggoracle pvt key
    local ger2="0xf991352bfa617ac3bd248b15ef46b03f9118b1c4fc5a6d9cc768126deb7b4d92"
    log "🔄 Inserting GER into map $ger2"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger2" --json
    assert_success
    local insert_global_exit_root_tx_resp2=$output
    log "insertGlobalExitRoot second transaction details: $insert_global_exit_root_tx_resp2"

    # claim dummy bridge corresponding to ger1
    local in_merkle_proof_ger1="[0x0000000000000000000000000000000000000000000000000000000000000000,0x62c61f81d725c13627a7916a8091bb259a539b5117262fceef227b1d72b8d5df,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
    local in_rollup_merkle_proof_ger1="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
    local in_global_index_ger1=18446744073709551618
    local in_main_exit_root_ger1="0xb13e35a3b4655ae13db68adab3c173d468bfd60da795045be46809691cb6de1b"
    local in_rollup_exit_root_ger1="0x0000000000000000000000000000000000000000000000000000000000000000"
    local in_orig_net_ger1=0
    local in_orig_addr_ger1="0x0000000000000000000000000000000000000000"
    local in_dest_net_ger1=1
    local in_dest_addr_ger1="0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"
    local in_amount_ger1=30000005400000000
    local in_metadata_ger1="0x"

    run cast send --legacy --private-key "$aggoracle_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$l2_bridge_addr" \
        "$CLAIM_ASSET_FN_SIG" \
        "$in_merkle_proof_ger1" \
        "$in_rollup_merkle_proof_ger1" \
        $in_global_index_ger1 \
        $in_main_exit_root_ger1 \
        $in_rollup_exit_root_ger1 \
        $in_orig_net_ger1 \
        $in_orig_addr_ger1 \
        $in_dest_net_ger1 \
        $in_dest_addr_ger1 \
        $in_amount_ger1 \
        $in_metadata_ger1
    assert_success
    local claim_tx_resp_ger1=$output
    log "🔍 Claim transaction details: $claim_tx_resp_ger1"

    # claim dummy bridge corresponding to ger2
    local in_merkle_proof_ger2="[0x6a2f7e404a3e04b641f11de1cff3ec66473c125738fd83cf308434ec6ab99915,0x62c61f81d725c13627a7916a8091bb259a539b5117262fceef227b1d72b8d5df,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
    local in_rollup_merkle_proof_ger2="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
    local in_global_index_ger2=18446744073709551619
    local in_main_exit_root_ger2="0xb275430dc63e86a3d4e1bc87be1819aa4beb37619b1f6e6f590369c752f2d420"
    local in_rollup_exit_root_ger2="0x0000000000000000000000000000000000000000000000000000000000000000"
    local in_orig_net_ger2=0
    local in_orig_addr_ger2="0x0000000000000000000000000000000000000000"
    local in_dest_net_ger2=1
    local in_dest_addr_ger2="0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"
    local in_amount_ger2=40000005400000000
    local in_metadata_ger2="0x"

    run cast send --legacy --private-key "$aggoracle_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$l2_bridge_addr" \
        "$CLAIM_ASSET_FN_SIG" \
        "$in_merkle_proof_ger2" \
        "$in_rollup_merkle_proof_ger2" \
        $in_global_index_ger2 \
        $in_main_exit_root_ger2 \
        $in_rollup_exit_root_ger2 \
        $in_orig_net_ger2 \
        $in_orig_addr_ger2 \
        $in_dest_net_ger2 \
        $in_dest_addr_ger2 \
        $in_amount_ger2 \
        $in_metadata_ger2
    assert_success
    local claim_tx_resp_ger2=$output
    log "🔍 Claim transaction details: $claim_tx_resp_ger2"

    # Bridge first native token from L1 to L2 with amount 0.0400000054 ether
    destination_addr=$receiver
    local initial_receiver_balance1
    initial_receiver_balance1=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance1 eth" >&3

    echo "=== Running first L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    amount=40000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash1=$output
    log "bridge_tx_hash1: $bridge_tx_hash1"

    # Bridge second native token from L1 to L2 with amount 0.0300000054 ether
    local initial_receiver_balance2
    initial_receiver_balance2=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance2 eth" >&3

    echo "=== Running second L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    amount=30000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash2=$output
    log "bridge_tx_hash2: $bridge_tx_hash2"

    amount=20000005400000000

    # remove ger1 and ger2
    log "🔄 Removing GER from map $ger1 and $ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$ger1,$ger2]"
    assert_success
    local remove_tx_hash="$output"
    log "🔗 Removal transaction hash: $remove_tx_hash"

    # Wait a moment for transaction to be mined
    sleep 2

    log "Querying $ger1 from L2"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger1"
    assert_success
    final_status_ger1="$output"
    assert_equal "$final_status_ger1" "0"
    log "✅ GER1: $ger1 successfully removed (status: $final_status_ger1)"

    log "Querying $ger2 from L2"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger2"
    assert_success
    final_status_ger2="$output"
    assert_equal "$final_status_ger2" "0"
    log "✅ GER2: $ger2 successfully removed (status: $final_status_ger2)"

    # TODO: check remove GER events is present on aggkit l2gersync db

    # Unset claim via AgglayerBridgeL2:unsetMultipleClaims
    log "🔄 Unsetting claims of global index $in_global_index_ger1 and $in_global_index_ger2 using unsetMultipleClaims"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[$in_global_index_ger1, $in_global_index_ger2]"
    assert_success
    local unset_claims_tx_hash="$output"
    log "🔗 Unset claims transaction hash: $unset_claims_tx_hash"

    # Wait a moment for transaction to be mined
    sleep 2

    # Verify that claims were actually unset by checking isClaimed status
    # Extract deposit counts from global indexes (this is bridge-specific logic)
    local deposit_count_ger1=$((in_global_index_ger1 & 0xFFFFFFFF))
    local deposit_count_ger2=$((in_global_index_ger2 & 0xFFFFFFFF))
    local origin_network=0  # Based on the test setup

    log "Verifying claim status for deposit_count $deposit_count_ger1 (GER1)"
    run is_claimed "$deposit_count_ger1" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger1="$output"
    assert_equal "$claim_status_ger1" "false"
    log "✅ GER1 claim successfully unset (deposit_count: $deposit_count_ger1, status: $claim_status_ger1)"

    log "Verifying claim status for deposit_count $deposit_count_ger2 (GER2)"
    run is_claimed "$deposit_count_ger2" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger2="$output"
    assert_equal "$claim_status_ger2" "false"
    log "✅ GER2 claim successfully unset (deposit_count: $deposit_count_ger2, status: $claim_status_ger2)"

    # TODO: check unset claim tx are present on aggkit bridge db

    # set claims using AgglayerBridgeL2:setMultipleClaims
    log "🔄 Setting claims of global index $in_global_index_ger2 and $in_global_index_ger2 using setMultipleClaims"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$set_multiple_claims_func_sig" "[$in_global_index_ger2, $in_global_index_ger1]"
    assert_success
    local set_claims_tx_hash="$output"
    log "🔗 Set claims transaction hash: $set_claims_tx_hash"

    # Wait a moment for transaction to be mined
    sleep 2

    # Verify that claims were actually set by checking isClaimed status
    # Using same deposit counts from global indexes as before
    log "Verifying claim status for deposit_count $deposit_count_ger2 (GER2) - should now be claimed"
    run is_claimed "$deposit_count_ger2" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger2="$output"
    assert_equal "$claim_status_ger2" "true"
    log "✅ GER2 claim successfully set (deposit_count: $deposit_count_ger2, status: $claim_status_ger2)"

    log "Verifying claim status for deposit_count $deposit_count_ger1 (GER1) - should now be claimed"
    run is_claimed "$deposit_count_ger1" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger1="$output"
    assert_equal "$claim_status_ger1" "true"
    log "✅ GER1 claim successfully set (deposit_count: $deposit_count_ger1, status: $claim_status_ger1)"

    # TODO: check set claim tx are present on aggkit bridge db

    # update claims values using forceEmitDetailedClaimEvent on L2 bridge contract
    # extract claim parameters from bridge_tx_hash1 which is first bridge tx after reorg
    local claim_params_1
    claim_params_1=$(extract_claim_parameters_json "$bridge_tx_hash1" "first_tx_after_reorg" "$l1_rpc_network_id")
    log "🔍 Claim parameters 1: $claim_params_1"

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

    # Ensure they are valid cast array formats: ["0x..","0x.."]
    proof_local_exit_root_1=$(normalize_cast_array "$proof_local_exit_root_1")
    proof_rollup_exit_root_1=$(normalize_cast_array "$proof_rollup_exit_root_1")

    local claim_params_2
    claim_params_2=$(extract_claim_parameters_json "$bridge_tx_hash2" "second_tx_after_reorg" "$l1_rpc_network_id")
    log "🔍 Claim parameters 2: $claim_params_2"

    local proof_local_exit_root_2
    proof_local_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_2
    proof_rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_rollup_exit_root')
    local global_index_2
    global_index_2=$(echo "$claim_params_2" | jq -r '.global_index')
    local mainnet_exit_root_2
    mainnet_exit_root_2=$(echo "$claim_params_2" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_2
    rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.rollup_exit_root')
    local origin_network_2
    origin_network_2=$(echo "$claim_params_2" | jq -r '.origin_network')
    local origin_address_2
    origin_address_2=$(echo "$claim_params_2" | jq -r '.origin_address')
    local destination_network_2
    destination_network_2=$(echo "$claim_params_2" | jq -r '.destination_network')
    local destination_address_2
    destination_address_2=$(echo "$claim_params_2" | jq -r '.destination_address')
    local amount_2
    amount_2=$(echo "$claim_params_2" | jq -r '.amount')
    local metadata_2
    metadata_2=$(echo "$claim_params_2" | jq -r '.metadata')

    # Ensure they are valid cast array formats: ["0x..","0x.."]
    proof_local_exit_root_2=$(normalize_cast_array "$proof_local_exit_root_2")
    proof_rollup_exit_root_2=$(normalize_cast_array "$proof_rollup_exit_root_2")

    # Forcibly emit detailed claim event
    log "🔧 Forcibly emitting detailed claim event to fix the aggkit state"
    local leaf_type="0" # asset leaf type
    local detailed_claim_data="[($proof_local_exit_root_1, $proof_rollup_exit_root_1, $global_index_1, $mainnet_exit_root_1, $rollup_exit_root_1, $leaf_type, $origin_network, $origin_address_1, $destination_network_1, $destination_address_1, $amount_1, $metadata_1),($proof_local_exit_root_2, $proof_rollup_exit_root_2, $global_index_2, $mainnet_exit_root_2, $rollup_exit_root_2, $leaf_type, $origin_network_2, $origin_address_2, $destination_network_2, $destination_address_2, $amount_2, $metadata_2)]"

    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" \
        "$force_emit_detailed_claim_event_func_sig" "$detailed_claim_data"
    assert_success
    log "✅ Detailed claim event forcibly emitted tx hash: $output"

    # # TODO: check detailed claim events are present on aggkit bridge db

    echo "=== Running LxLy bridge eth L1 to L2 amount:$amount" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_final=$output
    echo "=== Running LxLy claim L1 to L2 for $bridge_tx_hash_final" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_final" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    global_index_last_claim_event=$output
    assert_success

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_last_claim_event"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index_last_claim_event"
    log "✅ Certificate settlement completed for global index: $global_index_last_claim_event"
}

@test "Test Case B2 FEP mode" {
    # Bridge first native token from L1 to L2 with amount 0.0200000054 ether
    destination_addr=$receiver
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    run process_bridge_claim "claim L1: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    sender_balance_after_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after claim $sender_balance_after_claim eth" >&3

    # inject GER1 on L2 using aggoracle pvt key
    local ger1="0xeddc1e373486f80fe4ee28eecdb1cc92f0ec309c931712d546041817599e0bea"
    log "🔄 Inserting GER into map $ger1"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger1" --json
    assert_success
    local insert_global_exit_root_tx_resp1=$output
    log "insertGlobalExitRoot first transaction details: $insert_global_exit_root_tx_resp1"

    # inject GER2 on L2 using aggoracle pvt key
    local ger2="0xf991352bfa617ac3bd248b15ef46b03f9118b1c4fc5a6d9cc768126deb7b4d92"
    log "🔄 Inserting GER into map $ger2"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger2" --json
    assert_success
    local insert_global_exit_root_tx_resp2=$output
    log "insertGlobalExitRoot second transaction details: $insert_global_exit_root_tx_resp2"

    # claim dummy bridge corresponding to ger1
    local in_merkle_proof_ger1="[0x0000000000000000000000000000000000000000000000000000000000000000,0x62c61f81d725c13627a7916a8091bb259a539b5117262fceef227b1d72b8d5df,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
    local in_rollup_merkle_proof_ger1="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
    local in_global_index_ger1=18446744073709551618
    local in_main_exit_root_ger1="0xb13e35a3b4655ae13db68adab3c173d468bfd60da795045be46809691cb6de1b"
    local in_rollup_exit_root_ger1="0x0000000000000000000000000000000000000000000000000000000000000000"
    local in_orig_net_ger1=0
    local in_orig_addr_ger1="0x0000000000000000000000000000000000000000"
    local in_dest_net_ger1=1
    local in_dest_addr_ger1="0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"
    local in_amount_ger1=30000005400000000
    local in_metadata_ger1="0x"

    run cast send --legacy --private-key "$aggoracle_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$l2_bridge_addr" \
        "$CLAIM_ASSET_FN_SIG" \
        "$in_merkle_proof_ger1" \
        "$in_rollup_merkle_proof_ger1" \
        $in_global_index_ger1 \
        $in_main_exit_root_ger1 \
        $in_rollup_exit_root_ger1 \
        $in_orig_net_ger1 \
        $in_orig_addr_ger1 \
        $in_dest_net_ger1 \
        $in_dest_addr_ger1 \
        $in_amount_ger1 \
        $in_metadata_ger1
    assert_success
    local claim_tx_resp_ger1=$output
    log "🔍 Claim transaction details: $claim_tx_resp_ger1"

    # claim dummy bridge corresponding to ger2
    local in_merkle_proof_ger2="[0x6a2f7e404a3e04b641f11de1cff3ec66473c125738fd83cf308434ec6ab99915,0x62c61f81d725c13627a7916a8091bb259a539b5117262fceef227b1d72b8d5df,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
    local in_rollup_merkle_proof_ger2="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
    local in_global_index_ger2=18446744073709551619
    local in_main_exit_root_ger2="0xb275430dc63e86a3d4e1bc87be1819aa4beb37619b1f6e6f590369c752f2d420"
    local in_rollup_exit_root_ger2="0x0000000000000000000000000000000000000000000000000000000000000000"
    local in_orig_net_ger2=0
    local in_orig_addr_ger2="0x0000000000000000000000000000000000000000"
    local in_dest_net_ger2=1
    local in_dest_addr_ger2="0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"
    local in_amount_ger2=40000005400000000
    local in_metadata_ger2="0x"

    run cast send --legacy --private-key "$aggoracle_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$l2_bridge_addr" \
        "$CLAIM_ASSET_FN_SIG" \
        "$in_merkle_proof_ger2" \
        "$in_rollup_merkle_proof_ger2" \
        $in_global_index_ger2 \
        $in_main_exit_root_ger2 \
        $in_rollup_exit_root_ger2 \
        $in_orig_net_ger2 \
        $in_orig_addr_ger2 \
        $in_dest_net_ger2 \
        $in_dest_addr_ger2 \
        $in_amount_ger2 \
        $in_metadata_ger2
    assert_success
    local claim_tx_resp_ger2=$output
    log "🔍 Claim transaction details: $claim_tx_resp_ger2"

    # Bridge first native token from L1 to L2 with amount 0.0400000054 ether
    destination_addr=$receiver
    local initial_receiver_balance1
    initial_receiver_balance1=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance1 eth" >&3

    echo "=== Running first L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    amount=40000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash1=$output
    log "bridge_tx_hash1: $bridge_tx_hash1"

    # Bridge second native token from L1 to L2 with amount 0.0300000054 ether
    local initial_receiver_balance2
    initial_receiver_balance2=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance2 eth" >&3

    echo "=== Running second L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    amount=30000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash2=$output
    log "bridge_tx_hash2: $bridge_tx_hash2"

    amount=20000005400000000

    # remove ger1 and ger2
    log "🔄 Removing GER from map $ger1 and $ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$ger1,$ger2]"
    assert_success
    local remove_tx_hash="$output"
    log "🔗 Removal transaction hash: $remove_tx_hash"

    # Wait a moment for transaction to be mined
    sleep 2

    log "Querying $ger1 from L2"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger1"
    assert_success
    final_status_ger1="$output"
    assert_equal "$final_status_ger1" "0"
    log "✅ GER1: $ger1 successfully removed (status: $final_status_ger1)"

    log "Querying $ger2 from L2"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger2"
    assert_success
    final_status_ger2="$output"
    assert_equal "$final_status_ger2" "0"
    log "✅ GER2: $ger2 successfully removed (status: $final_status_ger2)"

    # TODO: check remove GER events is present on aggkit l2gersync db

    # Unset claim via AgglayerBridgeL2:unsetMultipleClaims
    log "🔄 Unsetting claims of global index $in_global_index_ger1 and $in_global_index_ger2 using unsetMultipleClaims"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[$in_global_index_ger1, $in_global_index_ger2]"
    assert_success
    local unset_claims_tx_hash="$output"
    log "🔗 Unset claims transaction hash: $unset_claims_tx_hash"

    # Wait a moment for transaction to be mined
    sleep 2

    # Verify that claims were actually unset by checking isClaimed status
    # Extract deposit counts from global indexes (this is bridge-specific logic)
    local deposit_count_ger1=$((in_global_index_ger1 & 0xFFFFFFFF))
    local deposit_count_ger2=$((in_global_index_ger2 & 0xFFFFFFFF))
    local origin_network=0  # Based on the test setup

    log "Verifying claim status for deposit_count $deposit_count_ger1 (GER1)"
    run is_claimed "$deposit_count_ger1" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger1="$output"
    assert_equal "$claim_status_ger1" "false"
    log "✅ GER1 claim successfully unset (deposit_count: $deposit_count_ger1, status: $claim_status_ger1)"

    log "Verifying claim status for deposit_count $deposit_count_ger2 (GER2)"
    run is_claimed "$deposit_count_ger2" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local claim_status_ger2="$output"
    assert_equal "$claim_status_ger2" "false"
    log "✅ GER2 claim successfully unset (deposit_count: $deposit_count_ger2, status: $claim_status_ger2)"

    # TODO: check unset claim tx are present on aggkit bridge db

    # local bridge_tx_hash1=0xbbc519bc8fecac8a2011123145642ae6da0e3d3fd0db0f2397ac2f6e16288462
    # local bridge_tx_hash2=0x6be31ce6d7c343492e706a8c1ccdd41edd638a6092ce1c7625b72ef9948af1bc

    # update claims values using forceEmitDetailedClaimEvent on L2 bridge contract
    # extract claim parameters from bridge_tx_hash1 which is first bridge tx after reorg
    local claim_params_1
    claim_params_1=$(extract_claim_parameters_json "$bridge_tx_hash1" "first_tx_after_reorg" "$l1_rpc_network_id")
    log "🔍 Claim parameters 1: $claim_params_1"

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

    # Ensure they are valid cast array formats: ["0x..","0x.."]
    proof_local_exit_root_1=$(normalize_cast_array "$proof_local_exit_root_1")
    proof_rollup_exit_root_1=$(normalize_cast_array "$proof_rollup_exit_root_1")

    local claim_params_2
    claim_params_2=$(extract_claim_parameters_json "$bridge_tx_hash2" "second_tx_after_reorg" "$l1_rpc_network_id")
    log "🔍 Claim parameters 2: $claim_params_2"

    local proof_local_exit_root_2
    proof_local_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_2
    proof_rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_rollup_exit_root')
    local global_index_2
    global_index_2=$(echo "$claim_params_2" | jq -r '.global_index')
    local mainnet_exit_root_2
    mainnet_exit_root_2=$(echo "$claim_params_2" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_2
    rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.rollup_exit_root')
    local origin_network_2
    origin_network_2=$(echo "$claim_params_2" | jq -r '.origin_network')
    local origin_address_2
    origin_address_2=$(echo "$claim_params_2" | jq -r '.origin_address')
    local destination_network_2
    destination_network_2=$(echo "$claim_params_2" | jq -r '.destination_network')
    local destination_address_2
    destination_address_2=$(echo "$claim_params_2" | jq -r '.destination_address')
    local amount_2
    amount_2=$(echo "$claim_params_2" | jq -r '.amount')
    local metadata_2
    metadata_2=$(echo "$claim_params_2" | jq -r '.metadata')

    # Ensure they are valid cast array formats: ["0x..","0x.."]
    proof_local_exit_root_2=$(normalize_cast_array "$proof_local_exit_root_2")
    proof_rollup_exit_root_2=$(normalize_cast_array "$proof_rollup_exit_root_2")

    echo "=== Running claim for first bridge transaction $bridge_tx_hash1" >&3
    run process_bridge_claim "latest-n-injected-ger: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash1" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_first_claim_event=$output
    log "Global index of first claim event: $global_index_first_claim_event"

    echo "=== Running claim for second bridge transaction $bridge_tx_hash2" >&3
    run process_bridge_claim "latest-n-injected-ger: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash2" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_second_claim_event=$output
    log "Global index of second claim event: $global_index_second_claim_event"

    # # TODO: check detailed claim events are present on aggkit bridge db

    echo "=== Running LxLy bridge eth L1 to L2 amount:$amount" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_final=$output
    echo "=== Running LxLy claim L1 to L2 for $bridge_tx_hash_final" >&3
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_final" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    global_index_last_claim_event=$output
    assert_success

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_last_claim_event"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index_last_claim_event"
    log "✅ Certificate settlement completed for global index: $global_index_last_claim_event"
}
