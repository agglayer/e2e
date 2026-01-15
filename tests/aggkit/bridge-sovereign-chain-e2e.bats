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

  # backwardLET takes deposit count, frontier, leaf hash, and rollup merkle proof
  readonly backward_let_func_sig="function backwardLET(uint256,bytes32[32],bytes32,bytes32[32])"
  # forwardLET takes LeafData[] (leafType, originNetwork, originAddress, destinationNetwork, destinationAddress, amount, metadata) and expectedLER
  readonly forward_let_func_sig="function forwardLET((uint8,uint32,address,uint32,address,uint256,bytes)[],bytes32)"
  readonly get_root_func_sig="function getRoot() (bytes32)"
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

@test "Test inject invalid GER on L2 - B1 case" {
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

@test "Test backwardLET with reorg scenarios" {
  manage_kurtosis_service "start" "zkevm-bridge-service-001"
  manage_kurtosis_service "stop" "bridge-spammer-001"

  zkevm_bridge_url=$(_resolve_url_or_use_env "TEST_ZKEVM_BRIDGE_URL" \
        "zkevm-bridge-service-001" "rpc" \
        "Zk EVM Bridge service is not running" false)

  # Step 1: Make 1 bridge from L1 to L2 and claim it
  log "Step 1: Making 1 bridge from L1 to L2 and claiming it"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  amount=$(cast --to-unit 0.5ether wei)

  log "Bridge L1 -> L2 (0.5 ETH)"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local step1_bridge_tx_hash="$output"
  log "Bridge tx hash: $step1_bridge_tx_hash"

  # Claim the bridge on L2
  log "Claiming bridge on L2"
  run process_bridge_claim "step1" "$l1_rpc_network_id" "$step1_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  log "Claimed bridge, global_index: $output"

  # Stop aggkit to make sure no cert goes, otherwise we cant reorg to a block before the cert was settled
  manage_kurtosis_service "stop" "aggkit-001"

  # Step 2: Make 5 bridges from L2 to L1 and store their info
  log "Step 2: Making 5 bridges from L2 to L1"
  local l2_to_l1_tx_hashes=()
  destination_addr="$sender_addr"
  destination_net="$l1_rpc_network_id"
  amount=$(cast --to-unit 0.01ether wei)

  for i in {1..5}; do
    log "Bridge $i/5: L2 -> L1"
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    l2_to_l1_tx_hashes+=("$output")
    log "Bridge $i/5 tx hash: $output"
  done
  log "Completed 5 bridges from L2 to L1"

  # Step 3: Get bridge info for all 5 bridges (needed for forwardLET)
  log "Step 3: Fetching bridge info for all 5 bridges"
  local bridge_infos=()
  for i in {0..4}; do
    local tx_hash="${l2_to_l1_tx_hashes[$i]}"
    run get_bridge "reorg-test-bridge-$((i+1))" "$l2_rpc_network_id" "$tx_hash" 50 10 "$aggkit_bridge_url"
    assert_success
    bridge_infos+=("$output")
    log "Bridge $((i+1)) info: $output"
  done

  # Get the last bridge deposit count and expected LER
  local last_bridge_info="${bridge_infos[4]}"
  local last_deposit_count
  last_deposit_count=$(echo "$last_bridge_info" | jq -r '.deposit_count')
  log "Last L2->L1 deposit count: $last_deposit_count"

  # Get the current LER from L2 bridge contract BEFORE backwardLET
  log "Fetching current LER from L2 bridge contract (before backwardLET)"
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$get_root_func_sig"
  assert_success
  local expected_ler="$output"
  log "Expected LER (to restore after forwardLET): $expected_ler"

  # Get deposit count before backwardLET
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local deposit_count_after_5_bridges="$output"
  log "Deposit count after 5 bridges: $deposit_count_after_5_bridges"

  # Step 4: Perform backwardLET to roll back 3 deposits
  log "Step 4: Performing backwardLET to roll back 3 deposit counts"
  local backward_target_deposit_count=$((last_deposit_count - 2))
  log "Rolling back to deposit count: $backward_target_deposit_count"

  sleep 10
  # Get backward-let data from zkevm-bridge-service
  log "Fetching backward-let proof data"
  local backward_let_response
  backward_let_response=$(curl -s "$zkevm_bridge_url/backward-let?net_id=$l2_rpc_network_id&deposit_cnt=$backward_target_deposit_count")
  log "backward-let response: $backward_let_response"

  local backward_leaf_hash
  backward_leaf_hash=$(echo "$backward_let_response" | jq -r '.leaf_hash')
  local backward_frontier
  backward_frontier=$(echo "$backward_let_response" | jq -r '.frontier | "[" + (join(",")) + "]"')
  local backward_rollup_merkle_proof
  backward_rollup_merkle_proof=$(echo "$backward_let_response" | jq -r '.rollup_merkle_proof | "[" + (join(",")) + "]"')

  # Note down block number before backwardLET
  local l2_block_before_backward_let
  l2_block_before_backward_let=$(cast block-number --rpc-url "$L2_RPC_URL")
  l2_blockhash_before_backward_let=$(cast block "$l2_block_before_backward_let" --rpc-url "$L2_RPC_URL" --json | jq -r '.hash')
  log "L2 block number before backwardLET: $l2_block_before_backward_let"
  log "L2 block hash before backwardLET: $l2_blockhash_before_backward_let"

  # Activate emergency state and execute backwardLET
  log "Activating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$activate_emergency_state_func_sig"
  assert_success
  log "Emergency state activated"

  log "Executing backwardLET"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$backward_let_func_sig" "$backward_target_deposit_count" "$backward_frontier" "$backward_leaf_hash" "$backward_rollup_merkle_proof"
  assert_success
  log "backwardLET executed successfully"

  # Deactivate emergency state
  log "Deactivating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$deactivate_emergency_state_func_sig"
  assert_success
  log "Emergency state deactivated"

  # Note down block number after backwardLET
  local l2_block_after_backward_let
  l2_block_after_backward_let=$(cast block-number --rpc-url "$L2_RPC_URL")
  l2_blockhash_after_backward_let=$(cast block "$l2_block_after_backward_let" --rpc-url "$L2_RPC_URL" --json | jq -r '.hash')
  log "L2 block number after backwardLET: $l2_block_after_backward_let"
  log "L2 block hash after backwardLET: $l2_blockhash_after_backward_let"
  sleep 10

  # Step 5: Do a reorg to undo backwardLET - revert to block before backwardLET
  log "Step 5: Performing L2 reorg to revert state before backwardLET"
  log "Target block for reorg: $l2_block_before_backward_let"

  # Stop the L2 consensus client before reorg
  manage_kurtosis_service "stop" "op-batcher-001"
  manage_kurtosis_service "stop" "op-cl-1-op-node-op-geth-001"
  manage_kurtosis_service "stop" "op-cl-2-op-node-op-geth-001"
  sleep 10

  # Perform the reorg using debug_setHead (only affects execution client)
  local target_hex
  target_hex=$(printf "0x%x" "$l2_block_before_backward_let")
  log "Executing debug_setHead to block $target_hex (execution client only)"
  run cast rpc debug_setHead "$target_hex" --rpc-url "$L2_RPC_URL"
  assert_success
  log "debug_setHead executed successfully on execution client"

  # Restart the L2 consensus client - it should resync from the execution client's rolled-back state
  # The op-node will query the execution client's current head and resync from there
  manage_kurtosis_service "start" "op-cl-1-op-node-op-geth-001"
  manage_kurtosis_service "start" "op-cl-2-op-node-op-geth-001"
  manage_kurtosis_service "start" "op-batcher-001"
  sleep 10

  L2_RPC_URL=$(_resolve_url_or_use_env "TEST_L2_RPC_URL" \
        "op-el-1-op-geth-op-node-001" "rpc" "cdk-erigon-rpc-001" "rpc" \
        "Failed to resolve L2 RPC URL" true)

  # Step 6: Check the state of L2 - deposit count should be same as after making 5 bridges
  log "Step 6: Checking L2 state after reorg"
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local deposit_count_after_reorg="$output"
  log "Deposit count after reorg: $deposit_count_after_reorg"
  assert_equal "$deposit_count_after_reorg" "$deposit_count_after_5_bridges"
  log "Deposit count matches expected value after reorg"

  # Step 7: Check the state of bridge service - it should have the 5 bridges
  log "Step 7: Checking bridge service state"
  for i in {0..4}; do
    local tx_hash="${l2_to_l1_tx_hashes[$i]}"
    run get_bridge "reorg-verify-bridge-$((i+1))" "$l2_rpc_network_id" "$tx_hash" 50 10 "$aggkit_bridge_url"
    assert_success
    log "Bridge $((i+1)) still exists in bridge service"
  done
  log "All 5 bridges are present in bridge service"

  # Step 8: Do a txn from L1 to L2 to see if cert settles
  log "Step 8: Making bridge from L1 to L2 to verify certificate settlement after reorg"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  amount=$(cast --to-unit 0.1ether wei)
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local final_bridge_tx_hash="$output"
  log "Final bridge tx hash: $final_bridge_tx_hash"

  manage_kurtosis_service "start" "aggkit-001"
  aggkit_rpc_url=$(_resolve_url_or_use_env "TEST_AGGKIT_RPC_URL" \
        "aggkit-001" "rpc" "cdk-node-001" "rpc" \
        "Failed to resolve aggkit rpc url" true)

  # Claim the bridge on L2
  log "Claiming final bridge on L2"
  run process_bridge_claim "" "$l1_rpc_network_id" "$final_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local final_global_index="$output"
  log "Claimed final bridge, global_index: $final_global_index"

  # Wait for certificate settlement
  log "Waiting for certificate settlement containing global index: $final_global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$final_global_index"
  log "Certificate settled for global index: $final_global_index"

  log "backwardLET with reorg scenarios test completed successfully!"

  manage_kurtosis_service "stop" "zkevm-bridge-service-001"
  manage_kurtosis_service "start" "bridge-spammer-001"
}

@test "Test forwardLET with reorg scenarios" {
  manage_kurtosis_service "start" "zkevm-bridge-service-001"
  manage_kurtosis_service "stop" "bridge-spammer-001"

  zkevm_bridge_url=$(_resolve_url_or_use_env "TEST_ZKEVM_BRIDGE_URL" \
        "zkevm-bridge-service-001" "rpc" \
        "Zk EVM Bridge service is not running" false)

  # Step 1: Make 1 bridge from L1 to L2 and claim it
  log "Step 1: Making 1 bridge from L1 to L2 and claiming it"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  amount=$(cast --to-unit 0.5ether wei)

  log "Bridge L1 -> L2 (0.5 ETH)"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local step1_bridge_tx_hash="$output"
  log "Bridge tx hash: $step1_bridge_tx_hash"

  # Claim the bridge on L2
  log "Claiming bridge on L2"
  run process_bridge_claim "step1" "$l1_rpc_network_id" "$step1_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  log "Claimed bridge, global_index: $output"

  manage_kurtosis_service "stop" "aggkit-001"

  # Step 2: Make 5 bridges from L2 to L1 and store their info
  log "Step 2: Making 5 bridges from L2 to L1"
  local l2_to_l1_tx_hashes=()
  destination_addr="$sender_addr"
  destination_net="$l1_rpc_network_id"
  amount=$(cast --to-unit 0.01ether wei)

  for i in {1..5}; do
    log "Bridge $i/5: L2 -> L1"
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    l2_to_l1_tx_hashes+=("$output")
    log "Bridge $i/5 tx hash: $output"
  done
  log "Completed 5 bridges from L2 to L1"

  # Step 3: Get bridge info for all 5 bridges (needed for forwardLET)
  log "Step 3: Fetching bridge info for all 5 bridges"
  local bridge_infos=()
  for i in {0..4}; do
    local tx_hash="${l2_to_l1_tx_hashes[$i]}"
    run get_bridge "reorg-test-bridge-$((i+1))" "$l2_rpc_network_id" "$tx_hash" 50 10 "$aggkit_bridge_url"
    assert_success
    bridge_infos+=("$output")
    log "Bridge $((i+1)) info: $output"
  done

  # Get the last bridge deposit count and expected LER
  local last_bridge_info="${bridge_infos[4]}"
  local last_deposit_count
  last_deposit_count=$(echo "$last_bridge_info" | jq -r '.deposit_count')
  log "Last L2->L1 deposit count: $last_deposit_count"

  # Get the current LER from L2 bridge contract BEFORE backwardLET
  log "Fetching current LER from L2 bridge contract (before backwardLET)"
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$get_root_func_sig"
  assert_success
  local expected_ler="$output"
  log "Expected LER (to restore after forwardLET): $expected_ler"

  # Get deposit count before backwardLET
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local deposit_count_after_5_bridges="$output"
  log "Deposit count after 5 bridges: $deposit_count_after_5_bridges"

  # Step 4: Perform backwardLET to roll back 3 deposits
  log "Step 4: Performing backwardLET to roll back 3 deposit counts"
  local backward_target_deposit_count=$((last_deposit_count - 2))
  log "Rolling back to deposit count: $backward_target_deposit_count"

  # Get backward-let data from zkevm-bridge-service
  log "Fetching backward-let proof data"
  local backward_let_response
  backward_let_response=$(curl -s "$zkevm_bridge_url/backward-let?net_id=$l2_rpc_network_id&deposit_cnt=$backward_target_deposit_count")
  log "backward-let response: $backward_let_response"

  local backward_leaf_hash
  backward_leaf_hash=$(echo "$backward_let_response" | jq -r '.leaf_hash')
  local backward_frontier
  backward_frontier=$(echo "$backward_let_response" | jq -r '.frontier | "[" + (join(",")) + "]"')
  local backward_rollup_merkle_proof
  backward_rollup_merkle_proof=$(echo "$backward_let_response" | jq -r '.rollup_merkle_proof | "[" + (join(",")) + "]"')

  # Step 5: Do a backwardLET of 3 bridges
  log "Step 5: Performing backwardLET to roll back 3 deposits"

  # Activate emergency state and execute backwardLET
  log "Activating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$activate_emergency_state_func_sig"
  assert_success
  log "Emergency state activated"

  log "Executing backwardLET"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$backward_let_func_sig" "$backward_target_deposit_count" "$backward_frontier" "$backward_leaf_hash" "$backward_rollup_merkle_proof"
  assert_success
  log "backwardLET executed successfully"

  # Deactivate emergency state
  log "Deactivating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$deactivate_emergency_state_func_sig"
  assert_success
  log "Emergency state deactivated"

  # Step 6: Do a forwardLET of 3 bridges
  log "Step 6: Performing forwardLET to restore 3 deposits"
  log "Using expected LER: $expected_ler"

  # Construct LeafData array from the rolled-back bridges (indices 2, 3, 4 - the last 3 that were rolled back)
  log "Constructing LeafData array for forwardLET"
  local leaves_array="["
  for i in 2 3 4; do
    local bridge_info="${bridge_infos[$i]}"
    local leaf_type
    leaf_type=$(echo "$bridge_info" | jq -r '.leaf_type')
    local origin_network
    origin_network=$(echo "$bridge_info" | jq -r '.origin_network')
    local origin_address
    origin_address=$(echo "$bridge_info" | jq -r '.origin_address')
    local dest_network
    dest_network=$(echo "$bridge_info" | jq -r '.destination_network')
    local dest_address
    dest_address=$(echo "$bridge_info" | jq -r '.destination_address')
    local bridge_amount
    bridge_amount=$(echo "$bridge_info" | jq -r '.amount')
    local metadata
    metadata=$(echo "$bridge_info" | jq -r '.metadata')

    # Default leaf_type to 0 if not present (asset bridge)
    if [[ "$leaf_type" == "null" || -z "$leaf_type" ]]; then
      leaf_type="0"
    fi

    # Default metadata to 0x if empty
    if [[ "$metadata" == "null" || -z "$metadata" ]]; then
      metadata="0x"
    fi

    log "Leaf $i: type=$leaf_type, originNet=$origin_network, originAddr=$origin_address, destNet=$dest_network, destAddr=$dest_address, amount=$bridge_amount"

    local leaf_tuple="($leaf_type,$origin_network,$origin_address,$dest_network,$dest_address,$bridge_amount,$metadata)"

    if [[ $i -eq 2 ]]; then
      leaves_array+="$leaf_tuple"
    else
      leaves_array+=",$leaf_tuple"
    fi
  done
  leaves_array+="]"
  log "Leaves array: $leaves_array"

  # Note down block number before forwardLET
  local l2_block_before_forward_let
  l2_block_before_forward_let=$(cast block-number --rpc-url "$L2_RPC_URL")
  log "L2 block number before forwardLET: $l2_block_before_forward_let"

  # Activate emergency state (required for forwardLET)
  log "Activating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$activate_emergency_state_func_sig"
  assert_success
  log "Emergency state activated"

  # Execute forwardLET
  log "Executing forwardLET"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$forward_let_func_sig" "$leaves_array" "$expected_ler"
  assert_success
  log "forwardLET executed successfully"

  # Deactivate emergency state
  log "Deactivating emergency state on L2 bridge"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$deactivate_emergency_state_func_sig"
  assert_success
  log "Emergency state deactivated"

  # Note down block number after forwardLET
  local l2_block_after_forward_let
  l2_block_after_forward_let=$(cast block-number --rpc-url "$L2_RPC_URL")
  log "L2 block number after forwardLET: $l2_block_after_forward_let"

  # Step 7: Check L2 contract and bridge service - new bridges should be added
  log "Step 7: Checking L2 state after forwardLET"
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local deposit_count_after_forward="$output"
  log "Deposit count after forwardLET: $deposit_count_after_forward"
  assert_equal "$deposit_count_after_forward" "$((last_deposit_count + 1))"
  log "Deposit count restored correctly after forwardLET"

  # Step 8: Do a reorg to revert the state (revert forwardLET)
  log "Step 8: Performing L2 reorg to revert forwardLET state"
  log "Target block for reorg: $l2_block_before_forward_let"

  # Stop the L2 consensus client before reorg
  manage_kurtosis_service "stop" "op-batcher-001"
  manage_kurtosis_service "stop" "op-cl-1-op-node-op-geth-001"
  manage_kurtosis_service "stop" "op-cl-2-op-node-op-geth-001"
  sleep 10

  # Perform the reorg using debug_setHead
  target_hex=$(printf "0x%x" "$l2_block_before_forward_let")
  log "Executing debug_setHead to block $target_hex"
  run cast rpc debug_setHead "$target_hex" --rpc-url "$L2_RPC_URL"
  assert_success
  log "debug_setHead executed successfully"

  # Restart the L2 consensus client - it should resync from the execution client's rolled-back state
  # The op-node will query the execution client's current head and resync from there
  manage_kurtosis_service "start" "op-cl-1-op-node-op-geth-001"
  manage_kurtosis_service "start" "op-cl-2-op-node-op-geth-001"
  manage_kurtosis_service "start" "op-batcher-001"
  sleep 10

  L2_RPC_URL=$(_resolve_url_or_use_env "TEST_L2_RPC_URL" \
        "op-el-1-op-geth-op-node-001" "rpc" "cdk-erigon-rpc-001" "rpc" \
        "Failed to resolve L2 RPC URL" true)

  # Step 9: Check L2 state - bridges added by forwardLET should not be present
  log "Step 9: Checking L2 state after reorg - forwardLET bridges should be reverted"
  run query_contract "$L2_RPC_URL" "$l2_bridge_addr" "$deposit_count_func_sig"
  assert_success
  local deposit_count_after_forward_reorg="$output"
  log "Deposit count after reorg (should be back to after backwardLET): $deposit_count_after_forward_reorg"
  assert_equal "$deposit_count_after_forward_reorg" "$backward_target_deposit_count"
  log "Deposit count correctly reverted after reorg"

  # Step 10: Do a txn from L1 to L2 to see if cert settles
  log "Step 10: Making bridge from L1 to L2 to verify certificate settlement after reorg"
  destination_addr="$receiver"
  destination_net="$l2_rpc_network_id"
  amount=$(cast --to-unit 0.1ether wei)
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local final_bridge_tx_hash="$output"
  log "Final bridge tx hash: $final_bridge_tx_hash"

  manage_kurtosis_service "start" "aggkit-001"
  aggkit_rpc_url=$(_resolve_url_or_use_env "TEST_AGGKIT_RPC_URL" \
        "aggkit-001" "rpc" "cdk-node-001" "rpc" \
        "Failed to resolve aggkit rpc url" true)

  # Claim the bridge on L2
  log "Claiming final bridge on L2"
  run process_bridge_claim "" "$l1_rpc_network_id" "$final_bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local final_global_index="$output"
  log "Claimed final bridge, global_index: $final_global_index"

  # Wait for certificate settlement
  log "Waiting for certificate settlement containing global index: $final_global_index"
  wait_to_settle_certificate_containing_global_index "$aggkit_rpc_url" "$final_global_index"
  log "Certificate settled for global index: $final_global_index"

  log "forwardLET with reorg scenarios test completed successfully!"

  manage_kurtosis_service "stop" "zkevm-bridge-service-001"
  manage_kurtosis_service "start" "bridge-spammer-001"
}
