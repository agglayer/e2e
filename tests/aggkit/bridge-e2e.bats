#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "ERC20 token deposit L2 -> L1" {
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path
    assert_success
    local l2_erc20_addr
    l2_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l2_erc20_addr"

    # Mint and Approve ERC20 tokens on L2
    local tokens_amount="10ether"
    local wei_amount
    wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$L2_RPC_URL" "$l2_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l2_bridge_addr"
    assert_success

    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "allowance(address owner, address spender)(uint256)" "$sender_addr" "$l2_bridge_addr"
    assert_success
    log "🔐 Allowance for bridge contract: $output [weis]"

    # Assert that balance of ERC20 token (on the L2) is correct
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l2_erc20_token_sender_balance
    l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    # Deposit on L2
    echo "==== 🚀 Depositing ERC20 token on L2 ($L2_RPC_URL)" >&3
    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    tokens_amount="1ether"
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l2_erc20_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Query balance of ERC20 token on L2
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l2_erc20_token_sender_balance
    l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    # Claim deposit (settle it on the L1)
    echo "==== 🔐 Claiming ERC20 token deposit on L1 ($l1_rpc_url)" >&3
    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url" "$sender_addr"
    assert_success

    run wait_for_expected_token "$l2_erc20_addr" "$l1_rpc_network_id" 30 2 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr
    origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l2_erc20_addr" "$origin_token_addr"

    local l1_wrapped_token_addr
    l1_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 L1 wrapped token address $l1_wrapped_token_addr"

    run verify_balance "$l1_rpc_url" "$l1_wrapped_token_addr" "$destination_addr" 0 "$tokens_amount"
    assert_success

    # Send approve transaction to the ERC20 token on L1
    tokens_amount="1ether"
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_wrapped_token_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Deposit the L1 wrapped token (bridge L1 -> L2)
    echo "==== 🚀 Depositing L1 wrapped token on L1 ($l1_rpc_url)" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_wrapped_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    echo "==== 🔐 Claiming deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    echo "==== 💰 Verifying balance on L2 ($L2_RPC_URL)" >&3
    run verify_balance "$L2_RPC_URL" "$l2_erc20_addr" "$destination_addr" "$l2_erc20_token_sender_balance" "$tokens_amount"
    assert_success

    # Query balance of ERC20 token on L1
    run query_contract "$l1_rpc_url" "$l1_wrapped_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_wrapped_token_balance
    l1_wrapped_token_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (wrapped ERC20 token L1): $l1_wrapped_token_balance [weis]"

    # Deposit on L2
    echo "==== 🚀 Depositing ERC20 token on L2 ($L2_RPC_URL)" >&3
    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    tokens_amount="1ether"
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l2_erc20_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    bridge_tx_hash=$output

    # Claim deposit (settle it on the L1)
    echo "==== 🔐 Claiming ERC20 token deposit on L1 ($l1_rpc_url)" >&3
    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url"
    assert_success

    echo "==== 💰 Verifying balance on L1 ($l1_rpc_url)" >&3
    run verify_balance "$l1_rpc_url" "$l1_wrapped_token_addr" "$destination_addr" "$l1_wrapped_token_balance" "$tokens_amount"
    assert_success
}


@test "Transfer message" {
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "====== claimMessage (L2)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    echo "====== bridgeMessage L2 -> L1" >&3
    destination_net=0
    run bridge_message "$destination_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "ERC20 token deposit L2 -> L1" {
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path
    assert_success
    local l2_erc20_addr
    l2_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l2_erc20_addr"

    # Mint and Approve ERC20 tokens on L2
    local tokens_amount="10ether"
    local wei_amount
    wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$L2_RPC_URL" "$l2_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l2_bridge_addr"
    assert_success

    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "allowance(address owner, address spender)(uint256)" "$sender_addr" "$l2_bridge_addr"
    assert_success
    log "🔐 Allowance for bridge contract: $output [weis]"

    # Assert that balance of ERC20 token (on the L2) is correct
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l2_erc20_token_sender_balance
    l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    # Deposit on L2
    echo "==== 🚀 Depositing ERC20 token on L2 ($L2_RPC_URL)" >&3
    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    tokens_amount="1ether"
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l2_erc20_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Query balance of ERC20 token on L2
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l2_erc20_token_sender_balance
    l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    echo "=== 🪤 Running L1 bridge to update l1infotree (sleep 300 secs)" >&3
    run update_l1_info_tree 300
    assert_success
    

    # Claim deposit (settle it on the L1)
    echo "==== 🔐 Claiming ERC20 token deposit on L1 ($l1_rpc_url)" >&3
    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url" "$sender_addr"
    assert_success

    run wait_for_expected_token "$l2_erc20_addr" "$l1_rpc_network_id" 30 2 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr
    origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l2_erc20_addr" "$origin_token_addr"

    local l1_wrapped_token_addr
    l1_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 L1 wrapped token address $l1_wrapped_token_addr"

    run verify_balance "$l1_rpc_url" "$l1_wrapped_token_addr" "$destination_addr" 0 "$tokens_amount"
    assert_success

    # Send approve transaction to the ERC20 token on L1
    tokens_amount="1ether"
    run send_tx "$l1_rpc_url" "$sender_private_key" "$l1_wrapped_token_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Deposit the L1 wrapped token (bridge L1 -> L2)
    echo "==== 🚀 Depositing L1 wrapped token on L1 ($l1_rpc_url)" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_wrapped_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    echo "==== 🔐 Claiming deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    echo "==== 💰 Verifying balance on L2 ($L2_RPC_URL)" >&3
    run verify_balance "$L2_RPC_URL" "$l2_erc20_addr" "$destination_addr" "$l2_erc20_token_sender_balance" "$tokens_amount"
    assert_success

    # Query balance of ERC20 token on L1
    run query_contract "$l1_rpc_url" "$l1_wrapped_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_wrapped_token_balance
    l1_wrapped_token_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (wrapped ERC20 token L1): $l1_wrapped_token_balance [weis]"

    # Deposit on L2
    echo "==== 🚀 2nd: Depositing ERC20 token on L2 ($L2_RPC_URL)" >&3
    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    tokens_amount="1ether"
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l2_erc20_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    bridge_tx_hash=$output

     echo "=== 🪤 2nd: Running L1 bridge to update l1infotree (sleep 500 secs)" >&3
    run update_l1_info_tree 500
    assert_success

    # Claim deposit (settle it on the L1)
    echo "==== 🔐 2nd: Claiming ERC20 token deposit on L1 ($l1_rpc_url)" >&3
    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url"
    assert_success

    echo "==== 💰 2nd: Verifying balance on L1 ($l1_rpc_url)" >&3
    run verify_balance "$l1_rpc_url" "$l1_wrapped_token_addr" "$destination_addr" "$l1_wrapped_token_balance" "$tokens_amount"
    assert_success
}




@test "Native token transfer L1 -> L2" {
    destination_addr=$receiver
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    assert_success

    sender_balance_after_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after claim $sender_balance_after_claim eth" >&3

    # verify receiver balance changed on L2
    local final_receiver_balance
    final_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Final receiver balance of native token on L2 $final_receiver_balance eth" >&3
    initial_receiver_balance_wei=$(cast --to-wei "$initial_receiver_balance")
    run verify_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr" "$initial_receiver_balance_wei" "$ether_value"
    assert_success

    # Attempt a second claim on L2 — this should fail because it's already been claimed
    echo "==== 🔐 Claiming deposit on L2 again (${L2_RPC_URL}) — expected to fail (already claimed)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
    log "💡 duplicate process_bridge_claim returns $output"
    assert_success

    # verify balance did not changed on L1 after duplicate claim
    sender_balance_after_duplicate_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after duplicate claim $sender_balance_after_duplicate_claim eth" >&3
    assert_equal "$sender_balance_after_claim" "$sender_balance_after_duplicate_claim"

    # verify balance did not changed on L2 after duplicate claim
    final_receiver_balance_wei=$(cast --to-wei "$final_receiver_balance")
    run verify_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr" "$final_receiver_balance_wei" "0ether"
    assert_success

    echo "=== Running L2 gas token ($native_token_addr) deposit to L1 network" >&3
    destination_addr=$sender_addr
    destination_net=0
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "Native token transfer L1 -> L2 - manipulated global index" {
    destination_addr=$sender_addr
    local initial_receiver_balance
    initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (claim will fail because global index is manipulated)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "true" "$sender_addr"
    assert_success
}
