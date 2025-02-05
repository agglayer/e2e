#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    load "$PROJECT_ROOT/core/helpers/common"
    _common_setup

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}

}

# bats test_tags=light,eoa
@test "Send EOA transaction" {
    local receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    local sender_addr=$(cast wallet address --private-key "$sender_private_key")
    local initial_nonce=$(cast nonce "$sender_addr" --rpc-url "$l2_rpc_url") || {
        echo "Failed to retrieve nonce for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }
    local value="10ether"

    # Successful transaction
    run send_tx "$l2_rpc_url" "$sender_private_key" "$receiver" "$value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Excessive transaction (should fail)
    local sender_balance=$(cast balance "$sender_addr" --ether --rpc-url "$l2_rpc_url") || {
        echo "Failed to retrieve balance for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }
    local excessive_value=$(echo "$sender_balance + 1" | bc)"ether"
    run send_tx "$l2_rpc_url" "$sender_private_key" "$receiver" "$excessive_value"
    assert_failure

    # Verify nonce was updated correctly
    local final_nonce=$(cast nonce "$sender_addr" --rpc-url "$l2_rpc_url") || {
        echo "Failed to retrieve nonce for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }
    assert_equal "$final_nonce" "$(echo "$initial_nonce + 1" | bc)"
}
