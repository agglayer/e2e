#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7823

# This file implements tests for EIP-7823
# https://eips.ethereum.org/EIPS/eip-7823

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
    # Deploy the contract
    run cast send --rpc-url $l1_rpc_url --private-key $l1_private_key --create $contract_bytecode --json
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

@test "Modexp regular calls" {
    contract_address=$(deploy_contract)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract" >&3
        exit 1
    fi
    echo "ModExp helper contract deployed at: $contract_address" >&3

    # lets call each function: modexp_test_0, modexp_test_1_base_1024, modexp_test_2_exp_1024, modexp_test_3_mod_1024, modexp_test_4_base_1025, modexp_test_5_exp_1025, modexp_test_6_mod_1025
    for signature in "modexp_test_0" "modexp_test_1_base_1024" "modexp_test_2_exp_1024" "modexp_test_3_mod_1024"; do
        echo "Calling $signature" >&3
        run cast call --rpc-url $l1_rpc_url --private-key $l1_private_key --gas-limit 1750000 $contract_address "$signature()(bytes32)"
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to call modexp precompile, output: $output" >&3
            exit 1
        fi
        echo "✅ Successfully called modexp precompile, result: $output" >&3
    done
}

@test "Modexp calls not valid for fusaka" {
    contract_address=$(deploy_contract)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract" >&3
        exit 1
    fi
    echo "ModExp helper contract deployed at: $contract_address" >&3

    # lets call each function: modexp_test_0, modexp_test_1_base_1024, modexp_test_2_exp_1024, modexp_test_3_mod_1024, modexp_test_4_base_1025, modexp_test_5_exp_1025, modexp_test_6_mod_1025
    for signature in "modexp_test_4_base_1025" "modexp_test_5_exp_1025" "modexp_test_6_mod_1025"; do
        echo "Calling $signature" >&3
        run cast call --rpc-url $l1_rpc_url --private-key $l1_private_key --gas-limit 1750000 $contract_address "$signature()(bytes32)"
        if [ "$status" -eq 0 ]; then
            echo "❌ The call was expected to fail, but it succeeded, output: $output" >&3
            exit 1
        fi
        echo "✅ Successfully failed modexp call with length > 1024, result: $output" >&3
    done
}
