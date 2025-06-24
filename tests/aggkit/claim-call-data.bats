setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test claim call data with two internal claims" {
    # first internal claim passes, second internal claim fails with same global index
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
    
    # Claim data (used for both claims)
    local proof_local_exit_root=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge" "$l1_rpc_network_id"
    assert_success
    local global_index=$output
    local mainnet_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network=$(echo "$bridge" | jq -r '.origin_network')
    local origin_token_address=$(echo "$bridge" | jq -r '.origin_address')
    local destination_network=$(echo "$bridge" | jq -r '.destination_network')
    local destination_address=$(echo "$bridge" | jq -r '.destination_address')
    local amount=$(echo "$bridge" | jq -r '.amount')
    local metadata="0x"

    local malformed_proof_local_exit_root=$(echo "$proof" | jq -r '.proof_local_exit_root[1] = "0xf077e0d22fd6721989347f053c33595697372ec8c0d0678b934bba193679e088" | .proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    log "🔧 Malformed proof for first claim: $malformed_proof_local_exit_root"
    local malformed_mainnet_exit_root=0x787bc577d07da1b6ca15c9b2c6d869e08a29663f498b65752604c75efee2cfe0

    # Execute attemptTwoClaims
    log "⚡ Executing attemptTwoClaims"
    local gas_price=1000000000

    local claim_output
    claim_output=$(cast send \
        "$double_claim_sc_addr" \
        "attemptTwoClaims(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
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
        "$malformed_proof_local_exit_root" \
        "$proof_rollup_exit_root" \
        "$global_index" \
        "$malformed_mainnet_exit_root" \
        "$rollup_exit_root" \
        "$origin_network" \
        "$origin_token_address" \
        "$destination_network" \
        "$destination_address" \
        "$amount" \
        "$metadata" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    log "📝 Claim output: $claim_output"
    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to execute attemptTwoClaims"
        log "$claim_output"
        exit 1
    fi

    local tx_hash=$(echo "$claim_output" | grep -o '0x[a-fA-F0-9]*')
    log "📝 Transaction hash: $tx_hash"

    # Validate the bridge_getClaims API
    log "global index: $global_index"
    run get_claim "$l2_rpc_network_id" "$global_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local first_claim="$output"
    log "📋 First claim: $first_claim"

    # ✅ Verify mainnet exit root matches expected value (should be the valid first claim)
    local first_claim_mainnet_exit_root=$(echo "$first_claim" | jq -r '.mainnet_exit_root')
    log "🌳 First claim mainnet exit root: $first_claim_mainnet_exit_root"
    log "🎯 Expected mainnet exit root: $mainnet_exit_root"

    # ✅ Assert that first_claim_mainnet_exit_root matches mainnet_exit_root (the valid one)
    assert_equal "$first_claim_mainnet_exit_root" "$mainnet_exit_root"
    
    log "🎉 Bridge claim was successfully processed (first claim passed, second was reverted)"
}