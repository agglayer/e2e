#!/usr/bin/env bash

# Internal helper: extract transaction hash from cast output
_extract_tx_hash() {
    local cast_output="$1"
    echo "$cast_output" | grep 'transactionHash' | awk '{print $2}' | tail -n 1
}

# Internal helper: verify balances after EOA transaction
# shellcheck disable=SC2154
_check_balances() {
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

    local sender_final_balance
    sender_final_balance=$(cast balance "$sender" --ether --rpc-url "$L2_RPC_URL") || return 1
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

# Internal helper: send an EOA (native ETH transfer) transaction
# shellcheck disable=SC2154
_send_eoa_transaction() {
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
    local comp_gas_price
    comp_gas_price=$(bc -l <<<"$gas_price * 3.5" | sed 's/\..*//')
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

    tx_hash=$(_extract_tx_hash "$cast_output")
    [[ -z "$tx_hash" ]] && {
        echo "Error: Failed to extract transaction hash."
        return 1
    }

    _check_balances "$sender" "$receiver_addr" "$value" "$tx_hash" "$sender_initial_balance" "$receiver_initial_balance"
    if [[ $? -ne 0 ]]; then
        echo "Error: Balance not updated correctly."
        return 1
    fi

    echo "Transaction successful (transaction hash: $tx_hash)"
}

# Internal helper: send a smart contract interaction transaction
# shellcheck disable=SC2154
_send_smart_contract_transaction() {
    local private_key="$1"
    local receiver_addr="$2"
    local function_sig="$3"
    shift 3
    local params=("$@")

    echo "Sending smart contract transaction to $receiver_addr with function signature: '$function_sig' and params: ${params[*]}" >&3

    # Send the smart contract interaction using cast
    local cast_output tx_hash
    cast_output=$(cast send "$receiver_addr" --rpc-url "$rpc_url" --private-key "$private_key" "$function_sig" "${params[@]}" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to send transaction. Output:"
        echo "$cast_output"
        return 1
    fi

    tx_hash=$(_extract_tx_hash "$cast_output")
    [[ -z "$tx_hash" ]] && {
        echo "Error: Failed to extract transaction hash."
        return 1
    }

    echo "Transaction successful (transaction hash: $tx_hash)"
}

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
        local sender_addr
        sender_addr=$(cast wallet address --private-key "$private_key")
        local sender_initial_balance receiver_initial_balance
        sender_initial_balance=$(cast balance "$sender_addr" --ether --rpc-url "$rpc_url") || return 1
        receiver_initial_balance=$(cast balance "$receiver_addr" --ether --rpc-url "$rpc_url") || return 1
        _send_eoa_transaction "$private_key" "$receiver_addr" "$value_or_function_sig" "$sender_addr" "$sender_initial_balance" "$receiver_initial_balance"
    else
        # Case: Smart contract interaction (contract interaction with function signature and parameters)
        _send_smart_contract_transaction "$private_key" "$receiver_addr" "$value_or_function_sig" "${params[@]}"
    fi
}
