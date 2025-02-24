#!/usr/bin/env bats

setup() {
    export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}

    # RPC Urls
    export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print pos el-1-geth-lighthouse rpc)"}

    # Contract addresses
    matic_contract_addresses=$(kurtosis files inspect pos matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.DepositManagerProxy')}
    export ERC20_TOKEN_ADDRESS=${ERC20_TOKEN_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.tokens.MaticToken')}
}

# bats file_tags=pos:any
@test "Trigger State Sync" {
    echo "✅ Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
    amount_to_bridge=10
    run send_tx "$L1_RPC_URL" "$PRIVATE_KEY" "$ERC20_TOKEN_ADDRESS" \
        "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" 10
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    echo "🚀 Depositing ERC20 to trigger a state sync..."
    run send_tx "$L1_RPC_URL" "$PRIVATE_KEY" "$DEPOSIT_MANAGER_PROXY_ADDRESS" \
        "depositERC20(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" 10
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # TODO
}
