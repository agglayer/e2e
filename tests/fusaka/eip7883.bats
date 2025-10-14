#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7883

# This file implements tests for EIP-7883
# https://eips.ethereum.org/EIPS/eip-7883

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    contract_bytecode=$(cat $PROJECT_ROOT/tests/fusaka/contracts/PreModExp.json | jq -r .bytecode.object)
    if [ -z "$contract_bytecode" ]; then
        echo "❌ Failed to read bytecode from $PROJECT_ROOT/tests/fusaka/contracts/PreModExp.json" >&3
        exit 1
    fi
    export contract_bytecode
}

function deploy_contract() {
    local rpc_url="$1"
    local private_key="$2"

    # Deploy the contract
    run cast send --rpc-url $rpc_url --private-key $private_key --create $contract_bytecode --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to deploy contract: $output" >&3
        exit 1
    fi

    contract_address=$(echo "$output" | jq -r '.contractAddress')
    if [ -z "$contract_address" ]; then
        echo "❌ Contract address not found in output" >&3
        exit 1
    fi

    echo $contract_address
}

@test "Modexp gas costs" {
    # L2
    contract_address=$(deploy_contract $l2_rpc_url $l2_private_key)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract" >&3
        exit 1
    fi
    echo "ModExp helper contract deployed on L2 at: $contract_address" >&3

    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --gas-limit 1750000 $contract_address "modexp_test_0()(bytes32)" --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to call modexp precompile, output: $output" >&3
        exit 1
    fi
    l1_gas_used=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)
    echo "✅ Successfully called modexp precompile on L2, gas used: $l1_gas_used" >&3

    # L1
    contract_address=$(deploy_contract $l1_rpc_url $l1_private_key)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract" >&3
        exit 1
    fi
    echo "ModExp helper contract deployed on L1 at: $contract_address" >&3

    run cast send --rpc-url $l1_rpc_url --private-key $l1_private_key --gas-limit 1750000 $contract_address "modexp_test_0()(bytes32)" --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to call modexp precompile, output: $output" >&3
        exit 1
    fi
    l2_gas_used=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)
    diff=$((l2_gas_used - l1_gas_used))
    if [ "$diff" -ne 300 ]; then
        echo "❌ Gas used on L2 is not 300 more than on L1, l1: $l1_gas_used, l2: $l2_gas_used, diff: $diff" >&3
        exit 1
    fi
    echo "✅ Successfully called modexp precompile on L1, gas used: $l2_gas_used, l2 gas used is 300 more than l1 gas used" >&3
}
