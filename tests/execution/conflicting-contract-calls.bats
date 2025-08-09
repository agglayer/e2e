#!/usr/bin/env bats
# bats file_tags=standard

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc)"}

    iteration_count=5

    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}

wait_block_increment() {
    local wait_blocks="$1"
    local timeout_seconds="$2"

    start_block=$(cast block-number --rpc-url "$l2_rpc_url")
    echo "DEBUG: starting block: $start_block" >&3
    echo "DEBUG: waiting until: $((start_block + wait_blocks))" >&3
    block_diff=0
    start_time=$(date +%s)
    
    while [[ $block_diff -lt $wait_blocks ]]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        if [[ $elapsed_time -ge $timeout_seconds ]]; then
            echo "ERROR: Timeout of ${timeout_seconds} seconds reached" >&3
            return 1
        fi
        
        current_block=$(cast block-number --rpc-url "$l2_rpc_url")
        echo "DEBUG: current block: $current_block" >&3
        block_diff=$((current_block - start_block))
        sleep 1
    done
}

is_cdk_erigon() {
    run cast rpc zkevm_getForkId --rpc-url "$l2_rpc_url"
    if [[ "$status" -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

@test "Make conflicting contract calls" {
    local ephemeral_data
    local ephemeral_private_key
    local ephemeral_address
    ephemeral_data=$(_generate_ephemeral_account "conflicting-contract-calls")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
    
    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"
    
    index=0;
    nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$l2_rpc_url")
    while true ; do
        index=$((index+1));
        if [[ $index -gt "$iteration_count" ]]; then
            break;
        fi
        echo "DEBUG: cast send --nonce \"$nonce\" --rpc-url \"$l2_rpc_url\" --gas-limit 21000 --gas-price \"$gas_price\" --async --legacy --private-key \"$ephemeral_private_key\" --value $index 0x0000000000000000000000000000000000000000" >&2
        # this should work
        run cast send \
            --nonce "$nonce" \
            --rpc-url "$l2_rpc_url" \
            --gas-limit 21000 \
            --gas-price "$gas_price" \
            --async \
            --legacy \
            --private-key "$ephemeral_private_key" \
            --value $index \
            0x0000000000000000000000000000000000000000
        if [[ "$status" -ne 0 ]]; then
            echo "Test $index expected success but failed: $output" >&2
            return 1
        fi
        echo "Test $index transaction hash: $output" >&2
        index=$((index+1));
        echo "DEBUG: cast send --nonce \"$nonce\" --rpc-url \"$l2_rpc_url\" --gas-limit 21000 --gas-price \"$gas_price\" --async --legacy --private-key \"$ephemeral_private_key\" --value $index 0x0000000000000000000000000000000000000000" >&2
        # this should fail
        run cast send \
            --nonce "$nonce" \
            --rpc-url "$l2_rpc_url" \
            --gas-limit 21000 \
            --gas-price "$gas_price" \
            --async \
            --legacy \
            --private-key "$ephemeral_private_key" \
            --value $index \
            0x0000000000000000000000000000000000000000
        txn_hash=$output
        txn_status=$status
        nonce=$((nonce + 1));
        # check if RPC client is using cdk-erigon
        if is_cdk_erigon; then
            # check if the command succeeded (exit code 0) but transaction failed (status 0 in output)
            if [[ "$txn_status" -eq 0 ]]; then
                # for cdk-erigon, even invalid transactions can exist in the pool for a short time before being rejected
                # wait for 3 blocks and then recheck if the transaction hash exists
                echo "DEBUG: cdk-erigon detected" >&2
                # usage: wait_block_increment <number_of_blocks_to_wait> <timeout_in_seconds>
                wait_block_increment 12 144
                # command succeeded, now check if transaction failed
                run cast tx "$txn_hash" --rpc-url "$l2_rpc_url"
                if [[ "$status" -ne 0 ]]; then
                    echo "Transaction correctly failed as expected" >&3
                else
                    echo "Test expected transaction to not exists but exists: $output" >&3
                    return 1
                fi
            else
                # transaction fails immediately as expected
                echo "Transaction correctly failed as expected" >&3
            fi
        else
            # process normally for non-cdk-erigon clients
            if [[ "$txn_status" -ne 1 ]]; then
                echo "Test $index expected fail but succeeded: $txn_hash" >&2
                return 1
            fi
        fi
    done
    for job in $(jobs -p); do wait "$job"; done
}
