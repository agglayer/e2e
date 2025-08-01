#!/usr/bin/env bats

#
# This file implements tests for EIP-2537: Precompile for BLS12-381 curve operations
# https://eips.ethereum.org/EIPS/eip-2537
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

    test_vectors_dir="./eip2537_test_vectors"

    # G1ADD
    export BLS12_G1ADD_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000b"
    export g1add_test_vectors_ok="$test_vectors_dir/add_G1_bls.json"
    export g1add_test_vectors_ko="$test_vectors_dir/fail-add_G1_bls.json"
    # G2ADD
    export BLS12_G2ADD_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000d"
    export g2add_test_vectors_ok="$test_vectors_dir/add_G2_bls.json"
    export g2add_test_vectors_ko="$test_vectors_dir/fail-add_G2_bls.json"
    # G1MUL
    export BLS12_G1MUL_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000c"
    export g1mul_test_vectors_ok="$test_vectors_dir/mul_G1_bls.json"
    export g1mul_test_vectors_ko="$test_vectors_dir/fail-mul_G1_bls.json"
    # G2MUL
    export BLS12_G2MUL_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000e"
    export g2mul_test_vectors_ok="$test_vectors_dir/mul_G2_bls.json"
    export g2mul_test_vectors_ko="$test_vectors_dir/fail-mul_G2_bls.json"
    # G1MSM
    export BLS12_G1MSM_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000c"
    export g1msm_test_vectors_ok="$test_vectors_dir/msm_G1_bls.json"
    export g1msm_test_vectors_ko="$test_vectors_dir/fail-msm_G1_bls.json"
    # G2MSM
    export BLS12_G2MSM_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000e"
    export g2msm_test_vectors_ok="$test_vectors_dir/msm_G2_bls.json"
    export g2msm_test_vectors_ko="$test_vectors_dir/fail-msm_G2_bls.json"
    # PAIRING_CHECK
    export BLS12_PAIRING_CHECK_PRECOMPILE_ADDR="0x000000000000000000000000000000000000000f"
    export pairing_check_test_vectors_ok="$test_vectors_dir/pairing_check_bls.json"
    export pairing_check_test_vectors_ko="$test_vectors_dir/fail-pairing_check_bls.json"
    # MAP_FP_TO_G1
    export BLS12_MAP_FP_TO_G1_PRECOMPILE_ADDR="0x0000000000000000000000000000000000000010"
    export map_fp_to_g1_test_vectors_ok="$test_vectors_dir/map_fp_to_G1_bls.json"
    export map_fp_to_g1_test_vectors_ko="$test_vectors_dir/fail-map_fp_to_G1_bls.json"
    # MAP_FP2_TO_G2
    export BLS12_MAP_FP2_TO_G2_PRECOMPILE_ADDR="0x0000000000000000000000000000000000000011"
    export map_fp2_to_g2_test_vectors_ok="$test_vectors_dir/map_fp2_to_G2_bls.json"
    export map_fp2_to_g2_test_vectors_ko="$test_vectors_dir/fail-map_fp2_to_G2_bls.json"
}

# These function is for tests that are expected to be working. Output is also checked against expected result.
function eip2537_test_ok() {
    test_name=$1
    test_vectors_ok=$2
    bls12_precompile_addr=$3

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
    test_name=$1
    test_vectors_ko=$2
    bls12_precompile_addr=$3

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

@test "G1ADD test vectors OK" {
    eip2537_test_ok "G1ADD" "$g1add_test_vectors_ok" "$BLS12_G1ADD_PRECOMPILE_ADDR"
}

@test "G1ADD test vectors KO" {
    eip2537_test_ko "G1ADD" "$g1add_test_vectors_ko" "$BLS12_G1ADD_PRECOMPILE_ADDR"
}

@test "G2ADD test vectors OK" {
    eip2537_test_ok "G2ADD" "$g2add_test_vectors_ok" "$BLS12_G2ADD_PRECOMPILE_ADDR"
}

@test "G2ADD test vectors KO" {
    eip2537_test_ko "G2ADD" "$g2add_test_vectors_ko" "$BLS12_G2ADD_PRECOMPILE_ADDR"
}

@test "G1MUL test vectors OK" {
    eip2537_test_ok "G1MUL" "$g1mul_test_vectors_ok" "$BLS12_G1MUL_PRECOMPILE_ADDR"
}

@test "G1MUL test vectors KO" {
    eip2537_test_ko "G1MUL" "$g1mul_test_vectors_ko" "$BLS12_G1MUL_PRECOMPILE_ADDR"
}

@test "G2MUL test vectors OK" {
    eip2537_test_ok "G2MUL" "$g2mul_test_vectors_ok" "$BLS12_G2MUL_PRECOMPILE_ADDR"
}

@test "G2MUL test vectors KO" {
    eip2537_test_ko "G2MUL" "$g2mul_test_vectors_ko" "$BLS12_G2MUL_PRECOMPILE_ADDR"
}

@test "G1MSM test vectors OK (long test)" {
    eip2537_test_ok "G1MSM" "$g1msm_test_vectors_ok" "$BLS12_G1MSM_PRECOMPILE_ADDR"
}

@test "G1MSM test vectors KO" {
    eip2537_test_ko "G1MSM" "$g1msm_test_vectors_ko" "$BLS12_G1MSM_PRECOMPILE_ADDR"
}

@test "G2MSM test vectors OK (long test)" {
    eip2537_test_ok "G2MSM" "$g2msm_test_vectors_ok" "$BLS12_G2MSM_PRECOMPILE_ADDR"
}

@test "G2MSM test vectors KO" {
    eip2537_test_ko "G2MSM" "$g2msm_test_vectors_ko" "$BLS12_G2MSM_PRECOMPILE_ADDR"
}

@test "PAIRING_CHECK test vectors OK" {
    eip2537_test_ok "PAIRING_CHECK" "$pairing_check_test_vectors_ok" "$BLS12_PAIRING_CHECK_PRECOMPILE_ADDR"
}

@test "PAIRING_CHECK test vectors KO" {
    eip2537_test_ko "PAIRING_CHECK" "$pairing_check_test_vectors_ko" "$BLS12_PAIRING_CHECK_PRECOMPILE_ADDR"
}

@test "MAP_FP_TO_G1 test vectors OK" {
    eip2537_test_ok "MAP_FP_TO_G1" "$map_fp_to_g1_test_vectors_ok" "$BLS12_MAP_FP_TO_G1_PRECOMPILE_ADDR"
}

@test "MAP_FP_TO_G1 test vectors KO" {
    eip2537_test_ko "MAP_FP_TO_G1" "$map_fp_to_g1_test_vectors_ko" "$BLS12_MAP_FP_TO_G1_PRECOMPILE_ADDR"
}

@test "MAP_FP2_TO_G2 test vectors OK" {
    eip2537_test_ok "MAP_FP2_TO_G2" "$map_fp2_to_g2_test_vectors_ok" "$BLS12_MAP_FP2_TO_G2_PRECOMPILE_ADDR"
}

@test "MAP_FP2_TO_G2 test vectors KO" {
    eip2537_test_ko "MAP_FP2_TO_G2" "$map_fp2_to_g2_test_vectors_ko" "$BLS12_MAP_FP2_TO_G2_PRECOMPILE_ADDR"
}
