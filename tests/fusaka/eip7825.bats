#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7825

# This file implements tests for EIP-7825
# https://eips.ethereum.org/EIPS/eip-7825

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

}

@test "Transaction with more than 2^24 gas" {
    bytecode="0x60016235FFFF20"

    # Lets send the tx to l2, it should work as there is no fusaka there
    run cast send --gas-limit 30000000 --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" --create $bytecode --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to submit transaction to L2, output: $output" >&3
        exit 1
    else
        gas=$(echo "$output" | jq -r '.gasUsed' | cast to-dec)
        # lets check it's greater than 16,777,216
        if [ "$gas" -le 16777216 ]; then
            echo "❌ Gas used is less than 16,777,216, output: $output" >&3
            exit 1
        fi
        echo "✅ Successfully submitted transaction to L2, gas used: $gas" >&3
    fi

    # Lets send the tx to l1, it should failif fusaka is enabled
    run cast send --gas-limit 30000000 --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" --create $bytecode
    if [ "$status" -eq 0 ]; then
        echo "❌ The transaction was expected to fail, but it succeeded, output: $output" >&3
        exit 1
    else
        echo "✅ Successfully failed transaction to L1" >&3
    fi
}
