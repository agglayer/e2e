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
  readonly is_claimed_func_sig="function isClaimed(uint32,uint32)"

  readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
}

get_certificate_height() {
    local aggkit_rpc_url=$1
    height=$(curl -X POST "$aggkit_rpc_url" -H "Content-Type: application/json" -d '{"method":"aggsender_getCertificateHeaderPerHeight", "params":[], "id":1}' | tail -n 1 | jq -r '.result.Header.Height')
    echo "$height"
    return 0
}

check_certificate_height() {
    local expected_height=$1
    local max_retries=${2:-10}
    local retry_delay=${3:-5}

    echo "=== Getting certificate height (expected: $expected_height, retry: $max_retries) ===" >&3
    local retry_count=0
    local height=0

    while [ $retry_count -lt $max_retries ]; do
        height=$(curl -X POST "$aggkit_rpc_url" -H "Content-Type: application/json" -d '{"method":"aggsender_getCertificateHeaderPerHeight", "params":[], "id":1}' | tail -n 1 | jq -r '.result.Header.Height')
        echo "Certificate height: $height" >&3

        if [ "$height" -eq "$expected_height" ]; then
            echo "Certificate height: $height" >&3
            return 0
        fi

        sleep $retry_delay
        retry_count=$((retry_count + 1))
    done
}

# @test "Test GlobalExitRoot removal" {
#   log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
#   local tokens_amount="0.1ether"
#   local wei_amount
#   wei_amount=$(cast --to-unit "$tokens_amount" wei)
#   destination_addr=$receiver
#   destination_net=$l2_rpc_network_id
#   amount=$wei_amount
#   meta_bytes="0x"

#   run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#   assert_success
#   local bridge_tx_hash=$output
#   run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
#   assert_success
#   local global_index=$output

#   log "⏳ Waiting for certificate settlement containing global index: $global_index"
#   wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
#   log "✅ Certificate settlement completed for global index: $global_index"

#   run cast logs \
#     --rpc-url "$L2_RPC_URL" \
#     --from-block 0x0 \
#     --to-block latest \
#     --address "$l2_ger_addr" \
#     "$update_hash_chain_value_event_sig" \
#     --json
#   assert_success
#   update_hash_chain_value_events="$output"
#   log "🔍 Fetched UpdateHashChainValue events: $update_hash_chain_value_events"

#   local last_ger
#   last_ger=$(echo "$update_hash_chain_value_events" | jq -r '.[-1].topics[1]')
#   assert_success
#   log "🔍 Last GER: $last_ger"

#   run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$last_ger"
#   assert_success
#   initial_status="$output"
#   if [[ "$initial_status" == "0" ]]; then
#     log "🚫 GER not found in map, cannot proceed with removal"
#     exit 1
#   fi

#   log "🔄 Removing GER from map $last_ger"
#   run send_tx "$L2_RPC_URL" "$l2_sovereign_admin_private_key" "$l2_ger_addr" "$remove_global_exit_roots_func_sig" "[$last_ger]"
#   assert_success
#   run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$last_ger"
#   assert_success
#   final_status="$output"
#   assert_equal "$final_status" "0"
#   log "✅ GER successfully removed"

#   log "🚀 Sending and claiming 1 bridge transaction from L1 to L2 after GER removal"
#   local tokens_amount="0.1ether"
#   local wei_amount
#   wei_amount=$(cast --to-unit "$tokens_amount" wei)
#   destination_addr=$receiver
#   destination_net=$l2_rpc_network_id
#   amount=$wei_amount
#   meta_bytes="0x"
#   run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#   assert_success
#   local bridge_tx_hash=$output
#   run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
#   assert_success
#   local global_index=$output

#   log "⏳ Waiting for certificate settlement containing global index: $global_index"
#   wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
#   log "✅ Certificate settlement completed for global index: $global_index"
# }

# @test "Test Sovereign Chain Bridge Events" {
#   log "=== 🧑‍💻 Running Sovereign Chain Bridge Events" >&3
#   run deploy_contract "$l1_rpc_url" "$sender_private_key" "$erc20_artifact_path"
#   assert_success

#   local l1_erc20_addr
#   l1_erc20_addr=$(echo "$output" | tail -n 1)
#   log "ERC20 contract address: $l1_erc20_addr"

#   # Mint and Approve ERC20 tokens on L1
#   local tokens_amount="0.1ether"
#   local wei_amount
#   wei_amount=$(cast --to-unit "$tokens_amount" wei)
#   run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
#   assert_success

#   # Assert that balance of gas token (on the L1) is correct
#   run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
#   assert_success
#   local l1_erc20_token_sender_balance
#   l1_erc20_token_sender_balance=$(echo "$output" |
#     tail -n 1 |
#     awk '{print $1}')
#   log "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]"

#   # DEPOSIT ON L1
#   destination_addr=$receiver
#   destination_net=$l2_rpc_network_id
#   amount=$(cast --to-unit "$tokens_amount" wei)
#   meta_bytes="0x"
#   run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
#   assert_success
#   local bridge_tx_hash=$output

#   # Claim deposits (settle them on the L2)
#   process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"

#   run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
#   assert_success
#   local token_mappings_result=$output

#   local l2_token_addr_legacy
#   l2_token_addr_legacy=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
#   log "L2 Token address legacy: $l2_token_addr_legacy"

#   run verify_balance "$L2_RPC_URL" "$l2_token_addr_legacy" "$receiver" 0 "$tokens_amount"
#   assert_success

#   # Deploy sovereign token erc20 contract on L2
#   run deploy_contract "$L2_RPC_URL" "$sender_private_key" "$erc20_artifact_path"
#   assert_success
#   local l2_token_addr_sovereign
#   l2_token_addr_sovereign=$(echo "$output" | tail -n 1)
#   log "L2 Token address sovereign: $l2_token_addr_sovereign"

#   # event SetSovereignTokenAddress
#   log "Emitting SetSovereignTokenAddress event"
#   arg1='[0]'
#   arg2="[$l1_erc20_addr]"
#   arg3="[$l2_token_addr_sovereign]"
#   arg4='[false]'
#   run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$set_multiple_sovereign_token_address_func_sig" "$arg1" "$arg2" "$arg3" "$arg4" --json
#   assert_success
#   local set_sov_token_addr_tx_resp=$output
#   log "setMultipleSovereignTokenAddress transaction details: $set_sov_token_addr_tx_resp"

#   # Decode the transaction details and check emmited event SetSovereignTokenAddress
#   set_sov_token_addr_log_data=$(echo "$set_sov_token_addr_tx_resp" | jq -r '.logs[0].data')
#   run cast decode-event "$set_sov_token_addr_log_data" --sig "$set_sovereign_token_address_event_sig" --json
#   assert_success
#   local set_sovereign_token_addrs_evt=$output
#   origin_network=$(jq -r '.[0]' <<<"$set_sovereign_token_addrs_evt")
#   origin_token_addr=$(jq -r '.[1]' <<<"$set_sovereign_token_addrs_evt")
#   sov_token_addr=$(jq -r '.[2]' <<<"$set_sovereign_token_addrs_evt")
#   is_not_mintable=$(jq -r '.[3]' <<<"$set_sovereign_token_addrs_evt")
#   assert_equal "0" "$origin_network"
#   assert_equal "${l1_erc20_addr,,}" "${origin_token_addr,,}"
#   assert_equal "${l2_token_addr_sovereign,,}" "${sov_token_addr,,}"
#   assert_equal "false" "$is_not_mintable"
#   log "✅ SetSovereignTokenAddress event successful"

#   # Query aggkit node for legacy token migrations
#   run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
#   assert_success
#   local initial_legacy_token_migrations="$output"
#   log "Initial legacy token migrations: $initial_legacy_token_migrations"
#   local initial_legacy_token_migrations_count
#   initial_legacy_token_migrations_count=$(echo "$initial_legacy_token_migrations" | jq -r '.count')

#   # event MigrateLegacyToken
#   log "Emitting MigrateLegacyToken event"
#   # Grant minter role to l2_bridge_addr on l2_token_addr_sovereign
#   MINTER_ROLE=$(cast keccak "MINTER_ROLE")
#   run cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$sender_private_key" "$l2_token_addr_sovereign" "$grant_role_func_sig" "$MINTER_ROLE" "$l2_bridge_addr"
#   assert_success
#   local grant_role_tx_hash=$output
#   log "✅ Minter role granted to $l2_bridge_addr on $l2_token_addr_sovereign: $grant_role_tx_hash"

#   run cast send --legacy --private-key "$sender_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$migrate_legacy_token_func_sig" "$l2_token_addr_legacy" 0 "0x" --json
#   assert_success
#   local migrate_legacy_token_tx_resp=$output
#   log "migrateLegacyToken transaction details: $migrate_legacy_token_tx_resp"
#   migrate_legacy_token_block_num=$(echo "$migrate_legacy_token_tx_resp" | jq -r '.blockNumber')
#   migrate_legacy_token_transaction_hash=$(echo "$migrate_legacy_token_tx_resp" | jq -r '.transactionHash')
#   log "migrate_from_block: $migrate_legacy_token_block_num"

#   # Find logs for MigrateLegacyToken event
#   run cast logs --rpc-url "$L2_RPC_URL" --from-block "$migrate_legacy_token_block_num" --to-block latest --address "$l2_bridge_addr" "$migrate_legacy_token_event_sig" --json
#   assert_success
#   local migrate_legacy_token_evt_logs=$output

#   # Decode the MigrateLegacyToken event
#   migrateLegacyToken_event_data=$(echo "$migrate_legacy_token_evt_logs" | jq -r '.[0].data')
#   run cast decode-event \
#     "$migrateLegacyToken_event_data" \
#     --sig "$migrate_legacy_token_event_sig" \
#     --json
#   assert_success
#   local migrate_legacy_token_event_data=$output
#   sender=$(jq -r '.[0]' <<<"$migrate_legacy_token_event_data")
#   legacy_token_addr=$(jq -r '.[1]' <<<"$migrate_legacy_token_event_data")
#   updated_token_addr=$(jq -r '.[2]' <<<"$migrate_legacy_token_event_data")
#   amount=$(jq -r '.[3]' <<<"$migrate_legacy_token_event_data")
#   assert_equal "$sender_addr" "$sender"
#   assert_equal "${l2_token_addr_legacy,,}" "${legacy_token_addr,,}"
#   assert_equal "${l2_token_addr_sovereign,,}" "${updated_token_addr,,}"
#   assert_equal "0" "$amount"
#   log "✅ MigrateLegacyToken event successful"

#   # Query aggkit node for legacy token mapping(bridge_getLegacyTokenMigrations)
#   run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10 "$migrate_legacy_token_transaction_hash"
#   assert_success
#   local legacy_token_migrations="$output"
#   local legacy_token_address
#   legacy_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].legacy_token_address')
#   local updated_token_address
#   updated_token_address=$(echo "$legacy_token_migrations" | jq -r '.legacy_token_migrations[0].updated_token_address')
#   assert_equal "${l2_token_addr_legacy,,}" "${legacy_token_address,,}"
#   assert_equal "${l2_token_addr_sovereign,,}" "${updated_token_address,,}"

#   # event RemoveLegacySovereignTokenAddress
#   log "Emitting RemoveLegacySovereignTokenAddress event"
#   run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$remove_legacy_sovereign_token_address_func_sig" "$l2_token_addr_legacy" --json
#   assert_success
#   local removeLegacySovereignTokenAddress_tx_details=$output
#   log "removeLegacySovereignTokenAddress transaction details: $removeLegacySovereignTokenAddress_tx_details"

#   # Decode the transaction details and check emmited event RemoveLegacySovereignTokenAddress
#   remove_legacy_token_event_data=$(echo "$removeLegacySovereignTokenAddress_tx_details" | jq -r '.logs[0].data')
#   run cast decode-event "$remove_legacy_token_event_data" --sig "$remove_legacy_sovereign_token_addr_event_sig" --json
#   assert_success
#   local remove_legacy_token_data=$output
#   removeLegacySovereignTokenAddress_event_sovereignTokenAddress=$(jq -r '.[0]' <<<"$remove_legacy_token_data")
#   assert_equal "${l2_token_addr_legacy,,}" "${removeLegacySovereignTokenAddress_event_sovereignTokenAddress,,}"
#   log "✅ RemoveLegacySovereignTokenAddress event successful, sleeping for 450 seconds to give aggkit time to index the event"

#   # sleep briefly to give aggkit time to index the event
#   # Increasing the sleep time to 450 seconds to give aggkit time to index the event as the settings for BridgeL2Sync is FinalizedBlock and not LatestBlock
#   sleep 450

#   # Query aggkit node for legacy token migrations
#   run get_legacy_token_migrations "$l2_rpc_network_id" 1 1 "$aggkit_bridge_url" 50 10
#   assert_success
#   local final_legacy_token_migrations="$output"
#   log "Final legacy token migrations: $final_legacy_token_migrations"
#   local final_legacy_token_migrations_count
#   final_legacy_token_migrations_count=$(echo "$final_legacy_token_migrations" | jq -r '.count')
#   assert_equal "$initial_legacy_token_migrations_count" "$final_legacy_token_migrations_count"
#   log "✅ Test Sovereign Chain Bridge Event successful"
# }

# @test "Test Unset claims Events -> claim and unset claim in same cert" {
#   local tokens_amount="0.1ether"
#   local wei_amount
#   wei_amount=$(cast --to-unit "$tokens_amount" wei)

#   local bridge_tx_hashes=()
#   local global_indexes=()
#   local deposit_counts=()

#   # Send 2 bridge transactions from L1 to L2
#   log "🚀 Sending 2 bridge transactions from L1 to L2"
#   for i in {1..2}; do
#     log "Sending bridge transaction $i/2"

#     destination_addr=$receiver
#     destination_net=$l2_rpc_network_id
#     amount=$(cast --to-unit "$tokens_amount" wei)
#     meta_bytes="0x"
#     run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#     assert_success
#     local bridge_tx_hash=$output
#     bridge_tx_hashes+=("$bridge_tx_hash")
#     run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 100 10 "$aggkit_bridge_url" "$sender_addr"
#     assert_success
#     local deposit_count=$(echo "$output" | jq -r '.deposit_count')
#     deposit_counts+=("$deposit_count")
#   done

#   log "🔐 Claiming 2 deposits on L2"
#   for i in {0..1}; do
#     local bridge_tx_hash=${bridge_tx_hashes[$i]}
#     run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
#     assert_success
#     local global_index
#     global_index=$(echo "$output" | tail -n 1)
#     global_indexes+=("$global_index")
#     if [[ "$i" == 1 ]]; then
#       log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
#       local last_one_global_indexes=("${global_indexes[1]}")
#       run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
#       assert_success
#       local unset_claims_tx_resp=$output
#       log "unsetMultipleClaims transaction details: $unset_claims_tx_resp"

#       log "🔍 Verifying that the last 1 claim is now unset"
#       local global_index=${global_indexes[1]}
#       local deposit_count=${deposit_counts[1]}
#       local origin_network=0
#       run is_claimed "$deposit_count" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
#       assert_success
#       local is_claimed_result=$output
#       if [[ "$is_claimed_result" == "false" ]]; then
#         log "✅ Global index $global_index is correctly marked as unclaimed after unset"
#       else
#         log "❌ Global index $global_index is still marked as claimed after unset"
#         exit 1
#       fi
#     fi
#   done

#   log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
#   run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#   assert_success
#   local bridge_tx_hash=$output
#   run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
#   assert_success
#   local global_index=$output

#   log "⏳ Waiting for certificate settlement containing global index: $global_index"
#   wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
#   log "✅ Certificate settlement completed for global index: $global_index"
# }

@test "Test Unset claims Events -> claim in 1 cert, unset claim in 2nd, forcibly set in 3rd" {
  local tokens_amount="0.1ether"
  local wei_amount
  wei_amount=$(cast --to-unit "$tokens_amount" wei)

  local bridge_tx_hashes=()
  local global_indexes=()
  local deposit_counts=()

  local certificate_height=$(get_certificate_height "$aggkit_rpc_url")
  log "Certificate height: $certificate_height"

  # Send 2 bridge transactions from L1 to L2
  log "🚀 Sending 2 bridge transactions from L1 to L2"
  for i in {1..2}; do
    log "Sending bridge transaction $i/2"

    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit "$tokens_amount" wei)
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    bridge_tx_hashes+=("$bridge_tx_hash")
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 100 10 "$aggkit_bridge_url" "$sender_addr"
    assert_success
    local deposit_count=$(echo "$output" | jq -r '.deposit_count')
    deposit_counts+=("$deposit_count")
  done

  log "🔐 Claiming 2 deposits on L2"
  for i in {0..1}; do
    local bridge_tx_hash=${bridge_tx_hashes[$i]}
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success
    local global_index
    global_index=$(echo "$output" | tail -n 1)
    global_indexes+=("$global_index")
  done

  log "⏳ Waiting for certificate settlement containing global index: ${global_indexes[1]}"
  wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "${global_indexes[1]}"
  log "✅ Certificate settlement completed for global index: ${global_indexes[1]}"

  local certificate_height=$(get_certificate_height "$aggkit_rpc_url")
  log "Certificate height: $certificate_height"

  log "🔄 Unsetting the last 1 claim using unsetMultipleClaims"
  local last_one_global_indexes=("${global_indexes[1]}")
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$unset_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
  assert_success
  local unset_claims_tx_resp=$output
  log "unsetMultipleClaims transaction details: $unset_claims_tx_resp"

  log "🔍 Verifying that the last 1 claim is now unset"
  local global_index=${global_indexes[1]}
  local deposit_count=${deposit_counts[1]}
  local origin_network=0
  run is_claimed "$deposit_count" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
  assert_success
  local is_claimed_result=$output
  if [[ "$is_claimed_result" == "false" ]]; then
    log "✅ Global index $global_index is correctly marked as unclaimed after unset"
  else
    log "❌ Global index $global_index is still marked as claimed after unset"
    exit 1
  fi

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output

  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"

  log "setting the last unset claim using setMultipleClaims"
  run cast send --legacy --private-key "$l2_sovereign_admin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$set_multiple_claims_func_sig" "[${last_one_global_indexes[0]}]" --json
  assert_success
  local set_claims_tx_resp=$output
  log "setMultipleClaims transaction details: $set_claims_tx_resp"

  log "🔍 Verifying that the last 1 claim is now set"
  local global_index=${global_indexes[1]}
  local deposit_count=${deposit_counts[1]}
  local origin_network=0
  run is_claimed "$deposit_count" "$origin_network" "$l2_bridge_addr" "$L2_RPC_URL"
  assert_success
  local is_claimed_result=$output
  if [[ "$is_claimed_result" == "true" ]]; then
    log "✅ Global index $global_index is correctly marked as claimed after set"
  else
    log "❌ Global index $global_index is still marked as unclaimed after set"
    exit 1
  fi

  log "🚀 Sending and claiming 1 bridge transaction from L1 to L2"
  run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
  assert_success
  local bridge_tx_hash=$output
  run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
  assert_success
  local global_index=$output

  log "⏳ Waiting for certificate settlement containing global index: $global_index"
  wait_to_settled_certificate_containing_global_index "$aggkit_rpc_url" "$global_index"
  log "✅ Certificate settlement completed for global index: $global_index"
}
