#!/usr/bin/env bats

setup() {
    load 'helpers/common-setup'
    load 'helpers/common'
    _common_setup

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    readonly contract_artifact="./contracts/erc20mock/ERC20Mock.json"
}

@test "Test ERC20Mock contract" {
    wallet_A_output=$(cast wallet new)
    address_A=$(echo "$wallet_A_output" | grep "Address" | awk '{print $2}')
    address_A_private_key=$(echo "$wallet_A_output" | grep "Private key" | awk '{print $3}')
    address_B=$(cast wallet new | grep "Address" | awk '{print $2}')

    # Deploy ERC20Mock
    run deploy_contract "$l2_rpc_url" "$sender_private_key" "$contract_artifact"
    assert_success
    contract_addr=$(echo "$output" | tail -n 1)

    # Mint ERC20 tokens
    local amount="5"
    run send_tx "$l2_rpc_url" "$sender_private_key" "$contract_addr" "$mint_fn_sig" "$address_A" "$amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Insufficient gas scenario (should fail)
    local bytecode=$(jq -r .bytecode "$contract_artifact")
    [[ -z "$bytecode" || "$bytecode" == "null" ]] && { echo "Error: Failed to read bytecode"; return 1; }

    local gas_units=$(cast estimate --rpc-url "$l2_rpc_url" --create "$bytecode")
    gas_units=$(echo "scale=0; $gas_units / 2" | bc)
    local gas_price=$(cast gas-price --rpc-url "$l2_rpc_url")
    local value=$(echo "$gas_units * $gas_price" | bc)
    local value_ether=$(cast to-unit "$value" ether)"ether"

    cast send --rpc-url "$l2_rpc_url" --private-key "$sender_private_key" "$address_A" --value "$value_ether" --legacy
    run deploy_contract "$l2_rpc_url" "$address_A_private_key" "$contract_artifact"
    assert_failure
}
