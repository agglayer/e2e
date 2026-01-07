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
  readonly insert_global_exit_root_func_sig="function insertGlobalExitRoot(bytes32)"
  readonly last_mer_func_sig="function lastMainnetExitRoot() (bytes32)"
  readonly force_emit_detailed_claim_event_func_sig="function forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])"

  readonly empty_proof=$(jq -nc '[range(32) | "0x0000000000000000000000000000000000000000000000000000000000000000"]')

  # backwardLET function signatures
  readonly backward_let_func_sig="function backwardLET(uint256,bytes32[32],bytes32,bytes32[32])"
  readonly activate_emergency_state_func_sig="function activateEmergencyState()"
  readonly deactivate_emergency_state_func_sig="function deactivateEmergencyState()"
  readonly deposit_count_func_sig="function depositCount() (uint256)"

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
  log "✅ RemoveLegacySovereignTokenAddress event successful"

  # Query aggkit node for legacy token migrations (retry logic handles indexing delays)
  run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10 "" "$initial_legacy_token_migrations_count"
  assert_success
  local final_legacy_token_migrations="$output"
  log "Final legacy token migrations: $final_legacy_token_migrations"
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

  # Remove invalid GER
  log "🔧 Removing invalid GER ($invalid_ger)"
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$invalid_ger]"
  assert_success
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$invalid_ger"
  assert_success
  assert_equal "$output" "0"
  log "✅ GER successfully removed"

  # Forcibly emit detailed claim event
  log "🔧 Forcibly emitting DetailedClaimEvent to fix the aggkit state"
  local leaf_type="0" # asset leaf type
  local claim_data="[($proof_ler, $proof_rer, $global_index, $mainnet_exit_root, $rollup_exit_root, $leaf_type, $origin_network, $origin_address, $destination_network, $destination_address, $amount, $metadata)]"
  run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_bridge_addr" \
      "$force_emit_detailed_claim_event_func_sig" "$claim_data"
  assert_success
  log "✅ Corrected DetailedClaimEvent forcibly emitted"

  # Wait for certificate settlement
  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}

@test "Test backwardLET feature" {
  log "=== 🧪 Testing backwardLET feature ===" >&3

  # Step 1: Make 1 bridge from L1 to L2 (0.7 ETH) and claim it
  log "🚀 Step 1: Making 1 bridge from L1 to L2 (0.7 ETH) and claiming it"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  amount=$(cast --to-unit 0.7ether wei)

  log "🚀 Bridge L1 -> L2 (0.7 ETH)"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local step1_bridge_tx_hash="$output"
  log "✅ Bridge tx hash: $step1_bridge_tx_hash"

  # Claim the bridge on L2
  log "🔐 Claiming bridge on L2"
  run process_bridge_claim "backwardLET-step1" "$l1_rpc_network_id" "$step1_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  log "✅ Claimed bridge, global_index: $output"
  local claimed_global_index="$output"
  # Wait for certificate to settle containing the claimed global index
  log "⏳ Waiting for certificate settlement containing global index: $claimed_global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$claimed_global_index"
  log "✅ Certificate settled for global index: $claimed_global_index"

  # Step 2: Make 3 bridges from L2 to L1
  log "🚀 Step 2: Making 3 bridges from L2 to L1"
  local l2_to_l1_tx_hashes=()
  destination_addr="$sender_addr"
  destination_net="$l1_rpc_network_id"
  amount=$(cast --to-unit 0.01ether wei)

  for i in {1..3}; do
    log "🚀 Bridge $i/3: L2 -> L1"
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    l2_to_l1_tx_hashes+=("$output")
    log "✅ Bridge $i/3 tx hash: $output"
  done
  log "✅ Completed 3 bridges from L2 to L1"

  log "Step 3: Getting the last L2->L1 bridge deposit count for backwardLET calculation"

  # Get the last L2->L1 bridge deposit count for backwardLET calculation
  local last_l2_bridge_tx="${l2_to_l1_tx_hashes[2]}"
  run get_bridge "backwardLET" "$l2_rpc_network_id" "$last_l2_bridge_tx" 50 10 "$aggkit_bridge_url"
  assert_success
  local last_bridge_info="$output"
  local last_deposit_count
  last_deposit_count=$(echo "$last_bridge_info" | jq -r '.deposit_count')
  log "📋 Last L2->L1 deposit count: $last_deposit_count"

  # Step 4: Perform backwardLET to remove 2 deposit counts
  log "🔧 Step 4: Performing backwardLET to roll back 2 deposit counts"

  # Calculate the target deposit count (remove 2 deposits, keep 1)
  local target_deposit_count=$((last_deposit_count - 2))
  log "📋 Rolling back to deposit count: $target_deposit_count"

  # Get backward-let data from zkevm-bridge-service
  log "🔍 Fetching backward-let proof data"
  local backward_let_response
  backward_let_response=$(curl -s "$zkevm_bridge_url/backward-let?net_id=$l2_rpc_network_id&deposit_cnt=$target_deposit_count")
  log "📋 backward-let response: $backward_let_response"

  local leaf_hash
  leaf_hash=$(echo "$backward_let_response" | jq -r '.leaf_hash')
  local frontier
  frontier=$(echo "$backward_let_response" | jq -r '.frontier | "[" + (join(",")) + "]"')
  local rollup_merkle_proof
  rollup_merkle_proof=$(echo "$backward_let_response" | jq -r '.rollup_merkle_proof | "[" + (join(",")) + "]"')

  log "📋 leaf_hash: $leaf_hash"
  log "📋 frontier: $frontier"
  log "📋 rollup_merkle_proof: $rollup_merkle_proof"

  # Activate emergency state (required for backwardLET)
  log "🚨 Activating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$activate_emergency_state_func_sig"
  assert_success
  log "✅ Emergency state activated"

  # Execute backwardLET
  log "🔄 Executing backwardLET"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$backward_let_func_sig" "$target_deposit_count" "$frontier" "$leaf_hash" "$rollup_merkle_proof"
  assert_success
  log "✅ backwardLET executed successfully"

  # Deactivate emergency state
  log "🔓 Deactivating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$deactivate_emergency_state_func_sig"
  assert_success
  log "✅ Emergency state deactivated"

  # Verify the deposit count has been rolled back
  sleep 10 # Wait for state to sync
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local current_deposit_count="$output"
  log "📋 Current deposit count after backwardLET: $current_deposit_count"

  # Step 5: Do a new bridge from L1 to L2 and verify certificate settles
  log "🚀 Step 5: Making new bridge from L1 to L2 after backwardLET"
  # Bridge from L1 to L2
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local step5_bridge_tx_hash="$output"
  log "✅ Step 5 bridge tx hash: $step5_bridge_tx_hash"

  # Claim the deposit on L2
  run process_bridge_claim "backwardLET-step5" "$l1_rpc_network_id" "$step5_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local claimed_global_index="$output"
  log "📋 Claimed global index: $claimed_global_index"

  # Wait for certificate to settle containing the claimed global index
  log "⏳ Waiting for certificate settlement containing global index: $claimed_global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$claimed_global_index"
  log "✅ Certificate settled for global index: $claimed_global_index"

  log "✅ backwardLET test completed successfully!"
}
