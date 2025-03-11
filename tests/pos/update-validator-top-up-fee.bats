#!/usr/bin/env bats

# Top-ups are amounts used to pay fees on the Heimdall chain.
# 1) When a new validator joins, they can mention a top-up amount to be used for fees, in addition
# to the staked amount, which will be used as balance on Heimdall chain to pay fees.
# 2) A user can also directly call the top-up function on the staking smart contract on Ethereum to
# increase the top-up balance on Heimdall.

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/pos-setup.bash"
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"
  pos_setup

  # Test parameters.
  export VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:="0x97538585a02A3f1B1297EB9979cE1b34ff953f1E"} # first validator
  export TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".result[] | select(.denom == "pol") | .amount"'
}

# bats file_tags=pos,validator
@test "update validator top-up fee" {
  initial_top_up_balance=$(eval "${TOP_UP_FEE_BALANCE_CMD}")
  echo "${VALIDATOR_ADDRESS} initial top-up balance: ${initial_top_up_balance}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  top_up_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${top_up_amount}"

  echo "Topping up the fee balance of the validator (${VALIDATOR_ADDRESS})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "topUpForFee(address,uint)" "${VALIDATOR_ADDRESS}" "${top_up_amount}"

  echo "Monitoring the top-up balance of the validator..."
  assert_eventually_equal "${TOP_UP_FEE_BALANCE_CMD}" $((initial_top_up_balance + top_up_amount))
}
