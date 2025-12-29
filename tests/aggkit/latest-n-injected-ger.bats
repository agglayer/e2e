#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
  load '../../core/helpers/agglayer-cdk-common-setup'
  _agglayer_cdk_common_setup

  # =============================================================================
  # FUNCTION SIGNATURES - Used for contract interactions
  # =============================================================================

  readonly update_hash_chain_value_event_sig="event UpdateHashChainValue(bytes32, bytes32)"

  # Global Exit Root (GER) Management Functions
  readonly remove_global_exit_roots_func_sig="function removeGlobalExitRoots(bytes32[])"          # Remove multiple GERs from mapping
  readonly global_exit_root_map_sig="function globalExitRootMap(bytes32) (uint256)"              # Query GER status from mapping
  readonly insert_global_exit_root_func_sig="function insertGlobalExitRoot(bytes32)"             # Insert single GER into mapping

  # Bridge Claim Management Functions
  readonly unset_multiple_claims_func_sig="function unsetMultipleClaims(uint256[])"              # Batch unset claim status for multiple global indexes
  readonly set_multiple_claims_func_sig="function setMultipleClaims(uint256[])"                  # Batch set claim status for multiple global indexes

  # Administrative Functions for Test Scenarios
  readonly force_emit_detailed_claim_event_func_sig="function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])"

  # =============================================================================
  # TEST ACCOUNT CONFIGURATION
  # =============================================================================

  # L2 Sovereign Admin - Has administrative privileges on L2 contracts
  readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}

  # AggOracle Account - Can inject Global Exit Roots for testing reorg scenarios
  readonly aggoracle_private_key=${AGGORACLE_PRIVATE_KEY:-"6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919"}
}

@test "Test invalid GER injection case B2 (PP mode)" {
    # Bridge first native token from L1 to L2 with amount 0.0200000054 ether
    destination_addr=$receiver
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    log "📊 Initial receiver balance on L2: $initial_receiver_balance ETH (address: $destination_addr)"

    log "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)"
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    log "✅ Bridge transaction completed: $bridge_tx_hash"

    log "🔄 Processing bridge claim on L2 (settling the deposit)"
    run process_bridge_claim "claim L1: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    sender_balance_after_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after claim $sender_balance_after_claim eth" >&3

    # inject incorrect GER1 (reorged on L1) to the L2 using aggoracle pvt key
    local ger1="0xeddc1e373486f80fe4ee28eecdb1cc92f0ec309c931712d546041817599e0bea"
    log "🔄 Injecting GER1: $ger1"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger1" --json
    assert_success
    local insert_global_exit_root_tx_resp1=$output
    log "✅ GER1: $insert_global_exit_root_tx_resp1 injection completed"

    # inject GER2(reorged on L1) on L2 using aggoracle pvt key
    local ger2="0xf991352bfa617ac3bd248b15ef46b03f9118b1c4fc5a6d9cc768126deb7b4d92"
    log "🔄 Injecting GER2: $ger2"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger2" --json
    assert_success
    local insert_global_exit_root_tx_resp2=$output
    log "✅ GER2: $insert_global_exit_root_tx_resp2 injection completed"

    # Execute dummy claim for GER1 to simulate invalid bridge claim
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
    log "🔍 First claim transaction details: $claim_tx_resp_ger1"

    # Execute dummy claim for GER2 to simulate invalid bridge claim
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
    log "🔍 Second claim transaction details: $claim_tx_resp_ger2"

    # Bridge first native token from L1 to L2 with amount 0.0400000054 ether
    destination_addr=$receiver
    local initial_receiver_balance1
    initial_receiver_balance1=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    log "Initial receiver balance of native token on L2 $initial_receiver_balance1 eth"

    echo "=== Running first L1 native token deposit (0.040 ETH) to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    amount=40000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash1=$output
    log "bridge_tx_hash1: $bridge_tx_hash1"

    # Bridge second native token from L1 to L2 with amount 0.0300000054 ether
    local initial_receiver_balance2
    initial_receiver_balance2=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    log "💰 Initial receiver balance: $initial_receiver_balance2 ETH"

    echo "=== Running second L1 native token deposit (0.030 ETH) to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    amount=30000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash2=$output
    log "bridge_tx_hash2: $bridge_tx_hash2"

    amount=20000005400000000

    # Remove invalid GERs from L2 GlobalExitRootManagerL2
    log "🗋 Removing invalid GERs from L2: $ger1, $ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$ger1,$ger2]"
    assert_success
    local remove_tx_hash="$output"
    log "🔗 GER removal transaction hash: $remove_tx_hash"

    # check if GER1 is removed from L2
    log "🔍 Verifying GER1 removal: $ger1"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger1"
    assert_success
    final_status_ger1="$output"
    assert_equal "$final_status_ger1" "0"
    log "✅ GER1: $ger1 successfully removed (status: $final_status_ger1)"

    # check if GER2 is removed from L2
    log "🔍 Verifying GER2 removal: $ger2"
    run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$ger2"
    assert_success
    final_status_ger2="$output"
    assert_equal "$final_status_ger2" "0"
    log "✅ GER2: $ger2 successfully removed (status: $final_status_ger2)"

    # Verify GER removal events are recorded in AggKit l2gersync database
    log "🔍 Verifying GER removal events are recorded in AggKit database for GER1: $ger1 and GER2: $ger2"

    # Check for GER1 removal event
    log "🔄 Checking for GER1 removal event: $ger1"
    run get_removed_gers "$aggkit_bridge_url" 50 5 "$ger1"
    assert_success
    log "✅ Found GER1 removal event: $ger1"

    # Check for GER2 removal event
    log "🔄 Checking for GER2 removal event: $ger2"
    run get_removed_gers "$aggkit_bridge_url" 50 5 "$ger2"
    assert_success
    log "✅ Found GER2 removal event: $ger2"

    log "🎉 Both GER removal events successfully verified in AggKit database"

    # Unset claim via AgglayerBridgeL2:unsetMultipleClaims
    log "🗑️ Unsetting claims for global indexes: $in_global_index_ger1, $in_global_index_ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[$in_global_index_ger1, $in_global_index_ger2]"
    assert_success
    local unset_claims_tx_hash="$output"
    log "🔗 Unset claims transaction hash: $unset_claims_tx_hash"

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

    # Verify claim unset transactions are recorded in AggKit bridge database
    log "🔍 Verifying unset claims are recorded in AggKit database for global indexes: $in_global_index_ger1, $in_global_index_ger2"

    # Check for unset claim of GER1
    log "🔄 Checking for unset claim with global_index: $in_global_index_ger1"
    run get_unset_claims "$aggkit_bridge_url" 30 5 "" "" "$in_global_index_ger1"
    assert_success
    log "✅ Found unset claim for global_index: $in_global_index_ger1"

    # Check for unset claim of GER2
    log "🔄 Checking for unset claim with global_index: $in_global_index_ger2"
    run get_unset_claims "$aggkit_bridge_url" 30 5 "" "" "$in_global_index_ger2"
    assert_success
    log "✅ Found unset claim for global_index: $in_global_index_ger2"

    log "🎉 Both unset claims successfully verified in AggKit database"

    # set claims using AgglayerBridgeL2:setMultipleClaims
    log "⚙️ Setting claims for global indexes: $in_global_index_ger2, $in_global_index_ger1"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$set_multiple_claims_func_sig" "[$in_global_index_ger2, $in_global_index_ger1]"
    assert_success
    local set_claims_tx_hash="$output"
    log "🔗 Set claims transaction hash: $set_claims_tx_hash"

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

    # Verify claim set transactions are recorded in AggKit bridge database
    log "🔍 Verifying set claims are recorded in AggKit database for global indexes: $in_global_index_ger1, $in_global_index_ger2"

    # Check for set claim of GER1
    log "🔄 Checking for set claim with global_index: $in_global_index_ger1"
    run get_set_claims "$aggkit_bridge_url" 30 5 "" "" "$in_global_index_ger1"
    assert_success
    log "✅ Found set claim for global_index: $in_global_index_ger1"

    # Check for set claim of GER2
    log "🔄 Checking for set claim with global_index: $in_global_index_ger2"
    run get_set_claims "$aggkit_bridge_url" 30 5 "" "" "$in_global_index_ger2"
    assert_success
    log "✅ Found set claim for global_index: $in_global_index_ger2"

    log "🎉 Both set claims successfully verified in AggKit database"

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

    # Verify detailed claim events are recorded in AggKit bridge database
    log "🔍 Verifying detailed claim events are recorded in AggKit database for global indexes: $global_index_1, $global_index_2"

    # Check for detailed claim event with global_index_1
    log "🔄 Checking for detailed claim event with global_index: $global_index_1"
    run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    log "✅ Found detailed claim event for global_index: $global_index_1"

    # Check for detailed claim event with global_index_2
    log "🔄 Checking for detailed claim event with global_index: $global_index_2"
    run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    log "✅ Found detailed claim event for global_index: $global_index_2"

    log "🎉 Both detailed claim events successfully verified in AggKit database"

    log "💰 Final L1 to L2 bridge transaction: $amount wei (0.020 ETH)"
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_final=$output
    log "⚖️ Processing final bridge claim: $bridge_tx_hash_final"
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_final" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    global_index_last_claim_event=$output
    assert_success

    log "⏳ Waiting for certificate settlement (global_index: $global_index_last_claim_event)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index_last_claim_event"
    log "✅ Certificate settlement completed for global index: $global_index_last_claim_event"
}

@test "Test invalid GER injection case B2 (FEP mode)" {
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
    log "✅ GER1: $insert_global_exit_root_tx_resp1 injection completed"

    # inject GER2 on L2 using aggoracle pvt key
    local ger2="0xf991352bfa617ac3bd248b15ef46b03f9118b1c4fc5a6d9cc768126deb7b4d92"
    log "🔄 Inserting GER into map $ger2"
    run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$ger2" --json
    assert_success
    local insert_global_exit_root_tx_resp2=$output
    log "✅ GER2: $insert_global_exit_root_tx_resp2 injection completed"

    # Execute dummy claim for GER1 to simulate invalid bridge claim
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

    # Execute dummy claim for GER2 to simulate invalid bridge claim
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
    log "💰 Initial receiver balance: $initial_receiver_balance1 ETH"

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
    log "💰 Initial receiver balance: $initial_receiver_balance2 ETH"

    echo "=== Running second L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    amount=30000005400000000
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash2=$output
    log "bridge_tx_hash2: $bridge_tx_hash2"

    amount=20000005400000000

    # Remove invalid GERs from L2 GlobalExitRootManagerL2
    log "🗋 Removing invalid GERs from L2: $ger1, $ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$ger1,$ger2]"
    assert_success
    local remove_tx_hash="$output"
    log "🔗 Removal transaction hash: $remove_tx_hash"

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

    # Verify GER removal events are recorded in AggKit l2gersync database
    log "🔍 Verifying GER removal events are recorded in AggKit database for GER1: $ger1 and GER2: $ger2"

    # Check for GER1 removal event
    log "🔄 Checking for GER1 removal event: $ger1"
    run get_removed_gers "$aggkit_bridge_url" 50 5 "$ger1"
    assert_success
    log "✅ Found GER1 removal event: $ger1"

    # Check for GER2 removal event
    log "🔄 Checking for GER2 removal event: $ger2"
    run get_removed_gers "$aggkit_bridge_url" 50 5 "$ger2"
    assert_success
    log "✅ Found GER2 removal event: $ger2"

    log "🎉 Both GER removal events successfully verified in AggKit database"


    # Unset claim via AgglayerBridgeL2:unsetMultipleClaims
    log "🗑️ Unsetting claims for global indexes: $in_global_index_ger1, $in_global_index_ger2"
    run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[$in_global_index_ger1, $in_global_index_ger2]"
    assert_success
    local unset_claims_tx_hash="$output"
    log "🔗 Unset claims transaction hash: $unset_claims_tx_hash"

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

    # Verify claim unset transactions are recorded in AggKit bridge database
    log "🔍 Verifying unset claims are recorded in AggKit database for global indexes: $in_global_index_ger1, $in_global_index_ger2"

    # Check for unset claim of GER1
    log "🔄 Checking for unset claim with global_index: $in_global_index_ger1"
    run get_unset_claims "$aggkit_bridge_url" 50 5 "" "" "$in_global_index_ger1"
    assert_success
    log "✅ Found unset claim for global_index: $in_global_index_ger1"

    # Check for unset claim of GER2
    log "🔄 Checking for unset claim with global_index: $in_global_index_ger2"
    run get_unset_claims "$aggkit_bridge_url" 50 5 "" "" "$in_global_index_ger2"
    assert_success
    log "✅ Found unset claim for global_index: $in_global_index_ger2"

    log "🎉 Both unset claims successfully verified in AggKit database"

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

    log "⚖️ Processing claim for first bridge transaction: $bridge_tx_hash1"
    run process_bridge_claim "latest-n-injected-ger: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash1" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_first_claim_event=$output
    log "Global index of first claim event: $global_index_first_claim_event"

    log "⚖️ Processing claim for second bridge transaction: $bridge_tx_hash2"
    run process_bridge_claim "latest-n-injected-ger: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash2" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_second_claim_event=$output
    log "Global index of second claim event: $global_index_second_claim_event"

    # Verify detailed claim events are recorded in AggKit bridge database
    log "🔍 Verifying detailed claim events are recorded in AggKit database for global indexes: $global_index_first_claim_event, $global_index_second_claim_event"

    # Check for detailed claim event with global_index_first_claim_event
    log "🔄 Checking for detailed claim event with global_index: $global_index_first_claim_event"
    run get_claim "$l2_rpc_network_id" "$global_index_first_claim_event" 50 10 "$aggkit_bridge_url"
    assert_success
    log "✅ Found detailed claim event for global_index: $global_index_first_claim_event"

    # Check for detailed claim event with global_index_second_claim_event
    log "🔄 Checking for detailed claim event with global_index: $global_index_second_claim_event"
    run get_claim "$l2_rpc_network_id" "$global_index_second_claim_event" 50 10 "$aggkit_bridge_url"
    assert_success
    log "✅ Found detailed claim event for global_index: $global_index_second_claim_event"

    log "🎉 Both detailed claim events successfully verified in AggKit database"

    log "💰 Final bridge transaction: $amount wei (0.020 ETH)"
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_final=$output
    log "⚖️ Processing final L1 to L2bridge claim: $bridge_tx_hash_final"
    run process_bridge_claim "bridge-e2e-2-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_final" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    global_index_last_claim_event=$output
    assert_success

    log "⏳ Waiting for certificate settlement (global_index: $global_index_last_claim_event)"
    wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index_last_claim_event"
    log "✅ Certificate settlement completed for global index: $global_index_last_claim_event"
}

# Case A: Bridge disappearance from L1 after L1 reorg
@test "Test invalid GER injection case A (PP mode)" {
  skip "This test should be run independently on a new setup as GER and claim proofs are hardcoded to create invalid GER and its claim proof"
  local tokens_amount="0.1ether"
  local wei_amount
  wei_amount=$(cast --to-unit "$tokens_amount" wei)

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output
  run cast logs \
    --rpc-url "$L2_RPC_URL" \
    --from-block 0x0 \
    --to-block latest \
    --address "$l2_ger_addr" \
    "$update_hash_chain_value_event_sig" \
    --json
  assert_success
  update_hash_chain_value_events="$output"
  log "🔍 Fetched UpdateHashChainValue events: $update_hash_chain_value_events"

  local last_ger
  last_ger=$(echo "$update_hash_chain_value_events" | jq -r '.[-1].topics[1]')
  assert_success
  log "🔍 Last GER: $last_ger"

  local next_ger="0xec6e62fb1ebe7e588e930cab12721206f45d561adb038417779a9564d920b117"
  log "🔄 Inserting GER into map $next_ger"
  run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$next_ger" --json
  assert_success
  local insert_global_exit_root_tx_resp=$output
  log "insertGlobalExitRoot transaction details: $insert_global_exit_root_tx_resp"

  local in_merkle_proof="[0x0000000000000000000000000000000000000000000000000000000000000000,0x2eb37ace6645410b513354bf42e69e348f9f31a2e67bbdf5ab1889b762c25ef2,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
  local in_rollup_merkle_proof="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
  local in_global_index=18446744073709551618
  local in_main_exit_root="0x8be6fa91487986960d25fb8c512269108957f54502161b74c503dfb4c0eca19f"
  local in_rollup_exit_root="0x0000000000000000000000000000000000000000000000000000000000000000"
  local in_orig_net=0
  local in_orig_addr="0x0000000000000000000000000000000000000000"
  local in_dest_net=1
  local in_dest_addr="0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"
  local in_amount=100000000000000000
  local in_metadata="0x"

  run cast send --legacy --private-key "$aggoracle_private_key" \
    --rpc-url "$L2_RPC_URL" \
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
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$next_ger]"
  assert_success
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$next_ger"
  assert_success
  final_status="$output"
  assert_equal "$final_status" "0"
  log "✅ GER successfully removed"

  # Verify GER removal is recorded in AggKit database
  log "🔍 Verifying GER removal is recorded in AggKit database: $next_ger"
  run get_removed_gers "$aggkit_bridge_url" 50 5 "$next_ger"
  assert_success
  log "✅ Found GER removal event for: $next_ger"

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("$in_global_index")
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
  assert_success
  local unset_claims_tx_resp=$output
  log "unsetMultipleClaims transaction details: $unset_claims_tx_resp"

  # Verify unset claim is recorded in AggKit database
  log "🔍 Verifying unset claim is recorded in AggKit database for global_index: $in_global_index"
  run get_unset_claims "$aggkit_bridge_url" 50 5 "" "" "$in_global_index"
  assert_success
  log "✅ Found unset claim for global_index: $in_global_index"

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output

  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}

# Case A: Bridge disappearance from L1 after L1 reorg
@test "Test invalid GER injection case A (FEP mode)" {
  skip "This test should be run independently on a new setup as GER and claim proofs are hardcoded to create invalid GER and its claim proof"
  local tokens_amount="0.1ether"
  local wei_amount
  wei_amount=$(cast --to-unit "$tokens_amount" wei)

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output
  run cast logs \
    --rpc-url "$L2_RPC_URL" \
    --from-block 0x0 \
    --to-block latest \
    --address "$l2_ger_addr" \
    "$update_hash_chain_value_event_sig" \
    --json
  assert_success
  update_hash_chain_value_events="$output"
  log "🔍 Fetched UpdateHashChainValue events: $update_hash_chain_value_events"

  local last_ger
  last_ger=$(echo "$update_hash_chain_value_events" | jq -r '.[-1].topics[1]')
  assert_success
  log "🔍 Last GER: $last_ger"

  local next_ger="0x8e280ba8e633001d3c6e36974e8c3caced9048682cc6b096716247aa5c44b3e5"
  log "🔄 Inserting GER into map $next_ger"
  run cast send --legacy --private-key "$aggoracle_private_key" --rpc-url "$L2_RPC_URL" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$next_ger" --json
  assert_success
  local insert_global_exit_root_tx_resp=$output
  log "insertGlobalExitRoot transaction details: $insert_global_exit_root_tx_resp"

  local in_merkle_proof="[0xe61c1508c0de559613555fdacdf38545b394eb333dfdd0a3714457c04849fa6d,0x46b7c3b6922b450746f74060a2ee59a2c34fb3083f3047ce13be7ef64fdfab22,0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9]"
  local in_rollup_merkle_proof="[0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000]"
  local in_global_index=18446744073709551619
  local in_main_exit_root="0x884ca5e58ea4fcc6fcf966407812145f8c0eae641224c291052782341a7b5f51"
  local in_rollup_exit_root="0x0000000000000000000000000000000000000000000000000000000000000000"
  local in_orig_net=0
  local in_orig_addr="0x0000000000000000000000000000000000000000"
  local in_dest_net=1
  local in_dest_addr="0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"
  local in_amount=20000005400000000
  local in_metadata="0x"

  run cast send --legacy --private-key "$aggoracle_private_key" \
    --rpc-url "$L2_RPC_URL" \
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
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$next_ger]"
  assert_success
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$next_ger"
  assert_success
  final_status="$output"
  assert_equal "$final_status" "0"
  log "✅ GER successfully removed"

  # Verify GER removal is recorded in AggKit database
  log "🔍 Verifying GER removal is recorded in AggKit database: $next_ger"
  run get_removed_gers "$aggkit_bridge_url" 50 5 "$next_ger"
  assert_success
  log "✅ Found GER removal event for: $next_ger"

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("$in_global_index")
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
  assert_success
  local unset_claims_tx_resp=$output
  log "unsetMultipleClaims transaction details: $unset_claims_tx_resp"

  # Verify unset claim is recorded in AggKit database
  log "🔍 Verifying unset claim is recorded in AggKit database for global_index: $in_global_index"
  run get_unset_claims "$aggkit_bridge_url" 50 5 "" "" "$in_global_index"
  assert_success
  log "✅ Found unset claim for global_index: $in_global_index"

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output

  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}

@test "Inject LatestBlock-N GER - A case PP (another test)" {
  skip "This test should be run by starting anvil and a new aggkit node. Start an anvil fork using L1 rpc url. Start another aggkit bridge service using L1 as anvil fork (only need to sync bridge service, can copy the data as well if data is large for L1)."

  # TODO: Configure l1_rpc_url and aggkit_bridge_url to use anvil and new aggkit node
  # l1_rpc_url="http://localhost:8545"
  # aggkit_bridge_url="http://localhost:5577"
  amount="0.1 ether"
  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output

  local l1_latest_ger
  l1_latest_ger=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" 'getLastGlobalExitRoot() (bytes32)')
  log "🔍 Latest L1 GER: $l1_latest_ger"

  log "🔄 Inserting invalid GER ($l1_latest_ger)"
  run send_tx "$L2_RPC_URL" "$aggoracle_private_key" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$l1_latest_ger"
  assert_success

  # Extract claim params compactly
  log "🔍 Extracting claim parameters"
  local claim_params
  claim_params=$(extract_claim_parameters_json "$bridge_tx_hash" "Invalid GER claim params" "$l1_rpc_network_id")

  # Convert the proof strings from "[0x..,0x..]" into proper array literals
  # jq outputs them as plain strings, so we normalize them here
  local proof_ler=$(echo "$claim_params" | jq -r '.proof_local_exit_root')
  local proof_rer=$(echo "$claim_params" | jq -r '.proof_rollup_exit_root')

  # Ensure they are valid cast array formats: ["0x..","0x.."]
  proof_ler=$(normalize_cast_array "$proof_ler")
  proof_rer=$(normalize_cast_array "$proof_rer")

  # Extract simple scalar fields
  local global_index=$(echo "$claim_params" | jq -r '.global_index')
  local mainnet_exit_root=$(echo "$claim_params" | jq -r '.mainnet_exit_root')
  local rollup_exit_root=$(echo "$claim_params" | jq -r '.rollup_exit_root')
  local origin_network=$(echo "$claim_params" | jq -r '.origin_network')
  local origin_address=$(echo "$claim_params" | jq -r '.origin_address')
  local destination_network=$(echo "$claim_params" | jq -r '.destination_network')
  local destination_address=$(echo "$claim_params" | jq -r '.destination_address')
  local amount=$(echo "$claim_params" | jq -r '.amount')
  local metadata=$(echo "$claim_params" | jq -r '.metadata')

  run cast send --legacy --private-key "$aggoracle_private_key" \
    --rpc-url "$L2_RPC_URL" \
    "$l2_bridge_addr" \
    "$CLAIM_ASSET_FN_SIG" \
    "$proof_ler" \
    "$proof_rer" \
    "$global_index" \
    "$mainnet_exit_root" \
    "$rollup_exit_root" \
    "$origin_network" \
    "$origin_address" \
    "$destination_network" \
    "$destination_address" \
    "$amount" \
    "$metadata"
  assert_success
  local claim_tx_resp=$output
  log "🔍 Claim transaction details: $claim_tx_resp"

  # TODO: Configure l1_rpc_url and aggkit_bridge_url to use actual L1 RPC URL and original aggkit node
  # l1_rpc_url="http://localhost:8545"
  # aggkit_bridge_url="http://localhost:5577"

  log "🔄 Removing GER from map $l1_latest_ger"
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$l1_latest_ger]"
  assert_success
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$l1_latest_ger"
  assert_success
  final_status="$output"
  assert_equal "$final_status" "0"
  log "✅ GER successfully removed"

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("$global_index")
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
  assert_success
  local unset_claims_tx_resp=$output
  log "unsetMultipleClaims transaction details: $unset_claims_tx_resp"

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output

  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}
