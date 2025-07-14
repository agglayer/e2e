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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    echo "=== Running L2 gas token ($native_token_addr) deposit to L1 network" >&3
    destination_addr=$sender_addr
    destination_net=0
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
}

# Bridge asset A -> Claim asset A -> Bridge asset B -> Claim asset B
@test "Bridge asset A -> Claim asset A -> Bridge asset B -> Claim asset B" {
    # Deploy first ERC20 token (Asset A)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_a=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address A: $l1_erc20_addr_a"

    # Deploy second ERC20 token (Asset B)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_b=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address B: $l1_erc20_addr_b"

    # Mint and Approve ERC20 tokens on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    
    # Mint and approve Asset A
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_a" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Mint and approve Asset B
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_b" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge Asset A from L1 to L2
    echo "==== 🚀 Depositing ERC20 token A on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr_a" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_a=$output

    # Claim Asset A on L2
    echo "==== 🔐 Claiming deposit A on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_a" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset A
    run wait_for_expected_token "$l1_erc20_addr_a" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_a=$output
    local l2_token_addr_a=$(echo "$token_mappings_result_a" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr A: $l2_token_addr_a" >&3

    # Verify balance of Asset A on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_a" "$receiver" 0 "$tokens_amount"
    assert_success

    # Bridge Asset B from L1 to L2
    echo "==== 🚀 Depositing ERC20 token B on L1 ($l1_rpc_url)" >&3
    run bridge_asset "$l1_erc20_addr_b" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_b=$output

    # Claim Asset B on L2
    echo "==== 🔐 Claiming deposit B on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_b" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset B
    run wait_for_expected_token "$l1_erc20_addr_b" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_b=$output
    local l2_token_addr_b=$(echo "$token_mappings_result_b" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr B: $l2_token_addr_b" >&3

    # Verify balance of Asset B on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_b" "$receiver" 0 "$tokens_amount"
    assert_success
}

# Bridge A -> Bridge B -> Claim A -> Claim B
@test "Bridge A -> Bridge B -> Claim A -> Claim B" {
    # Deploy first ERC20 token (Asset A)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_a=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address A: $l1_erc20_addr_a"

    # Deploy second ERC20 token (Asset B)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_b=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address B: $l1_erc20_addr_b"

    # Mint and Approve ERC20 tokens on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    
    # Mint and approve Asset A
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_a" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Mint and approve Asset B
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_b" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge Asset A from L1 to L2
    echo "==== 🚀 Depositing ERC20 token A on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr_a" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_a=$output

    # Bridge Asset B from L1 to L2
    echo "==== 🚀 Depositing ERC20 token B on L1 ($l1_rpc_url)" >&3
    run bridge_asset "$l1_erc20_addr_b" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_b=$output

    # Claim Asset A on L2
    echo "==== 🔐 Claiming deposit A on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_a" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset A
    run wait_for_expected_token "$l1_erc20_addr_a" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_a=$output
    local l2_token_addr_a=$(echo "$token_mappings_result_a" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr A: $l2_token_addr_a" >&3

    # Verify balance of Asset A on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_a" "$receiver" 0 "$tokens_amount"
    assert_success

    # Claim Asset B on L2
    echo "==== 🔐 Claiming deposit B on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_b" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset B
    run wait_for_expected_token "$l1_erc20_addr_b" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_b=$output
    local l2_token_addr_b=$(echo "$token_mappings_result_b" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr B: $l2_token_addr_b" >&3

    # Verify balance of Asset B on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_b" "$receiver" 0 "$tokens_amount"
    assert_success
}

# Bridge A -> Bridge B -> Claim B -> Claim A
@test "Bridge A -> Bridge B -> Claim B -> Claim A" {
    # Deploy first ERC20 token (Asset A)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_a=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address A: $l1_erc20_addr_a"

    # Deploy second ERC20 token (Asset B)
    run deploy_contract $l1_rpc_url $sender_private_key $erc20_artifact_path
    assert_success
    local l1_erc20_addr_b=$(echo "$output" | tail -n 1)
    log "📜 ERC20 contract address B: $l1_erc20_addr_b"

    # Mint and Approve ERC20 tokens on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    
    # Mint and approve Asset A
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_a" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Mint and approve Asset B
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$l1_erc20_addr_b" "$sender_private_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # Bridge Asset A from L1 to L2
    echo "==== 🚀 Depositing ERC20 token A on L1 ($l1_rpc_url)" >&3
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit $tokens_amount wei)
    meta_bytes="0x"
    run bridge_asset "$l1_erc20_addr_a" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_a=$output

    # Bridge Asset B from L1 to L2
    echo "==== 🚀 Depositing ERC20 token B on L1 ($l1_rpc_url)" >&3
    run bridge_asset "$l1_erc20_addr_b" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_b=$output

    # Claim Asset B on L2 (claiming B first)
    echo "==== 🔐 Claiming deposit B on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_b" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset B
    run wait_for_expected_token "$l1_erc20_addr_b" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_b=$output
    local l2_token_addr_b=$(echo "$token_mappings_result_b" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr B: $l2_token_addr_b" >&3

    # Verify balance of Asset B on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_b" "$receiver" 0 "$tokens_amount"
    assert_success

    # Claim Asset A on L2 (claiming A second)
    echo "==== 🔐 Claiming deposit A on L2 ($L2_RPC_URL)" >&3
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash_a" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL"

    # Wait for token mapping for Asset A
    run wait_for_expected_token "$l1_erc20_addr_a" "$l2_rpc_network_id" 50 10 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result_a=$output
    local l2_token_addr_a=$(echo "$token_mappings_result_a" | jq -r '.token_mappings[0].wrapped_token_address')
    echo "L2 token addr A: $l2_token_addr_a" >&3

    # Verify balance of Asset A on L2
    run verify_balance "$L2_RPC_URL" "$l2_token_addr_a" "$receiver" 0 "$tokens_amount"
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
