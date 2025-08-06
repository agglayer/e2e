#!/usr/bin/env bats
# bats file_tags=standard

# We're going to try to tune these tests to so that they're targeting
# 30M gas per second. When testing these cases with kurtosis it's
# likely that some local network issues might come up due to the
# implementation of the docker proxy. In this case, I'm bypassing the
# proxy all together to directly connect to the sequencer's native IP.
setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"

    legacy_flag=""
    # if kurtosis enclave inspect "$kurtosis_enclave_name" | grep -q "cdk-erigon-sequencer-001"; then
    #     legacy_flag="--legacy"
    #     echo "legacy mode enabled" >&3
    # fi

    tmp_output=${TMP_OUTPUT:-"/tmp/loadtest.out"}

    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}

@test "send 85,700 EOA transfers and confirm mined in 60 seconds" {
    ephemeral_data=$(_generate_ephemeral_account "polycli-eoa")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"

    sleep 1

    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$l2_rpc_url" \
            --concurrency 1 \
            --requests 854 \
            --private-key "$ephemeral_private_key" \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --rate-limit 5000 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 60 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target" >&3
        cat $tmp_output >&3
    fi
}

@test "send 41,200 ERC20 transfers and confirm mined in 240 seconds" {
    ephemeral_data=$(_generate_ephemeral_account "polycli-erc20")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"

    sleep 1

    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$l2_rpc_url" \
            --concurrency 100 \
            --requests 412 \
            --private-key "$ephemeral_private_key" \
            --rate-limit 5000 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --mode erc20 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 240 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target" >&3
        cat $tmp_output >&3
    fi
}

@test "send 20,800 ERC721 mints and confirm mined in 240 seconds" {
    ephemeral_data=$(_generate_ephemeral_account "polycli-erc721")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"

    sleep 1

    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$l2_rpc_url" \
            --concurrency 100 \
            --requests 208 \
            --private-key "$ephemeral_private_key" \
            --rate-limit 5000 \
            --mode erc721 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --iterations 1 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 240 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target" >&3
        cat $tmp_output >&3
    fi
}

# TODO this one is a little tricky because 1/2 of the time is deploying contracts.. Maybe adding a timeout parameter would be helpful or we should pre deploy the contracts
@test "send 10,200 Uniswapv3 swaps sent and mined in 300 seconds" {
    ephemeral_data=$(_generate_ephemeral_account "polycli-uniswap")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"

    sleep 1

    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$l2_rpc_url" \
            --concurrency 100 \
            --requests 102 \
            --private-key "$ephemeral_private_key" \
            --rate-limit 5000 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --mode uniswapv3 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 300 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target" >&3
        cat $tmp_output >&3
    fi
}
