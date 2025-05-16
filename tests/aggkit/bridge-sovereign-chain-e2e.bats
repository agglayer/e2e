setup() {
  load '../../core/helpers/common-setup'
  _common_setup

  readonly update_hash_chain_value_event_sig="UpdateHashChainValue(bytes32,bytes32)"
  readonly remove_global_exit_roots_func_sig="removeGlobalExitRoots(bytes32[])"
  readonly global_exit_root_map_sig="globalExitRootMap(bytes32)(uint256)"

  readonly l2_sovereign_admin_private_key=${L2_SOVEREIGN_ADMIN_PRIVATE_KEY:-"a574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
}

#!/usr/bin/env bats

load /usr/local/lib/bats-assert/load

@test "Test GlobalExitRoot removal" {
  echo "=== 🧑‍💻 Running GlobalExitRoot removal" >&3

  update_hash_chain_value_events=$(cast logs \
    --rpc-url "$L2_RPC_URL" \
    --from-block 0x0 \
    --to-block latest \
    --address "$l2_ger_addr" \
    "$update_hash_chain_value_event_sig" \
    --json)
  log "🔍 Fetched UpdateHashChainValue events: $update_hash_chain_value_events"

  update_hash_chain_value_last_event=$(echo "$update_hash_chain_value_events" | jq -r '.[-1]')
  last_ger=$(echo "$update_hash_chain_value_last_event" | jq -r '.topics[1]')
  log "🔍 Last GER: $last_ger"

  # Query initial status
  initial_status=$(cast call \
    $l2_ger_addr \
    "$global_exit_root_map_sig" \
    "$last_ger" \
    --rpc-url "$L2_RPC_URL")
  log "⏳ initial_status for GER $last_ger -> $initial_status"

  # Assert that the initial status is not zero
  assert ne "$initial_status" "0" "🚫 GER not found in map, cannot proceed with removal"

  # Remove the GER from map, sovereign admin should be the sender
  tx=$(cast send \
    --rpc-url "$L2_RPC_URL" \
    --private-key "$l2_sovereign_admin_private_key" \
    $l2_ger_addr \
    "$remove_global_exit_roots_func_sig" \
    "[$last_ger]" \
    --json)
  tx_hash=$(echo "$tx" | jq -r '.transactionHash')
  log "📨 Sent removeGlobalExitRoots tx: $tx_hash"

  # Query final status
  final_status=$(cast call \
    $l2_ger_addr \
    "$global_exit_root_map_sig" \
    "$last_ger" \
    --rpc-url "$L2_RPC_URL")
  log "⏳ final_status for GER $last_ger -> $final_status"

  # Assert that the final status is zero
  assert eq "$final_status" "0" "❌ Failed to remove GER"
  log "✅ GER successfully removed"
}
