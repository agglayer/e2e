setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test should allow two claimMessage calls (including reentrancy) from Rollup to Mainnet safely" {
    # Deploy the InternalClaims contract
    # /Users/rachitsonthalia/workspace/e2e/core/contracts/bridgeAsset/BridgeMessageReceiverMock.sol
    local mock_artifact_path="$PROJECT_ROOT/compiled-contracts/BridgeMessageReceiverMock.sol/BridgeMessageReceiverMock.json"

    # Get bytecode from the contract artifact
    local bytecode=$(jq -r '.bytecode.object // .bytecode' "$mock_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $mock_artifact_path"
        exit 1
    fi

    # ABI-encode the constructor argument (bridge address)
    local encoded_args=$(cast abi-encode "constructor(address)" "$l2_bridge_addr")
    if [[ -z "$encoded_args" ]]; then
        log "❌ Failed to ABI-encode constructor argument"
        exit 1
    fi

    # Concatenate bytecode and encoded constructor args
    local deploy_bytecode="${bytecode}${encoded_args:2}" # Remove 0x from encoded args

    # Set a fixed gas price (1 gwei)
    local gas_price=1000000000

    # Deploy the contract
    log "📝 Deploying InternalClaims contract"
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

    # Extract contract address from output
    local mock_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$mock_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi

    log "🎉 Deployed Reetrancy testing contract at: $mock_sc_addr"

    # send a bridge tx with dest= deployer address
    # ========================================
    # STEP 1: Bridge first asset and get all claim parameters
    # ========================================
    log "🌉 STEP 1: Bridging first asset from L1 to L2"
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id

    # Bridge first asset using the helper function
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_1=$output
    log "🌉 First bridge asset transaction hash: $bridge_tx_hash_1"

    # Get all claim parameters for first asset
    log "📋 Getting first bridge details"
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_1="$output"
    log "📝 First bridge response: $bridge_1"
    local deposit_count_1=$(echo "$bridge_1" | jq -r '.deposit_count')

    log "🌳 Getting L1 info tree index for first bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_1="$output"
    log "📝 First L1 info tree index: $l1_info_tree_index_1"

    log "Getting injected L1 info leaf for first bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_1="$output"
    log "📝 First injected info: $injected_info_1"

    log "🔐 Getting first claim proof"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_1" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_1="$output"
    log "📝 First proof: $proof_1"

    # Extract all claim parameters for first asset
    log "🎯 Extracting claim parameters for first asset"
    local proof_local_exit_root_1=$(echo "$proof_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_1=$(echo "$proof_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge_1" "$l1_rpc_network_id"
    assert_success
    local global_index_1=$output
    log "📝 First global index: $global_index_1"
    local mainnet_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_1=$(echo "$bridge_1" | jq -r '.origin_network')
    local origin_address_1=$(echo "$bridge_1" | jq -r '.origin_address')
    local destination_network_1=$(echo "$bridge_1" | jq -r '.destination_network')
    local destination_address_1=$(echo "$bridge_1" | jq -r '.destination_address')
    local amount_1=$(echo "$bridge_1" | jq -r '.amount')
    local metadata_1=$(echo "$bridge_1" | jq -r '.metadata')

    log "✅ First asset claim parameters extracted successfully"

    # send a bridge tx with dest=contract address
    # ========================================
    # STEP 2: Bridge second asset and get all claim parameters
    # ========================================
    log "🌉 STEP 2: Bridging second asset from L1 to L2"
    destination_addr=$mock_sc_addr
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "🌉 Second bridge asset transaction hash: $bridge_tx_hash_2"

    # Get all claim parameters for second asset
    log "📋 Getting second bridge details"
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_2="$output"
    log "📝 Second bridge response: $bridge_2"
    local deposit_count_2=$(echo "$bridge_2" | jq -r '.deposit_count')

    log "🌳 Getting L1 info tree index for second bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_2="$output"
    log "📝 Second L1 info tree index: $l1_info_tree_index_2"

    log "Getting injected L1 info leaf for second bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_2="$output"
    log "📝 Second injected info: $injected_info_2"

    log "🔐 Getting second claim proof"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_2" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_2="$output"
    log "📝 Second proof: $proof_2"

    # Extract all claim parameters for second asset
    log "🎯 Extracting claim parameters for second asset"
    local proof_local_exit_root_2=$(echo "$proof_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_2=$(echo "$proof_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge_2" "$l1_rpc_network_id"
    assert_success
    local global_index_2=$output
    log "📝 Second global index: $global_index_2"
    local mainnet_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_2=$(echo "$bridge_2" | jq -r '.origin_network')
    local origin_address_2=$(echo "$bridge_2" | jq -r '.origin_address')
    local destination_network_2=$(echo "$bridge_2" | jq -r '.destination_network')
    local destination_address_2=$(echo "$bridge_2" | jq -r '.destination_address')
    local amount_2=$(echo "$bridge_2" | jq -r '.amount')
    local metadata_2=$(echo "$bridge_2" | jq -r '.metadata')

    log "✅ Second asset claim parameters extracted successfully"

    ## update params on contract destination=deployer address
    # ========================================
    # STEP 3: Update contract with claim parameters
    # ========================================
    log "⚙️ STEP 3: Updating contract parameters with claim data"
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
        log "❌ Error: Failed to update parameters"
        log "$update_output"
        exit 1
    fi

    log "✅ Contract parameters updated successfully with claim data"

    # ========================================
    # STEP 6: Verify balances after both claims
    # ========================================
    log "💰 STEP 6: Verifying balances after both claims"

    # Get initial balances before any claims
    # amount=$(cast to-wei $ether_value ether)
    # local initial_sender_balance=$(cast balance "$sender_addr" --rpc-url "$L2_RPC_URL")
    # local initial_contract_balance=$(cast balance "$mock_sc_addr" --rpc-url "$L2_RPC_URL")

    # these values are in eth
    local initial_sender_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$sender_addr")
    local initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    local initial_sender_balance=$(cast to-wei "$initial_sender_balance" ether)
    local initial_contract_balance=$(cast to-wei "$initial_contract_balance" ether)

    ## call directly to l2 bridge contract to claim message (l1->l2) destination=contract address
    log "🌉 STEP 5: Claiming second asset from L1 to L2"
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_2" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    # will get global index here
    local global_index_2=$output
    log "🌉 Second claim global index: $global_index_2"

    # Already claimed deployer address: revert error 'AlreadyClaimed'
    # Send a claim tx again destination=deployer address

    # ========================================
    # STEP 8: Verify claim events were parsed correctly on aggkit
    # ========================================
    log "🔍 STEP 8: Verifying claim events were parsed correctly on aggkit"

    # Verify the first claim was processed correctly
    log "🔍 Validating first asset claim was processed"
    run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_1="$output"
    log "📋 First claim response: $claim_1"

    # Validate all parameters for first claim
    log "🔍 Validating all parameters for first claim"
    local claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
    local claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
    local claim_1_origin_network=$(echo "$claim_1" | jq -r '.origin_network')
    local claim_1_origin_address=$(echo "$claim_1" | jq -r '.origin_address')
    local claim_1_destination_network=$(echo "$claim_1" | jq -r '.destination_network')
    local claim_1_destination_address=$(echo "$claim_1" | jq -r '.destination_address')
    local claim_1_amount=$(echo "$claim_1" | jq -r '.amount')
    local claim_1_metadata=$(echo "$claim_1" | jq -r '.metadata')

    # Assert that the claim parameters match the expected values
    assert_equal "$claim_1_mainnet_exit_root" "$mainnet_exit_root_1"
    assert_equal "$claim_1_rollup_exit_root" "$rollup_exit_root_1"
    assert_equal "$claim_1_origin_network" "$origin_network_1"
    assert_equal "$claim_1_origin_address" "$origin_address_1"
    assert_equal "$claim_1_destination_network" "$destination_network_1"
    assert_equal "$claim_1_destination_address" "$destination_address_1"
    assert_equal "$claim_1_amount" "$amount_1"
    assert_equal "$claim_1_metadata" "$metadata_1"

    # Validate proofs for first claim
    log "🔍 Validating proofs for first claim"
    local claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    # Verify proof values match expected values
    assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
    assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"
    log "✅ First claim proofs validated successfully"
    log "✅ First claim all fields validated successfully"

    # Verify the second claim was processed correctly
    log "🔍 Validating second asset claim was processed"
    run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_2="$output"
    log "📋 Second claim response: $claim_2"

    # Validate all parameters for second claim
    log "🔍 Validating all parameters for second claim"
    local claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
    local claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
    local claim_2_origin_network=$(echo "$claim_2" | jq -r '.origin_network')
    local claim_2_origin_address=$(echo "$claim_2" | jq -r '.origin_address')
    local claim_2_destination_network=$(echo "$claim_2" | jq -r '.destination_network')
    local claim_2_destination_address=$(echo "$claim_2" | jq -r '.destination_address')
    local claim_2_amount=$(echo "$claim_2" | jq -r '.amount')
    local claim_2_metadata=$(echo "$claim_2" | jq -r '.metadata')

    # Assert that the claim parameters match the expected values
    assert_equal "$claim_2_mainnet_exit_root" "$mainnet_exit_root_2"
    assert_equal "$claim_2_rollup_exit_root" "$rollup_exit_root_2"
    assert_equal "$claim_2_origin_network" "$origin_network_2"
    assert_equal "$claim_2_origin_address" "$origin_address_2"
    assert_equal "$claim_2_destination_network" "$destination_network_2"
    assert_equal "$claim_2_destination_address" "$destination_address_2"
    assert_equal "$claim_2_amount" "$amount_2"
    assert_equal "$claim_2_metadata" "$metadata_2"

    # Validate proofs for second claim
    log "🔍 Validating proofs for second claim"
    local claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    # Verify proof values match expected values
    assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
    assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
    log "✅ Second claim proofs validated successfully"
    log "✅ Second claim all fields validated successfully"

    # ========================================
    # STEP 9: Final balance verification
    # ========================================
    log "💰 STEP 9: Final balance verification"

    # Get final balances (in eth)
    local final_sender_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$sender_addr")
    local final_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    local final_sender_balance=$(cast to-wei "$final_sender_balance" ether)
    local final_contract_balance=$(cast to-wei "$final_contract_balance" ether)

    log "📊 Initial sender balance: $initial_sender_balance wei"
    log "📊 Initial contract balance: $initial_contract_balance wei"
    log "📊 Final sender balance: $final_sender_balance wei"
    log "📊 Final contract balance: $mock_sc_addr $final_contract_balance wei"

    # Verify that the contract received the second asset (since it was the destination)
    local expected_contract_balance=$(echo "$initial_contract_balance + $amount_2" | bc)
    if [[ "$final_contract_balance" == "$expected_contract_balance" ]]; then
        log "✅ Contract balance correctly increased by the second asset amount"
    else
        log "❌ Contract balance verification failed"
        log "Expected: $expected_contract_balance, Got: $final_contract_balance"
        exit 1
    fi

    # Verify that the sender received the first asset (since it was the destination for the first claim)
    local expected_sender_balance=$(echo "$initial_sender_balance + $amount_1" | bc)
    if [[ "$final_sender_balance" == "$expected_sender_balance" ]]; then
        log "✅ Sender balance correctly increased by the first asset amount"
    else
        log "❌ Sender balance verification failed"
        log "Expected: $expected_sender_balance, Got: $final_sender_balance"
        exit 1
    fi

    log "🎉 Test completed successfully! Reentrancy protection is working correctly."
}
