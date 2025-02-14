#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/common.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"
}

# bats file_tags=light,erc20
@test "Test ERC20Mock contract" {
    # ✅ Generate fresh wallets
    wallet_A_json=$(cast wallet new --json)
    export ADDRESS_A=$(echo "$wallet_A_json" | jq -r '.[0].address')
    export PRIVATE_KEY_A=$(echo "$wallet_A_json" | jq -r '.[0].private_key')
    export ADDRESS_B=$(cast wallet new --json | jq -r '.[0].address')

    echo "👤 Wallet A: $ADDRESS_A"
    echo "🔑 Wallet A Private Key: (hidden)"
    echo "👤 Wallet B: $ADDRESS_B"

    # ✅ Deploy ERC20Mock Contract
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"
    assert_success
    export CONTRACT_ADDR=$(echo "$output" | tail -n 1)
    echo "🏗️ Deployed ERC20Mock at: $CONTRACT_ADDR"

    # ✅ Mint ERC20 Tokens
    local amount="5"
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$CONTRACT_ADDR" "$MINT_FN_SIG" "$ADDRESS_A" "$amount"
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
    gas_units=$(cast estimate --rpc-url "$L2_RPC_URL" --create "$bytecode")
    gas_units=$(echo "scale=0; $gas_units / 2" | bc)

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    local value
    value=$(echo "$gas_units * $gas_price" | bc)
    local value_ether
    value_ether=$(cast to-unit "$value" ether)"ether"

    echo "🚨 Deploying with insufficient gas: $value_ether"

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" "$ADDRESS_A" --value "$value_ether" --legacy

    # ✅ Explicitly Capture Deploy Contract Failure
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY_A" "$contract_artifact"
    assert_failure  # ✅ Should fail due to low gas
}
