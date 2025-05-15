setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

@test "Custom gas token deposit L1 -> L2" {
    echo "Custom gas token deposit (gas token addr: $gas_token_addr, L1 RPC: $l1_rpc_url, L2 RPC: $L2_RPC_URL)" >&3

    # SETUP
    # Set receiver address and query for its initial native token balance on the L2
    local initial_receiver_balance=$(cast balance "$receiver" --rpc-url "$L2_RPC_URL")
    echo "Initial receiver ($receiver) balance of native token on L2 $initial_receiver_balance" >&3

    local l1_minter_balance=$(cast balance "0x8943545177806ED17B9F23F0a21ee5948eCaa776" --rpc-url "$l1_rpc_url")
    echo "Initial minter balance on L1 $l1_minter_balance" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance" of gas token on L1 >&3

    # Mint gas token on L1
    local tokens_amount="0.1ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    local minter_key=${MINTER_KEY:-"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"}
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$gas_token_addr" "$minter_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of gas token (on the L1) is correct
    run query_contract "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_final_sender_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    local expected_balance=$(echo "$gas_token_init_sender_balance + $wei_amount" |
        bc |
        awk '{print $1}')

    echo "Sender balance ($sender_addr) (gas token L1): $gas_token_final_sender_balance" >&3
    assert_equal "$gas_token_final_sender_balance" "$expected_balance"

    # Send approve transaction to the gas token on L1
    deposit_ether_value="0.1ether"
    run send_tx "$l1_rpc_url" "$sender_private_key" "$gas_token_addr" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$deposit_ether_value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$l2_rpc_network_id
    amount=$wei_amount
    meta_bytes="0x"
    run bridge_asset "$gas_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the L2)
    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"
    local claim_global_index="$output"

    # Validate the bridge_getClaims API
    run get_claim "$l2_rpc_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_url"
    assert_success

    # Validate that the native token of receiver on L2 has increased by the bridge tokens amount
    run verify_balance "$L2_RPC_URL" "$native_token_addr" "$receiver" "$initial_receiver_balance" "$tokens_amount"
    assert_success
}

@test "Custom gas token withdrawal L2 -> L1" {
    echo "Custom gas token withdrawal (gas token addr: $gas_token_addr, L1 RPC: $l1_rpc_url, L2 RPC: $L2_RPC_URL)" >&3

    local initial_receiver_balance=$(cast call --rpc-url "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Receiver balance of gas token on L1 $initial_receiver_balance" >&3

    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim withdrawals (settle them on the L1)
    process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$l1_rpc_url"

    # Validate that the token of receiver on L1 has increased by the bridge tokens amount
    run verify_balance "$l1_rpc_url" "$gas_token_addr" "$destination_addr" "$initial_receiver_balance" "$ether_value"
    if [ $status -eq 0 ]; then
        break
    fi
    assert_success
}

# For some reason this test doesn't run well for the op-succinct stack, but only for pessimistic
@test "ERC20 token deposit L2 -> L1" {
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path
    assert_success
    local l2_erc20_addr=$(echo "$output" | tail -n 1 | tr '[:upper:]' '[:lower:]')
    log "📜 ERC20 contract address: $l2_erc20_addr"

    # Mint ERC20 tokens on L2
    local tokens_amount="10ether"
    local wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_erc20_tokens "$L2_RPC_URL" "$l2_erc20_addr" "$sender_private_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Assert that balance of ERC20 token (on the L2) is correct
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    # Send approve transaction to the ERC20 token on L2
    run send_tx "$L2_RPC_URL" "$sender_private_key" "$l2_erc20_addr" "$APPROVE_FN_SIG" "$l2_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
    run query_contract "$L2_RPC_URL" "$l2_erc20_addr" "allowance(address owner, address spender)(uint256)" "$sender_addr" "$l2_bridge_addr"
    assert_success
    log "🔐 Allowance for bridge contract: $output [weis]"

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
    local l2_erc20_token_sender_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    log "💰 Sender balance ($sender_addr) (ERC20 token L2): $l2_erc20_token_sender_balance [weis]"

    # Claim deposit (settle it on the L1)
    echo "==== 🔐 Claiming ERC20 token deposit on L1 ($l1_rpc_url)" >&3
    process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$l1_rpc_url"

    run wait_for_expected_token "$l2_erc20_addr" "$l1_rpc_network_id" 15 2 "$aggkit_bridge_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$l2_erc20_addr" "$origin_token_addr"

    local l1_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
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
    process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$L2_RPC_URL"

    echo "==== 💰 Verifying balance on L2 ($L2_RPC_URL)" >&3
    run verify_balance "$L2_RPC_URL" "$l2_erc20_addr" "$destination_addr" "$l2_erc20_token_sender_balance" "$tokens_amount"
    assert_success

    # Query balance of ERC20 token on L1
    run query_contract "$l1_rpc_url" "$l1_wrapped_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local l1_wrapped_token_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
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
    process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$l1_rpc_url"

    echo "==== 💰 Verifying balance on L1 ($l1_rpc_url)" >&3
    run verify_balance "$l1_rpc_url" "$l1_wrapped_token_addr" "$destination_addr" "$l1_wrapped_token_balance" "$tokens_amount"
    assert_success
}
