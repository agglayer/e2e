#!/usr/bin/env bash

function deploy_contract() {
    local rpc_url="$1"
    local private_key="$2"
    contract_artifact="$3"

    # Check if rpc_url is available
    if [[ -z "$rpc_url" ]]; then
        echo "Error: rpc_url parameter is not set."
        return 1
    fi

    if [[ ! -f "$contract_artifact" ]]; then
        echo "Error: Contract artifact '$contract_artifact' does not exist."
        return 1
    fi

    # Get the sender address
    local sender=$(cast wallet address "$private_key")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to retrieve sender address."
        return 1
    fi

    echo "Attempting to deploy contract artifact '$contract_artifact' to $rpc_url (sender: $sender)" >&3

    # Get bytecode from the contract artifact
    local bytecode=$(jq -r .bytecode "$contract_artifact")
    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        echo "Error: Failed to read bytecode from $contract_artifact"
        return 1
    fi

    # Send the transaction and capture the output
    gas_price=$(cast gas-price --rpc-url "$rpc_url")
    local comp_gas_price=$(bc -l <<<"$gas_price * 2.5" | sed 's/\..*//')
    if [[ $? -ne 0 ]]; then
        echo "Failed to calculate gas price" >&3
        exit 1
    fi
    local cast_output=$(cast send --rpc-url "$rpc_url" \
        --private-key "$private_key" \
        --gas-price $comp_gas_price \
        --legacy \
        --create "$bytecode" \
        2>&1)

    # Check if cast send was successful
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to send transaction."
        echo "$cast_output"
        return 1
    fi

    echo "Deploy contract output:" >&3
    echo "$cast_output" >&3

    # Extract the contract address from the output using updated regex
    local deployed_contract_address=$(echo "$cast_output" | grep -o 'contractAddress\s\+\(0x[a-fA-F0-9]\{40\}\)' | sed 's/contractAddress\s\+//')
    local deployed_contract_address=$(echo "$deployed_contract_address" | sed -E 's/^contractAddress[[:space:]]+//')
    echo "Deployed contract address: $deployed_contract_address" >&3

    if [[ -z "$deployed_contract_address" ]]; then
        echo "Error: Failed to extract deployed contract address"
        echo "$cast_output"
        return 1
    fi

    if [[ ! "$deployed_contract_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid contract address $deployed_contract_address"
        return 1
    fi

    # Print contract address for return
    echo "$deployed_contract_address"

    return 0
}