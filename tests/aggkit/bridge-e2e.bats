setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

@test "Transfer message" {
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "====== claimMessage (L2)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"

    echo "====== bridgeMessage L2 -> L1" >&3
    destination_net=0
    run bridge_message "$destination_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "ERC20 token deposit L1 -> L2" {
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr=$(echo "$output" | tail -n 1 | tr '[:upper:]' '[:lower:]')
    log "📜 ERC20 contract address: $l1_erc20_addr"

    # Mint ERC20 token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of ERC20 token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_erc20_token_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    echo "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]" >&3

    # Send approve transaction to the ERC20 token on L1
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_erc20_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT ON L1
    echo "==== 🚀 Depositing ERC20 token on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # CLAIM (settle deposit on L2)
    echo "==== 🔐 Claiming deposit on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"

    run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success
}

@test "Native token transfer L1 -> L2" {
    destination_addr=$sender_addr
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 "$initial_receiver_balance" eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"

    echo "=== Running L2 gas token ($native_token_addr) deposit to L1 network" >&3
    destination_addr=$sender_addr
    destination_net=0
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "Test Sovereign Chain Bridge Events" {
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success

    local l1_erc20_addr=$(echo "$output" | tail -n 1)
    log "ERC20 contract address: $l1_erc20_addr" >&3

    # Mint ERC20 tokens on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of gas token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_erc20_token_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    echo "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]" >&3

    # Send approve transaction to the gas token on L1
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_erc20_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT ON L1
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 50 10 "$aggkit_node_url"
    assert_success
    local bridge="$output"
    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_node_url"
    assert_success
    local l1_info_tree_index="$output"
    run find_injected_info_after_index "$l2_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local injected_info="$output"
    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_node_url"
    assert_success
    local proof="$output"
    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 50 10 "$l1_rpc_network_id" "$l2_bridge_addr"
    assert_success

    run wait_for_expected_token "$l1_erc20_addr" 50 10 "$aggkit_node_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr_legacy=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 Token address legacy: $l2_token_addr_legacy" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr_legacy" "$receiver" 0 "$tokens_amount"
    assert_success

    # Deploy sovereign token erc20 contract on L2
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path  
    assert_success  
    local l2_token_addr_sovereign=$(echo "$output" | tail -n 1)
    echo "L2 Token address sovereign: $l2_token_addr_sovereign" >&3

    log "Sending transaction to emit SetSovereignTokenAddress event" >&3
    setMultipleSovereignTokenAddress_func_sig="setMultipleSovereignTokenAddress(uint32[],address[],address[],bool[])"
    arg1='[0]'
    arg2="[$l1_erc20_addr]"
    arg3="[$l2_token_addr_sovereign]"
    arg4='[false]'

    run cast send --private-key "$l2_sovereignadmin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$setMultipleSovereignTokenAddress_func_sig" "$arg1" "$arg2" "$arg3" "$arg4" --json
    assert_success
    local setMultipleSovereignTokenAddress_tx_details=$output
    log "setMultipleSovereignTokenAddress transaction details: $setMultipleSovereignTokenAddress_tx_details" >&3

    # Decode the transaction details and check emmited event SetSovereignTokenAddress
    SetSovereignTokenAddress_event_sig="SetSovereignTokenAddress(uint32,address,address,bool)"
    setMultipleSovereignTokenAddres_tx_data=$(echo "$setMultipleSovereignTokenAddress_tx_details" | jq -r '.logs[0].data')
    run cast decode-event "$setMultipleSovereignTokenAddres_tx_data" --sig "$SetSovereignTokenAddress_event_sig" --json
    assert_success
    local setMultipleSovereignTokenAddres_event=$output
    setMultipleSovereignTokenAddre_event_originNetwork=$(jq -r '.[0]' <<<"$setMultipleSovereignTokenAddres_event")
    setMultipleSovereignTokenAddre_event_originTokenAddress=$(jq -r '.[1] | ascii_downcase' <<<"$setMultipleSovereignTokenAddres_event")
    setMultipleSovereignTokenAddre_event_sovereignTokenAddress=$(jq -r '.[2] | ascii_downcase' <<<"$setMultipleSovereignTokenAddres_event")
    setMultipleSovereignTokenAddre_event_isNotMintable=$(jq -r '.[3]' <<<"$setMultipleSovereignTokenAddres_event")
    assert_equal "0" "$setMultipleSovereignTokenAddre_event_originNetwork"
    assert_equal "$l1_erc20_addr" "$setMultipleSovereignTokenAddre_event_originTokenAddress"
    assert_equal "$l2_token_addr_sovereign" "$setMultipleSovereignTokenAddre_event_sovereignTokenAddress"
    assert_equal "false" "$setMultipleSovereignTokenAddre_event_isNotMintable"
    log "✅ SetSovereignTokenAddress event successful" >&3

    # event MigrateLegacyToken
    log "Emitting MigrateLegacyToken event" >&3
    # Grant minter role to l2_bridge_addr on l2_token_addr_sovereign
    MINTER_ROLE=$(cast keccak "MINTER_ROLE")
    run cast send --rpc-url "$L2_RPC_URL" --private-key "$sender_private_key" "$l2_token_addr_sovereign" "grantRole(bytes32,address)" "$MINTER_ROLE" "$l2_bridge_addr"
    assert_success
    local grant_role_tx_hash=$output
    log "✅ Minter role granted to $l2_bridge_addr on $l2_token_addr_sovereign: $grant_role_tx_hash" >&3

    migrateLegacyToken_func_sig="migrateLegacyToken(address,uint256,bytes)"
    run cast send --private-key "$sender_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$migrateLegacyToken_func_sig" "$l2_token_addr_legacy" 0  "0x" --json
    assert_success
    local migrateLegacyToken_tx_details=$output
    log "migrateLegacyToken transaction details: $migrateLegacyToken_tx_details" >&3
    migrateLegacyToken_tx_details_from_block=$(echo "$migrateLegacyToken_tx_details" | jq -r '.blockNumber')
    log "migrate_from_block: $migrateLegacyToken_tx_details_from_block" >&3

    # Find logs for MigrateLegacyToken event
    MigrateLegacyToken_event_sig="MigrateLegacyToken(address,address,address,uint256)"
    run cast logs --rpc-url $L2_RPC_URL --from-block "$migrateLegacyToken_tx_details_from_block" --to-block latest --address "$l2_bridge_addr" $MigrateLegacyToken_event_sig --json    
    assert_success
    local migrateLegacyToken_event_logs=$output

    # Decode the MigrateLegacyToken event
    migrateLegacyToken_event_data=$(echo "$migrateLegacyToken_event_logs" | jq -r '.[0].data')
    run cast decode-event \
        "$migrateLegacyToken_event_data" \
        --sig "MigrateLegacyToken(address,address,address,uint256)" \
        --json
    assert_success
    local migrateLegacyToken_event=$output
    migrateLegacyToken_event_sender=$(jq -r '.[0]' <<<"$migrateLegacyToken_event")
    migrateLegacyToken_event_legacyTokenAddress=$(jq -r '.[1] | ascii_downcase' <<<"$migrateLegacyToken_event")
    migrateLegacyToken_event_updatedTokenAddress=$(jq -r '.[2] | ascii_downcase' <<<"$migrateLegacyToken_event")
    migrateLegacyToken_event_amount=$(jq -r '.[3]' <<<"$migrateLegacyToken_event")
    assert_equal "$sender_addr" "$migrateLegacyToken_event_sender"
    assert_equal "$l2_token_addr_legacy" "$migrateLegacyToken_event_legacyTokenAddress"
    assert_equal "$l2_token_addr_sovereign" "$migrateLegacyToken_event_updatedTokenAddress"
    assert_equal "0" "$migrateLegacyToken_event_amount"
    log "✅ MigrateLegacyToken event successful" >&3

    # event RemoveLegacySovereignTokenAddress
    log "Sending transaction to emit RemoveLegacySovereignTokenAddress event" >&3
    removeLegacySovereignTokenAddress_func_sig="removeLegacySovereignTokenAddress(address)"
    run cast send --private-key "$l2_sovereignadmin_private_key" --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" "$removeLegacySovereignTokenAddress_func_sig" "$l2_token_addr_legacy" --json
    assert_success
    local removeLegacySovereignTokenAddress_tx_details=$output
    log "removeLegacySovereignTokenAddress transaction details: $removeLegacySovereignTokenAddress_tx_details" >&3

    # Decode the transaction details and check emmited event RemoveLegacySovereignTokenAddress
    RemoveLegacySovereignTokenAddress_event_sig="RemoveLegacySovereignTokenAddress(address)"
    removeLegacySovereignTokenAddress_event_data=$(echo "$removeLegacySovereignTokenAddress_tx_details" | jq -r '.logs[0].data')
    run cast decode-event "$removeLegacySovereignTokenAddress_event_data" --sig "$RemoveLegacySovereignTokenAddress_event_sig" --json
    assert_success
    local removeLegacySovereignTokenAddress_event=$output
    removeLegacySovereignTokenAddress_event_sovereignTokenAddress=$(jq -r '.[0] | ascii_downcase' <<<"$removeLegacySovereignTokenAddress_event")
    assert_equal "$l2_token_addr_legacy" "$removeLegacySovereignTokenAddress_event_sovereignTokenAddress"
    log "✅ RemoveLegacySovereignTokenAddress event successful" >&3
}

@test "Verify certificate settlement" {
    echo "Waiting 10 minutes to get some settle certificate...." >&3

    run $PROJECT_ROOT/core/helpers/scripts/agglayer_certificates_monitor.sh 1 600 $l2_rpc_network_id
    assert_success
}
