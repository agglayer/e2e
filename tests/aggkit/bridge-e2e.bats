setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Transfer message" {
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "====== claimMessage (L2)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    echo "====== bridgeMessage L2 -> L1" >&3
    destination_net=0
    run bridge_message "$destination_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

@test "ERC20 token deposit L1 -> L2" {
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l1_erc20_addr"

    # Mint and Approve ERC20 token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Assert that balance of ERC20 token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_erc20_token_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    echo "Sender balance ($sender_addr) (ERC20 token L1): $l1_erc20_token_sender_balance [weis]" >&3

    # DEPOSIT ON L1
    echo "==== 🚀 Depositing ERC20 token on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # CLAIM (settle deposit on L2)
    echo "==== 🔐 Claiming deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success

    # -----------------------------------------------------------------------------
    # Attempt a second “claim” on L2 — this should fail because it’s already been claimed
    # -----------------------------------------------------------------------------
    echo "==== 🔐 Claiming deposit on L2 again (${L2_RPC_URL}) — expected to fail (already claimed)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    log "💡 duplicate process_bridge_claim returns $output"
    assert_success

    # verify balance did not changed on L2
    ether_amount=$(echo "$tokens_amount" | sed 's/ether//')
    local receiver_balance_after_claim_wei=$(cast --to-wei "$ether_amount")
    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" "$receiver_balance_after_claim_wei" "0ether"
    assert_success

    # check that the sender’s ERC-20 balance on L1 remains unchanged
    run query_contract "$l1_rpc_url" "$l1_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_erc20_token_sender_balance_after_duplicate_claim=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    echo "Sender balance ($sender_addr) (ERC20 token L1) after duplicate claim: $l1_erc20_token_sender_balance_after_duplicate_claim [weis]" >&3
    # Assert it stayed at zero (because it was already claimed)
    assert_equal "$l1_erc20_token_sender_balance_after_duplicate_claim" 0
}

@test "Native token transfer L1 -> L2" {
    destination_addr=$sender_addr
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 "$initial_receiver_balance" eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the L2)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    sender_balance_after_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after claim "$sender_balance_after_claim" eth" >&3

    # verify receiver balance changed on L2
    local final_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Final receiver balance of native token on L2 "$final_receiver_balance" eth" >&3
    initial_receiver_balance_wei=$(cast --to-wei "$initial_receiver_balance")
    run verify_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr" "$initial_receiver_balance_wei" "$ether_value"
    assert_success

    # Attempt a second claim on L2 — this should fail because it’s already been claimed
    echo "==== 🔐 Claiming deposit on L2 again (${L2_RPC_URL}) — expected to fail (already claimed)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    log "💡 duplicate process_bridge_claim returns $output"
    assert_success

    # verify balance did not changed on L1 after duplicate claim
    sender_balance_after_duplicate_claim=$(get_token_balance "$l1_rpc_url" "$native_token_addr" "$destination_addr")
    log "Sender balance of native token on L1 after duplicate claim "$sender_balance_after_duplicate_claim" eth" >&3
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

@test "Bridge message A → Bridge asset B → Claim asset A → Claim message B" {
    # Step 1: Bridge message L1 -> L2
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=0
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_message_tx_hash=$output

    # Step 2: Deploy and bridge ERC20 token L1 -> L2
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l1_erc20_addr"

    # Mint and Approve ERC20 token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge ERC20 token
    echo "==== 🚀 Depositing ERC20 token on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_asset_tx_hash=$output

    # Step 3: Claim the bridged asset on L2
    echo "==== 🔐 Claiming asset deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_asset_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    # Verify the ERC20 token was bridged correctly
    run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success

    # Step 4: Claim the bridged message on L2
    echo "====== claimMessage (L2)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_message_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success
}

@test "Bridge message A → Bridge asset B → Claim message A → Claim asset B" {
    # Step 1: Bridge message L1 -> L2
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=0
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_message_tx_hash=$output

    # Step 2: Deploy and bridge ERC20 token L1 -> L2
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l1_erc20_addr"

    # Mint and Approve ERC20 token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge ERC20 token
    echo "==== 🚀 Depositing ERC20 token on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_asset_tx_hash=$output

    # Step 3: Claim the bridged message on L2 first
    echo "====== claimMessage (L2)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_message_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    # Step 4: Claim the bridged asset on L2
    echo "==== 🔐 Claiming asset deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_asset_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    # Verify the ERC20 token was bridged correctly
    run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success
}

@test "Bridge message A → Claim message A → Bridge asset B → Claim asset B" {
    # Step 1: Bridge message L1 -> L2
    echo "====== bridgeMessage L1 -> L2" >&3
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=0
    run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_message_tx_hash=$output

    # Step 2: Claim the bridged message on L2
    echo "====== claimMessage (L2)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_message_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    # Step 3: Deploy and bridge ERC20 token L1 -> L2
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address: $l1_erc20_addr"

    # Mint and Approve ERC20 token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge ERC20 token
    echo "==== 🚀 Depositing ERC20 token on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_asset_tx_hash=$output

    # Step 4: Claim the bridged asset on L2
    echo "==== 🔐 Claiming asset deposit on L2 ($L2_RPC_URL)" >&3
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_asset_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"
    assert_success

    # Verify the ERC20 token was bridged correctly
    run wait_for_expected_token "$l1_erc20_addr" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l1_erc20_addr" "$origin_token_addr"

    local l2_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr $l2_token_addr" >&3

    run verify_balance "$L2_RPC_URL" "$l2_token_addr" "$receiver" 0 "$tokens_amount"
    assert_success
}

@test "Native token transfer L1 -> L2 - manipulated global index" {
    destination_addr=$sender_addr
    local initial_receiver_balance=$(get_token_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr")
    echo "Initial receiver balance of native token on L2 "$initial_receiver_balance" eth" >&3

    echo "=== Running L1 native token deposit to L2 network $l2_rpc_network_id (native_token: $native_token_addr)" >&3
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (claim will fail because global index is manipulated)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "true"
    assert_success
}
