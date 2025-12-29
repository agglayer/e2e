#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7939

# This file implements tests for EIP-7939
# https://eips.ethereum.org/EIPS/eip-7939

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

}

@test "Transaction using new CLZ instruction" {
    bytecode="0x5F1E"  # PUSH0; CLZ(0)

    # Lets send the tx to l2, it should fail as it's not a valid instruction
    run cast send --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" --create $bytecode
    if [ "$status" -eq 0 ]; then
        echo "❌ The transaction was expected to fail, but it succeeded, output: $output" >&3
        exit 1
    else
        echo "✅ Successfully failed transaction to L2" >&3
    fi

    # Lets send the tx to l1, it should work if fusaka is enabled
    run cast send --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" --create $bytecode
    if [ "$status" -eq 0 ]; then
        echo "✅ Successfully executed CLZ instruction on L1" >&3
    else
        echo "❌ The transaction was expected to succeed, but it failed, output: $output" >&3
        exit 1
    fi
}
