#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/common.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"
}

# bats file_tags=light,erc20,el:any
@test "Test ERC20Mock contract" {
    # ✅ Generate fresh wallets
    wallet_A_json=$(cast wallet new --json)
    address_A=$(echo "$wallet_A_json" | jq -r '.[0].address')
    address_A_private_key=$(echo "$wallet_A_json" | jq -r '.[0].private_key')
    address_B=$(cast wallet new --json | jq -r '.[0].address')

    echo "👤 Wallet A: $address_A"
    echo "🔑 Wallet A Private Key: (hidden)"
    echo "👤 Wallet B: $address_B"

    # ✅ Deploy ERC20Mock Contract
    run deploy_contract "$l2_rpc_url" "$private_key" "$contract_artifact"
    assert_success
    contract_addr=$(echo "$output" | tail -n 1)
    echo "🏗️ Deployed ERC20Mock at: $contract_addr"

    # ✅ Mint ERC20 Tokens
    local amount="5"
    run send_tx "$l2_rpc_url" "$private_key" "$contract_addr" "$mint_fn_sig" "$address_A" "$amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # ✅ Insufficient Gas Scenario (Should Fail)
    local bytecode
    bytecode=$(jq -r .bytecode "$contract_artifact")

    if [[ -z "$bytecode" || "$bytecode" == "null" ]]; then
        echo "❌ ERROR: Failed to read bytecode"
        return 1
    fi

    local gas_units
    gas_units=$(cast estimate --rpc-url "$l2_rpc_url" --create "$bytecode")
    gas_units=$(echo "scale=0; $gas_units / 2" | bc)

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$l2_rpc_url")

    local value
    value=$(echo "$gas_units * $gas_price" | bc)
    local value_ether
    value_ether=$(cast to-unit "$value" ether)"ether"

    echo "🚨 Deploying with insufficient gas: $value_ether"

    cast send --rpc-url "$l2_rpc_url" --private-key "$private_key" "$address_A" --value "$value_ether" --legacy

    run deploy_contract "$l2_rpc_url" "$address_A_private_key" "$contract_artifact"
    assert_failure  # ✅ Should fail due to low gas
}
