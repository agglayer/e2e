#!/usr/bin/env bats
# bats file_tags=standard

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    iteration_count=3

    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
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
        run cast rpc zkevm_getForkId --rpc-url "$l2_rpc_url"
        if [[ "$status" -eq 0 ]]; then
            # for cdk-erigon, even invalid transactions can exist in the pool for a short time before being rejected
            # wait for 3 blocks and then recheck if the transaction hash exists
            echo "DEBUG: cdk-erigon detected" >&2
            start_block=$(cast block-number --rpc-url "$l2_rpc_url")
            block_diff=0
            while [[ $block_diff -lt 3 ]]; do
                echo "DEBUG: waiting for 3 blocks to be mined" >&2
                end_block=$(cast block-number --rpc-url "$l2_rpc_url")
                block_diff=$((end_block - start_block))
                sleep 2
            done
            run cast tx $txn_hash --rpc-url "$l2_rpc_url"
            if [[ "$status" -ne 0 ]]; then
                echo "DEBUG: transaction hash is dropped from the pool" >&2
                continue
            else
                echo "Test $index expected fail but succeed: $output" >&2
                return 1
            fi
        else
            # process normally for non-cdk-erigon clients
            if [[ "$txn_status" -ne 1 ]]; then
                echo "Test $index expected fail but succeed: $output" >&2
                return 1
            fi
        fi
    done
    wait < <(jobs -p)
}
