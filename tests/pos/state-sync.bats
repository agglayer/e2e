#!/usr/bin/env bats

setup() {
    # Load libraries.
    load "$PROJECT_ROOT/core/helpers/scripts/async.bash"

    # Define parameters.
    export ENCLAVE=${ENCLAVE:-"pos"}
    export ADDRESS=${ADDRESS:-"0x74Ed6F462Ef4638dc10FFb05af285e8976Fb8DC9"}
    export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}

    export L2_CL_NODE_TYPE=${L2_CL_NODE_TYPE:-"heimdall"}
    if [[ "${L2_CL_NODE_TYPE}" != "heimdall" && "${L2_CL_NODE_TYPE}" != "heimdall-v2" ]]; then
        echo "❌ Wrong L2 CL node type given: '${L2_CL_NODE_TYPE}'. Expected 'heimdall' or 'heimdall-v2'."
        exit 1
    fi

    # RPC Urls.
    export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"}
    if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
        export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" "l2-el-1-bor-heimdall-validator" rpc)}
        export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" "l2-cl-1-heimdall-bor-validator" http)}
    elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
        export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" "l2-el-1-bor-modified-for-heimdall-v2-heimdall-v2-validator" rpc)}
        export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" "l2-cl-1-heimdall-v2-bor-modified-for-heimdall-v2-validator" http)}
    fi

    # Contract addresses
    matic_contract_addresses=$(kurtosis files inspect "${ENCLAVE}" matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.DepositManagerProxy')}
    export ERC20_TOKEN_ADDRESS=${ERC20_TOKEN_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')}
    export L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS:-$(kurtosis files inspect "${ENCLAVE}" l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')}

    # Commands.
    if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
        HEIMDALL_STATE_SYNC_COUNT_CMD='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".result | length"'
    elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
        HEIMDALL_STATE_SYNC_COUNT_CMD='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".event_records | length"'
    fi
    export HEIMDALL_STATE_SYNC_COUNT_CMD="${HEIMDALL_STATE_SYNC_COUNT_CMD}"

    BOR_STATE_SYNC_COUNT_CMD='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'
    export BOR_STATE_SYNC_COUNT_CMD="${BOR_STATE_SYNC_COUNT_CMD}"
}

# bats file_tags=pos,state-sync
@test "Trigger State Sync" {
    # Get initial values.
    initial_balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${ADDRESS}")
    initial_heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
    initial_bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")
    echo "Initial values:"
    echo "- ${ADDRESS} L2 balance: ${initial_balance} ether."
    echo "- Heimdall state sync count: ${initial_heimdall_state_sync_count}."
    echo "- Bor state sync count: ${initial_bor_state_sync_count}."

    # Bridge some ERC20 tokens to trigger a state sync.
    echo "Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
        "${ERC20_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" 10

    echo "Depositing ERC20 to trigger a state sync..."
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
        "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${ERC20_TOKEN_ADDRESS}" 10

    # Monitor state syncs.
    timeout="180" # seconds
    interval="10" # seconds
    echo "Monitoring state syncs on Heimdall..."
    assert_eventually_greater_than "${HEIMDALL_STATE_SYNC_COUNT_CMD}" "${initial_heimdall_state_sync_count}" "${timeout}" "${interval}"

    echo "Monitoring state syncs on Bor..."
    assert_eventually_greater_than "${BOR_STATE_SYNC_COUNT_CMD}" "${initial_bor_state_sync_count}" "${timeout}" "${interval}"

    # Check new account balance on L2.
    new_balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${ADDRESS}")
    if [[ "${new_balance}" -lt "${initial_balance}" ]]; then
        echo "❌ ${ADDRESS} balance has not changed."
        exit 1
    fi
    echo "✅ ${ADDRESS} balance has increased: ${new_balance} ether."
}
