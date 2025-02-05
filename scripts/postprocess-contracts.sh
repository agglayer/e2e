#!/bin/bash

if [[ ! -d compiled-contracts ]]; then
    echo "It looks like you are not executing this script from the e2e root directory" >&2
    exit 1
fi

find compiled-contracts -mindepth 1 -type d -name '*.sol' | while read contract; do
    echo $contract
    contract_name=$(echo $contract | sed 's/compiled-contracts\/\(.*\).sol/\1/')
    echo $contract_name
    lower_contract_name=$(echo $contract_name | tr '[:upper:]' '[:lower:]')

    cat compiled-contracts/$contract_name.sol/$contract_name.json | jq -r '.abi' > core/contracts/abi/$lower_contract_name.abi
    cat compiled-contracts/$contract_name.sol/$contract_name.json | jq -r '.bytecode.object' | sed 's/^0x//'  > core/contracts/bin/$lower_contract_name.bin
done

find compiled-contracts -mindepth 1 -type d -name '*.yul' | while read contract; do
    echo $contract
    contract_name=$(echo $contract | sed 's/compiled-contracts\/\(.*\).yul/\1/')
    echo $contract_name
    lower_contract_name=$(echo $contract_name | tr '[:upper:]' '[:lower:]')

    cat compiled-contracts/$contract_name.yul/object.json | jq -r '.abi' > core/contracts/abi/$lower_contract_name.abi
    polycli wrap-contract $(cat compiled-contracts/$contract_name.yul/object.json | jq -r '.bytecode.object') | sed 's/^0x//' > core/contracts/bin/$lower_contract_name.bin
done
