#!/usr/bin/env bash

function check_balances() {
    local sender="$1"
    local receiver="$2"
    local amount="$3"
    local tx_hash="$4"
    local sender_initial_balance="$5"
    local receiver_initial_balance="$6"

    if [[ ! "$sender" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid sender address '$sender'."
        return 1
    fi

    if [[ ! "$receiver" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid receiver address '$receiver'."
        return 1
    fi

    if [[ ! "$tx_hash" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
        echo "Error: Invalid transaction hash: $tx_hash"
        return 1
    fi

    local sender_final_balance=$(cast balance "$sender" --ether --rpc-url "$L2_RPC_URL") || return 1
    echo "Sender final balance: '$sender_final_balance' wei"
    echo "RPC url: '$L2_RPC_URL'"

    local tx_output
    tx_output=$(cast tx "$tx_hash" --rpc-url "$L2_RPC_URL")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to fetch transaction details"
        echo "$tx_output"
        return 1
    fi

    echo "Transaction output: $tx_output"

    local gas_used
    gas_used=$(echo "$tx_output" | grep -Eo "gas\s+[0-9]+" | awk '{print $2}')
    local gas_price
    gas_price=$(echo "$tx_output" | grep -Eo "gasPrice\s+[0-9]+" | awk '{print $2}')

    if [[ -z "$gas_used" || -z "$gas_price" ]]; then
        echo "Error: Gas used or gas price not found in transaction output."
        return 1
    fi

    echo "Gas used: $gas_used"
    echo "Gas price: $gas_price"

    local gas_fee
    gas_fee=$(echo "$gas_used * $gas_price" | bc)
    local gas_fee_in_ether
    gas_fee_in_ether=$(cast to-unit "$gas_fee" ether)

    local sender_balance_change
    sender_balance_change=$(echo "$sender_initial_balance - $sender_final_balance" | bc)
    echo "Sender balance changed by: '$sender_balance_change' wei"
    echo "Gas fee paid: '$gas_fee_in_ether' ether"

    local receiver_final_balance
    receiver_final_balance=$(cast balance "$receiver" --ether --rpc-url "$L2_RPC_URL") || return 1
    local receiver_balance_change
    receiver_balance_change=$(echo "$receiver_final_balance - $receiver_initial_balance" | bc)
    echo "Receiver balance changed by: '$receiver_balance_change' wei"

    local value_in_ether
    value_in_ether=$(echo "$amount" | sed 's/ether$//')

    if ! echo "$receiver_balance_change == $value_in_ether" | bc -l; then
        echo "Error: receiver balance updated incorrectly. Expected: $value_in_ether, Actual: $receiver_balance_change"
        return 1
    fi

    local expected_sender_change
    expected_sender_change=$(echo "$value_in_ether + $gas_fee_in_ether" | bc)
    if ! echo "$sender_balance_change == $expected_sender_change" | bc -l; then
        echo "Error: sender balance updated incorrectly. Expected: $expected_sender_change, Actual: $sender_balance_change"
        return 1
    fi
}