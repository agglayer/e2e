#!/usr/bin/env bats

setup() {
    # Load libraries.
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'
    load "$PROJECT_ROOT/core/helpers/scripts/send_tx.bash"
    load "$PROJECT_ROOT/core/helpers/scripts/async.bash"

    # Define environment variables.
    export ENCLAVE=${ENCLAVE:-"pos"}
    export ADDRESS=${ADDRESS:-"0x74Ed6F462Ef4638dc10FFb05af285e8976Fb8DC9"}
    export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}

    export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print $ENCLAVE el-1-geth-lighthouse rpc)"}
    export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" l2-el-1-bor-heimdall-validator rpc)}
    export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)}
    export L2_CL_NODE_TYPE=${L2_CL_NODE_TYPE:-"heimdall"}

    matic_contract_addresses=$(kurtosis files inspect $ENCLAVE matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.DepositManagerProxy')}
    export ERC20_TOKEN_ADDRESS=${ERC20_TOKEN_ADDRESS:-$(echo $matic_contract_addresses | jq --raw-output '.root.tokens.MaticToken')}
    export L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS:-$(kurtosis files inspect $ENCLAVE l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')}
}

# bats file_tags=pos,state-sync
@test "Trigger State Sync" {
    # Check initial account balance on L2.
    initial_balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${ADDRESS}")
    echo "${ADDRESS} initial balance: ${initial_balance} ether."

    # Check initial state sync count.
    if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
        heimdall_state_sync_count_cmd='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".result | length"'
    elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
        heimdall_state_sync_count_cmd='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".event_records | length"'
    else
        echo '❌ Wrong L2 CL node type given: "${L2_CL_NODE_TYPE}". Expected "heimdall" or "heimdall-v2".'
        exit 1
    fi
    initial_heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
    echo "Heimdall initial state sync count: ${initial_heimdall_state_sync_count}."

    bor_state_sync_count_cmd='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'
    initial_bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")
    echo "Bor initial state sync count: ${initial_bor_state_sync_count}."

    # Bridge some ERC20 tokens to trigger a state sync.
    erc20_token_amount_to_bridge=10

    echo "✅ Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
    run send_tx "${L1_RPC_URL}" "${PRIVATE_KEY}" "${ERC20_TOKEN_ADDRESS}" \
        "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${erc20_token_amount_to_bridge}"

    echo "🚀 Depositing ERC20 to trigger a state sync..."
    run send_tx "${L1_RPC_URL}" "${PRIVATE_KEY}" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" \
        "depositERC20(address,uint)" "${ERC20_TOKEN_ADDRESS}" "${erc20_token_amount_to_bridge}"

    # Monitor state syncs on the L2 consensus layer.
    echo "👀 Monitoring state syncs on Heimdall..."
    assert_eventually_greater_than "${heimdall_state_sync_count_cmd}" "${initial_heimdall_state_sync_count}" 180 10

    # Monitor state syncs on the L2 execution layer.
    echo "👀 Monitoring state syncs on Bor..."
    cmd='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'
    assert_eventually_greater_than "${bor_state_sync_count_cmd}" "${initial_bor_state_sync_count}" 180 10

    # Check new account balance on L2.
    balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${ADDRESS}")
    if [[ "${balance}" -lt "${initial_balance}" ]]; then
        echo "❌ ${ADDRESS} balance has not changed."
        exit 1
    fi
    echo "✅ ${ADDRESS} balance has increased: ${balance} ether."
}
