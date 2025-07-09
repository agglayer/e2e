setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test reentrancy protection for bridge claims - should prevent double claiming" {
    # ========================================
    # STEP 1: Deploy the reentrancy testing contract
    # ========================================
    log "🔧 STEP 1: Deploying reentrancy testing contract"

    local mock_artifact_path="$PROJECT_ROOT/compiled-contracts/BridgeMessageReceiverMock.sol/BridgeMessageReceiverMock.json"

    # Validate artifact exists
    if [[ ! -f "$mock_artifact_path" ]]; then
        log "❌ Error: Contract artifact not found at $mock_artifact_path"
        exit 1
    fi

    # Extract bytecode from contract artifact
    local bytecode=$(jq -r '.bytecode.object // .bytecode' "$mock_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $mock_artifact_path"
        exit 1
    fi

    # ABI-encode constructor argument (bridge address)
    local encoded_args=$(cast abi-encode "constructor(address)" "$l2_bridge_addr")
    if [[ -z "$encoded_args" ]]; then
        log "❌ Failed to ABI-encode constructor argument"
        exit 1
    fi

    # Prepare deployment bytecode
    local deploy_bytecode="${bytecode}${encoded_args:2}" # Remove 0x prefix from encoded args

    # Deploy contract with fixed gas price
    local gas_price=1000000000
    log "📝 Deploying contract with gas price: $gas_price wei"

    local deploy_output
    deploy_output=$(cast send --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" \
        --legacy \
        --create "$deploy_bytecode" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to deploy contract"
        log "$deploy_output"
        exit 1
    fi

    # Extract deployed contract address
    local mock_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$mock_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi

    log "✅ Deployed reentrancy testing contract at: $mock_sc_addr"

    # ========================================
    # STEP 2: Bridge first asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 2: Bridging first asset from L1 to L2 (destination: deployer)"

    # Set destination for first bridge
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_1=$output
    log "✅ First bridge transaction hash: $bridge_tx_hash_1"

    # ========================================
    # STEP 3: Get claim parameters for first asset
    # ========================================
    log "📋 STEP 3: Retrieving claim parameters for first asset"

    # Get bridge details
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_1="$output"
    local deposit_count_1=$(echo "$bridge_1" | jq -r '.deposit_count')
    log "📝 First bridge deposit count: $deposit_count_1"

    # Get L1 info tree index
    log "🌳 Getting L1 info tree index for first bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_1="$output"
    log "📝 First L1 info tree index: $l1_info_tree_index_1"

    # Get injected L1 info leaf
    log "🍃 Getting injected L1 info leaf for first bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_1="$output"

    # Generate claim proof
    log "🔐 Generating claim proof for first asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_1" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_1="$output"

    # Extract claim parameters for first asset
    log "🎯 Extracting claim parameters for first asset"
    local proof_local_exit_root_1=$(echo "$proof_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_1=$(echo "$proof_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    run generate_global_index "$bridge_1" "$l1_rpc_network_id"
    assert_success
    local global_index_1=$output

    local mainnet_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_1=$(echo "$bridge_1" | jq -r '.origin_network')
    local origin_address_1=$(echo "$bridge_1" | jq -r '.origin_address')
    local destination_network_1=$(echo "$bridge_1" | jq -r '.destination_network')
    local destination_address_1=$(echo "$bridge_1" | jq -r '.destination_address')
    local amount_1=$(echo "$bridge_1" | jq -r '.amount')
    local metadata_1=$(echo "$bridge_1" | jq -r '.metadata')

    log "✅ First asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_1, Amount: $amount_1 wei"

    # ========================================
    # STEP 4: Bridge second asset (destination: contract address)
    # ========================================
    log "🌉 STEP 4: Bridging second asset from L1 to L2 (destination: contract)"

    # Set destination for second bridge
    destination_addr=$mock_sc_addr

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "✅ Second bridge transaction hash: $bridge_tx_hash_2"

    # ========================================
    # STEP 5: Get claim parameters for second asset
    # ========================================
    log "📋 STEP 5: Retrieving claim parameters for second asset"

    # Get bridge details
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_2="$output"
    local deposit_count_2=$(echo "$bridge_2" | jq -r '.deposit_count')
    log "📝 Second bridge deposit count: $deposit_count_2"

    # Get L1 info tree index
    log "🌳 Getting L1 info tree index for second bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_2="$output"

    # Get injected L1 info leaf
    log "🍃 Getting injected L1 info leaf for second bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_2="$output"

    # Generate claim proof
    log "🔐 Generating claim proof for second asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_2" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_2="$output"

    # Extract claim parameters for second asset
    log "🎯 Extracting claim parameters for second asset"
    local proof_local_exit_root_2=$(echo "$proof_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_2=$(echo "$proof_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    run generate_global_index "$bridge_2" "$l1_rpc_network_id"
    assert_success
    local global_index_2=$output

    local mainnet_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_2=$(echo "$bridge_2" | jq -r '.origin_network')
    local origin_address_2=$(echo "$bridge_2" | jq -r '.origin_address')
    local destination_network_2=$(echo "$bridge_2" | jq -r '.destination_network')
    local destination_address_2=$(echo "$bridge_2" | jq -r '.destination_address')
    local amount_2=$(echo "$bridge_2" | jq -r '.amount')
    local metadata_2=$(echo "$bridge_2" | jq -r '.metadata')

    log "✅ Second asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_2, Amount: $amount_2 wei"

    # ========================================
    # STEP 6: Update contract with first asset claim parameters
    # ========================================
    log "⚙️ STEP 6: Updating contract with first asset claim parameters"

    local update_output
    update_output=$(cast send \
        "$mock_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root_1" \
        "$proof_rollup_exit_root_1" \
        "$global_index_1" \
        "$mainnet_exit_root_1" \
        "$rollup_exit_root_1" \
        "$origin_network_1" \
        "$origin_address_1" \
        "$destination_network_1" \
        "$destination_address_1" \
        "$amount_1" \
        "$metadata_1" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to update contract parameters"
        log "$update_output"
        exit 1
    fi

    log "✅ Contract parameters updated successfully"

    # ========================================
    # STEP 7: Get initial balances for verification
    # ========================================
    log "💰 STEP 7: Recording initial balances for verification"

    # Get initial token balances (in ETH units)
    local initial_sender_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$sender_addr")
    local initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    # Convert to wei for precise comparison
    local initial_sender_balance_wei=$(cast to-wei "$initial_sender_balance" ether)
    local initial_contract_balance_wei=$(cast to-wei "$initial_contract_balance" ether)

    log "📊 Initial sender balance: $initial_sender_balance ETH ($initial_sender_balance_wei wei)"
    log "📊 Initial contract balance: $initial_contract_balance ETH ($initial_contract_balance_wei wei)"

    # ========================================
    # STEP 8: Claim second asset (should succeed)
    # ========================================
    log "🌉 STEP 8: Claiming second asset (should succeed)"

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_2" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_2_claimed=$output
    log "✅ Second asset claimed successfully, global index: $global_index_2_claimed"

    # ========================================
    # STEP 9: Test reentrancy protection
    # ========================================
    log "🔄 STEP 9: Testing reentrancy protection - attempting to claim first asset again"

    # Calculate gas price for reentrant claim
    local comp_gas_price=$(bc -l <<<"$gas_price * 1.5" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        log "❌ Failed to calculate gas price"
        return 1
    fi

    log "⏳ Attempting reentrant claim with parameters:"
    log "   Global index: $global_index_1"
    log "   Origin network: $origin_network_1"
    log "   Destination network: $destination_network_1"
    log "   Amount: $amount_1 wei"
    log "   Gas price: $comp_gas_price wei"

    # Create temporary file for error capture
    local tmp_response=$(mktemp)
    local revert_result

    # Attempt reentrant claim and capture any errors
    cast send --legacy --gas-price $comp_gas_price \
        --rpc-url $L2_RPC_URL \
        --private-key $sender_private_key \
        $l2_bridge_addr "claimMessage(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root_1" "$proof_rollup_exit_root_1" $global_index_1 $mainnet_exit_root_1 $rollup_exit_root_1 \
        $origin_network_1 $origin_address_1 $destination_network_1 $destination_address_1 $amount_1 $metadata_1 2>$tmp_response || {
        # Use existing function to check revert code
        check_claim_revert_code "$tmp_response"
        revert_result=$?
        rm -f "$tmp_response"
    }

    # Validate reentrancy protection
    if [[ $revert_result -eq 0 ]]; then
        log "✅ Reentrancy protection working correctly - claim failed with AlreadyClaimed"
    else
        log "❌ Reentrancy protection failed - unexpected error (return code: $revert_result)"
        return 1
    fi

    # ========================================
    # STEP 10: Verify claim events in aggkit
    # ========================================
    log "🔍 STEP 10: Verifying claim events were processed correctly by aggkit"

    # Verify first claim was processed
    log "🔍 Validating first asset claim processing"
    run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_1="$output"
    log "📋 First claim response received"

    # Validate first claim parameters
    log "🔍 Validating first claim parameters"
    local claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
    local claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
    local claim_1_origin_network=$(echo "$claim_1" | jq -r '.origin_network')
    local claim_1_origin_address=$(echo "$claim_1" | jq -r '.origin_address')
    local claim_1_destination_network=$(echo "$claim_1" | jq -r '.destination_network')
    local claim_1_destination_address=$(echo "$claim_1" | jq -r '.destination_address')
    local claim_1_amount=$(echo "$claim_1" | jq -r '.amount')
    local claim_1_metadata=$(echo "$claim_1" | jq -r '.metadata')

    # Assert parameter consistency
    assert_equal "$claim_1_mainnet_exit_root" "$mainnet_exit_root_1"
    assert_equal "$claim_1_rollup_exit_root" "$rollup_exit_root_1"
    assert_equal "$claim_1_origin_network" "$origin_network_1"
    assert_equal "$claim_1_origin_address" "$origin_address_1"
    assert_equal "$claim_1_destination_network" "$destination_network_1"
    assert_equal "$claim_1_destination_address" "$destination_address_1"
    assert_equal "$claim_1_amount" "$amount_1"
    assert_equal "$claim_1_metadata" "$metadata_1"

    # Validate first claim proofs
    log "🔍 Validating first claim proofs"
    local claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
    assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"
    log "✅ First claim validated successfully"

    # Verify second claim was processed
    log "🔍 Validating second asset claim processing"
    run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_2="$output"
    log "📋 Second claim response received"

    # Validate second claim parameters
    log "🔍 Validating second claim parameters"
    local claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
    local claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
    local claim_2_origin_network=$(echo "$claim_2" | jq -r '.origin_network')
    local claim_2_origin_address=$(echo "$claim_2" | jq -r '.origin_address')
    local claim_2_destination_network=$(echo "$claim_2" | jq -r '.destination_network')
    local claim_2_destination_address=$(echo "$claim_2" | jq -r '.destination_address')
    local claim_2_amount=$(echo "$claim_2" | jq -r '.amount')
    local claim_2_metadata=$(echo "$claim_2" | jq -r '.metadata')

    # Assert parameter consistency
    assert_equal "$claim_2_mainnet_exit_root" "$mainnet_exit_root_2"
    assert_equal "$claim_2_rollup_exit_root" "$rollup_exit_root_2"
    assert_equal "$claim_2_origin_network" "$origin_network_2"
    assert_equal "$claim_2_origin_address" "$origin_address_2"
    assert_equal "$claim_2_destination_network" "$destination_network_2"
    assert_equal "$claim_2_destination_address" "$destination_address_2"
    assert_equal "$claim_2_amount" "$amount_2"
    assert_equal "$claim_2_metadata" "$metadata_2"

    # Validate second claim proofs
    log "🔍 Validating second claim proofs"
    local claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
    assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
    log "✅ Second claim validated successfully"

    # ========================================
    # STEP 11: Final balance verification
    # ========================================
    log "💰 STEP 11: Verifying final balances"

    # Get final balances (in eth)
    local final_sender_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$sender_addr")
    local final_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    local final_sender_balance_wei=$(cast to-wei "$final_sender_balance" ether)
    local final_contract_balance_wei=$(cast to-wei "$final_contract_balance" ether)

    log "📊 Initial sender balance(wei): $initial_sender_balance_wei"
    log "📊 Initial contract balance(wei): $initial_contract_balance_wei"
    log "📊 Final sender balance(wei): $final_sender_balance_wei"
    log "📊 Final contract balance(wei): $mock_sc_addr $final_contract_balance_wei"

    # Verify contract received second asset
    local expected_contract_balance_wei=$(echo "$initial_contract_balance_wei + $amount_2" | bc)
    if [[ "$final_contract_balance_wei" == "$expected_contract_balance_wei" ]]; then
        log "✅ Contract balance correctly increased by second asset amount"
    else
        log "❌ Contract balance verification failed"
        log "Expected: $expected_contract_balance, Got: $final_contract_balance"
        exit 1
    fi

    # Verify sender received first asset
    local expected_sender_balance_wei=$(echo "$initial_sender_balance_wei + $amount_1" | bc)
    if [[ "$final_sender_balance_wei" == "$expected_sender_balance_wei" ]]; then
        log "✅ Sender balance correctly increased by first asset amount"
    else
        log "❌ Sender balance verification failed"
        log "Expected: $expected_sender_balance, Got: $final_sender_balance"
        exit 1
    fi

    log "🎉 Test completed successfully! Reentrancy protection is working correctly."
}
