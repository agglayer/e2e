#!/usr/bin/env bash

function query_contract() {
    local rpc_url="$1"       # RPC URL
    local addr="$2"          # Contract address
    local funcSignature="$3" # Function signature
    shift 3                  # Shift past the first 3 arguments
    local params=("$@")      # Collect remaining arguments as parameters array

    echo "Querying state of $addr account (RPC URL: $rpc_url) with function signature: '$funcSignature' and params: '${params[*]}'" >&3

    # Check if rpc url is available
    if [[ -z "$rpc_url" ]]; then
        echo "Error: rpc_url parameter is not provided."
        return 1
    fi

    # Check if the contract address is valid
    if [[ ! "$addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid contract address '$addr'."
        return 1
    fi

    # Call the contract using `cast call`
    local result
    result=$(cast call --rpc-url "$rpc_url" "$addr" "$funcSignature" "${params[@]}" 2>&1)

    # Check if the call was successful
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to query contract."
        echo "$result"
        return 1
    fi

    # Return the result (contract query response)
    echo "$result"

    return 0
}