#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7935

# This file implements tests for EIP-7935
# https://eips.ethereum.org/EIPS/eip-7935

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

}

@test "Test block gas limit increase to 60M" {
    bytecode="0x60016222FFFF20"

    # This tx consumes about 10M gas. Lets send few of them and check there is some block close to 60M (or at least over 36M)
    txhashes=()
    nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l1_eth_address")
    for i in $(seq 1 15); do
        run cast send --gas-limit 16000000 --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" --async --nonce "$nonce" --create $bytecode
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to submit transaction to L1, output: $output" >&3
            exit 1
        else
            txhashes+=("$output")
            echo "✅ Successfully submitted transaction $i, nonce=$nonce, txhash=$output" >&3
            nonce=$((nonce + 1))
        fi
    done

    # lets check in which block they were mined
    blocks=()
    for txhash in "${txhashes[@]}"; do
        run cast receipt $txhash --rpc-url "$l1_rpc_url" --json
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to get receipt for transaction $txhash, output: $output" >&3
            exit 1
        fi
        tx_status=$(echo "$output" | jq -r '.status' | cast to-dec)
        if [ "$tx_status" -ne 1 ]; then
            echo "❌ Transaction $txhash was not successful, output: $output" >&3
            exit 1
        fi
        block=$(echo "$output" | jq -r '.blockNumber' | cast to-dec)
        gas_used=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)
        echo "✅ Transaction $txhash was mined in block $block, gas used: $gas_used" >&3
        blocks+=("$block")
    done


    found_block_with_gas_used_over_36M=0

    # Lets check each unique block for its gas
    for block in $(printf "%s\n" "${blocks[@]}" | sort -n | uniq); do
        run cast block $block --rpc-url "$l1_rpc_url" --json
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to retrieve block $block, output: $output" >&3
            exit 1
        fi
        gas_used=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)
        echo "✅ Block $block has gas used: $gas_used" >&3
        if [ "$gas_used" -gt 36000000 ]; then
            found_block_with_gas_used_over_36M=$((found_block_with_gas_used_over_36M + 1))
        fi
    done

    if [ "$found_block_with_gas_used_over_36M" -eq 0 ]; then
        echo "❌ No block found with gas used over 36M" >&3 
        exit 1
    fi
    echo "✅ Found $found_block_with_gas_used_over_36M blocks with gas used over 36M" >&3

}