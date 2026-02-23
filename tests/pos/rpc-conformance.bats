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

# ---------------------------------------------------------------------------
# eth_getBalance
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "eth_getBalance returns non-zero for funded account and zero for unused address" {
    # Funded account.
    balance_raw=$(cast rpc eth_getBalance "\"$eth_address\"" '"latest"' --rpc-url "$L2_RPC_URL")
    balance_raw=$(echo "$balance_raw" | tr -d '"')
    if ! [[ "$balance_raw" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "eth_getBalance returned non-hex: $balance_raw" >&2
        return 1
    fi
    balance_dec=$(cast to-dec "$balance_raw")
    if [[ "$balance_dec" -eq 0 ]]; then
        echo "Expected non-zero balance for funded address $eth_address, got 0" >&2
        return 1
    fi

    # Fresh (unused) address must have zero balance.
    fresh_addr=$(cast wallet new --json | jq -r '.[0].address')
    fresh_raw=$(cast rpc eth_getBalance "\"$fresh_addr\"" '"latest"' --rpc-url "$L2_RPC_URL")
    fresh_raw=$(echo "$fresh_raw" | tr -d '"')
    fresh_dec=$(cast to-dec "$fresh_raw")
    if [[ "$fresh_dec" -ne 0 ]]; then
        echo "Expected zero balance for unused address, got: $fresh_dec" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# eth_getTransactionByHash / eth_getTransactionByBlockNumberAndIndex
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "eth_getTransactionByHash and ByBlockNumberAndIndex return consistent tx data" {
    # Send a tx so we have something to query.
    receipt=$(cast send --legacy --gas-limit 21000 --private-key "$PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" --json 0x0000000000000000000000000000000000000000)

    tx_hash=$(echo "$receipt" | jq -r '.transactionHash')
    block_number=$(echo "$receipt" | jq -r '.blockNumber')
    tx_index=$(echo "$receipt" | jq -r '.transactionIndex')

    # eth_getTransactionByHash
    tx_by_hash=$(cast rpc eth_getTransactionByHash "\"$tx_hash\"" --rpc-url "$L2_RPC_URL")
    hash_from_result=$(echo "$tx_by_hash" | jq -r '.hash')
    if [[ "$hash_from_result" != "$tx_hash" ]]; then
        echo "eth_getTransactionByHash returned wrong hash: $hash_from_result" >&2
        return 1
    fi

    # eth_getTransactionByBlockNumberAndIndex
    tx_by_idx=$(cast rpc eth_getTransactionByBlockNumberAndIndex \
        "\"$block_number\"" "\"$tx_index\"" --rpc-url "$L2_RPC_URL")
    hash_from_idx=$(echo "$tx_by_idx" | jq -r '.hash')
    if [[ "$hash_from_idx" != "$tx_hash" ]]; then
        echo "eth_getTransactionByBlockNumberAndIndex returned wrong hash: $hash_from_idx" >&2
        return 1
    fi

    # Cross-check: 'from' field must be identical.
    from_hash=$(echo "$tx_by_hash" | jq -r '.from')
    from_idx=$(echo "$tx_by_idx" | jq -r '.from')
    if [[ "$(echo "$from_hash" | tr '[:upper:]' '[:lower:]')" != "$(echo "$from_idx" | tr '[:upper:]' '[:lower:]')" ]]; then
        echo "Inconsistent 'from': byHash=$from_hash byIndex=$from_idx" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# eth_getTransactionCount
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "eth_getTransactionCount returns hex nonce matching cast nonce" {
    result=$(cast rpc eth_getTransactionCount "\"$eth_address\"" '"latest"' --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')
    if ! [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "eth_getTransactionCount returned non-hex: $result" >&2
        return 1
    fi
    nonce_rpc=$(cast to-dec "$result")
    nonce_cast=$(cast nonce "$eth_address")
    if [[ "$nonce_rpc" != "$nonce_cast" ]]; then
        echo "eth_getTransactionCount ($nonce_rpc) != cast nonce ($nonce_cast)" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# eth_getBlockTransactionCountByNumber / ByHash
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc,evm-block
@test "eth_getBlockTransactionCountByNumber and ByHash agree on tx count" {
    block=$(cast rpc eth_getBlockByNumber '"latest"' 'false' --rpc-url "$L2_RPC_URL")
    block_number=$(echo "$block" | jq -r '.number')
    block_hash=$(echo "$block" | jq -r '.hash')
    actual_count=$(echo "$block" | jq '.transactions | length')

    count_by_num=$(cast rpc eth_getBlockTransactionCountByNumber "\"$block_number\"" --rpc-url "$L2_RPC_URL")
    count_by_num=$(echo "$count_by_num" | tr -d '"')
    count_by_num_dec=$(cast to-dec "$count_by_num")

    count_by_hash=$(cast rpc eth_getBlockTransactionCountByHash "\"$block_hash\"" --rpc-url "$L2_RPC_URL")
    count_by_hash=$(echo "$count_by_hash" | tr -d '"')
    count_by_hash_dec=$(cast to-dec "$count_by_hash")

    if [[ "$count_by_num_dec" != "$actual_count" ]]; then
        echo "ByNumber count ($count_by_num_dec) != block tx array length ($actual_count)" >&2
        return 1
    fi
    if [[ "$count_by_hash_dec" != "$actual_count" ]]; then
        echo "ByHash count ($count_by_hash_dec) != block tx array length ($actual_count)" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# eth_getStorageAt
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "eth_getStorageAt returns zero for EOA and valid 32-byte word for contracts" {
    # EOA storage slot 0 must be the zero word.
    result=$(cast rpc eth_getStorageAt "\"$eth_address\"" '"0x0"' '"latest"' --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')
    zero_word="0x0000000000000000000000000000000000000000000000000000000000000000"
    if [[ "$result" != "$zero_word" ]]; then
        echo "Expected zero word for EOA storage slot 0, got: $result" >&2
        return 1
    fi

    # StateReceiver is a system contract — its storage response must be a valid 32-byte hex word.
    sr_result=$(cast rpc eth_getStorageAt "\"$L2_STATE_RECEIVER_ADDRESS\"" '"0x0"' '"latest"' --rpc-url "$L2_RPC_URL")
    sr_result=$(echo "$sr_result" | tr -d '"')
    if ! [[ "$sr_result" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo "eth_getStorageAt for StateReceiver returned invalid format: $sr_result" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# EIP-1559: eth_maxPriorityFeePerGas / eth_feeHistory
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc,evm-gas
@test "eth_maxPriorityFeePerGas returns a valid hex value" {
    result=$(cast rpc eth_maxPriorityFeePerGas --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')
    if ! [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "eth_maxPriorityFeePerGas returned non-hex: $result" >&2
        return 1
    fi
    echo "eth_maxPriorityFeePerGas: $(cast to-dec "$result") wei" >&3
}

# bats test_tags=evm-rpc,evm-gas
@test "eth_feeHistory returns baseFeePerGas array and oldestBlock" {
    # Request 4 blocks of history with no reward percentiles.
    result=$(cast rpc eth_feeHistory '"0x4"' '"latest"' '[]' --rpc-url "$L2_RPC_URL")

    # Must contain oldestBlock.
    oldest=$(echo "$result" | jq -r '.oldestBlock // empty')
    if [[ -z "$oldest" ]]; then
        echo "eth_feeHistory missing oldestBlock" >&2
        return 1
    fi

    # baseFeePerGas: array with >= 1 valid hex entries.
    base_fee_len=$(echo "$result" | jq '.baseFeePerGas | length')
    if [[ "$base_fee_len" -lt 1 ]]; then
        echo "eth_feeHistory returned empty baseFeePerGas array" >&2
        return 1
    fi
    invalid_fees=$(echo "$result" | jq '[.baseFeePerGas[] | select(test("^0x[0-9a-fA-F]+$") | not)] | length')
    if [[ "$invalid_fees" -gt 0 ]]; then
        echo "eth_feeHistory has $invalid_fees invalid baseFeePerGas entries" >&2
        return 1
    fi

    # gasUsedRatio: array of numbers.
    ratio_len=$(echo "$result" | jq '.gasUsedRatio | length')
    if [[ "$ratio_len" -lt 1 ]]; then
        echo "eth_feeHistory returned empty gasUsedRatio array" >&2
        return 1
    fi

    echo "eth_feeHistory: oldestBlock=$oldest baseFees=$base_fee_len ratios=$ratio_len" >&3
}

# ---------------------------------------------------------------------------
# eth_getBlockByNumber fullTransactions=true
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc,evm-block
@test "eth_getBlockByNumber with fullTransactions=true returns full tx objects" {
    # Send a tx so the block definitely contains one.
    receipt=$(cast send --legacy --gas-limit 21000 --private-key "$PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" --json 0x0000000000000000000000000000000000000000)
    block_number=$(echo "$receipt" | jq -r '.blockNumber')

    block=$(cast rpc eth_getBlockByNumber "\"$block_number\"" 'true' --rpc-url "$L2_RPC_URL")

    tx_count=$(echo "$block" | jq '.transactions | length')
    if [[ "$tx_count" -eq 0 ]]; then
        echo "Block $block_number has no transactions (expected at least 1)" >&2
        return 1
    fi

    # With fullTransactions=true, entries must be objects (not hash strings).
    first_type=$(echo "$block" | jq -r '.transactions[0] | type')
    if [[ "$first_type" != "object" ]]; then
        echo "Expected full tx objects, got JSON type: $first_type" >&2
        return 1
    fi

    # Full tx objects must contain standard fields.
    for field in hash from to gas nonce value blockNumber transactionIndex; do
        val=$(echo "$block" | jq -r ".transactions[0].$field // empty")
        if [[ -z "$val" ]]; then
            echo "Full tx object missing required field: $field" >&2
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# net_version / web3_clientVersion
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "net_version returns a non-empty numeric string" {
    result=$(cast rpc net_version --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')
    if ! [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "net_version returned non-numeric: $result" >&2
        return 1
    fi
    echo "net_version: $result" >&3
}

# bats test_tags=evm-rpc
@test "web3_clientVersion returns a non-empty version string" {
    result=$(cast rpc web3_clientVersion --rpc-url "$L2_RPC_URL")
    result=$(echo "$result" | tr -d '"')
    if [[ -z "$result" ]]; then
        echo "web3_clientVersion returned empty string" >&2
        return 1
    fi
    echo "web3_clientVersion: $result" >&3
}

# ---------------------------------------------------------------------------
# Block field validation (post-London)
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc,evm-block
@test "latest block contains required post-London fields and valid shapes" {
    block=$(cast rpc eth_getBlockByNumber '"latest"' 'false' --rpc-url "$L2_RPC_URL")

    # baseFeePerGas: present and non-zero (mandatory post-London/EIP-1559).
    base_fee=$(echo "$block" | jq -r '.baseFeePerGas // empty')
    if [[ -z "$base_fee" ]]; then
        echo "Block missing baseFeePerGas (required post-London)" >&2
        return 1
    fi
    if [[ "$(cast to-dec "$base_fee")" -eq 0 ]]; then
        echo "baseFeePerGas is zero (expected non-zero)" >&2
        return 1
    fi

    # mixHash (prevRandao post-Merge): 32-byte hex.
    mix_hash=$(echo "$block" | jq -r '.mixHash // empty')
    if [[ -z "$mix_hash" ]]; then
        echo "Block missing mixHash (prevRandao) field" >&2
        return 1
    fi
    if ! [[ "$mix_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo "mixHash has invalid shape: $mix_hash (expected 0x + 64 hex chars)" >&2
        return 1
    fi

    # Standard header fields must be present.
    for field in number hash parentHash stateRoot transactionsRoot receiptsRoot \
                 miner gasLimit gasUsed timestamp logsBloom; do
        val=$(echo "$block" | jq -r ".$field // empty")
        if [[ -z "$val" ]]; then
            echo "Block missing required field: $field" >&2
            return 1
        fi
    done

    # gasLimit must be positive.
    gas_limit=$(echo "$block" | jq -r '.gasLimit')
    if [[ "$(cast to-dec "$gas_limit")" -eq 0 ]]; then
        echo "gasLimit is zero" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Bor-specific RPC methods
# ---------------------------------------------------------------------------

# bats test_tags=evm-rpc
@test "bor_getSnapshot returns snapshot with validator data" {
    set +e
    result=$(cast rpc bor_getSnapshot '"latest"' --rpc-url "$L2_RPC_URL" 2>&1)
    rpc_exit=$?
    set -e

    if [[ $rpc_exit -ne 0 ]]; then
        if echo "$result" | grep -qi "method not found\|not supported\|does not exist\|no such method"; then
            skip "bor_getSnapshot not available on this node"
        fi
        echo "bor_getSnapshot RPC error: $result" >&2
        return 1
    fi

    # Snapshot must contain a validatorSet or validators field.
    has_vals=$(echo "$result" | jq 'has("validatorSet") or has("validators")')
    if [[ "$has_vals" != "true" ]]; then
        echo "bor_getSnapshot missing validatorSet/validators: $(echo "$result" | head -c 300)" >&2
        return 1
    fi
}

# bats test_tags=evm-rpc
@test "bor_getAuthor returns a valid address for latest block" {
    set +e
    result=$(cast rpc bor_getAuthor '"latest"' --rpc-url "$L2_RPC_URL" 2>&1)
    rpc_exit=$?
    set -e

    if [[ $rpc_exit -ne 0 ]]; then
        if echo "$result" | grep -qi "method not found\|not supported\|does not exist\|no such method"; then
            skip "bor_getAuthor not available on this node"
        fi
        echo "bor_getAuthor RPC error: $result" >&2
        return 1
    fi

    result=$(echo "$result" | tr -d '"')
    if ! [[ "$result" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        echo "bor_getAuthor returned invalid address: $result" >&2
        return 1
    fi
    echo "bor_getAuthor: $result" >&3
}

# bats test_tags=evm-rpc
@test "bor_getCurrentValidators returns a non-empty validator list" {
    set +e
    result=$(cast rpc bor_getCurrentValidators --rpc-url "$L2_RPC_URL" 2>&1)
    rpc_exit=$?
    set -e

    if [[ $rpc_exit -ne 0 ]]; then
        if echo "$result" | grep -qi "method not found\|not supported\|does not exist\|no such method"; then
            skip "bor_getCurrentValidators not available on this node"
        fi
        echo "bor_getCurrentValidators RPC error: $result" >&2
        return 1
    fi

    count=$(echo "$result" | jq 'if type == "array" then length else 0 end')
    if [[ "$count" -eq 0 ]]; then
        echo "bor_getCurrentValidators returned empty or non-array result" >&2
        return 1
    fi
    echo "bor_getCurrentValidators: $count validators" >&3
}
