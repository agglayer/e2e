#!/usr/bin/env bats

setup() {
    true
}


setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"pectra"}

    export l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    export l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    export l1_bridge_addr=${L1_BRIDGE_ADDR:-"$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 'cat /opt/zkevm/combined-001.json | jq -r .polygonZkEVMBridgeAddress')"}

    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    export l2_bridge_addr=${L2_BRIDGE_ADDR:-"$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 'cat /opt/zkevm/combined-001.json | jq -r .polygonZkEVML2BridgeAddress')"}

    export bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"}
    export network_id=$(cast call  --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    export claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    export autoclaim_timeout_seconds=${AUTCLAIM_TIMEOUT_SECONDS:-"300"}
    export l1_claim_timeout_seconds=${L1_CLAIM_TIMEOUT_SECONDS:-"900"}

    export zero_address=$(cast address-zero)

    # Random wallet
    random_wallet=$(cast wallet new --json)
    export random_address=$(echo "$random_wallet" | jq -r '.[0].address')
    export random_private_key=$(echo "$random_wallet" | jq -r '.[0].privateKey')


    # G1ADD
    export BLS12_G1ADD_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000b"
    export g1add_test_vectors_ok="./test_vectors/add_G1_bls.json"
    export g1add_test_vectors_ko="./test_vectors/fail-add_G1_bls.json"

    # G2ADD
    export BLS12_G2ADD_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000d"
    export g2add_test_vectors_ok="./test_vectors/add_G2_bls.json"
    export g2add_test_vectors_ko="./test_vectors/fail-add_G2_bls.json"

}

# These function is for tests that are expected to be working. Output is also checked against expected result.
function eip2537_test_ok() {
    local test_name=$1
    local test_vectors_ok=$2
    local bls12_precompile_addr=$3

    echo "Running EIP-2537 test vectors from path $BATS_TEST_DIRNAME/$test_vectors_ok for $test_name"

    count=$(jq length "$BATS_TEST_DIRNAME/$test_vectors_ok")
    echo "Running $count EIP-2537 $test_name test vectors..."

    for i in $(seq 0 $((count - 1))); do
        input=$(jq -r ".[$i].Input" "$BATS_TEST_DIRNAME/$test_vectors_ok")
        expected_output=$(jq -r ".[$i].Expected" "$BATS_TEST_DIRNAME/$test_vectors_ok")
        name=$(jq -r ".[$i].Name" "$BATS_TEST_DIRNAME/$test_vectors_ok")

        # strip 0x if present
        input=${input#0x}
        expected_output=${expected_output#0x}

        run cast call "$bls12_precompile_addr" "0x$input" --rpc-url "$l2_rpc_url"
        # strip 0x from output
        output=${output#0x}

        if [ "$status" -ne 0 ]; then
            echo "❌ Test #$i ($name) failed to execute"
            echo "Input: $input"
            echo "Error: $output"
            false
        elif [ "$output" != "$expected_output" ]; then
            echo "❌ Test #$i ($name) failed"
            echo "Input: $input"
            echo "Expected: $expected_output"
            echo "Got:      $output"
            false
        else
            echo "✅ Test #$i ($name) passed"
        fi
    done
}

# These functions are for tests that are expected to fail. Output is also checked against expected error.
function eip2537_test_ko() {
    local test_name=$1
    local test_vectors_ko=$2
    local bls12_precompile_addr=$3

    echo "Running EIP-2537 test vectors from path $BATS_TEST_DIRNAME/$test_vectors_ko for $test_name"

    count=$(jq length "$BATS_TEST_DIRNAME/$test_vectors_ko")
    echo "Running $count $test_name test vectors..."

    for i in $(seq 0 $((count - 1))); do
        input=$(jq -r ".[$i].Input" "$BATS_TEST_DIRNAME/$test_vectors_ko")
        expected_error=$(jq -r ".[$i].ExpectedError" "$BATS_TEST_DIRNAME/$test_vectors_ko")
        name=$(jq -r ".[$i].Name" "$BATS_TEST_DIRNAME/$test_vectors_ko")

        # strip 0x if present
        input=${input#0x}

        run cast call "$bls12_precompile_addr" "0x$input" --rpc-url "$l2_rpc_url"
        # strip 0x from output
        output=${output#0x}

        if [ "$status" -ne 1 ]; then
            echo "❌ Test #$i ($name) was expected to fail, but it did not"
            echo "Input: $input"
            echo "Output: $output"
            false
        elif [[ "$output" != *"$expected_error"* ]]; then
            echo "❌ Test #$i ($name) failed"
            echo "Input: $input"
            echo "Expected: $expected_error"
            echo "Got:      $output"
            false
        else
            echo "✅ Test #$i ($name) passed"
        fi
    done
}

# These are working test vectors for G1ADD that need to success and return the expected output.
@test "G1ADD test vectors OK" {
    eip2537_test_ok "G1ADD" "$g1add_test_vectors_ok" "$BLS12_G1ADD_PRECOMPILE_ADDR"
}

# These are test vectors for G1ADD that are expected to fail and return a specific error.
@test "G1ADD test vectors KO" {
    eip2537_test_ko "G1ADD" "$g1add_test_vectors_ko" "$BLS12_G1ADD_PRECOMPILE_ADDR"
}

# These are working test vectors for G2ADD that need to success and return the expected output.
@test "G2ADD test vectors OK" {
    eip2537_test_ok "G2ADD" "$g2add_test_vectors_ok" "$BLS12_G2ADD_PRECOMPILE_ADDR"
}

# These are test vectors for G2ADD that are expected to fail and return a specific error.
@test "G2ADD test vectors KO" {
    eip2537_test_ko "G2ADD" "$g2add_test_vectors_ko" "$BLS12_G2ADD_PRECOMPILE_ADDR"
}

