#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/scripts/send_tx.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=light,eoa,el:any
@test "Send EOA transaction" {
    export RECEIVER="${RECEIVER:-0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6}"

    # ✅ Fix SC2155: Assign before exporting
    local sender_temp
    sender_temp=$(cast wallet address --private-key "$PRIVATE_KEY") || {
        echo "❌ Failed to retrieve sender address from private key."
        return 1
    }
    export SENDER_ADDR="$sender_temp"

    echo "👤 Sender Address: $SENDER_ADDR"
    echo "🎯 Receiver Address: $RECEIVER"
    echo "🔧 Using L2 RPC URL: $L2_RPC_URL"

    # ✅ Retrieve initial nonce
    local INITIAL_NONCE
    INITIAL_NONCE=$(cast nonce "$SENDER_ADDR" --rpc-url "$L2_RPC_URL") || {
        echo "❌ Failed to retrieve nonce for sender: $SENDER_ADDR using RPC URL: $L2_RPC_URL"
        return 1
    }
    echo "📜 Initial Nonce: $INITIAL_NONCE"

    local VALUE="10ether"

    # ✅ Successful transaction
    echo "🚀 Sending $VALUE from $SENDER_ADDR to $RECEIVER..."
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$VALUE"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # ✅ Excessive transaction (should fail)
    local SENDER_BALANCE
    SENDER_BALANCE=$(cast balance "$SENDER_ADDR" --ether --rpc-url "$L2_RPC_URL") || {
        echo "❌ Failed to retrieve balance for sender: $SENDER_ADDR using RPC URL: $L2_RPC_URL"
        return 1
    }

    local EXCESSIVE_VALUE
    EXCESSIVE_VALUE=$(echo "$SENDER_BALANCE + 1" | bc)"ether"
    echo "⚠️ Attempting to send excessive funds: $EXCESSIVE_VALUE (should fail)..."
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$EXCESSIVE_VALUE"
    assert_failure  # ✅ Transaction should fail

    # ✅ Verify nonce was updated correctly
    local FINAL_NONCE
    FINAL_NONCE=$(cast nonce "$SENDER_ADDR" --rpc-url "$L2_RPC_URL") || {
        echo "❌ Failed to retrieve nonce for sender: $SENDER_ADDR using RPC URL: $L2_RPC_URL"
        return 1
    }
    echo "📜 Final Nonce: $FINAL_NONCE"

    assert_equal "$FINAL_NONCE" "$(echo "$INITIAL_NONCE + 1" | bc)"
}
