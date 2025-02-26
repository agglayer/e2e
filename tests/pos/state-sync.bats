#!/usr/bin/env bats

setup() {
    # Load libraries.
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'
    load "$PROJECT_ROOT/core/helpers/common.bash"

    # Define environment variables.
    export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}

    export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print pos el-1-geth-lighthouse rpc)"}
    export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" l2-el-1-bor-heimdall-validator rpc)}
    export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)}
    export L2_CL_NODE_TYPE=${L2_CL_NODE_TYPE:-"heimdall"}

    matic_contract_addresses=$(kurtosis files inspect pos matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.DepositManagerProxy')}
    export ERC20_TOKEN_ADDRESS=${ERC20_TOKEN_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.tokens.MaticToken')}
    export L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS:-$(kurtosis files inspect pos l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')}
}

# bats file_tags=pos,state-sync
@test "Trigger State Sync" {
    # Bridge some ERC20 tokens to trigger a state sync.
    amount_to_bridge=10

    echo "✅ Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
    run send_tx "$L1_RPC_URL" "$PRIVATE_KEY" "$ERC20_TOKEN_ADDRESS" \
        "approve(address,uint)" "$L1_DEPOSIT_MANAGER_PROXY_ADDRESS" "$amount_to_bridge"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    echo "🚀 Depositing ERC20 to trigger a state sync..."
    run send_tx "$L1_RPC_URL" "$PRIVATE_KEY" "$L1_DEPOSIT_MANAGER_PROXY_ADDRESS" \
        "depositERC20(address,uint)" "$ERC20_TOKEN_ADDRESS" "$amount_to_bridge"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # Monitor state syncs on the L2 consensus layer.
    echo "👀 Monitoring state syncs on Heimdall..."
    while true; do
        if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
            state_sync_count=$(curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq '.result | length')
        elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
            state_sync_count=$(curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq '.event_records | length')
        else
            echo '❌ Wrong L2 CL node type given: "${L2_CL_NODE_TYPE}". Expected "heimdall" or "heimdall-v2".'
            exit 1
        fi

        if [[ "$state_sync_count" =~ ^[0-9]+$ ]] && [[ "$state_sync_count" -gt "0" ]]; then
            echo "✅ A state sync occured! State sync count: ${state_sync_count}."
            assert_equal "$state_sync_count" 1
            break
        else
            echo "No state sync occured yet... State sync count: ${state_sync_count}."
        fi

        echo "Waiting 5 seconds before next request..."
        sleep 5
    done

    # Monitor state syncs on the L2 execution layer.
    echo "👀 Monitoring state syncs on Bor..."
    while true; do
        run query_contract "$L2_RPC_URL" "$L2_STATE_RECEIVER_ADDRESS" "lastStateId()(uint)"
        assert_success
        latest_state_id=$(echo "$output" | tail -n 1)
        if [[ "$latest_state_id" =~ ^[0-9]+$ ]] && [[ "$latest_state_id" -gt "0" ]]; then
            echo "✅ A state sync was received! Latest state id: ${latest_state_id}."
            assert_equal "$latest_state_id" 1
            break
        else
            echo "No state sync received yet... Latest state id: ${latest_state_id}."
        fi

        echo "Waiting 5 seconds before next request..."
        sleep 5
    done

}
