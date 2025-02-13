#!/bin/bash
set -euo pipefail

deploy_test_contracts() {
    rpc_url=$1
    private_key=$2

    # Ensure RPC is alive
    if ! cast block-number --rpc-url "$rpc_url"; then
        echo "❌ RPC endpoint is not responding" >&2
        exit 1
    fi

    # Ensure the test account has funds
    eth_address=$(cast wallet address --private-key "$private_key")
    balance=$(cast balance --rpc-url "$rpc_url" "$eth_address")

    if [[ $balance -eq 0 ]]; then
        echo "❌ The test account is not funded" >&2
        exit 1
    fi

    # Ensure the deployment proxy exists
    deployment_proxy=$(cast code --rpc-url "$rpc_url" 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    if [[ $deployment_proxy == "0x" ]]; then
        echo "ℹ️  Deploying missing proxy contract..."
        cast send --legacy --value 0.1ether --rpc-url "$rpc_url" --private-key "$private_key" 0x3fab184622dc19b6109349b94811493bf2a45362
        cast publish --rpc-url "$rpc_url" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
    fi

    # Deploy `zkevm-counters` contract
    salt=0x0000000000000000000000000000000000000000000000000000000000000000
    counters_addr=$(cast create2 --salt "$salt" --init-code "$(cat core/contracts/bin/zkevm-counters.bin)")
    echo "ℹ️  Deployed zkevm-counters contract at: $counters_addr" >&2

    deployed_code=$(cast code --rpc-url "$rpc_url" "$counters_addr")
    if [[ $deployed_code == "0x" ]]; then
        echo "ℹ️  Deploying contract via proxy..."
        cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$salt$(cat core/contracts/bin/zkevm-counters.bin)"
    fi
}
