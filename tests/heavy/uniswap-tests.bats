#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    load "$PROJECT_ROOT/core/helpers/common"
    _common_setup

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
}

@test "Deploy and test UniswapV3 contract" {
    wallet_A_output=$(cast wallet new)
    address_A=$(echo "$wallet_A_output" | grep "Address" | awk '{print $2}')
    address_A_private_key=$(echo "$wallet_A_output" | grep "Private key" | awk '{print $3}')

    local value_ether="50ether"
    cast send --rpc-url "$l2_rpc_url" --private-key "$sender_private_key" "$address_A" --value "$value_ether" --legacy

    run polycli loadtest uniswapv3 --legacy -v 600 --rpc-url "$l2_rpc_url" --private-key "$address_A_private_key"
    assert_success

    output=$(echo "$output" | sed -r "s/\x1B\[[0-9;]*[mGKH]//g")

    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=WETH9"
    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=UniswapV3Factory"
    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=SwapRouter02"
}
