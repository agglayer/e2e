#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # Standard setup (wallet, funding, RPC, etc.)
}

# bats file_tags=regression,gas-limit-overflow,el:cdk-erigon
# https://github.com/0xPolygonHermez/cdk-erigon/issues/953
@test "rpc and sequencer handles two large transactions" {
    load "$PROJECT_ROOT/core/helpers/scripts/deploy_test_contracts.sh"
    load "$PROJECT_ROOT/core/helpers/scripts/assert_block_production.sh"

    # ✅ Deploy necessary contracts with new private key
    deploy_test_contracts "$l2_rpc_url" "$private_key"

    latest_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$public_address")
    echo "🔢 Latest nonce for $public_address: $latest_nonce"

    polycli loadtest \
            --send-only \
            --rpc-url "$l2_rpc_url" \
            --private-key "$private_key" \
            --requests 5 \
            --mode contract-call \
            --contract-address "$counters_addr" \
            --gas-limit 20000000 \
            --legacy \
            --calldata "$(cast abi-encode 'f(uint256)' 2)" \
            --nonce "$latest_nonce"

    # ✅ Assert block production (ensure chain is alive)
    assert_block_production "$l2_rpc_url" 12
}
