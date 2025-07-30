#!/usr/bin/env bats
# bats file_tags=standard

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}


@test "Make conflicting transaction to pool" {
    local ephemeral_data
    local ephemeral_private_key
    local ephemeral_address
    ephemeral_data=$(_generate_ephemeral_account "conflicting-transactions-to-pool")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
    
    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"
    
    nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$l2_rpc_url")

    # Send a future transaction that uses a lot of more than half of my balance
    run cast send \
            --nonce $((nonce + 1)) \
            --rpc-url "$l2_rpc_url" \
            --gas-limit 21000 \
            --gas-price "$gas_price" \
            --async \
            --legacy \
            --private-key "$ephemeral_private_key" \
            --value 0.5ether \
            0xC0FFEE0000000000000000000000000000000000;
    # echo "Command output: $output" >&3
    echo "Command status: $status" >&3
    if [[ "$status" -ne 0 ]]; then
        echo "Test expected success but failed: $output" >&3
        echo "Command status: $status" >&3
        return 1
    fi

    # let it process a bit
    sleep 5

    # send another transaction that should fail and also use more than half of my balance
    run cast send \
            --nonce $((nonce)) \
            --rpc-url "$l2_rpc_url" \
            --gas-limit 100000 \
            --gas-price "$gas_price" \
            --legacy \
            --value 0.5ether\
            --private-key "$ephemeral_private_key" \
            --create \
            0x60005B60010180405063000000025600
    # echo "Command output: $output" >&3
    echo "Command status: $status" >&3
    # Check if the command succeeded (exit code 0) but transaction failed (status 0 in output)
    if [[ "$status" -eq 0 ]]; then
        # Command succeeded, now check if transaction failed
        if echo "$output" | grep -q "status.*0.*failed"; then
            echo "Transaction correctly failed as expected" >&3
        else
            echo "Test expected transaction to fail but succeeded: $output" >&3
            return 1
        fi
    else
        echo "Command itself failed (couldn't send transaction): $output" >&3
        return 1
    fi
}
