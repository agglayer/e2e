#!/usr/bin/env bats
# bats file_tags=pessimistic

setup() {
    load "$PROJECT_ROOT/core/helpers/agglayer-cdk-common-setup.bash"
    _agglayer_cdk_common_setup
}

# bats file_tags=pessimistic,prover-stress
@test "prover stress test" {
    # ✅ Get wallet address
    local wallet_addr
    wallet_addr=$(cast wallet address --private-key "$PRIVATE_KEY") || {
        echo "❌ ERROR: Failed to retrieve wallet address"
        return 1
    }

    echo "👤 Wallet Address: $wallet_addr"

    # ✅ Define constant salt
    local salt="0x0000000000000000000000000000000000000000000000000000000000000000"

    # ✅ Deploy stress contract (if not already deployed)
    local stress_addr deployed_code
    stress_addr=$(cast create2 --salt "$salt" --init-code "$(cat core/contracts/bin/evm-stress.bin)")
    deployed_code=$(cast code --rpc-url "$L2_RPC_URL" "$stress_addr")

    if [[ "$deployed_code" == "0x" ]]; then
        echo "🚀 Deploying EVM Stress Contract..."
        cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            0x4e59b44847b379578588920ca78fbf26c0b4956c "$salt$(< core/contracts/bin/evm-stress.bin)"
    fi

    # ✅ Clean up test transactions file
    rm -f test-txs.ndjson

    # ✅ Send stress transactions
    for i in {0..51}; do
        local lim=1000000
        if [[ "$i" =~ ^(28|30)$ ]]; then
            lim=10000
        fi

        echo "⚡ Sending TX with action=$i, limit=$lim"

        cast send --gas-limit 29000000 \
            --json \
            --legacy \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$L2_RPC_URL" \
            "$stress_addr" \
            "$(cast abi-encode 'f(uint256 action, uint256 limit)' "$i" "$lim")" \
            | jq -c '.' | tee -a test-txs.ndjson
    done

    # ✅ Check for failed transactions
    local failed_txs
    failed_txs=$(jq -r 'select(.status == "0x0")' test-txs.ndjson)

    if [[ -n "$failed_txs" ]]; then
        echo "❌ ERROR: There were failures in our test contracts"
        echo "$failed_txs"
        exit 1
    fi
}
