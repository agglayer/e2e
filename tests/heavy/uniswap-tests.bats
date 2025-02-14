#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats test_tags=heavy,uniswap
@test "Deploy and test UniswapV3 contract" {
    # ✅ Generate a fresh wallet
    wallet_A_json=$(cast wallet new --json)
    export ADDRESS_A=$(echo "$wallet_A_json" | jq -r '.[0].address')
    export PRIVATE_KEY_A=$(echo "$wallet_A_json" | jq -r '.[0].private_key')

    echo "👤 Wallet A: $ADDRESS_A"
    echo "🔑 Wallet A Private Key: (hidden)"

    # ✅ Fund Wallet A with 30 ETH
    local VALUE_ETHER="30ether"
    echo "💰 Funding $ADDRESS_A with $VALUE_ETHER..."
    run cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" "$ADDRESS_A" --value "$VALUE_ETHER" --legacy
    assert_success
    echo "💰 Funded successfully!"

    # ✅ Deploy and Test UniswapV3
    echo "🚀 Deploying UniswapV3 contracts..."
    run polycli loadtest uniswapv3 --legacy -v 600 --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY_A"
    assert_success

    # ✅ Remove ANSI color codes from output (for cleaner assertions)
    output=$(echo "$output" | sed -r "s/\x1B\[[0-9;]*[mGKH]//g")
    
    # ✅ Validate deployed contract logs
    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=WETH9"
    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=UniswapV3Factory"
    assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=SwapRouter02"
}
