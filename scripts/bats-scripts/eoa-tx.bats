setup() {
    load 'helpers/common-setup'
    load 'helpers/common'
    _common_setup

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
}

@test "Send EOA transaction" {
    echo "Testing EOA transaction"

    local sender_addr=$(cast wallet address --private-key "$sender_private_key")
    echo "Sender Address: $sender_addr"

    local initial_nonce=$(cast nonce "$sender_addr" --rpc-url "$l2_rpc_url") || {
        echo "Failed to retrieve nonce for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }
    echo "Initial Nonce: $initial_nonce"

    local value="10ether"

    # Case 1: Transaction successful
    run send_tx "$l2_rpc_url" "$sender_private_key" "$receiver" "$value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Case 2: Transaction rejected (insufficient funds)
    local sender_balance=$(cast balance "$sender_addr" --ether --rpc-url "$l2_rpc_url") || {
        echo "Failed to retrieve balance for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }
    local excessive_value=$(echo "$sender_balance + 1" | bc)"ether"
    run send_tx "$l2_rpc_url" "$sender_private_key" "$receiver" "$excessive_value"
    assert_failure
    assert_output --regexp "Error: Transaction failed.*"
}
