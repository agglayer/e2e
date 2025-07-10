setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test execute multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call" {
    # ========================================
    # STEP 1: Deploy the reentrancy testing contract
    # ========================================
    log "🔧 STEP 1: Deploying reentrancy testing contract"

    local mock_artifact_path="$PROJECT_ROOT/core/contracts/bridgeAsset/BridgeMessageReceiverMock.json"

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
    # STEP 2: Bridge first asset (destination: contract address)
    # ========================================
    log "🌉 STEP 2: Bridging first asset from L1 to L2 (destination: contract)"

    # Set destination for first bridge to contract
    destination_addr=$mock_sc_addr
    destination_net=$l2_rpc_network_id
    amount_1_bridge=0.01
    amount_1_bridge_wei=$(cast to-wei "$amount_1_bridge" ether)
    amount=$amount_1_bridge_wei

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_1=$output
    log "✅ First bridge transaction hash: $bridge_tx_hash_1"

    # ========================================
    # STEP 3: Bridge second asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 3: Bridging second asset from L1 to L2 (destination: deployer)"

    # Set destination for second bridge to deployer
    destination_addr=$sender_addr
    amount_2_bridge=0.02
    amount_2_bridge_wei=$(cast to-wei "$amount_2_bridge" ether)
    amount=$amount_2_bridge_wei

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "✅ Second bridge transaction hash: $bridge_tx_hash_2"

    # ========================================
    # STEP 4: Bridge third asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 4: Bridging third asset from L1 to L2 (destination: deployer)"

    # Set destination for third bridge to deployer (same as second)
    destination_addr=$sender_addr
    amount_3_bridge=0.03
    amount_3_bridge_wei=$(cast to-wei "$amount_3_bridge" ether)
    amount=$amount_3_bridge_wei

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_3=$output
    log "✅ Third bridge transaction hash: $bridge_tx_hash_3"

    # ========================================
    # STEP 5: Get claim parameters for first asset (contract destination)
    # ========================================
    log "📋 STEP 5: Retrieving claim parameters for first asset (contract destination)"

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
    # STEP 6: Get claim parameters for second asset (deployer destination)
    # ========================================
    log "📋 STEP 6: Retrieving claim parameters for second asset (deployer destination)"

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
    log "📝 Second L1 info tree index: $l1_info_tree_index_2"

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
    # STEP 7: Get claim parameters for third asset (deployer destination)
    # ========================================
    log "📋 STEP 7: Retrieving claim parameters for third asset (deployer destination)"

    # Get bridge details
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_3="$output"
    local deposit_count_3=$(echo "$bridge_3" | jq -r '.deposit_count')
    log "📝 Third bridge deposit count: $deposit_count_3"

    # Get L1 info tree index
    log "🌳 Getting L1 info tree index for third bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_3="$output"
    log "📝 Third L1 info tree index: $l1_info_tree_index_3"

    # Get injected L1 info leaf
    log "🍃 Getting injected L1 info leaf for third bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_3="$output"

    # Generate claim proof
    log "🔐 Generating claim proof for third asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_3" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_3="$output"

    # Extract claim parameters for third asset
    log "🎯 Extracting claim parameters for third asset"
    local proof_local_exit_root_3=$(echo "$proof_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_3=$(echo "$proof_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    run generate_global_index "$bridge_3" "$l1_rpc_network_id"
    assert_success
    local global_index_3=$output

    local mainnet_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_3=$(echo "$bridge_3" | jq -r '.origin_network')
    local origin_address_3=$(echo "$bridge_3" | jq -r '.origin_address')
    local destination_network_3=$(echo "$bridge_3" | jq -r '.destination_network')
    local destination_address_3=$(echo "$bridge_3" | jq -r '.destination_address')
    local amount_3=$(echo "$bridge_3" | jq -r '.amount')
    local metadata_3=$(echo "$bridge_3" | jq -r '.metadata')

    log "✅ Third asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_3, Amount: $amount_3 wei"

    # ========================================
    # STEP 8: Update contract with second asset claim parameters (for reentrancy test)
    # ========================================
    log "⚙️ STEP 8: Updating contract with second asset claim parameters"

    local update_output
    update_output=$(cast send \
        "$mock_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "$proof_local_exit_root_2" \
        "$proof_rollup_exit_root_2" \
        "$global_index_2" \
        "$mainnet_exit_root_2" \
        "$rollup_exit_root_2" \
        "$origin_network_2" \
        "$origin_address_2" \
        "$destination_network_2" \
        "$destination_address_2" \
        "$amount_2" \
        "$metadata_2" \
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
    # STEP 9: Get initial balances for verification
    # ========================================
    log "💰 STEP 9: Recording initial balances for verification"

    # Get initial token balances (in ETH units)
    local initial_sender_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$sender_addr")
    local initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    # Convert to wei for precise comparison
    local initial_sender_balance_wei=$(cast to-wei "$initial_sender_balance" ether)
    local initial_contract_balance_wei=$(cast to-wei "$initial_contract_balance" ether)

    log "📊 Initial sender balance: $initial_sender_balance ETH ($initial_sender_balance_wei wei)"
    log "📊 Initial contract balance: $initial_contract_balance ETH ($initial_contract_balance_wei wei)"

    # ========================================
    # STEP 10: call testClaim from the smart contract with all the required parameters
    # ========================================
    log "🔧 STEP 10: Calling testClaim from smart contract with all required parameters"

    # Encode claimData1 (first asset claim parameters - destination: contract)
    log "📦 Encoding claimData1 (first asset - contract destination)"
    log "🔍 Debug - amount_1: $amount_1"
    log "🔍 Debug - global_index_1: $global_index_1"
    log "🔍 Debug - origin_network_1: $origin_network_1"
    log "🔍 Debug - destination_network_1: $destination_network_1"

    local claim_data_1=$(cast abi-encode \
        "tuple(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "${proof_local_exit_root_1[@]}" \
        "${proof_rollup_exit_root_1[@]}" \
        "$global_index_1" \
        "$mainnet_exit_root_1" \
        "$rollup_exit_root_1" \
        "$origin_network_1" \
        "$origin_address_1" \
        "$destination_network_1" \
        "$destination_address_1" \
        "$amount_1" \
        "$metadata_1")

    log "📦 claim_data_1: $claim_data_1"

    # Encode bridgeAsset parameters (for third asset bridge)
    log "📦 Encoding bridgeAsset parameters (third asset bridge)"
    amount_bridge=0.04
    amount_bridge_wei=$(cast to-wei "$amount_bridge" ether)
    log "🔍 Debug - amount_bridge_wei: $amount_bridge_wei"
    log "🔍 Debug - origin_network_1: $origin_network_1"
    log "🔍 Debug - sender_addr: $sender_addr"
    log "🔍 Debug - native_token_addr: $native_token_addr"

    local bridge_asset_data=$(cast abi-encode \
        "tuple(uint32,address,uint256,address,bool,bytes)" \
        "$origin_network_1" \
        "$sender_addr" \
        "$amount_bridge_wei" \
        "$native_token_addr" \
        "true" \
        "0x")

    log "📦 bridge_asset_data: $bridge_asset_data"

    # Encode claimData2 (third asset claim parameters - destination: deployer)
    log "📦 Encoding claimData2 (third asset - deployer destination)"
    local claim_data_2=$(cast abi-encode \
        "tuple(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
        "${proof_local_exit_root_3[@]}" \
        "${proof_rollup_exit_root_3[@]}" \
        "$global_index_3" \
        "$mainnet_exit_root_3" \
        "$rollup_exit_root_3" \
        "$origin_network_3" \
        "$origin_address_3" \
        "$destination_network_3" \
        "$destination_address_3" \
        "$amount_3_bridge_wei" \
        "$metadata_3")

    log "📦 claim_data_2: $claim_data_2"

    # Calculate gas price for testClaim
    local test_claim_gas_price=$(bc -l <<<"$gas_price * 2" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        log "❌ Failed to calculate gas price"
        return 1
    fi

    log "⏳ Calling testClaim with parameters:"
    log "   First claim global index: $global_index_1"
    log "   Second claim global index: $global_index_2"
    log "   Bridge asset amount: $amount_bridge_wei wei"
    log "   Gas price: $test_claim_gas_price wei"


    log "⏳ Calling testClaim..."
    if ! test_claim_output=$(cast send \
        "$mock_sc_addr" \
        "testClaim(bytes,bytes,bytes)" \
        "$claim_data_1" \
        "$bridge_asset_data" \
        "$claim_data_2" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$test_claim_gas_price" \
        --value "$amount_bridge_wei" 2>&1); then

        log "❌ testClaim failed"
        log "test_claim_output: $test_claim_output"
        exit 1
    else
        log "✅ testClaim succeeded"
        log "$test_claim_output"
    fi

    log "✅ testClaim executed successfully"
    log "📋 testClaim output: $test_claim_output"
}
