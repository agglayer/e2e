#!/usr/bin/env bats
# bats file_tags=op

etup() {
    rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    # bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    eth_address=$(cast wallet address --private-key "$private_key")
    export ETH_RPC_URL="$rpc_url"
}

# bats test_tags=smoke
@test "sweep account with precise gas and DA fee estimation" {
    wallet_info=$(cast wallet new --json | jq '.[0]')
    tmp_address=$(echo "$wallet_info" | jq -r '.address')
    tmp_private_key=$(echo "$wallet_info" | jq -r '.private_key')

    # Send 0.01 ETH to the new address
    cast send \
         --value "10000000000000000" \
         --private-key "$private_key" "$tmp_address"

    gas_price=$(cast gas-price)
    gas_price=$(bc <<< "$gas_price * 2")

    serialized_tx=$(cast mktx \
         --gas-price "$gas_price" \
         --gas-limit 21000 \
         --value "10000000000000000" \
         --private-key "$tmp_private_key" "$eth_address")
    da_cost=$(cast call --json 0x420000000000000000000000000000000000000F 'getL1Fee(bytes)(uint256)' "$serialized_tx" | jq -r '.[0]')

    # some fudge factor might be needed here since the da costs change very rapidly
    fudge_factor=1
    value_to_return=$(bc <<< "10000000000000000 - (21000 * $gas_price) - ($da_cost * $fudge_factor)" | sed 's/\..*$//')

    echo "Attempting to return $value_to_return wei based on DA cost of $da_cost, gas price $gas_price, and gas limit of 21,000"
    cast send \
         --gas-price "$gas_price" \
         --gas-limit 21000 \
         --value "$value_to_return" \
         --private-key "$tmp_private_key" "$eth_address"

}


# bats test_tags=smoke
@test "send concurrent transactions and verify DA fee handling" {
    a_wallet=$(cast wallet new --json)
    a_address=$(echo "$a_wallet" | jq -r .[0].address)
    a_private_key=$(echo "$a_wallet" | jq -r .[0].private_key)

    gas_limit=21000
    gas_price=$(cast gas-price --rpc-url "$rpc_url")
    test_fund_amount=$(cast to-wei 0.001)
    mult=2
    chain_id=$(cast chain-id --rpc-url "$rpc_url")

    serialized_tx=$(cast mktx \
                         --chain-id "$chain_id" \
                         --nonce 0 \
                         --priority-gas-price 0 \
                         --gas-price "$gas_price" \
                         --gas-limit "$gas_limit" \
                         --value "$test_fund_amount" \
                         --private-key "$a_private_key" "$(cast az)")
    datafee=$(cast call --rpc-url "$rpc_url" --json 0x420000000000000000000000000000000000000F 'getL1Fee(bytes)(uint256)' "$serialized_tx" | jq -r '.[0]')

    total_fund_amount=$(bc <<< "($mult * $test_fund_amount) + ($mult * $datafee) + ($mult * $gas_limit * $gas_price)" | sed 's/\..*$//')

    cast send \
         --gas-price "$gas_price" \
         --priority-gas-price 0 \
         --gas-limit "$gas_limit" \
         --private-key "$private_key" \
         --value "$total_fund_amount" \
         --rpc-url "$rpc_url" \
         "$a_address"

    cast send \
         --async \
         --gas-price "$gas_price" \
         --priority-gas-price 0 \
         --gas-limit "$gas_limit" \
         --private-key "$a_private_key" \
         --nonce 0 \
         --value 0.001ether \
         --rpc-url "$rpc_url" \
         "$(cast az)"

    cast send \
         --gas-price "$gas_price" \
         --priority-gas-price 0 \
         --gas-limit "$gas_limit" \
         --private-key "$a_private_key" \
         --nonce 1 \
         --value 0.001ether \
         --rpc-url "$rpc_url" \
         "$(cast az)"
}
