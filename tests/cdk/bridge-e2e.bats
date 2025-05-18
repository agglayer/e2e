setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

# Helper function to run native gas token deposit to WETH
native_gas_token_deposit_to_WETH() {
    local bridge_type="$1"

    echo "Bridge_type: $bridge_type" >&3

    destination_addr=$sender_addr
    local initial_receiver_balance=$(cast call --rpc-url "$L2_RPC_URL" "$weth_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Initial receiver balance of native token on L2 $initial_receiver_balance" >&3

    echo "=== Running LxLy deposit $bridge_type on L1 to network: $l2_rpc_network_id native_token: $native_token_addr" >&3
    
    destination_net=$l2_rpc_network_id

    if [[ $bridge_type == "bridgeMessage" ]]; then
        run bridge_message "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    else
        run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    fi
    assert_success
    local bridge_tx_hash=$output

    echo "=== Claiming on L2..." >&3
    timeout="120"
    claim_frequency="10"
    run claim_tx_hash "$timeout" "$bridge_tx_hash" "$destination_addr" "$L2_RPC_URL" "$bridge_api_url" "$l2_bridge_addr"
    assert_success

    run verify_balance "$L2_RPC_URL" "$weth_token_addr" "$destination_addr" "$initial_receiver_balance" "$ether_value"
    assert_success

    echo "=== $bridge_type L2 WETH: $weth_token_addr to L1 ETH" >&3
    destination_addr=$sender_addr
    destination_net=0

    if [[ $bridge_type == "bridgeMessage" ]]; then
        run bridge_message "$weth_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    else
        run bridge_asset "$weth_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    fi
    assert_success
    local bridge_tx_hash=$output

    echo "=== Claiming on L1..." >&3
    timeout="400"
    claim_frequency="60"
    run claim_tx_hash "$timeout" "$bridge_tx_hash" "$destination_addr" "$l1_rpc_url" "$bridge_api_url" "$l1_bridge_addr"
    assert_success
}

@test "Native gas token deposit to WETH - BridgeAsset" {
    run native_gas_token_deposit_to_WETH "bridgeAsset"
}

@test "Native gas token deposit to WETH - BridgeMessage" {
   run native_gas_token_deposit_to_WETH "bridgeMessage"
}

@test "Custom gas token deposit" {
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
    run mint_erc20_tokens "$l1_rpc_url" "$gas_token_addr" "$minter_key" "$sender_addr" "$tokens_amount"
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
    timeout="360"
    claim_frequency="10"
    run claim_tx_hash "$timeout" "$bridge_tx_hash" "$destination_addr" "$L2_RPC_URL" "$bridge_api_url" "$l2_bridge_addr"
    assert_success

    # Validate that the native token of receiver on L2 has increased by the bridge tokens amount
    run verify_balance "$L2_RPC_URL" "$native_token_addr" "$receiver" "$initial_receiver_balance" "$tokens_amount"
    assert_success
}

@test "Custom gas token withdrawal" {
    echo "Running LxLy withdrawal" >&3
    echo "Gas token addr $gas_token_addr, L1 RPC: $l1_rpc_url" >&3

    local initial_receiver_balance=$(cast call --rpc-url "$l1_rpc_url" "$gas_token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    echo "Receiver balance of gas token on L1 $initial_receiver_balance" >&3

    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim withdrawals (settle them on the L1)
    timeout="360"
    claim_frequency="10"
    destination_net=$l1_rpc_network_id
    run claim_tx_hash "$timeout" "$bridge_tx_hash" "$destination_addr" "$l1_rpc_url" "$bridge_api_url" "$l1_bridge_addr"
    assert_success

    # Validate that the token of receiver on L1 has increased by the bridge tokens amount
    run verify_balance "$l1_rpc_url" "$gas_token_addr" "$destination_addr" "$initial_receiver_balance" "$ether_value"
    if [ $status -eq 0 ]; then
        break
    fi
    assert_success
}
