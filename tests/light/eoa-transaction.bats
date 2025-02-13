#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common"
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=light,eoa,el:any
@test "Send EOA transaction" {
    local receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    local sender_addr=$(cast wallet address --private-key "$private_key")

    # ✅ Retrieve initial nonce
    local initial_nonce
    initial_nonce=$(cast nonce "$sender_addr" --rpc-url "$l2_rpc_url") || {
        echo "❌ Failed to retrieve nonce for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }

    local value="10ether"

    # ✅ Successful transaction
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$value"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # ✅ Excessive transaction (should fail)
    local sender_balance
    sender_balance=$(cast balance "$sender_addr" --ether --rpc-url "$l2_rpc_url") || {
        echo "❌ Failed to retrieve balance for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }

    local excessive_value
    excessive_value=$(echo "$sender_balance + 1" | bc)"ether"
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$excessive_value"
    assert_failure  # ✅ Transaction should fail

    # ✅ Verify nonce was updated correctly
    local final_nonce
    final_nonce=$(cast nonce "$sender_addr" --rpc-url "$l2_rpc_url") || {
        echo "❌ Failed to retrieve nonce for sender: $sender_addr using RPC URL: $l2_rpc_url"
        return 1
    }

    assert_equal "$final_nonce" "$(echo "$initial_nonce + 1" | bc)"
}
