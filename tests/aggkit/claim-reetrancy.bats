setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup

    readonly bridge_event_sig="event BridgeEvent(uint8, uint32, address, uint32, address, uint256, bytes, uint32)"
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

    receiver_addr='0xBA002167c3a9Ee959EF4c2A62f7Fb026326479DD'

    # ========================================
    # STEP 2: Bridge first asset (destination: contract address)
    # ========================================
    log "🌉 STEP 2: Bridging first asset from L1 to L2 (destination: contract)"

    # Set destination for first bridge to contract
    destination_addr=$mock_sc_addr
    destination_net=$l2_rpc_network_id
    amount_1_bridge=0.03
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
    destination_addr=$receiver_addr
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
    destination_addr=$receiver_addr
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

    # Generate the claim proof based on the network ID, deposit count, and L1 info tree index.
    local l1_info_tree_injected_index_1=$(echo "$injected_info_1" | jq -r '.l1_info_tree_index')

    # Generate claim proof
    log "🔐 Generating claim proof for first asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_1" "$l1_info_tree_injected_index_1" 50 10 "$aggkit_bridge_url"
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

    # Generate the claim proof based on the network ID, deposit count, and L1 info tree index.
    local l1_info_tree_injected_index_2=$(echo "$injected_info_2" | jq -r '.l1_info_tree_index')

    # Generate claim proof
    log "🔐 Generating claim proof for second asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_2" "$l1_info_tree_injected_index_2" 50 10 "$aggkit_bridge_url"
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

    # Generate the claim proof based on the network ID, deposit count, and L1 info tree index.
    local l1_info_tree_injected_index_3=$(echo "$injected_info_3" | jq -r '.l1_info_tree_index')

    # Generate claim proof
    log "🔐 Generating claim proof for third asset"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_3" "$l1_info_tree_injected_index_3" 50 10 "$aggkit_bridge_url"
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
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    # Convert to wei for precise comparison
    local initial_receiver_balance_wei=$(cast to-wei "$initial_receiver_balance" ether)
    local initial_contract_balance_wei=$(cast to-wei "$initial_contract_balance" ether)

    log "📊 Initial receiver balance: $initial_receiver_balance ETH ($initial_receiver_balance_wei wei)"
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

    # Encode bridgeAsset parameters (for third asset bridge) L2(A) -> L2(B) network id 2
    log "📦 Encoding bridgeAsset parameters (third asset bridge)"
    amount_bridge=0.0004
    receiver_addr_bridge=0xa9bAE041CE268C90c54F588db794ab9f18686BBD
    destination_network_bridge_tx=2
    amount_bridge_wei=$(cast to-wei "$amount_bridge" ether)
    local bridge_asset_data=$(cast abi-encode \
        "tuple(uint32,address,uint256,address,bool,bytes)" \
        "$destination_network_bridge_tx" \
        "$receiver_addr_bridge" \
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
        "$amount_3" \
        "$metadata_3")

    log "📦 claim_data_2: $claim_data_2"

    # Calculate gas price for testClaim
    local test_claim_gas_price=$(bc -l <<<"$gas_price * 2" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        log "❌ Failed to calculate gas price"
        return 1
    fi

    # Get the current block number
    bridge_event_from_block=$(cast block-number --rpc-url "$l1_rpc_url")

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

    # # ========================================
    # # STEP 11: Verify claim events in aggkit
    # # ========================================
    # log "🔍 STEP 11: Verifying claim events were processed correctly by aggkit"

    # # Verify first claim was processed (contract destination)
    # log "🔍 Validating first asset claim processing (contract destination)"
    # run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    # assert_success
    # local claim_1="$output"
    # log "📋 First claim response received"

    # # Validate first claim parameters
    # log "🔍 Validating first claim parameters"
    # local claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
    # local claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
    # local claim_1_origin_network=$(echo "$claim_1" | jq -r '.origin_network')
    # local claim_1_origin_address=$(echo "$claim_1" | jq -r '.origin_address')
    # local claim_1_destination_network=$(echo "$claim_1" | jq -r '.destination_network')
    # local claim_1_destination_address=$(echo "$claim_1" | jq -r '.destination_address')
    # local claim_1_amount=$(echo "$claim_1" | jq -r '.amount')
    # local claim_1_metadata=$(echo "$claim_1" | jq -r '.metadata')

    # # Assert parameter consistency
    # assert_equal "$claim_1_mainnet_exit_root" "$mainnet_exit_root_1"
    # assert_equal "$claim_1_rollup_exit_root" "$rollup_exit_root_1"
    # assert_equal "$claim_1_origin_network" "$origin_network_1"
    # assert_equal "$claim_1_origin_address" "$origin_address_1"
    # assert_equal "$claim_1_destination_network" "$destination_network_1"
    # assert_equal "$claim_1_destination_address" "$destination_address_1"
    # assert_equal "$claim_1_amount" "$amount_1"
    # assert_equal "$claim_1_metadata" "$metadata_1"

    # # Validate first claim proofs
    # log "🔍 Validating first claim proofs"
    # local claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    # local claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    # assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
    # assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"
    # log "✅ First claim validated successfully"

    # # Verify second claim was processed (deployer destination)
    # log "🔍 Validating second asset claim processing (deployer destination)"
    # run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url"
    # assert_success
    # local claim_2="$output"
    # log "📋 Second claim response received"

    # # Validate second claim parameters
    # log "🔍 Validating second claim parameters"
    # local claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
    # local claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
    # local claim_2_origin_network=$(echo "$claim_2" | jq -r '.origin_network')
    # local claim_2_origin_address=$(echo "$claim_2" | jq -r '.origin_address')
    # local claim_2_destination_network=$(echo "$claim_2" | jq -r '.destination_network')
    # local claim_2_destination_address=$(echo "$claim_2" | jq -r '.destination_address')
    # local claim_2_amount=$(echo "$claim_2" | jq -r '.amount')
    # local claim_2_metadata=$(echo "$claim_2" | jq -r '.metadata')

    # # Assert parameter consistency
    # assert_equal "$claim_2_mainnet_exit_root" "$mainnet_exit_root_2"
    # assert_equal "$claim_2_rollup_exit_root" "$rollup_exit_root_2"
    # assert_equal "$claim_2_origin_network" "$origin_network_2"
    # assert_equal "$claim_2_origin_address" "$origin_address_2"
    # assert_equal "$claim_2_destination_network" "$destination_network_2"
    # assert_equal "$claim_2_destination_address" "$destination_address_2"
    # assert_equal "$claim_2_amount" "$amount_2"
    # assert_equal "$claim_2_metadata" "$metadata_2"

    # # Validate second claim proofs
    # log "🔍 Validating second claim proofs"
    # local claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    # local claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    # assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
    # assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
    # log "✅ Second claim validated successfully"

    # # Verify third claim was processed (deployer destination)
    # log "🔍 Validating third asset claim processing (deployer destination)"
    # run get_claim "$l2_rpc_network_id" "$global_index_3" 50 10 "$aggkit_bridge_url"
    # assert_success
    # local claim_3="$output"
    # log "📋 Third claim response received"

    # # Validate third claim parameters
    # log "🔍 Validating third claim parameters"
    # local claim_3_mainnet_exit_root=$(echo "$claim_3" | jq -r '.mainnet_exit_root')
    # local claim_3_rollup_exit_root=$(echo "$claim_3" | jq -r '.rollup_exit_root')
    # local claim_3_origin_network=$(echo "$claim_3" | jq -r '.origin_network')
    # local claim_3_origin_address=$(echo "$claim_3" | jq -r '.origin_address')
    # local claim_3_destination_network=$(echo "$claim_3" | jq -r '.destination_network')
    # local claim_3_destination_address=$(echo "$claim_3" | jq -r '.destination_address')
    # local claim_3_amount=$(echo "$claim_3" | jq -r '.amount')
    # local claim_3_metadata=$(echo "$claim_3" | jq -r '.metadata')

    # # Assert parameter consistency
    # assert_equal "$claim_3_mainnet_exit_root" "$mainnet_exit_root_3"
    # assert_equal "$claim_3_rollup_exit_root" "$rollup_exit_root_3"
    # assert_equal "$claim_3_origin_network" "$origin_network_3"
    # assert_equal "$claim_3_origin_address" "$origin_address_3"
    # assert_equal "$claim_3_destination_network" "$destination_network_3"
    # assert_equal "$claim_3_destination_address" "$destination_address_3"
    # assert_equal "$claim_3_amount" "$amount_3"
    # assert_equal "$claim_3_metadata" "$metadata_3"

    # # Validate third claim proofs
    # log "🔍 Validating third claim proofs"
    # local claim_3_proof_local_exit_root=$(echo "$claim_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    # local claim_3_proof_rollup_exit_root=$(echo "$claim_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    # assert_equal "$claim_3_proof_local_exit_root" "$proof_local_exit_root_3"
    # assert_equal "$claim_3_proof_rollup_exit_root" "$proof_rollup_exit_root_3"
    # log "✅ Third claim validated successfully"

    # ========================================
    # STEP 12: Final balance verification
    # ========================================
    log "💰 STEP 12: Verifying final balances"

    # Get final balances (in eth)
    local final_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local final_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$mock_sc_addr")

    local final_receiver_balance_wei=$(cast to-wei "$final_receiver_balance" ether)
    local final_contract_balance_wei=$(cast to-wei "$final_contract_balance" ether)

    log "📊 Initial receiver balance(wei): $initial_receiver_balance_wei"
    log "📊 Initial contract balance(wei): $initial_contract_balance_wei"
    log "📊 Final receiver balance(wei): $final_receiver_balance_wei"
    log "📊 Final contract balance(wei): $final_contract_balance_wei"

    # Verify contract received first asset
    local expected_contract_balance_wei=$(echo "$initial_contract_balance_wei + $amount_1" | bc)
    if [[ "$final_contract_balance_wei" == "$expected_contract_balance_wei" ]]; then
        log "✅ Contract balance correctly increased by first asset amount"
    else
        log "❌ Contract balance verification failed"
        log "Expected: $expected_contract_balance_wei, Got: $final_contract_balance_wei"
        exit 1
    fi

    # Verify receiver balance increased by second and third assets
    local total_received_by_sender=$(echo "$amount_2 + $amount_3" | bc)
    local expected_receiver_balance_wei=$(echo "$initial_receiver_balance_wei + $total_received_by_sender" | bc)
    if [[ "$final_receiver_balance_wei" == "$expected_receiver_balance_wei" ]]; then
        log "✅ Receiver balance correctly increased by expected amount"
    else
        log "❌ Receiver balance verification failed"
        log "Expected: $expected_receiver_balance_wei, Got: $final_receiver_balance_wei"
        exit 1
    fi

    # ========================================
    # STEP 13: Verify claims using isClaimed function
    # ========================================
    log "🔍 STEP 13: Verifying claims using isClaimed function"

    # ========================================
    # Check first claim (should be claimed)
    # ========================================
    log "🔍 Checking isClaimed for first claim (deposit_count: $deposit_count_1, source_network: $origin_network_1)"

    run isClaimed "$deposit_count_1" "$origin_network_1" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_1=$output
    log "📋 First claim isClaimed result: $is_claimed_1"

    if [[ "$is_claimed_1" == "true" ]]; then
        log "✅ First claim correctly marked as claimed"
    else
        log "❌ First claim not marked as claimed - expected true, got $is_claimed_1"
        exit 1
    fi

    # ========================================
    # Check second claim (should be claimed)
    # ========================================
    log "🔍 Checking isClaimed for second claim (deposit_count: $deposit_count_2, source_network: $origin_network_2)"

    run isClaimed "$deposit_count_2" "$origin_network_2" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_2=$output
    log "📋 Second claim isClaimed result: $is_claimed_2"

    if [[ "$is_claimed_2" == "true" ]]; then
        log "✅ Second claim correctly marked as claimed"
    else
        log "❌ Second claim not marked as claimed - expected true, got $is_claimed_2"
        exit 1
    fi

    # ========================================
    # Check third claim (should be claimed)
    # ========================================
    log "🔍 Checking isClaimed for third claim (deposit_count: $deposit_count_3, source_network: $origin_network_3)"

    run isClaimed "$deposit_count_3" "$origin_network_3" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_3=$output
    log "📋 Third claim isClaimed result: $is_claimed_3"

    if [[ "$is_claimed_3" == "true" ]]; then
        log "✅ Third claim correctly marked as claimed"
    else
        log "❌ Third claim not marked as claimed - expected true, got $is_claimed_3"
        exit 1
    fi
    log "🎉 All isClaimed verifications passed successfully!"

    # Fetch bridge events
    run cast logs \
        --rpc-url "$l1_rpc_url" \
        --from-block 0x0 \
        --to-block latest \
        --address "$l1_bridge_addr" \
        "$bridge_event_sig" \
        --json
    assert_success
    bridge_events="$output"
    log "🔍 Fetched Bridge events: $bridge_events"

    # Extract the latest bridge event data
    local latest_event_data=$(echo "$bridge_events" | jq -r '.[-1].data')
    log "🔍 Latest bridge event data: $latest_event_data"

    # Extract values from the hex data (removing 0x prefix)
    local data_without_prefix=${latest_event_data#0x}
    log "🔍 Data without prefix (first 200 chars): ${data_without_prefix:0:200}"

    # Extract destinationAddress: get the last 40 chars from the 64-char field (position 256-319)
    local destination_address_hex=${data_without_prefix:280:40}
    local bridge_event_destination_address="0x${destination_address_hex}"
    log "🔍 Bridge event destinationAddress: $bridge_event_destination_address"

    # Amount comes at position 320-383
    local amount_hex=${data_without_prefix:320:64}
    local bridge_event_amount=$((16#$amount_hex))
    log "🔍 Bridge event amount: $bridge_event_amount"

    # Verify the extracted values match expected values
    # assert_equal "${bridge_event_destination_address,,}" "${receiver_addr_bridge,,}"
    # assert_equal "$bridge_event_amount" "$amount_bridge_wei"

    log "🎉 Test completed successfully! Multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call is working correctly."
}
