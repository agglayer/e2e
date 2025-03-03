setup() {
    rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    # bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    eth_address=$(cast wallet address --private-key "$private_key")
    export ETH_RPC_URL="$rpc_url"
}

# bats test_tags=smoke
@test "sweep account with precise gas and DA fee calculation" {
    wallet_info=$(cast wallet new --json | jq '.[0]')
    tmp_address=$(echo "$wallet_info" | jq -r '.address')
    tmp_private_key=$(echo "$wallet_info" | jq -r '.private_key')

    # Send 0.01 ETH to the new address
    cast send \
         --value "10000000000000000" \
         --private-key "$private_key" "$tmp_address"

    gas_price=$(cast gas-price)
    gas_price=$(bc <<< "$gas_price * 2")

    serialized_tx_len=$(cast mktx \
         --gas-price "$gas_price" \
         --gas-limit 21000 \
         --value "10000000000000000" \
         --private-key "$tmp_private_key" "$eth_address" | wc -c)
    serialized_tx_len=$(bc <<< "(($serialized_tx_len - 1) / 2) - 1")
    da_cost=$(cast call --json 0x420000000000000000000000000000000000000F 'getL1Fee(bytes)(uint256)' "$(printf "0x%x" "$serialized_tx_len")" | jq -r '.[0]')

    # some fudge factor might be needed here since the da costs change very rapidly
    fudge_factor=1.05
    value_to_return=$(bc <<< "10000000000000000 - (21000 * $gas_price) - ($da_cost * $fudge_factor)" | sed 's/\..*$//')

    printf "Attempting to return $value_to_return wei based on DA cost of $da_cost, gas price $gas_price, and gas limit of 21,000\n"
    cast send \
         --gas-price "$gas_price" \
         --gas-limit 21000 \
         --value "$value_to_return" \
         --private-key "$tmp_private_key" "$eth_address"

}
