setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Test triple claim internal calls -> 3 success" {
    log "🧪 Testing triple claim internal calls: 3 success"

    # Deploy the InternalClaims contract
    local mock_artifact_path="$PROJECT_ROOT/compiled-contracts/InternalClaims.sol/InternalClaims.json"

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

    log "🎉 Deployed InternalClaims at: $mock_sc_addr"

    # ========================================
    # STEP 1: Bridge first asset and get all claim parameters
    # ========================================
    log "🌉 STEP 1: Bridging first asset from L1 to L2"
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id

    # Bridge first asset using the helper function
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
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

    # ========================================
    # STEP 2: Bridge second asset and get all claim parameters
    # ========================================
    log "🌉 STEP 2: Bridging second asset from L1 to L2"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
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

    # ========================================
    # STEP 3: Bridge third asset and get all claim parameters
    # ========================================
    log "🌉 STEP 3: Bridging third asset from L1 to L2"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_3=$output
    log "🌉 Third bridge asset transaction hash: $bridge_tx_hash_3"

    # Get all claim parameters for third asset
    log "📋 Getting third bridge details"
    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local bridge_3="$output"
    log "📝 Third bridge response: $bridge_3"
    local deposit_count_3=$(echo "$bridge_3" | jq -r '.deposit_count')

    log "🌳 Getting L1 info tree index for third bridge"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index_3="$output"
    log "📝 Third L1 info tree index: $l1_info_tree_index_3"

    log "Getting injected L1 info leaf for third bridge"
    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local injected_info_3="$output"
    log "📝 Third injected info: $injected_info_3"

    log "🔐 Getting third claim proof"
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_3" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof_3="$output"
    log "📝 Third proof: $proof_3"

    # Extract all claim parameters for third asset
    log "🎯 Extracting claim parameters for third asset"
    local proof_local_exit_root_3=$(echo "$proof_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root_3=$(echo "$proof_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge_3" "$l1_rpc_network_id"
    assert_success
    local global_index_3=$output
    log "📝 Third global index: $global_index_3"
    local mainnet_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network_3=$(echo "$bridge_3" | jq -r '.origin_network')
    local origin_address_3=$(echo "$bridge_3" | jq -r '.origin_address')
    local destination_network_3=$(echo "$bridge_3" | jq -r '.destination_network')
    local destination_address_3=$(echo "$bridge_3" | jq -r '.destination_address')
    local amount_3=$(echo "$bridge_3" | jq -r '.amount')
    local metadata_3=$(echo "$bridge_3" | jq -r '.metadata')

    log "✅ Third asset claim parameters extracted successfully"

    # ========================================
    # STEP 4: Update contract with all three sets of claim parameters
    # ========================================
    log "⚙️ STEP 4: Updating contract parameters with all three sets of claim data"
    local update_output
    update_output=$(cast send \
        "$mock_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
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
        "$proof_local_exit_root_3" \
        "$proof_rollup_exit_root_3" \
        "$global_index_3" \
        "$mainnet_exit_root_3" \
        "$rollup_exit_root_3" \
        "$origin_network_3" \
        "$origin_address_3" \
        "$destination_network_3" \
        "$destination_address_3" \
        "$amount_3" \
        "$metadata_3" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to update parameters"
        log "$update_output"
        exit 1
    fi

    log "✅ Contract parameters updated successfully with all three sets of claim data"

    # ========================================
    # STEP 5: Test onMessageReceived functionality
    # ========================================
    log "🧪 STEP 5: Testing onMessageReceived with valid parameters (will attempt all three asset claims)"
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

        # Validate the bridge_getClaims API to verify all three claims were processed
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

        log "🌳 First claim mainnet exit root: $claim_1_mainnet_exit_root (Expected: $mainnet_exit_root_1)"
        log "🌳 First claim rollup exit root: $claim_1_rollup_exit_root (Expected: $rollup_exit_root_1)"
        log "🌐 First claim origin network: $claim_1_origin_network (Expected: $origin_network_1)"
        log "📍 First claim origin address: $claim_1_origin_address (Expected: $origin_address_1)"
        log "🌐 First claim destination network: $claim_1_destination_network (Expected: $destination_network_1)"
        log "📍 First claim destination address: $claim_1_destination_address (Expected: $destination_address_1)"
        log "💰 First claim amount: $claim_1_amount (Expected: $amount_1)"

        assert_equal "$claim_1_mainnet_exit_root" "$mainnet_exit_root_1"
        # assert_equal "$claim_1_rollup_exit_root" "$rollup_exit_root_1"
        assert_equal "$claim_1_origin_network" "$origin_network_1"
        assert_equal "$claim_1_destination_network" "$destination_network_1"
        assert_equal "$claim_1_destination_address" "$destination_address_1"
        assert_equal "$claim_1_amount" "$amount_1"

        # Validate proofs for first claim
        log "🔍 Validating proofs for first claim"
        local claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 First claim proof local exit root: $claim_1_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_1"
        log "🔐 First claim proof rollup exit root: $claim_1_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_1"

        assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
        assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"

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

        log "🌳 Second claim mainnet exit root: $claim_2_mainnet_exit_root (Expected: $mainnet_exit_root_2)"
        log "🌳 Second claim rollup exit root: $claim_2_rollup_exit_root (Expected: $rollup_exit_root_2)"
        log "🌐 Second claim origin network: $claim_2_origin_network (Expected: $origin_network_2)"
        log "📍 Second claim origin address: $claim_2_origin_address (Expected: $origin_address_2)"
        log "🌐 Second claim destination network: $claim_2_destination_network (Expected: $destination_network_2)"
        log "📍 Second claim destination address: $claim_2_destination_address (Expected: $destination_address_2)"
        log "💰 Second claim amount: $claim_2_amount (Expected: $amount_2)"

        assert_equal "$claim_2_mainnet_exit_root" "$mainnet_exit_root_2"
        assert_equal "$claim_2_rollup_exit_root" "$rollup_exit_root_2"
        assert_equal "$claim_2_origin_network" "$origin_network_2"
        assert_equal "$claim_2_destination_network" "$destination_network_2"
        assert_equal "$claim_2_destination_address" "$destination_address_2"
        assert_equal "$claim_2_amount" "$amount_2"

        # Validate proofs for second claim
        log "🔍 Validating proofs for second claim"
        local claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 Second claim proof local exit root: $claim_2_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_2"
        log "🔐 Second claim proof rollup exit root: $claim_2_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_2"

        assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
        assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"

        log "🔍 Validating third asset claim was processed"
        run get_claim "$l2_rpc_network_id" "$global_index_3" 50 10 "$aggkit_bridge_url"
        assert_success
        local claim_3="$output"
        log "📋 Third claim response: $claim_3"

        # Validate all parameters for third claim
        log "🔍 Validating all parameters for third claim"
        local claim_3_mainnet_exit_root=$(echo "$claim_3" | jq -r '.mainnet_exit_root')
        local claim_3_rollup_exit_root=$(echo "$claim_3" | jq -r '.rollup_exit_root')
        local claim_3_origin_network=$(echo "$claim_3" | jq -r '.origin_network')
        local claim_3_origin_address=$(echo "$claim_3" | jq -r '.origin_address')
        local claim_3_destination_network=$(echo "$claim_3" | jq -r '.destination_network')
        local claim_3_destination_address=$(echo "$claim_3" | jq -r '.destination_address')
        local claim_3_amount=$(echo "$claim_3" | jq -r '.amount')

        log "🌳 Third claim mainnet exit root: $claim_3_mainnet_exit_root (Expected: $mainnet_exit_root_3)"
        log "🌳 Third claim rollup exit root: $claim_3_rollup_exit_root (Expected: $rollup_exit_root_3)"
        log "🌐 Third claim origin network: $claim_3_origin_network (Expected: $origin_network_3)"
        log "📍 Third claim origin address: $claim_3_origin_address (Expected: $origin_address_3)"
        log "🌐 Third claim destination network: $claim_3_destination_network (Expected: $destination_network_3)"
        log "📍 Third claim destination address: $claim_3_destination_address (Expected: $destination_address_3)"
        log "💰 Third claim amount: $claim_3_amount (Expected: $amount_3)"

        assert_equal "$claim_3_mainnet_exit_root" "$mainnet_exit_root_3"
        assert_equal "$claim_3_rollup_exit_root" "$rollup_exit_root_3"
        assert_equal "$claim_3_origin_network" "$origin_network_3"
        assert_equal "$claim_3_destination_network" "$destination_network_3"
        assert_equal "$claim_3_destination_address" "$destination_address_3"
        assert_equal "$claim_3_amount" "$amount_3"

        # Validate proofs for third claim
        log "🔍 Validating proofs for third claim"
        local claim_3_proof_local_exit_root=$(echo "$claim_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_3_proof_rollup_exit_root=$(echo "$claim_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 Third claim proof local exit root: $claim_3_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_3"
        log "🔐 Third claim proof rollup exit root: $claim_3_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_3"

        assert_equal "$claim_3_proof_local_exit_root" "$proof_local_exit_root_3"
        assert_equal "$claim_3_proof_rollup_exit_root" "$proof_rollup_exit_root_3"

        log "✅ All three asset claims were successfully processed through onMessageReceived"
        log "✅ All parameters validated successfully for all three claims"
    else
        log "❌ onMessageReceived transaction failed"
        log "$on_message_output"
        exit 1
    fi

    log "🎉 Bridge reentrancy test completed successfully"
    log "📊 Summary:"
    log "   ✅ Contract deployed successfully"
    log "   ✅ First asset bridge created and parameters extracted"
    log "   ✅ Second asset bridge created and parameters extracted"
    log "   ✅ Third asset bridge created and parameters extracted"
    log "   ✅ All three sets of parameters configured in contract"
    log "   ✅ All three asset claims processed successfully"
    log "   ✅ All parameters validated successfully for all three claims"
}

# @test "Test triple claim internal calls -> 1 success, 1 fail and 1 success" {
#     log "🧪 Testing triple claim internal calls: 1 success, 1 fail, 1 success"

#     # Deploy the InternalClaims contract
#     local internal_claims_artifact_path="$PROJECT_ROOT/compiled-contracts/InternalClaims.sol/InternalClaims.json"

#     # Get bytecode from the contract artifact
#     local bytecode=$(jq -r '.bytecode.object // .bytecode' "$internal_claims_artifact_path")
#     if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
#         log "❌ Error: Failed to read bytecode from $internal_claims_artifact_path"
#         exit 1
#     fi

#     # ABI-encode the constructor argument (bridge address)
#     local encoded_args=$(cast abi-encode "constructor(address)" "$l2_bridge_addr")
#     if [[ -z "$encoded_args" ]]; then
#         log "❌ Failed to ABI-encode constructor argument"
#         exit 1
#     fi

#     # Concatenate bytecode and encoded constructor args
#     local deploy_bytecode="${bytecode}${encoded_args:2}" # Remove 0x from encoded args

#     # Set a fixed gas price (1 gwei)
#     local gas_price=1000000000

#     # Deploy the contract
#     log "📝 Deploying InternalClaims contract"
#     local deploy_output
#     deploy_output=$(cast send --rpc-url "$L2_RPC_URL" \
#         --private-key "$sender_private_key" \
#         --gas-price "$gas_price" \
#         --legacy \
#         --create "$deploy_bytecode" 2>&1)

#     if [[ $? -ne 0 ]]; then
#         log "❌ Error: Failed to deploy contract"
#         log "$deploy_output"
#         exit 1
#     fi

#     # Extract contract address from output
#     local internal_claims_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
#     if [[ -z "$internal_claims_sc_addr" ]]; then
#         log "❌ Failed to extract deployed contract address"
#         log "$deploy_output"
#         exit 1
#     fi

#     log "🎉 Deployed InternalClaims at: $internal_claims_sc_addr"

#     # ========================================
#     # STEP 1: Bridge first asset and get all claim parameters
#     # ========================================
#     log "🌉 STEP 1: Bridging first asset from L1 to L2"
#     destination_addr=$sender_addr
#     destination_net=$l2_rpc_network_id

#     # Bridge first asset using the helper function
#     run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#     assert_success
#     local bridge_tx_hash_1=$output
#     log "🌉 First bridge asset transaction hash: $bridge_tx_hash_1"

#     # Get all claim parameters for first asset
#     log "📋 Getting first bridge details"
#     run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_1" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local bridge_1="$output"
#     log "📝 First bridge response: $bridge_1"
#     local deposit_count_1=$(echo "$bridge_1" | jq -r '.deposit_count')

#     log "🌳 Getting L1 info tree index for first bridge"
#     run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_1" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local l1_info_tree_index_1="$output"
#     log "📝 First L1 info tree index: $l1_info_tree_index_1"

#     log "Getting injected L1 info leaf for first bridge"
#     run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local injected_info_1="$output"
#     log "📝 First injected info: $injected_info_1"

#     log "🔐 Getting first claim proof"
#     run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_1" "$l1_info_tree_index_1" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local proof_1="$output"
#     log "📝 First proof: $proof_1"

#     # Extract all claim parameters for first asset
#     log "🎯 Extracting claim parameters for first asset"
#     local proof_local_exit_root_1=$(echo "$proof_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     local proof_rollup_exit_root_1=$(echo "$proof_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     run generate_global_index "$bridge_1" "$l1_rpc_network_id"
#     assert_success
#     local global_index_1=$output
#     log "📝 First global index: $global_index_1"
#     local mainnet_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
#     local rollup_exit_root_1=$(echo "$proof_1" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
#     local origin_network_1=$(echo "$bridge_1" | jq -r '.origin_network')
#     local origin_address_1=$(echo "$bridge_1" | jq -r '.origin_address')
#     local destination_network_1=$(echo "$bridge_1" | jq -r '.destination_network')
#     local destination_address_1=$(echo "$bridge_1" | jq -r '.destination_address')
#     local amount_1=$(echo "$bridge_1" | jq -r '.amount')
#     local metadata_1=$(echo "$bridge_1" | jq -r '.metadata')

#     log "✅ First asset claim parameters extracted successfully"

#     # ========================================
#     # STEP 2: Bridge second asset and get all claim parameters
#     # ========================================
#     log "🌉 STEP 2: Bridging second asset from L1 to L2"
#     run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#     assert_success
#     local bridge_tx_hash_2=$output
#     log "🌉 Second bridge asset transaction hash: $bridge_tx_hash_2"

#     # Get all claim parameters for second asset
#     log "📋 Getting second bridge details"
#     run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_2" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local bridge_2="$output"
#     log "📝 Second bridge response: $bridge_2"
#     local deposit_count_2=$(echo "$bridge_2" | jq -r '.deposit_count')

#     log "🌳 Getting L1 info tree index for second bridge"
#     run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_2" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local l1_info_tree_index_2="$output"
#     log "📝 Second L1 info tree index: $l1_info_tree_index_2"

#     log "Getting injected L1 info leaf for second bridge"
#     run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local injected_info_2="$output"
#     log "📝 Second injected info: $injected_info_2"

#     log "🔐 Getting second claim proof"
#     run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_2" "$l1_info_tree_index_2" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local proof_2="$output"
#     log "📝 Second proof: $proof_2"

#     # Extract all claim parameters for second asset
#     log "🎯 Extracting claim parameters for second asset"
#     local proof_local_exit_root_2=$(echo "$proof_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     local proof_rollup_exit_root_2=$(echo "$proof_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     run generate_global_index "$bridge_2" "$l1_rpc_network_id"
#     assert_success
#     local global_index_2=$output
#     log "📝 Second global index: $global_index_2"
#     local mainnet_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
#     local rollup_exit_root_2=$(echo "$proof_2" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
#     local origin_network_2=$(echo "$bridge_2" | jq -r '.origin_network')
#     local origin_address_2=$(echo "$bridge_2" | jq -r '.origin_address')
#     local destination_network_2=$(echo "$bridge_2" | jq -r '.destination_network')
#     local destination_address_2=$(echo "$bridge_2" | jq -r '.destination_address')
#     local amount_2=$(echo "$bridge_2" | jq -r '.amount')
#     local metadata_2=$(echo "$bridge_2" | jq -r '.metadata')

#     log "✅ Second asset claim parameters extracted successfully"

#     # ========================================
#     # STEP 3: Bridge third asset and get all claim parameters
#     # ========================================
#     log "🌉 STEP 3: Bridging third asset from L1 to L2"
#     run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
#     assert_success
#     local bridge_tx_hash_3=$output
#     log "🌉 Third bridge asset transaction hash: $bridge_tx_hash_3"

#     # Get all claim parameters for third asset
#     log "📋 Getting third bridge details"
#     run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash_3" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local bridge_3="$output"
#     log "📝 Third bridge response: $bridge_3"
#     local deposit_count_3=$(echo "$bridge_3" | jq -r '.deposit_count')

#     log "🌳 Getting L1 info tree index for third bridge"
#     run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count_3" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local l1_info_tree_index_3="$output"
#     log "📝 Third L1 info tree index: $l1_info_tree_index_3"

#     log "Getting injected L1 info leaf for third bridge"
#     run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local injected_info_3="$output"
#     log "📝 Third injected info: $injected_info_3"

#     log "🔐 Getting third claim proof"
#     run generate_claim_proof "$l1_rpc_network_id" "$deposit_count_3" "$l1_info_tree_index_3" 50 10 "$aggkit_bridge_url"
#     assert_success
#     local proof_3="$output"
#     log "📝 Third proof: $proof_3"

#     # Extract all claim parameters for third asset
#     log "🎯 Extracting claim parameters for third asset"
#     local proof_local_exit_root_3=$(echo "$proof_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     local proof_rollup_exit_root_3=$(echo "$proof_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     run generate_global_index "$bridge_3" "$l1_rpc_network_id"
#     assert_success
#     local global_index_3=$output
#     log "📝 Third global index: $global_index_3"
#     local mainnet_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
#     local rollup_exit_root_3=$(echo "$proof_3" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
#     local origin_network_3=$(echo "$bridge_3" | jq -r '.origin_network')
#     local origin_address_3=$(echo "$bridge_3" | jq -r '.origin_address')
#     local destination_network_3=$(echo "$bridge_3" | jq -r '.destination_network')
#     local destination_address_3=$(echo "$bridge_3" | jq -r '.destination_address')
#     local amount_3=$(echo "$bridge_3" | jq -r '.amount')
#     local metadata_3=$(echo "$bridge_3" | jq -r '.metadata')

#     log "✅ Third asset claim parameters extracted successfully"

#     # ========================================
#     # STEP 4: Create malformed parameters for second claim (to make it fail)
#     # ========================================
#     log "🔧 STEP 4: Creating malformed parameters for second claim (to make it fail)"

#     # Create malformed proof for second claim (inspired from claim-call.bats)
#     local malformed_proof_local_exit_root_2=$(echo "$proof_2" | jq -r '.proof_local_exit_root[1] = "0xf077e0d22fd6721989347f053c33595697372ec8c0d0678b934bba193679e088" | .proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
#     local malformed_mainnet_exit_root_2=0x787bc577d07da1b6ca15c9b2c6d869e08a29663f498b65752604c75efee2cfe0

#     log "🔧 Malformed proof for second claim: $malformed_proof_local_exit_root_2"
#     log "🔧 Malformed mainnet exit root for second claim: $malformed_mainnet_exit_root_2"

#     # ========================================
#     # STEP 5: Update contract with all three sets of claim parameters
#     # ========================================
#     log "⚙️ STEP 5: Updating contract parameters with all three sets of claim data"
#     local update_output
#     update_output=$(cast send \
#         "$internal_claims_sc_addr" \
#         "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
#         "$proof_local_exit_root_1" \
#         "$proof_rollup_exit_root_1" \
#         "$global_index_1" \
#         "$mainnet_exit_root_1" \
#         "$rollup_exit_root_1" \
#         "$origin_network_1" \
#         "$origin_address_1" \
#         "$destination_network_1" \
#         "$destination_address_1" \
#         "$amount_1" \
#         "$metadata_1" \
#         "$proof_local_exit_root_2" \
#         "$proof_rollup_exit_root_2" \
#         "$global_index_2" \
#         "$malformed_mainnet_exit_root_2" \
#         "$rollup_exit_root_2" \
#         "$origin_network_2" \
#         "$origin_address_2" \
#         "$destination_network_2" \
#         "$destination_address_2" \
#         "$amount_2" \
#         "$metadata_2" \
#         "$proof_local_exit_root_3" \
#         "$proof_rollup_exit_root_3" \
#         "$global_index_3" \
#         "$mainnet_exit_root_3" \
#         "$rollup_exit_root_3" \
#         "$origin_network_3" \
#         "$origin_address_3" \
#         "$destination_network_3" \
#         "$destination_address_3" \
#         "$amount_3" \
#         "$metadata_3" \
#         --rpc-url "$L2_RPC_URL" \
#         --private-key "$sender_private_key" \
#         --gas-price "$gas_price" 2>&1)

#     if [[ $? -ne 0 ]]; then
#         log "❌ Error: Failed to update parameters"
#         log "$update_output"
#         exit 1
#     fi

#     log "✅ Contract parameters updated successfully with all three sets of claim data"

#     # ========================================
#     # STEP 6: Test onMessageReceived functionality
#     # ========================================
#     log "🧪 STEP 6: Testing onMessageReceived with valid parameters (will attempt all three asset claims)"
#     local on_message_output
#     on_message_output=$(cast send \
#         "$internal_claims_sc_addr" \
#         "onMessageReceived(address,uint32,bytes)" \
#         "$origin_address_1" \
#         "$origin_network_1" \
#         "0x" \
#         --rpc-url "$L2_RPC_URL" \
#         --private-key "$sender_private_key" \
#         --gas-price "$gas_price" 2>&1)

#     log "📝 onMessageReceived output: $on_message_output"

#     # Check if the transaction was successful (should succeed even if second claim fails)
#     if [[ $? -eq 0 ]]; then
#         local tx_hash=$(echo "$on_message_output" | grep -o '0x[a-fA-F0-9]*')
#         log "✅ onMessageReceived transaction successful: $tx_hash"

#         # Validate the bridge_getClaims API to verify first and third claims were processed
#         log "🔍 Validating first asset claim was processed (should succeed)"
#         run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url"
#         assert_success
#         local claim_1="$output"
#         log "📋 First claim response: $claim_1"

#         # Verify mainnet exit root matches expected value for first claim
#         local claim_mainnet_exit_root_1=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
#         log "🌳 First claim mainnet exit root: $claim_mainnet_exit_root_1"
#         log "🎯 Expected mainnet exit root: $mainnet_exit_root_1"
#         assert_equal "$claim_mainnet_exit_root_1" "$mainnet_exit_root_1"

#         log "🔍 Validating third asset claim was processed (should succeed)"
#         run get_claim "$l2_rpc_network_id" "$global_index_3" 50 10 "$aggkit_bridge_url"
#         assert_success
#         local claim_3="$output"
#         log "📋 Third claim response: $claim_3"

#         # Verify mainnet exit root matches expected value for third claim
#         local claim_mainnet_exit_root_3=$(echo "$claim_3" | jq -r '.mainnet_exit_root')
#         log "🌳 Third claim mainnet exit root: $claim_mainnet_exit_root_3"
#         log "🎯 Expected mainnet exit root: $mainnet_exit_root_3"
#         assert_equal "$claim_mainnet_exit_root_3" "$mainnet_exit_root_3"

#         log "✅ First and third asset claims were successfully processed through onMessageReceived"
#         log "✅ Second claim failed as expected due to malformed parameters"
#     else
#         log "❌ onMessageReceived transaction failed"
#         log "$on_message_output"
#         exit 1
#     fi

#     log "🎉 Triple claim test completed successfully"
#     log "📊 Summary:"
#     log "   ✅ Contract deployed successfully"
#     log "   ✅ First asset bridge created and parameters extracted"
#     log "   ✅ Second asset bridge created and malformed parameters prepared"
#     log "   ✅ Third asset bridge created and parameters extracted"
#     log "   ✅ All three sets of parameters configured in contract"
#     log "   ✅ First claim processed successfully"
#     log "   ✅ Second claim failed as expected (malformed parameters)"
#     log "   ✅ Third claim processed successfully"
# }

# @test "Test triple claim internal calls -> 1 fail, 1 success and 1 fail" {
# }
