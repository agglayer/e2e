#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$SCRIPT_DIR"
source "$SCRIPT_DIR/send_eoa_tx.bash"
source "$SCRIPT_DIR/send_smart_contract_tx.bash"

function send_tx() {
    # Check if at least 4 arguments are provided
    if [[ $# -lt 4 ]]; then
        echo "Usage: send_tx <rpc_url> <private_key> <receiver> <value_or_function_signature> [<param1> <param2> ...]"
        return 1
    fi

    local rpc_url="$1"               # RPC URL
    local private_key="$2"           # Sender private key
    local receiver_addr="$3"         # Receiver address
    local value_or_function_sig="$4" # Value or function signature

    # Error handling: Ensure the receiver is a valid Ethereum address
    if [[ ! "$receiver_addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid receiver address '$receiver_addr'."
        return 1
    fi

    shift 4             # Shift the first 4 arguments (rpc_url, private_key, receiver_addr, value_or_function_sig)
    local params=("$@") # Collect all remaining arguments as function parameters

    # Get sender address from private key
    local sender
    sender=$(cast wallet address "$private_key") || {
        echo "Error: Failed to extract the sender address."
        return 1
    }

    # Check if the value_or_function_sig is a numeric value (Ether to be transferred)
    if [[ "$value_or_function_sig" =~ ^[0-9]+(\.[0-9]+)?(ether)?$ ]]; then
        # Case: Ether transfer (EOA transaction)
        # Get initial ether balances of sender and receiver
        local sender_addr=$(cast wallet address --private-key "$private_key")
        local sender_initial_balance receiver_initial_balance
        sender_initial_balance=$(cast balance "$sender_addr" --ether --rpc-url "$rpc_url") || return 1
        receiver_initial_balance=$(cast balance "$receiver_addr" --ether --rpc-url "$rpc_url") || return 1

        send_eoa_transaction "$private_key" "$receiver_addr" "$value_or_function_sig" "$sender_addr" "$sender_initial_balance" "$receiver_initial_balance"
    else
        # Case: Smart contract interaction (contract interaction with function signature and parameters)
        send_smart_contract_transaction "$private_key" "$receiver_addr" "$value_or_function_sig" "${params[@]}"
    fi
}