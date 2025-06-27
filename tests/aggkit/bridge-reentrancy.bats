setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

export BATS_LIB_PATH="$PWD/core/helpers/lib"
export PROJECT_ROOT="$PWD"
# export ENCLAVE="op"
export L2_SENDER_PRIVATE_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625

@test "Test bridge reentrancy with onMessageReceived internal calls" {
    log "🧪 Testing bridge reentrancy with onMessageReceived internal calls"

    # Deploy the BridgeMessageReceiverMock contract
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
    log "📝 Deploying BridgeMessageReceiverMock contract"
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

    log "🎉 Deployed BridgeMessageReceiverMock at: $mock_sc_addr"

    # ========================================
    # STEP 1: Bridge first message and get all claim parameters
    # ========================================
    log "🌉 STEP 1: Bridging first message from L1 to L2"
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    
    # Set up message bridging parameters
    amount=0  # No value for message bridging
    meta_bytes="0x746573745f6d657373616765" # "test_message" in hex
    
    # Bridge first message using the helper function
    run bridge_message "0x0000000000000000000000000000000000000000" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_1=$output
    log "🌉 First bridge message transaction hash: $bridge_tx_hash_1"

    # Get all claim parameters for first message
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

    # Extract all claim parameters for first message
    log "🎯 Extracting claim parameters for first message"
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
    
    log "✅ First message claim parameters extracted successfully"

    # ========================================
    # STEP 2: Bridge second message and get all claim parameters
    # ========================================
    log "🌉 STEP 2: Bridging second message from L1 to L2"
    run bridge_message "0x0000000000000000000000000000000000000000" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "🌉 Second bridge message transaction hash: $bridge_tx_hash_2"

    # Get all claim parameters for second message
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

    # Extract all claim parameters for second message
    log "🎯 Extracting claim parameters for second message"
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
    
    log "✅ Second message claim parameters extracted successfully"

    # ========================================
    # STEP 3: Update contract with both sets of claim parameters
    # ========================================
    log "⚙️ STEP 3: Updating contract parameters with both sets of claim data"
    local update_output
    update_output=$(cast send \
        "$mock_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root_1" \
        "$proof_rollup_exit_root_1" \
        "$proof_local_exit_root_2" \
        "$proof_rollup_exit_root_2" \
        "$global_index_1" \
        "$mainnet_exit_root_1" \
        "$rollup_exit_root_1" \
        "$global_index_2" \
        "$mainnet_exit_root_2" \
        "$rollup_exit_root_2" \
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

    log "✅ Contract parameters updated successfully with both sets of claim data"

    # ========================================
    # STEP 4: Test onMessageReceived functionality
    # ========================================
    log "🧪 STEP 4: Testing onMessageReceived with valid parameters (will use first set of parameters)"
    local on_message_output
    on_message_output=$(cast send \
        "$mock_sc_addr" \
        "onMessageReceived(address,uint32,bytes)" \
        "$origin_address_1" \
        "$origin_network_1" \
        "0x" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    log "📝 onMessageReceived output: $on_message_output"
    
    # Check if the transaction was successful
    if [[ $? -eq 0 ]]; then
        local tx_hash=$(echo "$on_message_output" | grep -o '0x[a-fA-F0-9]*')
        log "✅ onMessageReceived transaction successful: $tx_hash"
        
        # Validate the bridge_getClaims API to verify the claim was processed
        log "🔍 Validating first claim was processed"
        run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
        assert_success
        local claim_1="$output"
        log "📋 First claim response: $claim_1"
        
        # Verify mainnet exit root matches expected value
        local claim_mainnet_exit_root_1=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
        log "🌳 First claim mainnet exit root: $claim_mainnet_exit_root_1"
        log "🎯 Expected mainnet exit root: $mainnet_exit_root_1"
        assert_equal "$claim_mainnet_exit_root_1" "$mainnet_exit_root_1"
        
        log "✅ First claim was successfully processed through onMessageReceived"
    else
        log "❌ onMessageReceived transaction failed"
        log "$on_message_output"
        exit 1
    fi

    log "🎉 Bridge reentrancy test completed successfully"
    log "📊 Summary:"
    log "   ✅ Contract deployed successfully"
    log "   ✅ First bridge message created and parameters extracted"
    log "   ✅ Second bridge message created and parameters extracted"
    log "   ✅ Both sets of parameters configured in contract"
    log "   ✅ First claim processed successfully"
}
