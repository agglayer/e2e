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
  readonly last_mer_func_sig="function lastMainnetExitRoot() (bytes32)"
  readonly force_emit_detailed_claim_event_func_sig="function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])"

  readonly empty_proof=$(jq -nc '[range(32) | "0x0000000000000000000000000000000000000000000000000000000000000000"]')

  contracts_url="$(kurtosis port print "$ENCLAVE_NAME" "$contracts_container" http)"
  input_args="$(curl -s "${contracts_url}/opt/input/input_args.json")"

  # AGGORACLE_PRIVATE_KEY
  if [[ -n "${AGGORACLE_PRIVATE_KEY:-}" ]]; then
      aggoracle_private_key="$AGGORACLE_PRIVATE_KEY"
  else
      aggoracle_private_key="$(echo "$input_args" \
          | jq -r '.args.zkevm_l2_aggoracle_private_key')"
  fi
  readonly aggoracle_private_key

  # L2_SOVEREIGN_ADMIN_PRIVATE_KEY
  if [[ -n "${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-}" ]]; then
      l2_sovereign_admin_private_key="$L2_SOVEREIGN_ADMIN_PRIVATE_KEY"
  else
      l2_sovereign_admin_private_key="$(echo "$input_args" \
          | jq -r '.args.zkevm_l2_sovereignadmin_private_key')"
  fi
  readonly l2_sovereign_admin_private_key
}

@test "Test Sovereign Chain Bridge Events" {
  log "=== 🧑‍💻 Running Sovereign Chain Bridge Events" >&3
  run deploy_contract "$l1_rpc_url" "$sender_private_key" "$erc20_artifact_path"
  assert_success

  local l1_erc20_addr
  l1_erc20_addr=$(echo "$output" | tail -n 1)
  log "ERC20 contract address: $l1_erc20_addr"

  # Mint and Approve ERC20 tokens on L1
  local tokens_amount="0.1ether"
  local wei_amount
  wei_amount=$(cast --to-unit "$tokens_amount" wei)
  run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
  assert_success

  # Assert that balance of gas token (on the L1) is correct
  run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
  assert_success
  local l1_erc20_token_sender_balance
  l1_erc20_token_sender_balance=$(echo "$output" |
    tail -n 1 |
    awk '{print $1}')
  log "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]"

  # DEPOSIT ON L1
  destination_addr=$receiver
  destination_net=$l2_rpc_network_id
  amount=$(cast --to-unit "$tokens_amount" wei)
  meta_bytes="0x"
  run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output

  # Claim deposits (settle them on the L2)
  run process_bridge_claim "" "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success

  run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
  assert_success
  local token_mappings_result=$output

  local l2_token_addr_legacy
  l2_token_addr_legacy=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
  log "L2 Token address legacy: $l2_token_addr_legacy"

  run verify_balance "$L2_RPC_URL" "$l2_token_addr_legacy" "$receiver" 0 "$tokens_amount"
  assert_success

  # Deploy sovereign token erc20 contract on L2
  run deploy_contract "$L2_RPC_URL" "$sender_private_key" "$erc20_artifact_path"
  assert_success
  local l2_token_addr_sovereign
  l2_token_addr_sovereign=$(echo "$output" | tail -n 1)
  log "L2 Token address sovereign: $l2_token_addr_sovereign"

  # event SetSovereignTokenAddress
  log "Emitting SetSovereignTokenAddress event"
  arg1='[0]'
  arg2="[$l1_erc20_addr]"
  arg3="[$l2_token_addr_sovereign]"
  arg4='[false]'
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$set_multiple_sovereign_token_address_func_sig" "$arg1" "$arg2" "$arg3" "$arg4" --json
  assert_success
  local set_sov_token_addr_tx_resp=$output
  log "setMultipleSovereignTokenAddress transaction details: $set_sov_token_addr_tx_resp"

  # Decode the transaction details and check emmited event SetSovereignTokenAddress
  set_sov_token_addr_log_data=$(echo "$set_sov_token_addr_tx_resp" | jq -r '.logs[0].data')
  run cast decode-event "$set_sov_token_addr_log_data" --sig "$set_sovereign_token_address_event_sig" --json
  assert_success
  local set_sovereign_token_addrs_evt=$output
  origin_network=$(jq -r '.[0]' <<<"$set_sovereign_token_addrs_evt")
  origin_token_addr=$(jq -r '.[1]' <<<"$set_sovereign_token_addrs_evt")
  sov_token_addr=$(jq -r '.[2]' <<<"$set_sovereign_token_addrs_evt")
  is_not_mintable=$(jq -r '.[3]' <<<"$set_sovereign_token_addrs_evt")
  assert_equal "0" "$origin_network"
  assert_equal "${l1_erc20_addr,,}" "${origin_token_addr,,}"
  assert_equal "${l2_token_addr_sovereign,,}" "${sov_token_addr,,}"
  assert_equal "false" "$is_not_mintable"
  log "✅ SetSovereignTokenAddress event successful"

  # Query aggkit node for legacy token migrations
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
  assert_success
  local initial_legacy_token_migrations="$output"
  log "Initial legacy token migrations: $initial_legacy_token_migrations"
  local initial_legacy_token_migrations_count
  initial_legacy_token_migrations_count=$(echo "$initial_legacy_token_migrations" | jq -r '.count')

  # event MigrateLegacyToken
  log "Emitting MigrateLegacyToken event"
  # Grant minter role to l2_bridge_addr on l2_token_addr_sovereign
  MINTER_ROLE=$(cast keccak "MINTER_ROLE")
  run cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$sender_private_key" "$l2_token_addr_sovereign" "$grant_role_func_sig" "$MINTER_ROLE" "$l2_bridge_addr"
  assert_success
  local grant_role_tx_hash=$output
  log "✅ Minter role granted to $l2_bridge_addr on $l2_token_addr_sovereign: $grant_role_tx_hash"

  run cast send --legacy --private-key "$sender_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$migrate_legacy_token_func_sig" "$l2_token_addr_legacy" 0 "0x" --json
  assert_success
  local migrate_legacy_token_tx_resp=$output
  log "migrateLegacyToken transaction details: $migrate_legacy_token_tx_resp"
  migrate_legacy_token_block_num=$(echo "$migrate_legacy_token_tx_resp" | jq -r '.blockNumber')
  migrate_legacy_token_transaction_hash=$(echo "$migrate_legacy_token_tx_resp" | jq -r '.transactionHash')
  log "migrate_from_block: $migrate_legacy_token_block_num"

  # Find logs for MigrateLegacyToken event
  run cast logs --rpc-url "$L2_RPC_URL" --from-block "$migrate_legacy_token_block_num" --to-block latest --address "$l2_bridge_addr" "$migrate_legacy_token_event_sig" --json
  assert_success
  local migrate_legacy_token_evt_logs=$output

  # Decode the MigrateLegacyToken event
  migrateLegacyToken_event_data=$(echo "$migrate_legacy_token_evt_logs" | jq -r '.[0].data')
  run cast decode-event \
    "$migrateLegacyToken_event_data" \
    --sig "$migrate_legacy_token_event_sig" \
    --json
  assert_success
  local migrate_legacy_token_event_data=$output
  sender=$(jq -r '.[0]' <<<"$migrate_legacy_token_event_data")
  legacy_token_addr=$(jq -r '.[1]' <<<"$migrate_legacy_token_event_data")
  updated_token_addr=$(jq -r '.[2]' <<<"$migrate_legacy_token_event_data")
  amount=$(jq -r '.[3]' <<<"$migrate_legacy_token_event_data")
  assert_equal "$sender_addr" "$sender"
  assert_equal "${l2_token_addr_legacy,,}" "${legacy_token_addr,,}"
  assert_equal "${l2_token_addr_sovereign,,}" "${updated_token_addr,,}"
  assert_equal "0" "$amount"
  log "✅ MigrateLegacyToken event successful"

  # Query aggkit node for legacy token mapping(bridge_getLegacyTokenMigrations)
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10 "$migrate_legacy_token_transaction_hash"
  assert_success
  local legacy_token_migrations="$output"
  local legacy_token_address
  legacy_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].legacy_token_address')
  local updated_token_address
  updated_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].updated_token_address')
  assert_equal "${l2_token_addr_legacy,,}" "${legacy_token_address,,}"
  assert_equal "${l2_token_addr_sovereign,,}" "${updated_token_address,,}"

  # event RemoveLegacySovereignTokenAddress
  log "Emitting RemoveLegacySovereignTokenAddress event"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$remove_legacy_sovereign_token_address_func_sig" "$l2_token_addr_legacy" --json
  assert_success
  local removeLegacySovereignTokenAddress_tx_details=$output
  log "removeLegacySovereignTokenAddress transaction details: $removeLegacySovereignTokenAddress_tx_details"

  # Decode the transaction details and check emmited event RemoveLegacySovereignTokenAddress
  remove_legacy_token_event_data=$(echo "$removeLegacySovereignTokenAddress_tx_details" | jq -r '.logs[0].data')
  run cast decode-event "$remove_legacy_token_event_data" --sig "$remove_legacy_sovereign_token_addr_event_sig" --json
  assert_success
  local remove_legacy_token_data=$output
  removeLegacySovereignTokenAddress_event_sovereignTokenAddress=$(jq -r '.[0]' <<<"$remove_legacy_token_data")
  assert_equal "${l2_token_addr_legacy,,}" "${removeLegacySovereignTokenAddress_event_sovereignTokenAddress,,}"
  log "✅ RemoveLegacySovereignTokenAddress event successful, sleeping for 450 seconds to give aggkit time to index the event"

  # sleep briefly to give aggkit time to index the event
  # Increasing the sleep time to 450 seconds to give aggkit time to index the event as the settings for BridgeL2Sync is FinalizedBlock and not LatestBlock
  sleep 450

  # Query aggkit node for legacy token migrations
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
  assert_success
  local final_legacy_token_migrations="$output"
  log "Final legacy token migrations: $final_legacy_token_migrations"
  local final_legacy_token_migrations_count
  final_legacy_token_migrations_count=$(echo "$final_legacy_token_migrations" | jq -r '.count')
  assert_equal "$initial_legacy_token_migrations_count" "$final_legacy_token_migrations_count"
  log "✅ Test Sovereign Chain Bridge Event successful"
}

@test "Inject LatestBlock-N GER - A case PP" {
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

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("$in_global_index")
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

@test "Inject LatestBlock-N GER - A case FEP" {
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

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("$in_global_index")
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

@test "Test inject invalid GER on L2 (bridges are valid)" {
  log "🚀 Sending bridge from L1 to L2"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output

  # Construct and insert invalid GER
  log "⚠️ Constructing invalid GER and inserting into AgglayerGERL2 SC 🔧💥"
  run query_contract "$l1_rpc_url" "$l1_ger_addr" "$last_mer_func_sig"
  assert_success
  local last_mer=$output

  local invalid_rer="0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  local invalid_ger
  invalid_ger=$(cast keccak "$(cast abi-encode "f(bytes32, bytes32)" $last_mer $invalid_rer)")

  log "🔄 Inserting invalid GER ($invalid_ger)"
  run send_tx "$L2_RPC_URL" "$aggoracle_private_key" "$l2_ger_addr" "$insert_global_exit_root_func_sig" "$invalid_ger"
  assert_success

  # Extract claim params compactly
  log "🔍 Extracting claim parameters"
  local claim_params
  claim_params=$(extract_claim_parameters_json "$bridge_tx_hash" "Invalid GER claim params" "$l1_rpc_network_id")

  # Convert the proof strings from "[0x..,0x..]" into proper array literals
  # jq outputs them as plain strings, so we normalize them here
  local proof_ler=$(echo "$claim_params" | jq -r '.proof_local_exit_root')
  proof_rer=$(echo "$claim_params" | jq -r '.proof_rollup_exit_root')

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

  # Claim bridge
  local normalized_empty_proof
  normalized_empty_proof=$(normalize_cast_array "$empty_proof")
  log "⏳ Attempting to claim bridge with invalid GER"
  run send_tx "$L2_RPC_URL" "$sender_private_key" "$l2_bridge_addr" \
      "$CLAIM_ASSET_FN_SIG" \
      "$proof_ler" \
      "$normalized_empty_proof" \
      "$global_index" \
      "$mainnet_exit_root" \
      "$invalid_rer" \
      "$origin_network" \
      "$origin_address" \
      "$destination_network" \
      "$destination_address" \
      "$amount" \
      "$metadata"
  assert_success
  log "✅ Bridge claim successful despite invalid GER"

  log "🔍 Verifying that the claim with invalid GER is indexed"
  run get_claim "$l2_rpc_network_id" "$global_index" 12 30 "$aggkit_bridge_url"
  assert_success
  local indexed_claim="$output"
  assert_equal "$(echo "$indexed_claim" | jq -r '.rollup_exit_root')" "$invalid_rer"
  log "✅ The claim with invalid GER is indexed"

  # Forcibly emit detailed claim event
  log "🔧 Forcibly emitting detailed claim event to fix the aggkit state"
  local leaf_type="0" # asset leaf type
  local claim_data="[($proof_ler, $proof_rer, $global_index, $mainnet_exit_root, $rollup_exit_root, $leaf_type, $origin_network, $origin_address, $destination_network, $destination_address, $amount, $metadata)]"
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" \
      "$force_emit_detailed_claim_event_func_sig" "$claim_data"
  assert_success
  log "✅ Detailed claim event forcibly emitted"

  # Remove invalid GER
  log "🔧 Removing invalid GER ($invalid_ger)"
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$invalid_ger]"
  assert_success
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$invalid_ger"
  assert_success
  assert_equal "$output" "0"
  log "✅ GER successfully removed"

  # Wait for certificate settlement
  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}
