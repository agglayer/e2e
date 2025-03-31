#!/usr/bin/env bash

function verify_balance() {
    local rpc_url="$1"             # RPC URL
    local token_addr="$2"          # gas token contract address
    local account="$3"             # account address
    local initial_balance_wei="$4" # initial balance in Wei (decimal)
    local ether_amount="$5"        # amount to be added (in Ether, decimal)

    # Trim 'ether' from ether_amount if it exists
    ether_amount=$(echo "$ether_amount" | sed 's/ether//')
    local amount_wei=$(cast --to-wei "$ether_amount")

    # Get final balance in wei (after the operation)
    local final_balance_wei
    if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
        final_balance_wei=$(cast balance "$account" --rpc-url "$rpc_url" | awk '{print $1}')
    else
        final_balance_wei=$(cast call --rpc-url "$rpc_url" "$token_addr" "$BALANCE_OF_FN_SIG" "$destination_addr" | awk '{print $1}')
    fi
    echo "Final balance of $account in $rpc_url: $final_balance_wei wei" >&3

    # Calculate expected final balance (initial_balance + amount)
    local expected_final_balance_wei=$(echo "$initial_balance_wei + $amount_wei" | bc)

    # Check if final_balance matches the expected final balance
    if [ "$(echo "$final_balance_wei == $expected_final_balance_wei" | bc)" -eq 1 ]; then
        echo "✅ Balance verification successful: final balance is correct."
    else
        echo "❌ Balance verification failed: expected $expected_final_balance_wei but got $final_balance_wei." >&3
        exit 1
    fi
}
