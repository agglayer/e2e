#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    load "../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=transaction-eoa,evm-gas
@test "sender balance decreases by exactly gas cost plus value transferred" {
    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    receipt=$(cast send \
        --value 1000 \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000)

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot check balance invariant" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    expected_balance=$(bc <<< "$balance_before - 1000 - ($gas_used * $effective_gas_price)")

    if [[ "$balance_after" != "$expected_balance" ]]; then
        echo "Balance invariant violated:" >&2
        echo "  balance_before=$balance_before" >&2
        echo "  gas_used=$gas_used effective_gas_price=$effective_gas_price" >&2
        echo "  expected_balance=$expected_balance actual_balance=$balance_after" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
@test "recipient balance increases by exactly the value sent" {
    fresh_wallet=$(cast wallet new --json | jq '.[0]')
    recipient_address=$(echo "$fresh_wallet" | jq -r '.address')

    balance_before=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")
    if [[ "$balance_before" -ne 0 ]]; then
        echo "Fresh address unexpectedly has non-zero balance: $balance_before" >&2
        return 1
    fi

    send_amount=12345

    cast send \
        --value "$send_amount" \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$recipient_address" &>/dev/null

    balance_after=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    if [[ "$balance_after" -ne "$send_amount" ]]; then
        echo "Recipient balance mismatch: expected $send_amount, got $balance_after" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
@test "CREATE deploys to the address predicted by cast compute-address" {
    current_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected_addr=$(cast compute-address --nonce "$current_nonce" "$ephemeral_address")
    # cast compute-address may return "Computed Address: 0x..." — extract just the address
    expected_addr=$(echo "$expected_addr" | grep -oE '0x[0-9a-fA-F]{40}' | head -1)

    receipt=$(cast send \
        --nonce "$current_nonce" \
        --gas-limit 1000000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x00")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    actual_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # Normalize to lowercase for comparison
    expected_lower=$(echo "$expected_addr" | tr '[:upper:]' '[:lower:]')
    actual_lower=$(echo "$actual_addr" | tr '[:upper:]' '[:lower:]')

    if [[ "$expected_lower" != "$actual_lower" ]]; then
        echo "Contract address mismatch:" >&2
        echo "  expected (computed): $expected_lower" >&2
        echo "  actual (from receipt): $actual_lower" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_call does not consume gas or advance nonce" {
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    # eth_call should not change state
    cast call "$ephemeral_address" "0x" --rpc-url "$L2_RPC_URL" &>/dev/null

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    if [[ "$nonce_after" -ne "$nonce_before" ]]; then
        echo "Nonce changed after eth_call: before=$nonce_before after=$nonce_after" >&2
        return 1
    fi

    if [[ "$balance_after" -ne "$balance_before" ]]; then
        echo "Balance changed after eth_call: before=$balance_before after=$balance_after" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
@test "nonce increments by exactly 1 after each successful transaction" {
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    cast send \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        0x0000000000000000000000000000000000000000 &>/dev/null

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected=$(( nonce_before + 1 ))

    if [[ "$nonce_after" -ne "$expected" ]]; then
        echo "Nonce invariant violated: before=$nonce_before expected=$expected got=$nonce_after" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa,evm-gas
@test "out-of-gas transaction still increments sender nonce" {
    # An infinite-loop initcode with a gas limit that is above the intrinsic cost
    # for CREATE (21000 base + 32000 = 53000) but nowhere near enough to execute
    # the loop — the tx is mined, fails with OOG, but the nonce must still advance
    # (EIP-161 / Yellow Paper).
    # 0x5b600056 = JUMPDEST PUSH1 0x00 JUMP (infinite loop back to offset 0)
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    set +e
    cast send \
        --gas-limit 60000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x5b600056" &>/dev/null
    set -e

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected=$(( nonce_before + 1 ))

    if [[ "$nonce_after" -ne "$expected" ]]; then
        echo "Nonce not incremented after OOG tx: before=$nonce_before expected=$expected got=$nonce_after" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa,evm-gas
@test "total value is conserved: sender decrease equals recipient increase plus gas cost" {
    fresh_wallet=$(cast wallet new --json | jq '.[0]')
    recipient_address=$(echo "$fresh_wallet" | jq -r '.address')

    sender_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    recipient_before=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    transfer_amount=500000

    receipt=$(cast send \
        --value "$transfer_amount" \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$recipient_address")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot verify value conservation" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")
    gas_cost=$(bc <<< "$gas_used * $effective_gas_price")

    sender_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    recipient_after=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    sender_decrease=$(bc <<< "$sender_before - $sender_after")
    recipient_increase=$(bc <<< "$recipient_after - $recipient_before")
    expected_sender_decrease=$(bc <<< "$transfer_amount + $gas_cost")

    if [[ "$sender_decrease" != "$expected_sender_decrease" ]]; then
        echo "Value conservation violated (sender side):" >&2
        echo "  sender_decrease=$sender_decrease expected=$expected_sender_decrease" >&2
        echo "  transfer=$transfer_amount gas_cost=$gas_cost" >&2
        return 1
    fi

    if [[ "$recipient_increase" != "$transfer_amount" ]]; then
        echo "Value conservation violated (recipient side):" >&2
        echo "  recipient_increase=$recipient_increase expected=$transfer_amount" >&2
        return 1
    fi
}
