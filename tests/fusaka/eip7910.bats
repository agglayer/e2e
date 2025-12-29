#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7910

# This file implements tests for EIP-7910
# https://eips.ethereum.org/EIPS/eip-7910

setup() {
    true
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

}

@test "Test new RPC endpoint eth_config" {

    # Let's check its not available on L2, as fusaka is not enabled
    run cast rpc eth_config --rpc-url "$l2_rpc_url"
    if [ "$status" -eq 0 ]; then
        echo "❌ Successfully called eth_config on L2, expected to fail, output: $output" >&3
        exit 1
    else
        echo "✅ Successfully failed to call eth_config on L2, output: $output" >&3
    fi

    # Let's check its available on L1, as fusaka is enabled
    run cast rpc eth_config --rpc-url "$l1_rpc_url"
    if [ "$status" -eq 0 ]; then
        echo "✅ Successfully called eth_config on L1, output: $output" >&3
    else
        eth_config=$(echo "$output" | jq -r '.')
        echo "❌ Failed to call eth_config on L1, expected to succeed, output: $eth_config" >&3
        exit 1
    fi
}
