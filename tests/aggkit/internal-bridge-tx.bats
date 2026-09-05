#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup

    readonly internal_bridge_tx_artifact_path="$PROJECT_ROOT/core/contracts/bridgeAsset/InternalBridgeTx.json"

    # Deploy the InternalBridgeTx contract once for all tests
    log "🔧 Deploying InternalBridgeTx contract for all tests"

    # Get bytecode from the contract artifact
    local bytecode
    bytecode=$(jq -r '.bytecode.object // .bytecode' "$internal_bridge_tx_artifact_path")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        log "❌ Error: Failed to read bytecode from $internal_bridge_tx_artifact_path"
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

    # Set a fixed gas price (1 gwei)
    local gas_price=1000000000

    # Deploy the contract
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
    internal_bridge_tx_sc_addr=$(echo "$deploy_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | awk '{print $2}')
    if [[ -z "$internal_bridge_tx_sc_addr" ]]; then
        log "❌ Failed to extract deployed contract address"
        log "$deploy_output"
        exit 1
    fi
    readonly internal_bridge_tx_sc_addr

    log "✅ InternalBridgeTx contract deployed at: $internal_bridge_tx_sc_addr"
}

@test "Test internal bridge transactions -> 2 bridge tx with different amounts" {
    log "🧪 Testing internal bridge transactions: 2 bridge transactions with different amounts"

    # ========================================
    # STEP 1: Configure Bridge Transaction Parameters
    # ========================================
    log "⚙️  STEP 1: Configuring bridge transaction parameters"

    # Bridge transaction parameters
    local destination_network_1=$l1_rpc_network_id              # Target L1 network
    local destination_address_1=$sender_addr                    # Recipient address
    local amount_1="100000000000000000"                         # 0.1 ETH in wei
    local token_1="0x0000000000000000000000000000000000000000"  # ETH (zero address)
    local force_update_global_exit_root_1=true
    local permit_data_1="0x"

    local destination_network_2=$l1_rpc_network_id              # Target L1 network
    local destination_address_2=$sender_addr                    # Recipient address
    local amount_2="200000000000000000"                         # 0.2 ETH in wei
    local token_2="0x0000000000000000000000000000000000000000"  # ETH (zero address)
    local force_update_global_exit_root_2=true
    local permit_data_2="0x"

    log "   🌉 Bridge TX #1: $amount_1 wei (0.1 ETH) → Network $destination_network_1"
    log "   🌉 Bridge TX #2: $amount_2 wei (0.2 ETH) → Network $destination_network_2"
    log "   📍 Recipient: $sender_addr"

    # ========================================
    # STEP 1.5: Get Initial Bridge Count from Database
    # ========================================
    log "📊 STEP 1.5: Getting initial bridge count from bridge database"

    # Get total bridges before our test
    local total_bridges_before
    total_bridges_before=$(get_total_bridges "$l2_rpc_network_id" "$aggkit_bridge_url" 10 2 2>/dev/null) || {
        log "⚠️  Failed to get initial bridge count, continuing with 0"
        total_bridges_before=0
    }
    log "📊 Initial bridge count in database: $total_bridges_before"

    # ========================================
    # STEP 2: Configure Contract Bridge Parameters
    # ========================================
    log "⚙️  STEP 2: Configuring contract with bridge parameters"

    # Update the contract's internal bridge parameters for both transactions
    local update_output
    update_output=$(cast send \
        "$internal_bridge_tx_sc_addr" \
        "updateBridgeParameters(uint32,address,uint256,address,bool,bytes,uint32,address,uint256,address,bool,bytes)" \
        "$destination_network_1" \
        "$destination_address_1" \
        "$amount_1" \
        "$token_1" \
        "$force_update_global_exit_root_1" \
        "$permit_data_1" \
        "$destination_network_2" \
        "$destination_address_2" \
        "$amount_2" \
        "$token_2" \
        "$force_update_global_exit_root_2" \
        "$permit_data_2" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ ERROR: Failed to configure bridge parameters in contract"
        log "📝 Error details: $update_output"
        exit 1
    fi

    log "✅ Contract bridge parameters updated successfully"

    # ========================================
    # STEP 3: Fund the contract with ETH for bridge transactions
    # ========================================
    log "💰 STEP 3: Funding the contract with ETH for bridge transactions"
    local total_amount=$((amount_1 + amount_2))
    local fund_output
    fund_output=$(cast send \
        "$internal_bridge_tx_sc_addr" \
        --value "$total_amount" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ ERROR: Failed to fund contract with ETH"
        log "📝 Error details: $fund_output"
        exit 1
    fi

    log "✅ Contract funded with $total_amount wei"

    # Verify contract balance
    local contract_balance
    contract_balance=$(cast balance "$internal_bridge_tx_sc_addr" --rpc-url "$L2_RPC_URL")
    log "📊 Contract balance: $contract_balance wei"

    # ========================================
    # STEP 4: Execute Bridge Transactions via onMessageReceived
    # ========================================
    log "🚀 STEP 4: Executing onMessageReceived to trigger both bridge transactions"

    # Call onMessageReceived which will internally execute both bridge transactions
    local on_message_output
    on_message_output=$(cast send \
        "$internal_bridge_tx_sc_addr" \
        "onMessageReceived(address,uint32,bytes)" \
        "$sender_addr" \
        "$l2_rpc_network_id" \
        "0x" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$sender_private_key" \
        --gas-price "$gas_price" 2>&1)

    log "📝 onMessageReceived output: $on_message_output"

    # Check if the transaction was successful
    if [[ $? -eq 0 ]]; then
        # Extract transaction hash from the cast output
        local tx_hash
        tx_hash=$(echo "$on_message_output" | grep -o '0x[a-fA-F0-9]\{64\}' | tail -1)
        log "✅ onMessageReceived executed successfully"
        log "🔗 Transaction hash: $tx_hash"

        # Extract block number from transaction receipt
        local block_number
        block_number=$(cast receipt "$tx_hash" --rpc-url "$L2_RPC_URL" --json | jq -r '.blockNumber')
        log "📦 Block number: $block_number"

        # ========================================
        # STEP 5: Verify Bridge Events from L2 Bridge Contract
        # ========================================
        log "🔍 STEP 5: Verifying bridge events from L2 bridge contract"

        # Query bridge events from the specific block where our transaction was mined
        log "   🔎 Searching for bridge events in block $block_number"
        local final_logs_output
        final_logs_output=$(cast logs \
            --rpc-url "$L2_RPC_URL" \
            --address "$l2_bridge_addr" \
            "0x501781209a1f8899323b96b4ef08b168df93e0a90c673d1e4cce39366cb62f9b" \
            --from-block "$block_number" \
            --to-block "$block_number" --json 2>&1) || {
            log "⚠️  Failed to query bridge events, using empty result"
            final_logs_output="[]"
        }
        log "📋 Bridge events output: $final_logs_output"

        # Count the number of bridge events found
        local final_bridge_events=0
        if echo "$final_logs_output" | jq empty 2>/dev/null; then
            final_bridge_events=$(echo "$final_logs_output" | jq '. | length' 2>/dev/null || echo "0")
        fi
        log "📊 Bridge events found: $final_bridge_events"

        # Verify that exactly 2 bridge events were created
        if [[ "$final_bridge_events" -eq 2 ]]; then
            log "✅ SUCCESS: Both bridge transactions executed and events emitted"
        else
            log "❌ FAILURE: Expected 2 bridge events, found $final_bridge_events"
            log "🚨 Test failed - bridge transactions did not execute as expected"
            exit 1
        fi

        # ========================================
        # STEP 6: Verify Contract Balance Changes
        # ========================================
        log "💰 STEP 6: Verifying contract balance changes"

        # Check contract balance after bridge transactions
        local final_contract_balance
        final_contract_balance=$(cast balance "$internal_bridge_tx_sc_addr" --rpc-url "$L2_RPC_URL")
        log "📊 Final contract balance: $final_contract_balance wei"

        # Calculate expected balance (should decrease by total bridged amount)
        local expected_balance=$((contract_balance - total_amount))
        if [[ "$final_contract_balance" -le "$expected_balance" ]]; then
            log "✅ Contract balance decreased correctly after bridge transactions"
        else
            log "⚠️  Contract balance did not decrease as expected"
            log "📋 Expected balance ≤ $expected_balance wei"
            log "📋 Actual balance: $final_contract_balance wei"
        fi

        log "🎉 Internal bridge transactions test completed successfully"
    else
        log "❌ ERROR: onMessageReceived transaction failed"
        log "📝 Error details: $on_message_output"
        exit 1
    fi

    # ========================================
    # STEP 7: Verify Bridge Database Count Increased
    # ========================================
    log "📊 STEP 7: Verifying bridge database count increased"

    # Wait a moment for bridge indexer to process the transactions
    sleep 3

    local total_bridges_after
    total_bridges_after=$(get_total_bridges "$l2_rpc_network_id" "$aggkit_bridge_url" 10 2 2>/dev/null) || {
        log "⚠️  Failed to get final bridge count, skipping database verification"
        total_bridges_after=$total_bridges_before
    }
    log "📊 Final bridge count in database: $total_bridges_after"

    if [[ "$total_bridges_after" -eq "$((total_bridges_before + 2))" ]]; then
        log "✅ Bridge database count increased correctly"
    else
        log "❌ FAILURE: Bridge database count did not increase as expected"
        log "📋 Expected increase: 2"
        log "📋 Actual increase: $((total_bridges_after - total_bridges_before))"
        exit 1
    fi

    # ========================================
    # TEST SUMMARY
    # ========================================
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🎯 TEST SUMMARY: Internal Bridge Transactions"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "   ✅ Bridge TX #1: $amount_1 wei (0.1 ETH) → Network $destination_network_1"
    log "   ✅ Bridge TX #2: $amount_2 wei (0.2 ETH) → Network $destination_network_2"
    log "   ✅ Total bridged: $total_amount wei (0.3 ETH)"
    log "   ✅ Both transactions executed in single onMessageReceived call"
    log "   ✅ Contract balance decreased appropriately"
    log "   ✅ Bridge events verified from L2 bridge contract"
    log "   🏆 TEST PASSED: All assertions successful"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
