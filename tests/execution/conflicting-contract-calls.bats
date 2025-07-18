#!/usr/bin/env bats

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    iteration_count=20

    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}


@test "Make conflicting contract calls" {
    local ephemeral_data
    local ephemeral_private_key
    local ephemeral_address
    ephemeral_data=$(_generate_ephemeral_account "1")
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
        echo "Command output: $output" >&3
        if [[ "$status" -ne 0 ]]; then
            echo "Test $index expected success but failed: $output" >&3
            echo "Command status: $status" >&3
            return 1
        fi
        index=$((index+1));
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
        nonce=$((nonce + 1));
        echo "Command output: $output" >&3
        if [[ "$status" -ne 1 ]]; then
            echo "Test $index expected fail but succeed: $output" >&3
            echo "Command status: $status" >&3
            return 1
        fi
    done
    wait < <(jobs -p)
}
