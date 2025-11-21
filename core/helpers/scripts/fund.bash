#!/bin/bash
set -euo pipefail

# Function is used to fund a receiver address with native tokens.
# It takes four arguments:
# 1. sender_private_key: The private key of the sender
# 2. receiver_addr: The address of the receiver
# 3. amount: The amount of native tokens to send (in wei)
# 4. rpc_url: The RPC URL of the Ethereum network
# The function will attempt to send the specified amount of native tokens to the receiver address.
# If the transaction fails, it will retry up to 3 times with a 3-second delay between attempts.
function fund() {
    local sender_private_key=$1
    local receiver_addr=$2
    local amount=$3
    local rpc_url=$4

    if [ -z "$sender_private_key" ] || [ -z "$receiver_addr" ] || [ -z "$amount" ] || [ -z "$rpc_url" ]; then
        echo "⚠️ Usage: fund <sender_private_key> <receiver_addr> <amount> <rpc_url>" >&3
        return 1
    fi

    local max_attempts=3
    local attempt=1
    local success=0

    while [ $attempt -le $max_attempts ]; do
        echo "🚀 Attempt $attempt to fund the $receiver_addr..." >&3

        local raw_gas_price
        raw_gas_price=$(cast gas-price --rpc-url "$rpc_url" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$raw_gas_price" ]; then
            echo "❌ Failed to fetch gas price from $rpc_url (attempt $attempt)" >&3
            break
        fi

        # Bump gas price by 50%
        local gas_price
        gas_price=$(echo "$raw_gas_price * 1.5" | bc -l | cut -f 1 -d '.')
        echo "Using bumped gas price: $gas_price [wei] (original: $raw_gas_price [wei])" >&3

        cast send --rpc-url "$rpc_url" \
            --legacy \
            --private-key "$sender_private_key" \
            --gas-price "$gas_price" \
            --value "$amount" \
            "$receiver_addr" || {
            echo "⚠️ Attempt $attempt failed. Retrying in 3s..." >&3
            sleep 3
            attempt=$((attempt + 1))
            continue
        }

        success=1
        break
    done

    if [ $success -eq 0 ]; then
        echo "❌ Failed to fund $receiver_addr after $max_attempts attempts. Continuing..." >&3
        return 1
    fi

    echo "✅ Successfully funded $receiver_addr with $amount of native tokens" >&3
}

# Function is used to fund a receiver address with native tokens up to specified amount.
# It takes four arguments:
# 1. sender_private_key: The private key of the sender
# 2. receiver_addr: The address of the receiver
# 3. amount: The amount of native tokens desired on receiver (in wei)
# 4. rpc_url: The RPC URL of the Ethereum network
function fund_up_to() {
    local sender_private_key=$1
    local receiver_addr=$2
    local amount=$3
    local rpc_url=$4

    local balance
    balance=$(cast balance --rpc-url "$rpc_url" "$receiver_addr")
    gap=$(echo "$amount - $balance" | bc -l | cut -f 1 -d '.')

    if [[ "$(echo "$gap <= 0" | bc)" -eq 1 ]]; then
        echo "✅ No need to fund $receiver_addr, current balance ($balance) is sufficient. Amount: $amount, Gap: $gap" >&3
        return 0
    else
        echo "⚠️ Funding $receiver_addr with additional $gap wei to reach desired amount of $amount wei." >&3
        fund "$sender_private_key" "$receiver_addr" "$gap" "$rpc_url"
    fi
}

function op_fund_all_available_balance() {
    local sender_private_key=$1
    local receiver_addr=$2
    local rpc_url=$3

    sender_addr=$(cast wallet address --private-key "$sender_private_key")
    sender_balance=$(cast balance "$sender_addr" --rpc-url "$rpc_url")
    echo "✅ Sender balance: $sender_balance" >&3

    basefee=$(cast basefee --rpc-url "$rpc_url")
    priority_fee=$(( 5 * 1000000000 ))
    max_fee=$(( basefee + priority_fee ))
    tx_cost=$(( max_fee * 21000 ))
    amount_to_send=$(echo "$sender_balance - $tx_cost" | bc)

    run cast send --rpc-url "$rpc_url" --private-key "$sender_private_key" --gas-price "$max_fee" --priority-gas-price "$priority_fee" --value "$amount_to_send" "$receiver_addr"
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to send tx" >&3
        exit 1
    fi
    new_sender_balance=$(cast balance "$sender_addr" --rpc-url "$rpc_url")
    echo "✅ Successfully drained sender balance from $sender_balance to $new_sender_balance" >&3 
}