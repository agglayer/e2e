#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup

    readonly internal_claims_artifact_path="$PROJECT_ROOT/core/contracts/bridgeAsset/InternalClaims.json"

    # Deploy the InternalClaims contract once for all tests
    log "🔧 Deploying InternalClaims contract for all tests"

    # Get bytecode from the contract artifact
    local bytecode
    bytecode=$(jq -r '.bytecode.object // .bytecode' "$internal_claims_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $internal_claims_artifact_path"
        exit 1
    fi

    # ABI-encode the constructor argument (bridge address)
    local encoded_args
    encoded_args=$(cast abi-encode "constructor(address)" "$l2_bridge_addr")
    if [[ -z "$encoded_args" ]]; then
        log "❌ Failed to ABI-encode constructor argument"
        exit 1
    fi

    # Concatenate bytecode and encoded constructor args
    local deploy_bytecode="${bytecode}${encoded_args:2}" # Remove 0x from encoded args

    # Deploy the contract
    local deploy_output
    deploy_output=$(cast send --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --create "$deploy_bytecode" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to deploy contract"
        log "$deploy_output"
        exit 1
    fi

    # Extract contract address from output
    internal_claim_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$internal_claim_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi
    readonly internal_claim_sc_addr

    log "✅ InternalClaims contract deployed at: $internal_claim_sc_addr"
}

@test "Test triple claim internal calls -> 3 success" {
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

    # Extract claim parameters for first asset
    local claim_params_1
    claim_params_1=$(extract_claim_parameters_json "$bridge_tx_hash_1" "first" "$sender_addr")
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


    # ========================================
    # STEP X: Bridge some random assets
    # ========================================
    log "🌉 STEP X: Bridging third asset from L1 to L2"

    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success


    # ========================================
    # STEP 2: Bridge second asset and get all claim parameters
    # ========================================
    log "🌉 STEP 2: Bridging second asset from L1 to L2"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_2=$output
    log "🌉 Second bridge asset transaction hash: $bridge_tx_hash_2"

    # Extract claim parameters for second asset
    local claim_params_2
    claim_params_2=$(extract_claim_parameters_json "$bridge_tx_hash_2" "second" "$sender_addr")
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

    # ========================================
    # STEP 3: Bridge third asset and get all claim parameters
    # ========================================
    log "🌉 STEP 4: Bridging third asset from L1 to L2"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_3=$output
    log "🌉 Third bridge asset transaction hash: $bridge_tx_hash_3"

    # Extract claim parameters for third asset
    local claim_params_3
    claim_params_3=$(extract_claim_parameters_json "$bridge_tx_hash_3" "third" "$sender_addr")
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

    log "✅ Third asset claim parameters extracted successfully"

    # ========================================
    # STEP 4: Bridge fourth asset
    # ========================================
    log "🌉 STEP 4: Bridging fourth asset from L1 to L2"
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_4=$output
    log "🌉 Fourth bridge asset transaction hash: $bridge_tx_hash_4"

    # Extract claim parameters for fourth asset
    local claim_params_4
    claim_params_4=$(extract_claim_parameters_json "$bridge_tx_hash_4" "fourth" "$sender_addr")
    local proof_local_exit_root_4
    proof_local_exit_root_4=$(echo "$claim_params_4" | jq -r '.proof_local_exit_root')
    local proof_rollup_exit_root_4
    proof_rollup_exit_root_4=$(echo "$claim_params_4" | jq -r '.proof_rollup_exit_root')
    local global_index_4
    global_index_4=$(echo "$claim_params_4" | jq -r '.global_index')
    local mainnet_exit_root_4
    mainnet_exit_root_4=$(echo "$claim_params_4" | jq -r '.mainnet_exit_root')
    local rollup_exit_root_4
    rollup_exit_root_4=$(echo "$claim_params_4" | jq -r '.rollup_exit_root')
    local origin_network_4
    origin_network_4=$(echo "$claim_params_4" | jq -r '.origin_network')
    local origin_address_4
    origin_address_4=$(echo "$claim_params_4" | jq -r '.origin_address')
    local destination_network_4
    destination_network_4=$(echo "$claim_params_4" | jq -r '.destination_network')
    local destination_address_4
    destination_address_4=$(echo "$claim_params_4" | jq -r '.destination_address')
    local amount_4
    amount_4=$(echo "$claim_params_4" | jq -r '.amount')
    local metadata_4
    metadata_4=$(echo "$claim_params_4" | jq -r '.metadata')

    log "✅ Fourth asset claim parameters extracted successfully"

    # ========================================
    # STEP 5: Update contract with all four sets of claim parameters
    # ========================================
    log "⚙️ STEP 5: Updating contract parameters with all four sets of claim data"
    local update_output
    update_output=$(cast send \
        "$internal_claim_sc_addr" \
        "updateParameters(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes,bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
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
        "$proof_local_exit_root_4" \
        "$proof_rollup_exit_root_4" \
        "$global_index_4" \
        "$mainnet_exit_root_4" \
        "$rollup_exit_root_4" \
        "$origin_network_4" \
        "$origin_address_4" \
        "$destination_network_4" \
        "$destination_address_4" \
        "$amount_4" \
        "$metadata_4" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to update parameters"
        log "$update_output"
        exit 1
    fi

    log "✅ Contract parameters updated successfully with all four sets of claim data"

    # ========================================
    # STEP 6: Test onMessageReceived functionality
    # ========================================
    log "🧪 STEP 6: Testing onMessageReceived with valid parameters (will attempt all four asset claims)"
    local on_message_output
    on_message_output=$(cast send \
        "$internal_claim_sc_addr" \
        "onMessageReceived(address,uint32,bytes)" \
        "$origin_address_1" \
        "$origin_network_1" \
        "0x" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" 2>&1)

    log "📝 onMessageReceived output: $on_message_output"

    # Check if the transaction was successful
    if [[ $? -eq 0 ]]; then
        local tx_hash
        tx_hash=$(echo "$on_message_output" | grep -o '0x[a-fA-F0-9]*')
        log "✅ onMessageReceived transaction successful: $tx_hash"

        # Validate the bridge service get claims API to verify all claims were processed
        log "🔍 Validating first asset claim was processed"
        log "Global index: $global_index_1"
        run get_claim "$l2_rpc_network_id" "$global_index_1" 50 10 "$aggkit_bridge_url" "$internal_claim_sc_addr"
        assert_success
        local claim_1="$output"
        log "📋 First claim response: $claim_1"

        # Validate all parameters for first claim
        log "🔍 Validating all parameters for first claim"
        local claim_1_mainnet_exit_root
        claim_1_mainnet_exit_root=$(echo "$claim_1" | jq -r '.mainnet_exit_root')
        local claim_1_rollup_exit_root
        claim_1_rollup_exit_root=$(echo "$claim_1" | jq -r '.rollup_exit_root')
        local claim_1_global_exit_root
        claim_1_global_exit_root=$(echo "$claim_1" | jq -r '.global_exit_root')
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
        local claim_1_proof_local_exit_root
        claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root')
        local claim_1_proof_rollup_exit_root
        claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root')

        local n_claim_1_proof_local_exit_root
        local n_proof_local_exit_root_1
        local n_claim_1_proof_rollup_exit_root
        local n_proof_rollup_exit_root_1
        n_claim_1_proof_local_exit_root=$(echo "$claim_1_proof_local_exit_root" | tr -d '[:space:]"')
        n_proof_local_exit_root_1=$(echo "$proof_local_exit_root_1" | tr -d '[:space:]"')
        n_claim_1_proof_rollup_exit_root=$(echo "$claim_1_proof_rollup_exit_root" | tr -d '[:space:]"')
        n_proof_rollup_exit_root_1=$(echo "$proof_rollup_exit_root_1" | tr -d '[:space:]"')

        log "🌳 First claim mainnet exit root: $claim_1_mainnet_exit_root (Expected: $mainnet_exit_root_1)"
        log "🌳 First claim rollup exit root: $claim_1_rollup_exit_root (Expected: $rollup_exit_root_1)"
        log "🌳 First claim global exit root: $claim_1_global_exit_root"
        log "🌐 First claim origin network: $claim_1_origin_network (Expected: $origin_network_1)"
        log "📍 First claim origin address: $claim_1_origin_address (Expected: $origin_address_1)"
        log "🌐 First claim destination network: $claim_1_destination_network (Expected: $destination_network_1)"
        log "📍 First claim destination address: $claim_1_destination_address (Expected: $destination_address_1)"
        log "💰 First claim amount: $claim_1_amount (Expected: $amount_1)"
        log "📄 First claim metadata: $claim_1_metadata (Expected: $metadata_1)"
        log "🌳 First claim proof_local_exit_root: $n_claim_1_proof_local_exit_root (Expected: $n_proof_local_exit_root_1)"
        log "🌳 First claim proof_rollup_exit_root: $n_claim_1_proof_rollup_exit_root (Expected: $n_proof_rollup_exit_root_1)"

        # Verify all field values match expected values
        assert_equal "$claim_1_mainnet_exit_root" "$mainnet_exit_root_1"
        assert_equal "$claim_1_rollup_exit_root" "$rollup_exit_root_1"
        assert_equal "$claim_1_origin_network" "$origin_network_1"
        assert_equal "$claim_1_origin_address" "$origin_address_1"
        assert_equal "$claim_1_destination_network" "$destination_network_1"
        assert_equal "$claim_1_destination_address" "$destination_address_1"
        assert_equal "$claim_1_amount" "$amount_1"
        assert_equal "$claim_1_metadata" "$metadata_1"
        assert_equal "$n_claim_1_proof_local_exit_root" "$n_proof_local_exit_root_1"
        assert_equal "$n_claim_1_proof_rollup_exit_root" "$n_proof_rollup_exit_root_1"

        # Validate proofs for first claim
        log "🔍 Validating proofs for first claim"
        local claim_1_proof_local_exit_root
        claim_1_proof_local_exit_root=$(echo "$claim_1" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_1_proof_rollup_exit_root
        claim_1_proof_rollup_exit_root=$(echo "$claim_1" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 First claim proof local exit root: $claim_1_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_1"
        log "🔐 First claim proof rollup exit root: $claim_1_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_1"

        # Verify proof values match expected values
        assert_equal "$claim_1_proof_local_exit_root" "$proof_local_exit_root_1"
        assert_equal "$claim_1_proof_rollup_exit_root" "$proof_rollup_exit_root_1"
        log "✅ First claim proofs validated successfully"
        log "✅ First claim all fields validated successfully"

        log "🔍 Validating second asset claim was processed"
        run get_claim "$l2_rpc_network_id" "$global_index_2" 50 10 "$aggkit_bridge_url" "$internal_claim_sc_addr"
        assert_success
        local claim_2="$output"
        log "📋 Second claim response: $claim_2"

        # Validate all parameters for second claim
        log "🔍 Validating all parameters for second claim"
        local claim_2_mainnet_exit_root
        claim_2_mainnet_exit_root=$(echo "$claim_2" | jq -r '.mainnet_exit_root')
        local claim_2_rollup_exit_root
        claim_2_rollup_exit_root=$(echo "$claim_2" | jq -r '.rollup_exit_root')
        local claim_2_global_exit_root
        claim_2_global_exit_root=$(echo "$claim_2" | jq -r '.global_exit_root')
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
        local claim_2_proof_local_exit_root
        claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root')
        local claim_2_proof_rollup_exit_root
        claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root')

        local n_claim_2_proof_local_exit_root
        local n_proof_local_exit_root_2
        local n_claim_2_proof_rollup_exit_root
        local n_proof_rollup_exit_root_2
        n_claim_2_proof_local_exit_root=$(echo "$claim_2_proof_local_exit_root" | tr -d '[:space:]"')
        n_proof_local_exit_root_2=$(echo "$proof_local_exit_root_2" | tr -d '[:space:]"')
        n_claim_2_proof_rollup_exit_root=$(echo "$claim_2_proof_rollup_exit_root" | tr -d '[:space:]"')
        n_proof_rollup_exit_root_2=$(echo "$proof_rollup_exit_root_2" | tr -d '[:space:]"')

        log "🌳 Second claim mainnet exit root: $claim_2_mainnet_exit_root (Expected: $mainnet_exit_root_2)"
        log "🌳 Second claim rollup exit root: $claim_2_rollup_exit_root (Expected: $rollup_exit_root_2)"
        log "🌳 Second claim global exit root: $claim_2_global_exit_root"
        log "🌐 Second claim origin network: $claim_2_origin_network (Expected: $origin_network_2)"
        log "📍 Second claim origin address: $claim_2_origin_address (Expected: $origin_address_2)"
        log "🌐 Second claim destination network: $claim_2_destination_network (Expected: $destination_network_2)"
        log "📍 Second claim destination address: $claim_2_destination_address (Expected: $destination_address_2)"
        log "💰 Second claim amount: $claim_2_amount (Expected: $amount_2)"
        log "📄 Second claim metadata: $claim_2_metadata (Expected: $metadata_2)"
        log "🌳 Second claim proof_local_exit_root: $n_claim_2_proof_local_exit_root (Expected: $n_proof_local_exit_root_2)"
        log "🌳 Second claim proof_rollup_exit_root: $n_claim_2_proof_rollup_exit_root (Expected: $n_proof_rollup_exit_root_2)"

        # Verify all field values match expected values
        assert_equal "$claim_2_mainnet_exit_root" "$mainnet_exit_root_2"
        assert_equal "$claim_2_rollup_exit_root" "$rollup_exit_root_2"
        assert_equal "$claim_2_origin_network" "$origin_network_2"
        assert_equal "$claim_2_origin_address" "$origin_address_2"
        assert_equal "$claim_2_destination_network" "$destination_network_2"
        assert_equal "$claim_2_destination_address" "$destination_address_2"
        assert_equal "$claim_2_amount" "$amount_2"
        assert_equal "$claim_2_metadata" "$metadata_2"
        assert_equal "$n_claim_2_proof_local_exit_root" "$n_proof_local_exit_root_2"
        assert_equal "$n_claim_2_proof_rollup_exit_root" "$n_proof_rollup_exit_root_2"

        # Validate proofs for second claim
        log "🔍 Validating proofs for second claim"
        local claim_2_proof_local_exit_root
        claim_2_proof_local_exit_root=$(echo "$claim_2" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_2_proof_rollup_exit_root
        claim_2_proof_rollup_exit_root=$(echo "$claim_2" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 Second claim proof local exit root: $claim_2_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_2"
        log "🔐 Second claim proof rollup exit root: $claim_2_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_2"

        # Verify proof values match expected values
        assert_equal "$claim_2_proof_local_exit_root" "$proof_local_exit_root_2"
        assert_equal "$claim_2_proof_rollup_exit_root" "$proof_rollup_exit_root_2"
        log "✅ Second claim proofs validated successfully"
        log "✅ Second claim all fields validated successfully"

        log "🔍 Validating third asset claim was processed"
        run get_claim "$l2_rpc_network_id" "$global_index_3" 50 10 "$aggkit_bridge_url" "$internal_claim_sc_addr"
        assert_success
        local claim_3="$output"
        log "📋 Third claim response: $claim_3"

        # Validate all parameters for third claim
        log "🔍 Validating all parameters for third claim"
        local claim_3_mainnet_exit_root
        claim_3_mainnet_exit_root=$(echo "$claim_3" | jq -r '.mainnet_exit_root')
        local claim_3_rollup_exit_root
        claim_3_rollup_exit_root=$(echo "$claim_3" | jq -r '.rollup_exit_root')
        local claim_3_global_exit_root
        claim_3_global_exit_root=$(echo "$claim_3" | jq -r '.global_exit_root')
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
        local claim_3_proof_local_exit_root
        claim_3_proof_local_exit_root=$(echo "$claim_3" | jq -r '.proof_local_exit_root')
        local claim_3_proof_rollup_exit_root
        claim_3_proof_rollup_exit_root=$(echo "$claim_3" | jq -r '.proof_rollup_exit_root')

        local n_claim_3_proof_local_exit_root
        local n_proof_local_exit_root_3
        local n_claim_3_proof_rollup_exit_root
        local n_proof_rollup_exit_root_3
        n_claim_3_proof_local_exit_root=$(echo "$claim_3_proof_local_exit_root" | tr -d '[:space:]"')
        n_proof_local_exit_root_3=$(echo "$proof_local_exit_root_3" | tr -d '[:space:]"')
        n_claim_3_proof_rollup_exit_root=$(echo "$claim_3_proof_rollup_exit_root" | tr -d '[:space:]"')
        n_proof_rollup_exit_root_3=$(echo "$proof_rollup_exit_root_3" | tr -d '[:space:]"')

        log "🌳 Third claim mainnet exit root: $claim_3_mainnet_exit_root (Expected: $mainnet_exit_root_3)"
        log "🌳 Third claim rollup exit root: $claim_3_rollup_exit_root (Expected: $rollup_exit_root_3)"
        log "🌳 Third claim global exit root: $claim_3_global_exit_root"
        log "🌐 Third claim origin network: $claim_3_origin_network (Expected: $origin_network_3)"
        log "📍 Third claim origin address: $claim_3_origin_address (Expected: $origin_address_3)"
        log "🌐 Third claim destination network: $claim_3_destination_network (Expected: $destination_network_3)"
        log "📍 Third claim destination address: $claim_3_destination_address (Expected: $destination_address_3)"
        log "💰 Third claim amount: $claim_3_amount (Expected: $amount_3)"
        log "📄 Third claim metadata: $claim_3_metadata (Expected: $metadata_3)"
        log "🌳 Third claim proof_local_exit_root: $n_claim_3_proof_local_exit_root (Expected: $n_proof_local_exit_root_3)"
        log "🌳 Third claim proof_rollup_exit_root: $n_claim_3_proof_rollup_exit_root (Expected: $n_proof_rollup_exit_root_3)"

        # Verify all field values match expected values
        assert_equal "$claim_3_mainnet_exit_root" "$mainnet_exit_root_3"
        assert_equal "$claim_3_rollup_exit_root" "$rollup_exit_root_3"
        assert_equal "$claim_3_origin_network" "$origin_network_3"
        assert_equal "$claim_3_origin_address" "$origin_address_3"
        assert_equal "$claim_3_destination_network" "$destination_network_3"
        assert_equal "$claim_3_destination_address" "$destination_address_3"
        assert_equal "$claim_3_amount" "$amount_3"
        assert_equal "$claim_3_metadata" "$metadata_3"
        assert_equal "$n_claim_3_proof_local_exit_root" "$n_proof_local_exit_root_3"
        assert_equal "$n_claim_3_proof_rollup_exit_root" "$n_proof_rollup_exit_root_3"

        # Validate proofs for third claim
        log "🔍 Validating proofs for third claim"
        local claim_3_proof_local_exit_root
        claim_3_proof_local_exit_root=$(echo "$claim_3" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
        local claim_3_proof_rollup_exit_root
        claim_3_proof_rollup_exit_root=$(echo "$claim_3" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')

        log "🔐 Third claim proof local exit root: $claim_3_proof_local_exit_root"
        log "🔐 Expected proof local exit root: $proof_local_exit_root_3"
        log "🔐 Third claim proof rollup exit root: $claim_3_proof_rollup_exit_root"
        log "🔐 Expected proof rollup exit root: $proof_rollup_exit_root_3"

        # Verify proof values match expected values
        assert_equal "$claim_3_proof_local_exit_root" "$proof_local_exit_root_3"
        assert_equal "$claim_3_proof_rollup_exit_root" "$proof_rollup_exit_root_3"
        log "✅ Third claim proofs validated successfully"
        log "✅ Third claim all fields validated successfully"
        log "✅ All four asset claims were successfully processed through onMessageReceived"
        log "✅ All parameters validated successfully for all four claims"
    else
        log "❌ onMessageReceived transaction failed"
        log "$on_message_output"
        exit 1
    fi

    log "🎉 Test triple claim internal calls -> 3 success completed successfully"
    log "📊 Summary:"
    log "   ✅ First asset bridge created and parameters extracted"
    log "   ✅ Second asset bridge created and parameters extracted"
    log "   ✅ Third asset bridge created and parameters extracted"
    log "   ✅ Fourth asset bridge created and parameters extracted"
    log "   ✅ All four sets of parameters configured in contract"
    log "   ✅ All asset claims processed successfully"
    log "   ✅ All parameters validated successfully for all claims"
}
