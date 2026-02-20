#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    # Load libraries.
    load "../../core/helpers/pos-setup.bash"
    pos_setup

    eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")
    export ETH_RPC_URL="$L2_RPC_URL"
}

# bats test_tags=evm-rpc
@test "eth_chainId returns a value matching cast chain-id" {
    chain_id_hex=$(cast rpc eth_chainId --rpc-url "$L2_RPC_URL")
    # strip quotes if present
    chain_id_hex=$(echo "$chain_id_hex" | tr -d '"')
    chain_id_dec=$(cast to-dec "$chain_id_hex")
    expected=$(cast chain-id)
    if [[ "$chain_id_dec" != "$expected" ]]; then
        echo "eth_chainId $chain_id_dec != cast chain-id $expected" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc,evm-block
@test "eth_getBlockByHash result matches eth_getBlockByNumber for latest block" {
    block_by_number=$(cast rpc eth_getBlockByNumber '["latest", false]' --rpc-url "$L2_RPC_URL")
    block_number=$(echo "$block_by_number" | jq -r '.number')
    block_hash=$(echo "$block_by_number" | jq -r '.hash')

    block_by_hash=$(cast rpc eth_getBlockByHash "[\"$block_hash\", false]" --rpc-url "$L2_RPC_URL")
    number_from_hash=$(echo "$block_by_hash" | jq -r '.number')

    if [[ "$block_number" != "$number_from_hash" ]]; then
        echo "block number from eth_getBlockByNumber ($block_number) != eth_getBlockByHash ($number_from_hash)" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getTransactionReceipt returns null for unknown transaction hash" {
    result=$(cast rpc eth_getTransactionReceipt '["0x0000000000000000000000000000000000000000000000000000000000000000"]' --rpc-url "$L2_RPC_URL")
    if [[ "$result" != "null" ]]; then
        echo "Expected null for unknown tx hash, got: $result" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc,evm-gas
@test "eth_estimateGas for EOA transfer returns 21000" {
    gas=$(cast estimate --value 1 0x0000000000000000000000000000000000000000)
    if [[ "$gas" -ne 21000 ]]; then
        echo "Expected 21000 gas for EOA transfer, got: $gas" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_call to plain EOA returns 0x" {
    result=$(cast call "$eth_address" "0x")
    if [[ "$result" != "0x" ]]; then
        echo "Expected 0x from eth_call to EOA, got: $result" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getLogs returns empty array for future block range" {
    latest_block=$(cast block-number)
    future_block=$(( latest_block + 1000 ))
    future_block_hex=$(cast to-hex "$future_block")

    result=$(cast rpc eth_getLogs "[{\"fromBlock\": \"$future_block_hex\", \"toBlock\": \"$future_block_hex\"}]" --rpc-url "$L2_RPC_URL")
    length=$(echo "$result" | jq 'length')
    if [[ "$length" -ne 0 ]]; then
        echo "Expected empty array for future block range, got length: $length" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getLogs for block 0 to 0 returns a valid array" {
    result=$(cast rpc eth_getLogs '[{"fromBlock": "0x0", "toBlock": "0x0"}]' --rpc-url "$L2_RPC_URL")
    type=$(echo "$result" | jq -r 'type')
    if [[ "$type" != "array" ]]; then
        echo "Expected array from eth_getLogs block 0-0, got type: $type" >&2
        return 1
    fi
}
