setup() {
  load '../../core/helpers/common-setup'
  _common_setup

  readonly update_hash_chain_value_event_sig="event UpdateHashChainValue(bytes32, bytes32)"
  readonly remove_global_exit_roots_func_sig="function removeGlobalExitRoots(bytes32[])"
  readonly global_exit_root_map_sig="function globalExitRootMap(bytes32) (uint256)"

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
  tx_hash=$(echo "$output" | grep -oP '(?<=transaction hash: )0x\w+')
  log "📨 Sent removeGlobalExitRoots tx: $tx_hash"

  # Query final status
  run query_contract "$L2_RPC_URL" "$l2_ger_addr" "$global_exit_root_map_sig" "$last_ger"
  assert_success
  final_status="$output"
  log "⏳ final_status for GER $last_ger -> $final_status"

  # Assert that the final status is zero
  assert_equal "$final_status" "0"
  log "✅ GER successfully removed"
}
