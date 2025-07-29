#!/usr/bin/env bats

#
# This file implements tests for EIP-2935: Serve historical block hashes from state
# https://eips.ethereum.org/EIPS/eip-2935
#

setup() {
    true
}


setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"pectra"}
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    export HISTORY_STORAGE_ADDRESS="0x0000F90827F1C53a10cb7A02335B175320002935"
    export HISTORY_SERVE_WINDOW=8191

    export num_random_blocks_to_check=${NUM_RANDOM_BLOCKS:-30}
    export num_random_blocks_to_check_fail=${NUM_RANDOM_BLOCKS_FAIL:-10}
}

function eip2935_check_block() {
    block_number=$1
    padded_block=$(printf "%064x" "$block_number")

    echo "🔍 Running EIP-2935 check block for block number $block_number"

    current_block=$(cast block-number --rpc-url "$l2_rpc_url")

    # let's check it's at most $HISTORY_SERVE_WINDOW blocks behind
    if (( block_number < current_block - HISTORY_SERVE_WINDOW )); then
        echo "❌ Block number $block_number is too old to be served by the history storage contract"
        false
    fi

    run cast call "$HISTORY_STORAGE_ADDRESS" $padded_block --rpc-url "$l2_rpc_url"

    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to call history storage contract for block number $block_number"
        echo "Error: $output"
        false
    else
        # lets check the output is the right block hash
        expected_hash=$(cast block "$block_number" --field hash --rpc-url "$l2_rpc_url")
        if [ "$output" != "$expected_hash" ]; then
            echo "❌ Block hash for block number $block_number does not match"
            echo "Expected: $expected_hash"
            echo "Got:      $output"
            false
        fi
        echo "✅ Successfully called history storage contract for block number $block_number, block hash matches: $output"
    fi
}

function eip2935_check_block_fail() {
    block_number=$1
    padded_block=$(printf "%064x" "$block_number")

    echo "🔍 Running EIP-2935 check block for block number $block_number (expected to fail)"

    run cast call "$HISTORY_STORAGE_ADDRESS" $padded_block --rpc-url "$l2_rpc_url"

    if [ "$status" -ne 1 ]; then
        echo "❌ We expected to fail but the call to history storage contract for block number $block_number succeeded"
        echo "Result: $output"
        false
    else
        echo "✅ Successfully failed to call history storage contract for block number $block_number as expected"
        echo "Error: $output"
    fi
}

@test "EIP-2935: Random historical block hashes from state" {
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    oldest_block=$((current_block - HISTORY_SERVE_WINDOW))

    for i in $(seq 1 "$num_random_blocks_to_check"); do
        # pick random offset within window
        offset=$((RANDOM % HISTORY_SERVE_WINDOW))
        block_to_check=$((oldest_block + offset))

        eip2935_check_block "$block_to_check"
    done
}

@test "EIP-2935: Oldest possible historical block hash from state" {
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    echo "Current block: $current_block"

    # Adding one to avoid race condition with the current block number
    block_to_check=$((current_block - HISTORY_SERVE_WINDOW + 1))
    eip2935_check_block "$block_to_check"
}

@test "EIP-2935: Checking blocks outside historical serve window" {
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    oldest_block=$((current_block - HISTORY_SERVE_WINDOW))

    for i in $(seq 1 "$num_random_blocks_to_check_fail"); do
        # pick random offset within window
        offset=$((RANDOM % HISTORY_SERVE_WINDOW))
        block_to_check=$((oldest_block - offset))

        eip2935_check_block_fail "$block_to_check"
    done
}