pos_setup() {
  # Private key used to send transactions.
  export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}

  # The type of the L2 CL node is used to determine how to fetch the different RPC and API URLs.
  export L2_CL_NODE_TYPE=${L2_CL_NODE_TYPE:-"heimdall"}
  if [[ "${L2_CL_NODE_TYPE}" != "heimdall" && "${L2_CL_NODE_TYPE}" != "heimdall-v2" ]]; then
    echo "❌ Wrong L2 CL node type given: '${L2_CL_NODE_TYPE}'. Expected 'heimdall' or 'heimdall-v2'."
    exit 1
  fi

  # The name of the Kurtosis enclave (used for default values).
  export ENCLAVE=${ENCLAVE:-"pos"}

  # L1 and L2 RPC and API URLs.
  export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"}
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" "l2-el-1-bor-heimdall-validator" rpc)}
    export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" "l2-cl-1-heimdall-bor-validator" http)}
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE}" "l2-el-1-bor-modified-for-heimdall-v2-heimdall-v2-validator" rpc)}
    export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" "l2-cl-1-heimdall-v2-bor-modified-for-heimdall-v2-validator" http)}
  fi

  # Contract addresses.
  matic_contract_addresses=$(kurtosis files inspect "${ENCLAVE}" matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
  export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.DepositManagerProxy')}
  export L1_STAKE_MANAGER_PROXY_ADDRESS=${L1_STAKE_MANAGER_PROXY_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.StakeManagerProxy')}
  export L1_MATIC_TOKEN_ADDRESS=${L1_MATIC_TOKEN_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')}

  export L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS:-$(kurtosis files inspect "${ENCLAVE}" l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')}
}
