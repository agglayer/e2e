setup() {
    load '../../core/helpers/common-setup'
    _common_setup

    # Load bridge sovereign chain setup functions
    load '../../core/helpers/bridge-sovereign-chain-setup'
    _bridge_sovereign_chain_setup
}

@test "Test GlobalExitRoot removal" {
    echo "=== 🧑‍💻 Running UpdateRemovalHashChainValue" >&3

    update_hash_chain_value_events=$(cast logs \
        --rpc-url     "$L2_RPC_URL" \
        --from-block  0x0 \
        --to-block    latest \
        --address     "$l2_ger_addr" \
        "UpdateHashChainValue(bytes32,bytes32)" \
        --json)
    log "🔍 Fetched UpdateHashChainValue events: $update_hash_chain_value_events"

    update_hash_chain_value_last_event=$(echo "$update_hash_chain_value_events" | jq -r '.[-1]')
    last_ger=$(echo "$update_hash_chain_value_last_event" | jq -r '.topics[1]')
    log "🔍 Last GER: $last_ger"

    # Query initial status
    initial_status=$(cast call \
      $l2_ger_addr \
      "globalExitRootMap(bytes32)(uint256)" \
      "$last_ger" \
      --rpc-url "$L2_RPC_URL")
    log "⏳ initial_status for GER $last_ger -> $initial_status"
    
    if [ "$initial_status" -eq 0 ]; then
      log "🚫 GER not found in map, skipping removal"
      return 1
    fi

    # Remove the GER from map, sovereign admin should be the sender
    tx=$(cast send \
      --rpc-url "$L2_RPC_URL" \
      --private-key "$l2_sovereign_admin_private_key" \
      $l2_ger_addr \
      "removeGlobalExitRoots(bytes32[])" \
      "[$last_ger]" \
      --json)
    tx_hash=$(echo "$tx" | jq -r '.transactionHash')
    log "📨 Sent removeGlobalExitRoots tx: $tx_hash"

    # Query final status
    final_status=$(cast call \
      $l2_ger_addr \
      "globalExitRootMap(bytes32)(uint256)" \
      "$last_ger" \
      --rpc-url "$L2_RPC_URL")
    log "⏳ final_status for GER $last_ger -> $final_status"
    
    if [ "$final_status" -eq 0 ]; then
      log "✅ GER successfully removed"
    else
      log "❌ Failed to remove GER"
      return 1
    fi
}
