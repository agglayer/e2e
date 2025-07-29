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
    if [[ -n "$L2_RPC_URL" ]]; then
        export l2_rpc_url="$L2_RPC_URL"
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc 2>/dev/null); then
        export l2_rpc_url
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc 2>/dev/null); then
        export l2_rpc_url
    else
        echo "❌ Failed to determine L2 RPC URL. Please set L2_RPC_URL" >&2
        exit 1
    fi

    export HISTORY_STORAGE_ADDRESS="0x0000F90827F1C53a10cb7A02335B175320002935"
    export HISTORY_SERVE_WINDOW=8191

    export num_random_blocks_to_check=${NUM_RANDOM_BLOCKS:-30}
    export num_random_blocks_to_check_fail=${NUM_RANDOM_BLOCKS_FAIL:-10}
}

function eip2935_check_block() {
    block_number=$1
    if (( block_number < 0 )); then
        echo "❌ Block number cannot be negative: $block_number"
        false
    fi

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
    if (( block_number < 0 )); then
        echo "❌ Block number cannot be negative: $block_number"
        false
    fi

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
    if (( oldest_block < 0 )); then
        oldest_block=0
    fi

    range=$((current_block - oldest_block))
    if (( range > HISTORY_SERVE_WINDOW )); then
        range=HISTORY_SERVE_WINDOW
    fi

    for _ in $(seq 1 "$num_random_blocks_to_check"); do
        # pick random offset within window
        offset=$((RANDOM % range))
        block_to_check=$((oldest_block + offset))

        eip2935_check_block "$block_to_check"
    done
}

@test "EIP-2935: Oldest possible historical block hash from state" {
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    echo "Current block: $current_block"

    # Adding one to avoid race condition with the current block number
    block_to_check=$((current_block - HISTORY_SERVE_WINDOW + 1))
    if (( block_to_check < 0 )); then
        block_to_check=0
    fi
    eip2935_check_block "$block_to_check"
}

@test "EIP-2935: Checking blocks outside historical serve window" {
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    oldest_block=$((current_block - HISTORY_SERVE_WINDOW))
    # not enough time has passed to have a block outside the window, let's fail the test
    if (( oldest_block < 0 )); then
        echo "❌ Not enough blocks produced to test outside the historical serve window (current block: $current_block, serve_window: $HISTORY_SERVE_WINDOW)"
        true
        return
    fi

    range=oldest_block
    if (( range > HISTORY_SERVE_WINDOW )); then
        range=HISTORY_SERVE_WINDOW
    fi

    for _ in $(seq 1 "$num_random_blocks_to_check_fail"); do
        # pick random offset within window
        offset=$((RANDOM % range))
        block_to_check=$((oldest_block - offset))

        eip2935_check_block_fail "$block_to_check"
    done
}