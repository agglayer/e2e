# We're going to try to tune these tests to so that they're targeting
# 30M gas per second. When testing these cases with kurtosis it's
# likely that some local network issues might come up due to the
# implementation of the docker proxy. In this case, I'm by passing the
# proxy all together to directly connect to the sequencer's native IP.
setup() {
    rpc_url=${RPC_URL:-"$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"}
    private_key=${PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    eth_address=$(cast wallet address --private-key "$private_key")

    legacy_mode=${LEGACY_MODE:-"false"}
    legacy_flag=""
    if [[ $legacy_flag == "true" ]]; then
        legacy_flag="--legacy"
    fi

    request_total=$((polycli_load_concurrency*polycli_load_requests))
    tmp_output=${TMP_OUTPUT:-"/tmp/loadtest.out"}
}

@test "send 85,700 EOA transfers and confirm mined in 60 seconds" {
    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$rpc_url" \
            --concurrency 1 \
            --requests 854 \
            --private-key "$private_key" \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --rate-limit 5000 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 60 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target"
        exit 1
    fi
}

@test "send 61,200 ERC20 transfers and confirm mined in 60 seconds" {
    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$rpc_url" \
            --concurrency 100 \
            --requests 612 \
            --private-key "$private_key" \
            --rate-limit 5000 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --mode erc20 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 60 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target"
        exit 1
    fi
}

@test "send 29,800 ERC721 mints and confirm mined in 60 seconds" {
    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$rpc_url" \
            --concurrency 100 \
            --requests 298 \
            --private-key "$private_key" \
            --rate-limit 5000 \
            --mode erc721 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --iterations 1 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 60 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target"
        exit 1
    fi
}

# TODO this one is a little tricky because 1/2 of the time is deploying contracts.. Maybe adding a timeout parameter would be helpful or we should pre deploy the contracts
@test "send 17,200 Uniswapv3 swaps sent and mined in 150 seconds" {
    start=$(date +%s)
    polycli loadtest \
            $legacy_flag \
            --rpc-url "$rpc_url" \
            --concurrency 100 \
            --requests 172 \
            --private-key "$private_key" \
            --rate-limit 5000 \
            --verbosity 600 \
            --gas-price-multiplier 1.0 \
            --mode uniswapv3 &>> "$tmp_output"
    end=$(date +%s)
    duration=$((end-start))

    if [[ $duration -gt 150 ]]; then
        echo "The test ended up taking $duration seconds to complete. This is below the expected performance target"
        exit 1
    fi
}
