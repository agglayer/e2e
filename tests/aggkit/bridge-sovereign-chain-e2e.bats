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

  readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
}

@test "Test GlobalExitRoot removal" {
  echo "=== 🧑‍💻 Running GlobalExitRoot removal" >&3

  # Fetch UpdateHashChainValue events
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

  # Extract last GER
  local last_ger=$(echo "$update_hash_chain_value_events" | jq -r '.[-1].topics[1]')
  assert_success
  log "🔍 Last GER: $last_ger"

  # Query initial status
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$last_ger"
  assert_success
  initial_status="$output"
  log "⏳ initial_status for GER $last_ger -> $initial_status"

  # Assert that the initial status is not zero
  if [[ "$initial_status" == "0" ]]; then
    log "🚫 GER not found in map, cannot proceed with removal"
    exit 1
  fi

  # Remove the GER from map, sovereign admin should be the sender
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$last_ger]"
  assert_success
  log "🔄 Removing GER from map $last_ger"

  # Query final status
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$last_ger"
  assert_success
  final_status="$output"
  log "⏳ final_status for GER $last_ger -> $final_status"

  # Assert that the final status is zero
  assert_equal "$final_status" "0"
  log "✅ GER successfully removed"
}

@test "Test Sovereign Chain Bridge Events" {
  log "=== 🧑‍💻 Running Sovereign Chain Bridge Events" >&3
  run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
  assert_success

  local l1_erc20_addr=$(echo "$output" | tail -n 1)
  log "ERC20 contract address: $l1_erc20_addr"

  # Mint and Approve ERC20 tokens on L1
  local tokens_amount="0.1ether"
  local wei_amount=$(cast --to-unit $tokens_amount wei)
  run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
  assert_success

  # Assert that balance of gas token (on the L1) is correct
  run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
  assert_success
  local l1_erc20_token_sender_balance=$(echo "$output" |
    tail -n 1 |
    awk '{print $1}')
  log "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]"

  # DEPOSIT ON L1
  destination_addr=$receiver
  destination_net=$l2_rpc_network_id
  amount=$(cast --to-unit $tokens_amount wei)
  meta_bytes="0x"
  run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output

  # Claim deposits (settle them on the L2)
  process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"

  run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
  assert_success
  local token_mappings_result=$output

  local l2_token_addr_legacy=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
  log "L2 Token address legacy: $l2_token_addr_legacy"

  run verify_balance "$L2_RPC_URL" "$l2_token_addr_legacy" "$receiver" 0 "$tokens_amount"
  assert_success

  # Deploy sovereign token erc20 contract on L2
  run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path
  assert_success
  local l2_token_addr_sovereign=$(echo "$output" | tail -n 1)
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
  local initial_legacy_token_migrations_count=$(echo "$initial_legacy_token_migrations" | jq -r '.count')

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
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
  assert_success
  local legacy_token_migrations="$output"
  local legacy_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].legacy_token_address')
  local updated_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].updated_token_address')
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
  log "✅ RemoveLegacySovereignTokenAddress event successful"

  # Query aggkit node for legacy token migrations
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
  assert_success
  local final_legacy_token_migrations="$output"
  log "Final legacy token migrations: $final_legacy_token_migrations"
  local final_legacy_token_migrations_count=$(echo "$final_legacy_token_migrations" | jq -r '.count')
  assert_equal "$initial_legacy_token_migrations_count" "$final_legacy_token_migrations_count"
  log "✅ Test Sovereign Chain Bridge Event successful"
}
