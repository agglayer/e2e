#!/usr/bin/env bats

setup() {
    rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    # bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    # private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
}


# bats test_tags=smoke
@test "request finalized safe and latest blocks" {
    prev_finalized_block=0
    prev_safe_block=0
    prev_latest_block=0

    export ETH_RPC_URL="$rpc_url"

    # shellcheck disable=SC2034
    for i in {1..20}; do
        finalized_block=$(cast block-number finalized)
        safe_block=$(cast block-number safe)
        latest_block=$(cast block-number latest)

        if [[ $finalized_block -eq 0 || $safe_block -eq 0 || $latest_block -eq 0 ]]; then
            echo "Safe, finalized, and latest blocks are not all non-zero"
            exit 1
        fi

        if [[ $latest_block -lt $safe_block ]]; then
            echo "The latest block is less than the safe block. This should never happen"
            exit 1
        fi

        if [[ $safe_block -lt $finalized_block ]]; then
            echo "The safe block is less than the finalized block. This should never happen"
            exit 1
        fi

        if [[ $prev_latest_block -gt $latest_block ]]; then
            echo "The latest block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_latest_block" "$latest_block"
            exit 1
        fi

        if [[ $prev_safe_block -gt $safe_block ]]; then
            echo "The safe block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_safe_block" "$safe_block"
            exit 1
        fi

        if [[ $prev_finalized_block -gt $finalized_block ]]; then
            echo "The safe block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_finalized_block" "$finalized_block"
            exit 1
        fi

        prev_finalized_block="$finalized_block"
        prev_safe_block="$safe_block"
        prev_latest_block="$latest_block"

        sleep 2
    done
}
