# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup

    readonly bridge_event_sig="event BridgeEvent(uint8, uint32, address, uint32, address, uint256, bytes, uint32)"
    readonly claim_reentrancy_sc_artifact_path="$PROJECT_ROOT/core/contracts/bridgeAsset/BridgeMessageReceiverMock.json"

    # Deploy the reentrancy testing contract once for all tests
    log "🔧 Deploying reentrancy testing contract for all tests"

    # Validate artifact exists
    if [[ ! -f "$claim_reentrancy_sc_artifact_path" ]]; then
        log "❌ Error: Contract artifact not found at $claim_reentrancy_sc_artifact_path"
        exit 1
    fi

    # Extract bytecode from contract artifact
    local bytecode
    bytecode=$(jq -r '.bytecode.object // .bytecode' "$claim_reentrancy_sc_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $claim_reentrancy_sc_artifact_path"
        exit 1
    fi

    # ABI-encode constructor argument (bridge address)
    local encoded_args
    encoded_args=$(cast abi-encode "constructor(address)" "$l2_bridge_addr")
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
    readonly claim_reentrancy_sc_addr
    claim_reentrancy_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$claim_reentrancy_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi

    log "✅ Reentrancy testing contract deployed at: $claim_reentrancy_sc_addr"
}

@test "Test reentrancy protection for bridge claims - should prevent double claiming" {
    # ========================================
    # STEP 1: Bridge first asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 1: Bridging first asset from L1 to L2 (destination: deployer)"

    # Set destination for first bridge
    receiver_addr='0x15E13226E42ebB16fAD9E9A42B149954c5bD00e0'
    destination_addr=$receiver_addr
    destination_net=$l2_rpc_network_id

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_1=$output
    log "✅ First bridge transaction hash: $bridge_tx_hash_1"

    # ========================================
    # STEP 2: Get claim parameters for first asset
    # ========================================
    log "📋 STEP 2: Retrieving claim parameters for first asset"

    # Use the helper function to extract claim parameters
    local claim_params_1
    claim_params_1=$(extract_claim_parameters_json "$bridge_tx_hash_1" "first")

    # Parse the JSON response to extract individual parameters
    local proof_local_exit_root_1
    proof_local_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_1
    proof_rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_rollup_exit_root')
    local global_index_1
    global_index_1=$(echo "$claim_params_1" | jq -r '.global_index')
    local mainnet_exit_root_1
    mainnet_exit_root_1=$(echo "$claim_params_1" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_1
    rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.rollup_exit_root')
    local origin_network_1
    origin_network_1=$(echo "$claim_params_1" | jq -r '.origin_network')
    local origin_address_1
    origin_address_1=$(echo "$claim_params_1" | jq -r '.origin_address')
    local destination_network_1
    destination_network_1=$(echo "$claim_params_1" | jq -r '.destination_network')
    local destination_address_1
    destination_address_1=$(echo "$claim_params_1" | jq -r '.destination_address')
    local amount_1
    amount_1=$(echo "$claim_params_1" | jq -r '.amount')
    local metadata_1
    metadata_1=$(echo "$claim_params_1" | jq -r '.metadata')

    log "✅ First asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_1, Amount: $amount_1 wei"

    # ========================================
    # STEP 3: Bridge second asset (destination: contract address)
    # ========================================
    log "🌉 STEP 3: Bridging second asset from L1 to L2 (destination: contract)"

    # Set destination for second bridge
    destination_addr=$claim_reentrancy_sc_addr

    # Execute bridge transaction
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "✅ Second bridge transaction hash: $bridge_tx_hash_2"

    # ========================================
    # STEP 4: Get claim parameters for second asset
    # ========================================
    log "📋 STEP 4: Retrieving claim parameters for second asset"

    # Use the helper function to extract claim parameters
    local claim_params_2
    claim_params_2=$(extract_claim_parameters_json "$bridge_tx_hash_2" "second")

    # Parse the JSON response to extract individual parameters
    local proof_local_exit_root_2
    proof_local_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_2
    proof_rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_rollup_exit_root')
    local global_index_2
    global_index_2=$(echo "$claim_params_2" | jq -r '.global_index')
    local mainnet_exit_root_2
    mainnet_exit_root_2=$(echo "$claim_params_2" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_2
    rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.rollup_exit_root')
    local origin_network_2
    origin_network_2=$(echo "$claim_params_2" | jq -r '.origin_network')
    local origin_address_2
    origin_address_2=$(echo "$claim_params_2" | jq -r '.origin_address')
    local destination_network_2
    destination_network_2=$(echo "$claim_params_2" | jq -r '.destination_network')
    local destination_address_2
    destination_address_2=$(echo "$claim_params_2" | jq -r '.destination_address')
    local amount_2
    amount_2=$(echo "$claim_params_2" | jq -r '.amount')
    local metadata_2
    metadata_2=$(echo "$claim_params_2" | jq -r '.metadata')

    log "✅ Second asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_2, Amount: $amount_2 wei"

    # ========================================
    # STEP 5: Update contract with first asset claim parameters
    # ========================================
    log "⚙️ STEP 5: Updating contract with first asset claim parameters"

    local gas_price=1000000000
    local update_output
    update_output=$(cast send \
        "$claim_reentrancy_sc_addr" \
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
    # STEP 6: Get initial balances for verification
    # ========================================
    log "💰 STEP 6: Recording initial balances for verification"

    # Get initial token balances (in ETH units)
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local initial_contract_balance
    initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$claim_reentrancy_sc_addr")

    # Convert to wei for precise comparison
    local initial_receiver_balance_wei
    initial_receiver_balance_wei=$(cast to-wei "$initial_receiver_balance" ether)
    local initial_contract_balance_wei
    initial_contract_balance_wei=$(cast to-wei "$initial_contract_balance" ether)

    log "📊 Initial receiver balance: $initial_receiver_balance ETH ($initial_receiver_balance_wei wei)"
    log "📊 Initial contract balance: $initial_contract_balance ETH ($initial_contract_balance_wei wei)"

    # ========================================
    # STEP 7: Claim second asset (should succeed)
    # ========================================
    log "🌉 STEP 7: Claiming second asset (should succeed)"

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_2" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
    local global_index_2_claimed=$output
    log "✅ Second asset claimed successfully, global index: $global_index_2_claimed"

    # ========================================
    # STEP 8: Test reentrancy protection
    # ========================================
    log "🔄 STEP 8: Testing reentrancy protection - attempting to claim first asset again"

    # Calculate gas price for reentrant claim
    local comp_gas_price
    comp_gas_price=$(bc -l <<<"$gas_price * 1.5" | sed 's/\..*//')
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
    local tmp_response
    tmp_response=$(mktemp)
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
    # STEP 9: Verify claim events in aggkit
    # ========================================
    log "🔍 STEP 9: Verifying claim events were processed correctly by aggkit"

    # Verify first claim was processed
    log "🔍 Validating first asset claim processing"
    run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_1="$output"
    log "📋 First claim response received"

    # Validate first claim parameters
    log "🔍 Validating first claim parameters"
    local claim_1_mainnet_exit_root
    claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
    local claim_1_rollup_exit_root
    claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
    local claim_1_origin_network
    claim_1_origin_network=$(echo "$claim_1" | jq -r '.origin_network')
    local claim_1_origin_address
    claim_1_origin_address=$(echo "$claim_1" | jq -r '.origin_address')
    local claim_1_destination_network
    claim_1_destination_network=$(echo "$claim_1" | jq -r '.destination_network')
    local claim_1_destination_address
    claim_1_destination_address=$(echo "$claim_1" | jq -r '.destination_address')
    local claim_1_amount
    claim_1_amount=$(echo "$claim_1" | jq -r '.amount')
    local claim_1_metadata
    claim_1_metadata=$(echo "$claim_1" | jq -r '.metadata')

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
    local claim_1_proof_local_exit_root
    claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_1_proof_rollup_exit_root
    claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

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
    local claim_2_mainnet_exit_root
    claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
    local claim_2_rollup_exit_root
    claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
    local claim_2_origin_network
    claim_2_origin_network=$(echo "$claim_2" | jq -r '.origin_network')
    local claim_2_origin_address
    claim_2_origin_address=$(echo "$claim_2" | jq -r '.origin_address')
    local claim_2_destination_network
    claim_2_destination_network=$(echo "$claim_2" | jq -r '.destination_network')
    local claim_2_destination_address
    claim_2_destination_address=$(echo "$claim_2" | jq -r '.destination_address')
    local claim_2_amount
    claim_2_amount=$(echo "$claim_2" | jq -r '.amount')
    local claim_2_metadata
    claim_2_metadata=$(echo "$claim_2" | jq -r '.metadata')

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
    local claim_2_proof_local_exit_root
    claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_2_proof_rollup_exit_root
    claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
    assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
    log "✅ Second claim validated successfully"

    # ========================================
    # STEP 10: Final balance verification
    # ========================================
    log "💰 STEP 10: Verifying final balances"

    # Get final balances (in eth)
    local final_receiver_balance
    final_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local final_contract_balance
    final_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$claim_reentrancy_sc_addr")

    local final_receiver_balance_wei
    final_receiver_balance_wei=$(cast to-wei "$final_receiver_balance" ether)
    local final_contract_balance_wei
    final_contract_balance_wei=$(cast to-wei "$final_contract_balance" ether)

    log "📊 Initial receiver balance(wei): $initial_receiver_balance_wei"
    log "📊 Initial contract balance(wei): $initial_contract_balance_wei"
    log "📊 Final receiver balance(wei): $final_receiver_balance_wei"
    log "📊 Final contract balance(wei): $final_contract_balance_wei"

    # Verify contract received second asset
    local expected_contract_balance_wei
    expected_contract_balance_wei=$(echo "$initial_contract_balance_wei + $amount_2" | bc)
    if [[ "$final_contract_balance_wei" == "$expected_contract_balance_wei" ]]; then
        log "✅ Contract balance correctly increased by second asset amount"
    else
        log "❌ Contract balance verification failed"
        log "Expected: $expected_contract_balance_wei, Got: $final_contract_balance_wei"
        exit 1
    fi

    # Verify receiver received first asset
    local expected_receiver_balance_wei
    expected_receiver_balance_wei=$(echo "$initial_receiver_balance_wei + $amount_1" | bc)
    if [[ "$final_receiver_balance_wei" == "$expected_receiver_balance_wei" ]]; then
        log "✅ Receiver balance correctly increased by first asset amount"
    else
        log "❌ receiver balance verification failed"
        log "initial_receiver_balance_wei: $initial_receiver_balance_wei"
        log "amount_1: $amount_1"
        log "final_receiver_balance_wei: $final_receiver_balance_wei"
        log "expected_receiver_balance_wei: $expected_receiver_balance_wei"
        log "Expected: $expected_receiver_balance_wei, Got: $final_receiver_balance_wei"
        exit 1
    fi

    log "🎉 Test completed successfully! Reentrancy protection is working correctly."

    # ========================================
    # STEP 11: Verify claims using is_claimed function
    # ========================================
    log "🔍 STEP 11: Verifying claims using is_claimed function"

    # Get deposit counts for all claims
    local deposit_count_1
    deposit_count_1=$(echo "$claim_params_1" | jq -r '.deposit_count')
    local deposit_count_2
    deposit_count_2=$(echo "$claim_params_2" | jq -r '.deposit_count')

    # ========================================
    # Check first claim (should be claimed)
    # ========================================
    log "🔍 Checking is_claimed for first claim (deposit_count: $deposit_count_1, source_network: $origin_network_1)"

    run is_claimed "$deposit_count_1" "$origin_network_1" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_1=$output
    log "📋 First claim is_claimed result: $is_claimed_1"

    if [[ "$is_claimed_1" == "true" ]]; then
        log "✅ First claim correctly marked as claimed"
    else
        log "❌ First claim not marked as claimed - expected true, got $is_claimed_1"
        exit 1
    fi

    # ========================================
    # Check second claim (should be claimed)
    # ========================================
    log "🔍 Checking is_claimed for second claim (deposit_count: $deposit_count_2, source_network: $origin_network_2)"

    run is_claimed "$deposit_count_2" "$origin_network_2" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_2=$output
    log "📋 Second claim is_claimed result: $is_claimed_2"

    if [[ "$is_claimed_2" == "true" ]]; then
        log "✅ Second claim correctly marked as claimed (as expected)"
    else
        log "❌ Second claim incorrectly marked as NOT claimed - expected true, got $is_claimed_2"
        exit 1
    fi

    log "🎉 All is_claimed verifications passed successfully!"
}

@test "Test execute multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call" {
    # ========================================
    # STEP 1: Bridge first asset (destination: contract address)
    # ========================================
    log "🌉 STEP 1: Bridging first asset from L1 to L2 (destination: contract)"

    # Set destination for first bridge to contract
    destination_addr=$claim_reentrancy_sc_addr
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
    # STEP 2: Bridge second asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 2: Bridging second asset from L1 to L2 (destination: deployer)"

    # Set destination for second bridge to deployer
    receiver_addr='0xBA002167c3a9Ee959EF4c2A62f7Fb026326479DD'
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
    # STEP 3: Bridge third asset (destination: deployer address)
    # ========================================
    log "🌉 STEP 3: Bridging third asset from L1 to L2 (destination: deployer)"

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
    # STEP 4: Get claim parameters for first asset (contract destination)
    # ========================================
    log "📋 STEP 4: Retrieving claim parameters for first asset (contract destination)"

    # Use the helper function to extract claim parameters
    local claim_params_1
    claim_params_1=$(extract_claim_parameters_json "$bridge_tx_hash_1" "first")

    # Parse the JSON response to extract individual parameters
    local proof_local_exit_root_1
    proof_local_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_1
    proof_rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.proof_rollup_exit_root')
    local global_index_1
    global_index_1=$(echo "$claim_params_1" | jq -r '.global_index')
    local mainnet_exit_root_1
    mainnet_exit_root_1=$(echo "$claim_params_1" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_1
    rollup_exit_root_1=$(echo "$claim_params_1" | jq -r '.rollup_exit_root')
    local origin_network_1
    origin_network_1=$(echo "$claim_params_1" | jq -r '.origin_network')
    local origin_address_1
    origin_address_1=$(echo "$claim_params_1" | jq -r '.origin_address')
    local destination_network_1
    destination_network_1=$(echo "$claim_params_1" | jq -r '.destination_network')
    local destination_address_1
    destination_address_1=$(echo "$claim_params_1" | jq -r '.destination_address')
    local amount_1
    amount_1=$(echo "$claim_params_1" | jq -r '.amount')
    local metadata_1
    metadata_1=$(echo "$claim_params_1" | jq -r '.metadata')
    local deposit_count_1
    deposit_count_1=$(echo "$claim_params_1" | jq -r '.deposit_count')

    log "✅ First asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_1, Amount: $amount_1 wei"

    # ========================================
    # STEP 5: Get claim parameters for second asset (deployer destination)
    # ========================================
    log "📋 STEP 5: Retrieving claim parameters for second asset (deployer destination)"

    # Use the helper function to extract claim parameters
    local claim_params_2
    claim_params_2=$(extract_claim_parameters_json "$bridge_tx_hash_2" "second")

    # Parse the JSON response to extract individual parameters
    local proof_local_exit_root_2
    proof_local_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_2
    proof_rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.proof_rollup_exit_root')
    local global_index_2
    global_index_2=$(echo "$claim_params_2" | jq -r '.global_index')
    local mainnet_exit_root_2
    mainnet_exit_root_2=$(echo "$claim_params_2" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_2
    rollup_exit_root_2=$(echo "$claim_params_2" | jq -r '.rollup_exit_root')
    local origin_network_2
    origin_network_2=$(echo "$claim_params_2" | jq -r '.origin_network')
    local origin_address_2
    origin_address_2=$(echo "$claim_params_2" | jq -r '.origin_address')
    local destination_network_2
    destination_network_2=$(echo "$claim_params_2" | jq -r '.destination_network')
    local destination_address_2
    destination_address_2=$(echo "$claim_params_2" | jq -r '.destination_address')
    local amount_2
    amount_2=$(echo "$claim_params_2" | jq -r '.amount')
    local metadata_2
    metadata_2=$(echo "$claim_params_2" | jq -r '.metadata')
    local deposit_count_2
    deposit_count_2=$(echo "$claim_params_2" | jq -r '.deposit_count')

    log "✅ Second asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_2, Amount: $amount_2 wei"

    # ========================================
    # STEP 6: Get claim parameters for third asset (deployer destination)
    # ========================================
    log "📋 STEP 6: Retrieving claim parameters for third asset (deployer destination)"

    # Use the helper function to extract claim parameters
    local claim_params_3
    claim_params_3=$(extract_claim_parameters_json "$bridge_tx_hash_3" "third")

    # Parse the JSON response to extract individual parameters
    local proof_local_exit_root_3
    proof_local_exit_root_3=$(echo "$claim_params_3" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_3
    proof_rollup_exit_root_3=$(echo "$claim_params_3" | jq -r '.proof_rollup_exit_root')
    local global_index_3
    global_index_3=$(echo "$claim_params_3" | jq -r '.global_index')
    local mainnet_exit_root_3
    mainnet_exit_root_3=$(echo "$claim_params_3" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_3
    rollup_exit_root_3=$(echo "$claim_params_3" | jq -r '.rollup_exit_root')
    local origin_network_3
    origin_network_3=$(echo "$claim_params_3" | jq -r '.origin_network')
    local origin_address_3
    origin_address_3=$(echo "$claim_params_3" | jq -r '.origin_address')
    local destination_network_3
    destination_network_3=$(echo "$claim_params_3" | jq -r '.destination_network')
    local destination_address_3
    destination_address_3=$(echo "$claim_params_3" | jq -r '.destination_address')
    local amount_3
    amount_3=$(echo "$claim_params_3" | jq -r '.amount')
    local metadata_3
    metadata_3=$(echo "$claim_params_3" | jq -r '.metadata')
    local deposit_count_3
    deposit_count_3=$(echo "$claim_params_3" | jq -r '.deposit_count')

    log "✅ Third asset claim parameters extracted successfully"
    log "📊 Global index: $global_index_3, Amount: $amount_3 wei"

    # ========================================
    # STEP 7: Update contract with second asset claim parameters (for reentrancy test)
    # ========================================
    log "⚙️ STEP 7: Updating contract with second asset claim parameters"

    local gas_price=1000000000
    local update_output
    update_output=$(cast send \
        "$claim_reentrancy_sc_addr" \
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
    # STEP 8: Get initial balances for verification
    # ========================================
    log "💰 STEP 8: Recording initial balances for verification"

    # Get initial token balances (in ETH units)
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local initial_contract_balance
    initial_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$claim_reentrancy_sc_addr")

    # Convert to wei for precise comparison
    local initial_receiver_balance_wei
    initial_receiver_balance_wei=$(cast to-wei "$initial_receiver_balance" ether)
    local initial_contract_balance_wei
    initial_contract_balance_wei=$(cast to-wei "$initial_contract_balance" ether)

    log "📊 Initial receiver balance: $initial_receiver_balance ETH ($initial_receiver_balance_wei wei)"
    log "📊 Initial contract balance: $initial_contract_balance ETH ($initial_contract_balance_wei wei)"

    # ========================================
    # STEP 9: call testClaim from the smart contract with all the required parameters
    # ========================================
    log "🔧 STEP 9: Calling testClaim from smart contract with all required parameters"

    # Encode claimData1 (first asset claim parameters - destination: contract)
    log "📦 Encoding claimData1 (first asset - contract destination)"
    log "🔍 Debug - amount_1: $amount_1"
    log "🔍 Debug - global_index_1: $global_index_1"
    log "🔍 Debug - origin_network_1: $origin_network_1"
    log "🔍 Debug - destination_network_1: $destination_network_1"

    local claim_data_1
    claim_data_1=$(cast abi-encode \
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
    local bridge_asset_data
    bridge_asset_data=$(cast abi-encode \
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
    local claim_data_2
    claim_data_2=$(cast abi-encode \
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
    local test_claim_gas_price
    test_claim_gas_price=$(bc -l <<<"$gas_price * 2" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        log "❌ Failed to calculate gas price"
        return 1
    fi

    log "⏳ Calling testClaim..."
    if ! test_claim_output=$(cast send \
        "$claim_reentrancy_sc_addr" \
        "testClaim(bytes,bytes,bytes)" \
        "$claim_data_1" \
        "$bridge_asset_data" \
        "$claim_data_2" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$test_claim_gas_price" \
        --value "$amount_bridge_wei" \
        --json 2>&1); then

        log "❌ testClaim failed"
        log "test_claim_output: $test_claim_output"
        exit 1
    else
        log "✅ testClaim succeeded"
        log "$test_claim_output"
    fi

    log "✅ testClaim executed successfully"
    log "📋 testClaim output: $test_claim_output"

    # extract tx hash from test_claim_output
    local test_claim_tx_hash
    test_claim_tx_hash=$(echo "$test_claim_output" | jq -r '.transactionHash')
    log "📝 testClaim tx hash: $test_claim_tx_hash"

    # ========================================
    # STEP 10: Verify claim events in aggkit
    # ========================================
    log "🔍 STEP 10: Verifying claim events were processed correctly by aggkit"

    # Verify first claim was processed (contract destination)
    log "🔍 Validating first asset claim processing (contract destination)"
    run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_1="$output"
    log "📋 First claim response received"

    # Validate first claim parameters
    log "🔍 Validating first claim parameters"
    local claim_1_mainnet_exit_root
    claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
    local claim_1_rollup_exit_root
    claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
    local claim_1_origin_network
    claim_1_origin_network=$(echo "$claim_1" | jq -r '.origin_network')
    local claim_1_origin_address
    claim_1_origin_address=$(echo "$claim_1" | jq -r '.origin_address')
    local claim_1_destination_network
    claim_1_destination_network=$(echo "$claim_1" | jq -r '.destination_network')
    local claim_1_destination_address
    claim_1_destination_address=$(echo "$claim_1" | jq -r '.destination_address')
    local claim_1_amount
    claim_1_amount=$(echo "$claim_1" | jq -r '.amount')
    local claim_1_metadata
    claim_1_metadata=$(echo "$claim_1" | jq -r '.metadata')

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
    local claim_1_proof_local_exit_root
    claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_1_proof_rollup_exit_root
    claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
    assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"
    log "✅ First claim validated successfully"

    # Verify second claim was processed (deployer destination)
    log "🔍 Validating second asset claim processing (deployer destination)"
    run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_2="$output"
    log "📋 Second claim response received"

    # Validate second claim parameters
    log "🔍 Validating second claim parameters"
    local claim_2_mainnet_exit_root
    claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
    local claim_2_rollup_exit_root
    claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
    local claim_2_origin_network
    claim_2_origin_network=$(echo "$claim_2" | jq -r '.origin_network')
    local claim_2_origin_address
    claim_2_origin_address=$(echo "$claim_2" | jq -r '.origin_address')
    local claim_2_destination_network
    claim_2_destination_network=$(echo "$claim_2" | jq -r '.destination_network')
    local claim_2_destination_address
    claim_2_destination_address=$(echo "$claim_2" | jq -r '.destination_address')
    local claim_2_amount
    claim_2_amount=$(echo "$claim_2" | jq -r '.amount')
    local claim_2_metadata
    claim_2_metadata=$(echo "$claim_2" | jq -r '.metadata')

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
    local claim_2_proof_local_exit_root
    claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_2_proof_rollup_exit_root
    claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
    assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
    log "✅ Second claim validated successfully"

    # Verify third claim was processed (deployer destination)
    log "🔍 Validating third asset claim processing (deployer destination)"
    run get_claim "$l2_rpc_network_id" "$global_index_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local claim_3="$output"
    log "📋 Third claim response received"

    # Validate third claim parameters
    log "🔍 Validating third claim parameters"
    local claim_3_mainnet_exit_root
    claim_3_mainnet_exit_root=$(echo "$claim_3" | jq -r '.mainnet_exit_root')
    local claim_3_rollup_exit_root
    claim_3_rollup_exit_root=$(echo "$claim_3" | jq -r '.rollup_exit_root')
    local claim_3_origin_network
    claim_3_origin_network=$(echo "$claim_3" | jq -r '.origin_network')
    local claim_3_origin_address
    claim_3_origin_address=$(echo "$claim_3" | jq -r '.origin_address')
    local claim_3_destination_network
    claim_3_destination_network=$(echo "$claim_3" | jq -r '.destination_network')
    local claim_3_destination_address
    claim_3_destination_address=$(echo "$claim_3" | jq -r '.destination_address')
    local claim_3_amount
    claim_3_amount=$(echo "$claim_3" | jq -r '.amount')
    local claim_3_metadata
    claim_3_metadata=$(echo "$claim_3" | jq -r '.metadata')

    # Assert parameter consistency
    assert_equal "$claim_3_mainnet_exit_root" "$mainnet_exit_root_3"
    assert_equal "$claim_3_rollup_exit_root" "$rollup_exit_root_3"
    assert_equal "$claim_3_origin_network" "$origin_network_3"
    assert_equal "$claim_3_origin_address" "$origin_address_3"
    assert_equal "$claim_3_destination_network" "$destination_network_3"
    assert_equal "$claim_3_destination_address" "$destination_address_3"
    assert_equal "$claim_3_amount" "$amount_3"
    assert_equal "$claim_3_metadata" "$metadata_3"

    # Validate third claim proofs
    log "🔍 Validating third claim proofs"
    local claim_3_proof_local_exit_root
    claim_3_proof_local_exit_root=$(echo "$claim_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local claim_3_proof_rollup_exit_root
    claim_3_proof_rollup_exit_root=$(echo "$claim_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

    assert_equal "$claim_3_proof_local_exit_root" "$proof_local_exit_root_3"
    assert_equal "$claim_3_proof_rollup_exit_root" "$proof_rollup_exit_root_3"
    log "✅ Third claim validated successfully"

    # ========================================
    # STEP 11: Final balance verification
    # ========================================
    log "💰 STEP 11: Verifying final balances"

    # Get final balances (in eth)
    local final_receiver_balance
    final_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$receiver_addr")
    local final_contract_balance
    final_contract_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$claim_reentrancy_sc_addr")

    local final_receiver_balance_wei
    final_receiver_balance_wei=$(cast to-wei "$final_receiver_balance" ether)
    local final_contract_balance_wei
    final_contract_balance_wei=$(cast to-wei "$final_contract_balance" ether)

    log "📊 Initial receiver balance(wei): $initial_receiver_balance_wei"
    log "📊 Initial contract balance(wei): $initial_contract_balance_wei"
    log "📊 Final receiver balance(wei): $final_receiver_balance_wei"
    log "📊 Final contract balance(wei): $final_contract_balance_wei"

    # Verify contract received first asset
    local expected_contract_balance_wei
    expected_contract_balance_wei=$(echo "$initial_contract_balance_wei + $amount_1" | bc)
    if [[ "$final_contract_balance_wei" == "$expected_contract_balance_wei" ]]; then
        log "✅ Contract balance correctly increased by first asset amount"
    else
        log "❌ Contract balance verification failed"
        log "Expected: $expected_contract_balance_wei, Got: $final_contract_balance_wei"
        exit 1
    fi

    # Verify receiver balance increased by second and third assets
    local total_received_by_sender
    total_received_by_sender=$(echo "$amount_2 + $amount_3" | bc)
    local expected_receiver_balance_wei
    expected_receiver_balance_wei=$(echo "$initial_receiver_balance_wei + $total_received_by_sender" | bc)
    if [[ "$final_receiver_balance_wei" == "$expected_receiver_balance_wei" ]]; then
        log "✅ Receiver balance correctly increased by expected amount"
    else
        log "❌ Receiver balance verification failed"
        log "Expected: $expected_receiver_balance_wei, Got: $final_receiver_balance_wei"
        exit 1
    fi

    # ========================================
    # STEP 12: Verify claims using is_claimed function
    # ========================================
    log "🔍 STEP 12: Verifying claims using is_claimed function"

    # ========================================
    # Check first claim (should be claimed)
    # ========================================
    log "🔍 Checking is_claimed for first claim (deposit_count: $deposit_count_1, source_network: $origin_network_1)"

    run is_claimed "$deposit_count_1" "$origin_network_1" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_1=$output
    log "📋 First claim is_claimed result: $is_claimed_1"

    if [[ "$is_claimed_1" == "true" ]]; then
        log "✅ First claim correctly marked as claimed"
    else
        log "❌ First claim not marked as claimed - expected true, got $is_claimed_1"
        exit 1
    fi

    # ========================================
    # Check second claim (should be claimed)
    # ========================================
    log "🔍 Checking is_claimed for second claim (deposit_count: $deposit_count_2, source_network: $origin_network_2)"

    run is_claimed "$deposit_count_2" "$origin_network_2" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_2=$output
    log "📋 Second claim is_claimed result: $is_claimed_2"

    if [[ "$is_claimed_2" == "true" ]]; then
        log "✅ Second claim correctly marked as claimed"
    else
        log "❌ Second claim not marked as claimed - expected true, got $is_claimed_2"
        exit 1
    fi

    # ========================================
    # Check third claim (should be claimed)
    # ========================================
    log "🔍 Checking is_claimed for third claim (deposit_count: $deposit_count_3, source_network: $origin_network_3)"

    run is_claimed "$deposit_count_3" "$origin_network_3" "$l2_bridge_addr" "$L2_RPC_URL"
    assert_success
    local is_claimed_3=$output
    log "📋 Third claim is_claimed result: $is_claimed_3"

    if [[ "$is_claimed_3" == "true" ]]; then
        log "✅ Third claim correctly marked as claimed"
    else
        log "❌ Third claim not marked as claimed - expected true, got $is_claimed_3"
        exit 1
    fi
    log "🎉 All is_claimed verifications passed successfully!"

    # ========================================
    # STEP 13: Verify bridge event from aggkit
    # ========================================
    log "🔍 STEP 13: Verifying bridge event from aggkit with tx hash: $test_claim_tx_hash"

    # Get bridge details
    run get_bridge "$l2_rpc_network_id" "$test_claim_tx_hash" 300 10 "$aggkit_bridge_url"
    assert_success
    local bridge_test_claim="$output"
    log "📝 bridge_test_claim: $bridge_test_claim"
    local amount_test_claim
    amount_test_claim=$(echo "$bridge_test_claim" | jq -r '.amount')
    local destination_address_test_claim
    destination_address_test_claim=$(echo "$bridge_test_claim" | jq -r '.destination_address')
    assert_equal "$amount_test_claim" "$amount_bridge_wei"
    assert_equal "$destination_address_test_claim" "$receiver_addr_bridge"

    log "🎉 Test completed successfully! Multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call is working correctly."
}
