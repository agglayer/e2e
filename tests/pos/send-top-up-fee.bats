#!/usr/bin/env bats

# Top-ups are amounts used to pay fees on the Heimdall chain.
# 1) When a new validator joins, they can mention a top-up amount to be used for fees, in addition
# to the staked amount, which will be used as balance on Heimdall chain to pay fees.
# 2) A user can also directly call the top-up function on the staking smart contract on Ethereum to
# increase the top-up balance on Heimdall.

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"

  # Define test parameters.
  export ENCLAVE=${ENCLAVE:-"pos"}
  export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}
  export VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:="TODO"}

  # RPC Urls.
  export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"}
  export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)}

  # Contract addresses.
  matic_contract_addresses=$(kurtosis files inspect "${ENCLAVE}" matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
  export STAKE_MANAGER_PROXY_ADDRESS=${STAKE_MANAGER_PROXY_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.StakeManagerProxy')}
  export MATIC_TOKEN_ADDRESS=${MATIC_TOKEN_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')}

  # Commands.
  TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq ".result[0].amount"'
}

# bats file_tags=pos,top-up-fee
@test "send top-up fee" {
  initial_top_up_balance=$(eval "${TOP_UP_FEE_BALANCE_CMD}")
  echo "${VALIDATOR_ADDRESS} initial top-up balance: ${initial_top_up_balance}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  top_up_amount = $(cast to-wei 1 ether)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${STAKE_MANAGER_PROXY_ADDRESS}" "${top_up_amount}"

  echo "Topping up the fee balance of the validator (${VALIDATOR_ADDRESS})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${STAKE_MANAGER_PROXY_ADDRESS}" "topUpForFee(address,uint)" "${VALIDATOR_ADDRESS}" "${top_up_amount}"

  echo "Monitoring the top-up balance of the validator..."
  assert_eventually_equal "${TOP_UP_FEE_BALANCE_CMD}" $((initial_top_up_balance + top_up_amount))
}
