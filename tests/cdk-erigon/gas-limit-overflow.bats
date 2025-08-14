#!/usr/bin/env bats
# bats file_tags=cdk-erigon

setup() {
    load "$PROJECT_ROOT/core/helpers/agglayer-cdk-common-setup.bash"
    _agglayer_cdk_common_setup  # ✅ Standard setup (wallet, funding, RPC, etc.)
}

# bats file_tags=evm-gas
@test "RPC and sequencer handle two large transactions" {    
    # ✅ Deploy necessary contracts and capture deployed address
    deploy_test_contracts "$L2_RPC_URL" "$PRIVATE_KEY"
    
    export COUNTERS_ADDR="$COUNTERS_ADDR" # from deploy test contracts

    # ✅ Get the latest nonce for the sender address
    local latest_nonce
    latest_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$PUBLIC_ADDRESS") || {
        echo "❌ ERROR: Failed to retrieve nonce for $PUBLIC_ADDRESS."
        return 1
    }

    echo "🔢 Latest nonce for $PUBLIC_ADDRESS: $latest_nonce"

    # ✅ Send large contract-call transactions
    polycli loadtest \
        --send-only \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --requests 5 \
        --mode contract-call \
        --contract-address "$COUNTERS_ADDR" \
        --gas-limit 20000000 \
        --legacy \
        --calldata "$(cast abi-encode 'f(uint256)' 2)" \
        --nonce "$latest_nonce"

    # ✅ Assert block production (ensure chain is alive)
    assert_block_production "$L2_RPC_URL" 12
}
