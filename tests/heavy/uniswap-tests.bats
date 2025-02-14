#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=heavy,uniswap,el:any
@test "Deploy and test UniswapV3 contract" {
    # ✅ Generate a fresh wallet
    wallet_A_json=$(cast wallet new --json)
    address_A=$(echo "$wallet_A_json" | jq -r '.[0].address')
    address_A_private_key=$(echo "$wallet_A_json" | jq -r '.[0].private_key')

    echo "👤 Wallet A: $address_A"
    echo "🔑 Wallet A Private Key: (hidden)"

    # # ✅ Fund Wallet A with 20 ETH
    # local value_ether="30ether"
    # funding_tx_hash=$(cast send --rpc-url "$l2_rpc_url" --private-key "$private_key" "$address_A" --value "$value_ether" --legacy)
    # echo "💰 Funded $address_A with $value_ether (TX: $funding_tx_hash)"
    # 
    # # ✅ Deploy and Test UniswapV3
    # run polycli loadtest uniswapv3 --legacy -v 600 --rpc-url "$l2_rpc_url" --private-key "$address_A_private_key"
    # assert_success
    # 
    # # ✅ Remove ANSI color codes from output (for cleaner assertions)
    # output=$(echo "$output" | sed -r "s/\x1B\[[0-9;]*[mGKH]//g")
    # 
    # # ✅ Validate deployed contract logs
    # assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=WETH9"
    # assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=UniswapV3Factory"
    # assert_output --regexp "Contract deployed address=0x[a-fA-F0-9]{40} name=SwapRouter02"
}
