#!/usr/bin/env bats

#
# This file implements tests for EIP-7623: Increase calldata cost
# https://eips.ethereum.org/EIPS/eip-7623
#

setup() {
    true
}


setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"pectra"}
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}

    # Specific for tx cost calculation
    export TOTAL_COST_FLOOR_PER_TOKEN=10
    export STANDARD_TOKEN_COST=4

    # Random wallet
    random_wallet=$(cast wallet new --json)
    random_address=$(echo "$random_wallet" | jq -r '.[0].address')
    random_private_key=$(echo "$random_wallet" | jq -r '.[0].privateKey')

    export random_address
    export random_private_key
}


function tokens_from_calldata() {
    hex_input=$1
    tokens=0

    # Strip the 0x prefix
    hex=${hex_input#0x}

    # Ensure even number of hex characters
    if (( ${#hex} % 2 != 0 )); then
        echo "Invalid hex input length for $hex_input"
        exit 1
    fi

    zero_count=0
    nonzero_count=0

    # Loop over every byte (2 hex chars)
    for (( i=0; i<${#hex}; i+=2 )); do
    byte="0x${hex:$i:2}"
    if [[ "$byte" == "0x00" ]]; then
        ((zero_count++))
    else
        ((nonzero_count++))
    fi
    done

    # tokens_in_calldata = zero_bytes_in_calldata + nonzero_bytes_in_calldata * 4
    tokens=$((zero_count + nonzero_count * 4))
    echo "$tokens"
}


# These function is for tests that are expected to be working. Output is also checked against expected result.
function eip7623_check_gas() {
    bytes=$1
    expected_tokens=$(tokens_from_calldata "$bytes")

    # cost has to be 21000 + tokens * TOTAL_COST_FLOOR_PER_TOKEN (if no execution, so we start with 0x00 just in case)
    pectra_expected_cost=$((21000 + expected_tokens * TOTAL_COST_FLOOR_PER_TOKEN))
    pre_ectra_expected_cost=$((21000 + expected_tokens * STANDARD_TOKEN_COST))

    run cast send  --rpc-url $l2_rpc_url --private-key $l2_private_key $random_address $bytes --json
    gas_used=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)

    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to execute transaction with calldata $bytes"
        echo "Error: $output"
        false
    elif [ "$gas_used" -ne "$pectra_expected_cost" ]; then
        echo "❌ Test failed for calldata $bytes"
        echo "Expected cost: $pectra_expected_cost, got: $gas_used, pre_pectra cost: $pre_ectra_expected_cost"
        false
    else
        echo "✅ Test passed for calldata $bytes, gas used: $gas_used, expected: $pectra_expected_cost"
    fi
}


@test "EIP-7623: Check gas cost for empty calldata" {
    eip7623_check_gas "0x"
}

@test "EIP-7623: Check gas cost for 0x00" {
    eip7623_check_gas "0x00"
}

@test "EIP-7623: Check gas cost for 0x0001" {
    eip7623_check_gas "0x0001"
}

@test "EIP-7623: Check gas cost for 0x000100" {
    eip7623_check_gas "0x000100"
}

@test "EIP-7623: Check gas cost for 0x000000" {
    eip7623_check_gas "0x000000"
}

@test "EIP-7623: Check gas cost for 0x00aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff001100220033004400550066007700880099" {
    eip7623_check_gas "0x00aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff001100220033004400550066007700880099"
}

@test "EIP-7623: Check gas cost for 0xffff" {
    eip7623_check_gas "0xffff"
}
