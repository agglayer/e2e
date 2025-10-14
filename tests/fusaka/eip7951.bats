#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7951

# This file implements tests for EIP-7951
# https://eips.ethereum.org/EIPS/eip-7951

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    contract_bytecode=$(cat $PROJECT_ROOT/tests/fusaka/contracts/P256Harness.json | jq -r .bytecode.object)
    if [ -z "$contract_bytecode" ]; then
        echo "❌ Failed to read bytecode from $PROJECT_ROOT/tests/fusaka/contracts/P256Harness.json" >&3
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


@test "p256verify call" {
    contract_address=$(deploy_contract $l1_rpc_url $l1_private_key)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract" >&3
        exit 1
    fi
    echo "p256verify helper contract deployed at: $contract_address" >&3

    # 160-byte input = h || r || s || qx || qy
    # https://eips.ethereum.org/assets/eip-7951/test-vectors.json
    input160="bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca6050232ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e184cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd762927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e"

    run cast send $contract_address "verify(bytes)" $input160 --rpc-url $l1_rpc_url --private-key $l1_private_key --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to call p256verify, output: $output" >&3
        exit 1
    fi
    txhash=$(echo "$output" | jq -r '.transactionHash')
    status=$(echo "$output" | jq -r '.status' | cast to-dec)
    if [ "$status" -ne 1 ]; then
        echo "❌ Failed to call p256verify, status: $status" >&3
        exit 1
    fi
    echo "✅ Successfully called p256verify, txhash: $txhash, status: $status" >&3


    run cast call $contract_address "last()(bytes32)" --rpc-url $l1_rpc_url
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to get last result, output: $output" >&3
        exit 1
    fi
    last=$(echo "$output" | cast to-dec)
    if [ "$last" -eq 99 ]; then
        echo "❌ Last result has not been updated, its still $last" >&3
        exit 1
    elif [ "$last" -eq 0 ]; then
        echo "❌ Last result is 0, that indicates that the call failed" >&3
        exit 1
    elif [ "$last" -eq 1 ]; then
        echo "✅ Last result is 1, success" >&3
    else
        echo "❌ Last result is $last, something went wrong" >&3
        exit 1
    fi
}
