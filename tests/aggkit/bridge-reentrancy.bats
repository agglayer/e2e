setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

export BATS_LIB_PATH="$PWD/core/helpers/lib"
export PROJECT_ROOT="$PWD"
export ENCLAVE="op"
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

    # Bridge a message from L1 to L2 to create a valid bridge transaction
    log "🌉 Bridging message from L1 to L2"
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    
    # Set up message bridging parameters
    amount=0  # No value for message bridging
    is_forced=false
    meta_bytes="0x746573745f6d657373616765" # "test_message" in hex
    
    # Bridge message using the helper function
    run bridge_message "0x0000000000000000000000000000000000000000" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    log "🌉 Bridge message transaction hash: $bridge_tx_hash"

    # Get bridge details and proofs for the bridge
    log "📋 Getting bridge details"
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge="$output"
    log "📝 Bridge response: $bridge"
    local deposit_count=$(echo "$bridge" | jq -r '.deposit_count')
    
    log "🌳 Getting L1 info tree index"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"
    log "📝 L1 info tree index: $l1_info_tree_index"
    
    log "Getting injected L1 info leaf"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info="$output"
    log "📝 Injected info: $injected_info"
    
    log "🔐 Getting claim proof"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof="$output"
    log "📝 Proof: $proof"

    # Format the data for the contract call
    log "🎯 Formatting data for contract call"
    
    # Extract claim parameters for message bridging
    local proof_local_exit_root=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge" "$l1_rpc_network_id"
    assert_success
    local global_index=$output
    local mainnet_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network=$(echo "$bridge" | jq -r '.origin_network')
    local origin_address=$(echo "$bridge" | jq -r '.origin_address')  # For messages, this is the origin address, not token address
    local destination_network=$(echo "$bridge" | jq -r '.destination_network')
    local destination_address=$(echo "$bridge" | jq -r '.destination_address')
    local amount=$(echo "$bridge" | jq -r '.amount')
    local metadata=$(echo "$bridge" | jq -r '.metadata')  # Use the actual metadata from the bridge

    # Update the contract parameters with valid claim data
    log "⚙️ Updating contract parameters"
    local update_output
    update_output=$(cast send \
        "$mock_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root" \
        "$proof_rollup_exit_root" \
        "$global_index" \
        "$mainnet_exit_root" \
        "$rollup_exit_root" \
        "$origin_network" \
        "$origin_address" \
        "$destination_network" \
        "$destination_address" \
        "$amount" \
        "$metadata" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to update parameters"
        log "$update_output"
        exit 1
    fi

    log "✅ Contract parameters updated successfully"

    # Test 1: Call onMessageReceived with valid parameters
    log "🧪 Test 1: Calling onMessageReceived with valid parameters"
    local on_message_output
    on_message_output=$(cast send \
        "$mock_sc_addr" \
        "onMessageReceived(address,uint32,bytes)" \
        "$origin_address" \
        "$origin_network" \
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
        log "🔍 Validating claim was processed"
        run get_claim "$l2_rpc_network_id" "$global_index" 50 10 "$aggkit_bridge_url"
        assert_success
        local claim="$output"
        log "📋 Claim response: $claim"
        
        # Verify mainnet exit root matches expected value
        local claim_mainnet_exit_root=$(echo "$claim" | jq -r '.mainnet_exit_root')
        log "🌳 Claim mainnet exit root: $claim_mainnet_exit_root"
        log "🎯 Expected mainnet exit root: $mainnet_exit_root"
        assert_equal "$claim_mainnet_exit_root" "$mainnet_exit_root"
        
        log "✅ Claim was successfully processed through onMessageReceived"
    else
        log "❌ onMessageReceived transaction failed"
        log "$on_message_output"
        exit 1
    fi

    log "🎉 Bridge reentrancy test completed successfully"
    log "📊 Summary:"
    log "   ✅ Contract deployed successfully"
}
