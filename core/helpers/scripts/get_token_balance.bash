#!/bin/bash
set -euo pipefail

# Function to get the token balance of a given address
# It checks if the token address is zero (ETH) or a valid ERC20 token address
# and retrieves the balance (in ETH) accordingly.
function get_token_balance() {
    local rpc_url="$1"      # RPC URL
    local token_addr="$2"   # Token address (0x0 for ETH)
    local account_addr="$3" # Account address

    # Validation: Ensure all arguments are provided
    if [[ -z "$rpc_url" || -z "$token_addr" || -z "$account_addr" ]]; then
        echo "Error: Missing arguments. Usage: get_token_balance <rpc_url> <token_addr> <account_addr>" >&2
        return 1
    fi

    # Validation: Check if Ethereum addresses are valid (starts with 0x and is 42 characters long)
    for addr in "$token_addr" "$account_addr"; do
        if ! [[ "$addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: Invalid Ethereum address '$addr'" >&2
            return 1
        fi
    done

    local token_balance

    if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
        token_balance=$(cast balance -e --rpc-url "$rpc_url" "$account_addr")
    else
        local balance_wei=$(cast call --rpc-url "$rpc_url" "$token_addr" "$BALANCE_OF_FN_SIG" "$account_addr" | awk '{print $1}')
        token_balance=$(cast --from-wei "$balance_wei")
    fi

    echo $token_balance
}
