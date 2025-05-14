#!/bin/bash
set -euo pipefail

deploy_test_contracts() {
    local RPC_URL="$L2_RPC_URL"
    local PRIVATE_KEY="$PRIVATE_KEY"

    # ✅ Ensure RPC is alive
    if ! cast block-number --rpc-url "$RPC_URL"; then
        echo "❌ ERROR: RPC endpoint is not responding" >&2
        exit 1
    fi

    # ✅ Ensure the test account has funds
    local ETH_ADDRESS
    ETH_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")
    local BALANCE
    BALANCE=$(cast balance --rpc-url "$RPC_URL" "$ETH_ADDRESS")

    if [[ "$BALANCE" -eq 0 ]]; then
        echo "❌ ERROR: The test account is not funded" >&2
        exit 1
    fi

    # ✅ Ensure the deployment proxy exists
    local DEPLOYMENT_PROXY
    DEPLOYMENT_PROXY=$(cast code --rpc-url "$RPC_URL" 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    
    if [[ "$DEPLOYMENT_PROXY" == "0x" ]]; then
        echo "ℹ️  Deploying missing proxy contract..."
        cast send --legacy --value 0.1ether --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" 0x3fab184622dc19b6109349b94811493bf2a45362
        cast publish --rpc-url "$RPC_URL" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
    fi

    # ✅ Deploy `zkevm-counters` contract using standardized SALT
    COUNTERS_ADDR=$(cast create2 --salt "$DEPLOY_SALT" --init-code "$(cat core/contracts/bin/zkevm-counters.bin)")
    export COUNTERS_ADDR
    
    echo "ℹ️  Deployed zkevm-counters contract at: $COUNTERS_ADDR" >&2

    # ✅ Verify Deployment
    local DEPLOYED_CODE
    DEPLOYED_CODE=$(cast code --rpc-url "$RPC_URL" "$COUNTERS_ADDR")

    if [[ "$DEPLOYED_CODE" == "0x" ]]; then
        echo "ℹ️  Deploying contract via proxy..."
        cast send --legacy --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$DEPLOY_SALT$(cat core/contracts/bin/zkevm-counters.bin)"
    fi
}
