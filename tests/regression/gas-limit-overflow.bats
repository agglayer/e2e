#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standard setup (wallet, funding, RPC, etc.)
}

# bats file_tags=regression,gas-limit-overflow
@test "rpc and sequencer handles two large transactions" {    
    load "$PROJECT_ROOT/core/helpers/scripts/deploy_test_contracts.sh"
    load "$PROJECT_ROOT/core/helpers/scripts/assert_block_production.sh"

    # ✅ Deploy necessary contracts with standardized env variables
    deploy_test_contracts "$L2_RPC_URL" "$PRIVATE_KEY"

    latest_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$PUBLIC_ADDRESS")
    echo "🔢 Latest nonce for $PUBLIC_ADDRESS: $latest_nonce"

    polycli loadtest \
            --send-only \
            --rpc-url "$L2_RPC_URL" \
            --private-key "$PRIVATE_KEY" \
            --requests 5 \
            --mode contract-call \
            --contract-address "$counters_addr" \
            --gas-limit 20000000 \
            --legacy \
            --calldata "$(cast abi-encode 'f(uint256)' 2)" \
            --nonce "$latest_nonce"

    # ✅ Assert block production (ensure chain is alive)
    assert_block_production "$L2_RPC_URL" 12
}
