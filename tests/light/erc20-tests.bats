#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/common.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"
}

# bats file_tags=light,erc20
@test "Test ERC20Mock contract" {
  
    export PRIVATE_KEY="$PRIVATE_KEY"
    
    # ✅ Generate fresh wallets
    local wallet_A_json
    wallet_A_json=$(cast wallet new --json) || {
        echo "❌ ERROR: Failed to generate Wallet A"
        return 1
    }

    local address_a private_key_a
    address_a=$(echo "$wallet_A_json" | jq -r '.[0].address')
    private_key_a=$(echo "$wallet_A_json" | jq -r '.[0].private_key')

    local address_b
    address_b=$(cast wallet new --json | jq -r '.[0].address') || {
        echo "❌ ERROR: Failed to generate Wallet B"
        return 1
    }

    # ✅ Export variables after assignment
    export ADDRESS_A="$address_a"
    export PRIVATE_KEY_A="$private_key_a"
    export ADDRESS_B="$address_b"

    echo "👤 Wallet A: $ADDRESS_A"
    echo "🔑 Wallet A Private Key: (hidden)"
    echo "👤 Wallet B: $ADDRESS_B"

    # ✅ Deploy ERC20Mock Contract
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"
    assert_success

    # ✅ Fix SC2155: Assign before exporting
    local contract_temp
    contract_temp=$(echo "$output" | tail -n 1)
    export CONTRACT_ADDR="$contract_temp"

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

    local gas_units gas_price value value_ether
    gas_units=$(cast estimate --rpc-url "$L2_RPC_URL" --create "$bytecode") || return 1
    gas_units=$(echo "scale=0; $gas_units / 2" | bc)
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL") || return 1
    value=$(echo "$gas_units * $gas_price" | bc)
    value_ether=$(cast to-unit "$value" ether)"ether"

    echo "🚨 Deploying with insufficient gas: $value_ether"

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" "$ADDRESS_A" --value "$value_ether" --legacy

    # ✅ Explicitly Capture Deploy Contract Failure
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY_A" "$contract_artifact"
    assert_failure  # ✅ Should fail due to low gas
}
