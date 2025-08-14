#!/usr/bin/env bats
# bats file_tags=pectra
#
# This file implements tests for EIP-7685: General purpose execution layer requests
# https://eips.ethereum.org/EIPS/eip-7685
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

    EMPTY_REQUESTS_HASH=$(echo -n "" | openssl dgst -sha256 -binary | xxd -p -c 256 | sed 's/^/0x/')
    export EMPTY_REQUESTS_HASH
}

function eip7685_check_block() {
    block_number=$1
    if (( block_number < 0 )); then
        echo "❌ Block number cannot be negative: $block_number"
        false
    fi

    run cast block "$block_number" --rpc-url "$l2_rpc_url" --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to retrieve block $block_number"
        echo "Error: $output"
        false
    else
        requestsHash=$(echo $output | jq -r .requestsHash)
        if [ -z "$requestsHash" ]; then
            echo "❌ No requestsHash found for block number $block_number"
            false
        else
            if [ "$requestsHash" == "$EMPTY_REQUESTS_HASH" ]; then
                echo "✅ Successfully retrieved requestsHash for block number $block_number: $requestsHash (empty requests list)"
            else
                echo "✅ Successfully retrieved requestsHash for block number $block_number: $requestsHash"
            fi
        fi
    fi
}

@test "EIP-7685: RequestsHash in block header" {
    # we wait for current_block to be at least 10:
    current_block=$(cast block-number --rpc-url "$l2_rpc_url")
    if ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
        echo "❌ Failed to retrieve current block number, got: $current_block"
        false
    fi
    while (( current_block < 10 )); do
        echo "⏳ Waiting for current block to reach 10 (current: $current_block)"
        sleep 3
        current_block=$(cast block-number --rpc-url "$l2_rpc_url")
        if ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
            echo "❌ Failed to retrieve current block number, got: $current_block"
            false
        fi
    done

    # we loop from current_block to current_block - 10:
    for ((block_number = current_block; block_number > current_block - 10; block_number--)); do
        eip7685_check_block "$block_number"
    done
}
