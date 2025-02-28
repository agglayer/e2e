#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/extract_tx_hash.bash"
source "$SCRIPT_DIR/check_balances.bash"

function send_eoa_transaction() {
    local private_key="$1"
    local receiver_addr="$2"
    local value="$3"
    local sender="$4"
    local sender_initial_balance="$5"
    local receiver_initial_balance="$6"

    echo "Sending EOA transaction (from: $sender, rpc url: $rpc_url) to: $receiver_addr with value: $value" >&3

    # Send transaction via cast
    local cast_output tx_hash
    gas_price=$(cast gas-price --rpc-url "$rpc_url")
    local comp_gas_price=$(bc -l <<<"$gas_price * 3.5" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        echo "Failed to calculate gas price" >&3
        exit 1
    fi
    echo "cast send --gas-price $comp_gas_price --rpc-url $rpc_url --private-key $private_key $receiver_addr --value $value --legacy" >&3
    cast_output=$(cast send --gas-price $comp_gas_price --rpc-url "$rpc_url" --private-key "$private_key" "$receiver_addr" --value "$value" --legacy 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to send transaction. Output:"
        echo "$cast_output"
        return 1
    fi

    tx_hash=$(extract_tx_hash "$cast_output")
    [[ -z "$tx_hash" ]] && {
        echo "Error: Failed to extract transaction hash."
        return 1
    }

    check_balances "$sender" "$receiver_addr" "$value" "$tx_hash" "$sender_initial_balance" "$receiver_initial_balance"
    if [[ $? -ne 0 ]]; then
        echo "Error: Balance not updated correctly."
        return 1
    fi

    echo "Transaction successful (transaction hash: $tx_hash)"
}