#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip11

# PIP-11: Deterministic Finality via Milestones
# https://github.com/maticnetwork/Polygon-Improvement-Proposals/blob/main/PIPs/PIP-11.md
#
# Bor implements milestone-based finality: the chain is locked at milestone points
# and cannot be reorged beyond them. This enables the "finalized" block tag in
# eth_getBlockByNumber, similar to Ethereum's beacon-chain finality.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=execution-specs,pip11,finality
@test "PIP-11: eth_getBlockByNumber 'finalized' returns a valid block" {
    # The "finalized" tag should return a block that has been finalized by
    # the milestone mechanism. If not supported, the RPC returns an error.
    set +e
    local result
    result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["finalized",false]}' \
        "$L2_RPC_URL")
    set -e

    # Check for RPC error
    local error
    error=$(echo "$result" | jq -r '.error.message // empty')
    if [[ -n "$error" ]]; then
        skip "Node does not support 'finalized' block tag: $error"
    fi

    # Extract block fields
    local block_number
    block_number=$(echo "$result" | jq -r '.result.number // empty')
    local block_hash
    block_hash=$(echo "$result" | jq -r '.result.hash // empty')

    if [[ -z "$block_number" || -z "$block_hash" ]]; then
        echo "Finalized block response missing number or hash" >&2
        echo "Response: $(echo "$result" | jq -c '.result')" >&2
        return 1
    fi

    local block_num_dec
    block_num_dec=$(printf "%d" "$block_number")

    echo "Finalized block: number=$block_num_dec hash=$block_hash" >&3

    if [[ "$block_num_dec" -lt 0 ]]; then
        echo "Finalized block number is negative: $block_num_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip11,finality
@test "PIP-11: finalized block number is less than or equal to latest block number" {
    # The finalized block must always be at or behind the latest block.
    # Finality lags behind the chain tip by the milestone confirmation delay.
    set +e
    local finalized_result
    finalized_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["finalized",false]}' \
        "$L2_RPC_URL")
    set -e

    local error
    error=$(echo "$finalized_result" | jq -r '.error.message // empty')
    if [[ -n "$error" ]]; then
        skip "Node does not support 'finalized' block tag: $error"
    fi

    local finalized_hex
    finalized_hex=$(echo "$finalized_result" | jq -r '.result.number // empty')
    if [[ -z "$finalized_hex" ]]; then
        skip "Finalized block response has no number field"
    fi

    local finalized_dec
    finalized_dec=$(printf "%d" "$finalized_hex")

    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Finalized: $finalized_dec, Latest: $latest_block" >&3

    if [[ "$finalized_dec" -gt "$latest_block" ]]; then
        echo "Finalized block ($finalized_dec) is ahead of latest ($latest_block)" >&2
        return 1
    fi

    local lag=$(( latest_block - finalized_dec ))
    echo "Finality lag: $lag blocks" >&3
}

# bats test_tags=execution-specs,pip11,finality
@test "PIP-11: 'safe' block tag returns a valid block between finalized and latest" {
    # Bor also supports the "safe" block tag which should be between
    # finalized and latest (or equal to either).
    set +e
    local safe_result
    safe_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["safe",false]}' \
        "$L2_RPC_URL")
    set -e

    local error
    error=$(echo "$safe_result" | jq -r '.error.message // empty')
    if [[ -n "$error" ]]; then
        skip "Node does not support 'safe' block tag: $error"
    fi

    local safe_hex
    safe_hex=$(echo "$safe_result" | jq -r '.result.number // empty')
    if [[ -z "$safe_hex" ]]; then
        skip "Safe block response has no number field"
    fi

    local safe_dec
    safe_dec=$(printf "%d" "$safe_hex")

    # Get finalized
    local finalized_result
    finalized_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["finalized",false]}' \
        "$L2_RPC_URL")
    local finalized_hex
    finalized_hex=$(echo "$finalized_result" | jq -r '.result.number // empty')

    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Safe: $safe_dec, Latest: $latest_block" >&3

    if [[ "$safe_dec" -gt "$latest_block" ]]; then
        echo "Safe block ($safe_dec) is ahead of latest ($latest_block)" >&2
        return 1
    fi

    # If finalized is available, safe should be >= finalized
    if [[ -n "$finalized_hex" ]]; then
        local finalized_dec
        finalized_dec=$(printf "%d" "$finalized_hex")
        echo "Finalized: $finalized_dec" >&3
        if [[ "$safe_dec" -lt "$finalized_dec" ]]; then
            echo "Safe block ($safe_dec) is behind finalized ($finalized_dec)" >&2
            return 1
        fi
    fi
}
