setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test claim call data with normalClaim and high gas limit" {
    # Deploy the TestDoubleClaim contract
    local double_claim_artifact_path="$PROJECT_ROOT/core/contracts/testdoubleclaim/TestDoubleClaim.json"
    
    # Get bytecode from the contract artifact
    local bytecode=$(jq -r '.bytecode.object // .bytecode' "$double_claim_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $double_claim_artifact_path"
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
    log "📝 Deploying contract with cast send --create"
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
    local double_claim_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$double_claim_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi

    log "🎉 Deployed TestDoubleClaim at: $double_claim_sc_addr"

    # Bridge WETH from L1 to L2 (First bridge)
    log "🌉 Bridging WETH from L1 to L2"
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output
    log "🌉 Bridge transaction hash: $bridge_tx_hash"

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
    
    # Claim data
    local proof_local_exit_root=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    
    # Debug: Log the formatted proof arrays
    log "🔍 Debug - proof_local_exit_root: $proof_local_exit_root"
    log "🔍 Debug - proof_rollup_exit_root: $proof_rollup_exit_root"
    
    run generate_global_index "$bridge" "$l1_rpc_network_id"
    assert_success
    local global_index=$output
    log "🌳 Global index: $global_index"
    local mainnet_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network=$(echo "$bridge" | jq -r '.origin_network')
    local origin_token_address=$(echo "$bridge" | jq -r '.origin_address')
    local destination_network=$(echo "$bridge" | jq -r '.destination_network')
    local destination_address=$(echo "$bridge" | jq -r '.destination_address')
    local amount=$(echo "$bridge" | jq -r '.amount')
    local metadata="0x"
    
    # Execute normalClaim with very high gas limit
    log "⚡ Executing normalClaim with high gas limit"
    log "🔍 Debug - Contract address: $double_claim_sc_addr"
    log "🔍 Debug - Global index: $global_index"
    log "🔍 Debug - Mainnet exit root: $mainnet_exit_root"
    log "🔍 Debug - Rollup exit root: $rollup_exit_root"
    log "🔍 Debug - Origin network: $origin_network"
    log "🔍 Debug - Origin token address: $origin_token_address"
    log "🔍 Debug - Destination network: $destination_network"
    log "🔍 Debug - Destination address: $destination_address"
    log "🔍 Debug - Amount: $amount"
    log "🔍 Debug - Metadata: $metadata"
    local gas_price=1000000000

    local claim_output
    claim_output=$(cast send \
        "$double_claim_sc_addr" \
        "normalClaim(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root" \
        "$proof_rollup_exit_root" \
        "$global_index" \
        "$mainnet_exit_root" \
        "$rollup_exit_root" \
        "$origin_network" \
        "$origin_token_address" \
        "$destination_network" \
        "$destination_address" \
        "$amount" \
        "$metadata" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" \
        --gas-limit 500000 2>&1)

    log "📝 Claim output: $claim_output"
    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to execute normalClaim with high gas limit"
        log "$claim_output"
        exit 1
    fi

    local tx_hash=$(echo "$claim_output" | grep -o '0x[a-fA-F0-9]*')
    log "📝 Transaction hash: $tx_hash"

    # Try direct claim to bridge contract with the same parameters
    log "🔗 Testing direct claim to bridge contract"
    local direct_claim_output
    direct_claim_output=$(cast send \
        "$l2_bridge_addr" \
        "claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root" \
        "$proof_rollup_exit_root" \
        "$global_index" \
        "$mainnet_exit_root" \
        "$rollup_exit_root" \
        "$origin_network" \
        "$origin_token_address" \
        "$destination_network" \
        "$destination_address" \
        "$amount" \
        "$metadata" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" \
        --gas-limit 500000 2>&1)

    log "📝 Direct claim output: $direct_claim_output"
    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to execute direct claim to bridge contract"
        log "$direct_claim_output"
        # Don't exit here, just log the error for comparison
    else
        local direct_tx_hash=$(echo "$direct_claim_output" | grep -o '0x[a-fA-F0-9]*')
        log "📝 Direct claim transaction hash: $direct_tx_hash"
        log "✅ Direct claim to bridge contract succeeded"
    fi

    # Validate the bridge_getClaims API
    log "global index: $global_index"
    run get_claim "$l2_rpc_network_id" "$global_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local first_claim="$output"
    log "📋 First claim: $first_claim"
    
    log "🎉 Bridge claim was successfully processed with high gas limit"
}