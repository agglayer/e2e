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
    block_by_number=$(cast rpc eth_getBlockByNumber '"latest"' 'false' --rpc-url "$L2_RPC_URL")
    block_number=$(echo "$block_by_number" | jq -r '.number')
    block_hash=$(echo "$block_by_number" | jq -r '.hash')

    block_by_hash=$(cast rpc eth_getBlockByHash "\"$block_hash\"" 'false' --rpc-url "$L2_RPC_URL")
    number_from_hash=$(echo "$block_by_hash" | jq -r '.number')

    if [[ "$block_number" != "$number_from_hash" ]]; then
        echo "block number from eth_getBlockByNumber ($block_number) != eth_getBlockByHash ($number_from_hash)" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getTransactionReceipt returns null for unknown transaction hash" {
    result=$(cast rpc eth_getTransactionReceipt '"0x0000000000000000000000000000000000000000000000000000000000000000"' --rpc-url "$L2_RPC_URL")
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

    # Bor returns -32000 "invalid block range params" for future blocks; other nodes
    # may return [].  Both are acceptable — the only invalid outcome is a non-empty
    # array, which would mean the node fabricated logs for a block that doesn't exist.
    result=$(cast rpc eth_getLogs "{\"fromBlock\": \"$future_block_hex\", \"toBlock\": \"$future_block_hex\"}" \
        --rpc-url "$L2_RPC_URL" 2>&1) || true
    if echo "$result" | jq -e 'type == "array" and length > 0' &>/dev/null; then
        echo "Expected empty response for future block range, got non-empty log array: $result" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getLogs for block 0 to 0 returns a valid array" {
    result=$(cast rpc eth_getLogs '{"fromBlock": "0x0", "toBlock": "0x0"}' --rpc-url "$L2_RPC_URL")
    type=$(echo "$result" | jq -r 'type')
    if [[ "$type" != "array" ]]; then
        echo "Expected array from eth_getLogs block 0-0, got type: $type" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc,evm-gas
@test "eth_gasPrice returns a valid non-zero hex value" {
    result=$(cast rpc eth_gasPrice --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')

    if ! [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "eth_gasPrice returned non-hex value: $result" >&2
        return 1
    fi

    price_dec=$(cast to-dec "$result")
    if [[ "$price_dec" -eq 0 ]]; then
        echo "eth_gasPrice returned zero — a positive gas price is required" >&2
        return 1
    fi
    echo "eth_gasPrice: $price_dec wei" >&3
}

# bats test_tags=evm-rpc
@test "eth_getCode returns 0x for an EOA" {
    code=$(cast code "$eth_address" --rpc-url "$L2_RPC_URL")
    if [[ "$code" != "0x" ]]; then
        echo "Expected 0x for EOA eth_getCode, got: $code" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "eth_getCode returns non-empty bytecode for L2 StateReceiver contract" {
    # L2_STATE_RECEIVER_ADDRESS is a system contract pre-deployed at genesis by Bor.
    # Its code must be non-empty; an empty result would indicate a broken genesis state.
    code=$(cast code "$L2_STATE_RECEIVER_ADDRESS" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        echo "Expected non-empty code for StateReceiver ($L2_STATE_RECEIVER_ADDRESS), got: $code" >&2
        return 1
    fi
    echo "StateReceiver code length: $(( (${#code} - 2) / 2 )) bytes" >&3
}

# bats test_tags=evm-rpc
@test "eth_getLogs with reversed block range returns error or empty array" {
    # fromBlock > toBlock is either an error or an empty array — never a non-empty result.
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    if [[ "$latest_block" -lt 1 ]]; then
        skip "Need at least block 1 to form a reversed range"
    fi

    from_hex=$(cast to-hex "$latest_block")
    to_hex=$(cast to-hex "$(( latest_block - 1 ))")

    result=$(cast rpc eth_getLogs "{\"fromBlock\": \"$from_hex\", \"toBlock\": \"$to_hex\"}" \
        --rpc-url "$L2_RPC_URL" 2>&1) || true

    # Acceptable: a JSON-RPC error object, or an empty array [].
    # Not acceptable: a non-empty array with log entries.
    if echo "$result" | jq -e 'type == "array" and length > 0' &>/dev/null; then
        echo "eth_getLogs with reversed range returned non-empty log array: $result" >&2
        return 1
    fi
}
