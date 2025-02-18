#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup
}

# bats file_tags=heavy,prover-stress
@test "large evm stress transactions" {
    load "$PROJECT_ROOT/core/helpers/scripts/deploy_test_contracts.sh"

    # ✅ Ensure private key is assigned
    if [[ -z "${PRIVATE_KEY:-}" ]]; then
        echo "❌ ERROR: PRIVATE_KEY is not set!"
        return 1
    fi

    # ✅ Get sender address
    SENDER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
    echo "👤 Sender Address: $SENDER_ADDR"

    # ✅ Define variables with standard capitalization
    SALT="0x0000000000000000000000000000000000000000000000000000000000000000"
    STRESS_ADDR=$(cast create2 --salt "$SALT" --init-code "$(cat core/contracts/bin/evm-stress.bin)")
    DEPLOYED_CODE=$(cast code --rpc-url "$L2_RPC_URL" "$STRESS_ADDR")

    # ✅ Deploy if contract is missing
    if [[ "$DEPLOYED_CODE" == "0x" ]]; then
        echo "🚀 Deploying EVM Stress contract..."
        cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$SALT$(cat core/contracts/bin/evm-stress.bin)"
    fi

    rm -f test-txs.ndjson

    for i in {0..51}; do
        LIM=1000000
        if [[ "$i" =~ ^(28|30)$ ]]; then
            LIM=10000
        fi

        # ✅ Send transactions with proper quoting
        cast send --gas-limit 29000000 \
             --json \
             --legacy \
             --private-key "$PRIVATE_KEY" \
             --rpc-url "$L2_RPC_URL" \
             "$STRESS_ADDR" \
             "$(cast abi-encode 'f(uint256 action, uint256 limit)' "$i" "$LIM")" | jq -c '.' | tee -a test-txs.ndjson
    done

    FAILED_TXS=$(jq -r 'select(.status == "0x0")' test-txs.ndjson)

    if [[ -n "$FAILED_TXS" ]]; then
        echo "❌ ERROR: Some test transactions failed!"
        echo "$FAILED_TXS"
        exit 1
    fi
}
