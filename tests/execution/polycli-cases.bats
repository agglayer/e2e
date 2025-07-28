#!/usr/bin/env bats
# bats file_tags=standard

setup_file() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    # source existing helper functions for ephemeral account setup
    source "./tests/lxly/assets/bridge-tests-helper.bash"

    ephemeral_data=$(_generate_ephemeral_account "polycli-cases")
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "100000000000000000000"

    # Export variables for use in tests
    export ephemeral_private_key
    export ephemeral_address
    export l2_rpc_url
    export l2_private_key
}

@test "Deploy polycli loadtest contracts" {
    # Deploy polycli ERC20 Contract
    cast send --json --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --create "$(cat ./tests/execution/assets/ERC20.bin)" > erc20.out.json
    
    # Deploy polycli ERC721 Contract
    cast send --json --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --create "$(cat ./tests/execution/assets/ERC721.bin)" > erc721.out.json

    # Deploy polycli Loadtest Contract
    cast send --json --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --create "$(cat ./tests/execution/assets/LoadTester.bin)" > LoadTester.out.json
}

@test "Perform ERC20 Transfers" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode 2 --rate-limit 500 --requests 2 --concurrency 2 --erc20-address "$(jq -r '.contractAddress' erc20.out.json)" --rpc-url "$l2_rpc_url"
}

@test "Perform some ERC721 Mints" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 1 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 2 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 4 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 8 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 16 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 32 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode 7 --rate-limit 500 --requests 2 --concurrency 2 \
        --iterations 64 --erc721-address "$(jq -r '.contractAddress' erc721.out.json)" --rpc-url "$l2_rpc_url"
}

@test "Perform some Storage calls in the load tester contract" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 1 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 2 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 4 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 8 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 16 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 32 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 64 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 128 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 256 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 512 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 1024 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 2048 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 4096 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 8192 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
    polycli loadtest --private-key "$ephemeral_private_key" --mode s --rate-limit 500 --requests 1 --concurrency 1 \
        --byte-count 16384 --lt-address "$(jq -r '.contractAddress' LoadTester.out.json)" --rpc-url "$l2_rpc_url"
}

@test "Perform some uniswap v3 calls" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode uniswapv3 --rate-limit 100 --requests 32 --concurrency 2 \
        --rpc-url "$l2_rpc_url"
}

@test "Using polycli to call some precompiles" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode pr --rate-limit 100 --requests 8 --concurrency 16 \
        --rpc-url "$l2_rpc_url"
}

@test "Using polycli to do some inscriptions" {
    polycli loadtest --private-key "$ephemeral_private_key" --mode inscription --rate-limit 1000 --requests 10 --concurrency 50 --eth-amount 0 \
        --inscription-content 'data:,{"p":"prc-20","op":"mint","tick":"hava","amt":"100"}' --to-address "$ephemeral_address" --rpc-url "$l2_rpc_url"
}
