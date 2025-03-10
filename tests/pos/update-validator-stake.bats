#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"

  # Define test parameters.
  export ENCLAVE=${ENCLAVE:-"pos"}
  export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}
  export VALIDATOR_ID=${VALIDATOR_ID:="1"}

  # RPC Urls.
  export L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"}
  export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)}

  # Contract addresses.
  matic_contract_addresses=$(kurtosis files inspect "${ENCLAVE}" matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
  export STAKE_MANAGER_PROXY_ADDRESS=${STAKE_MANAGER_PROXY_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.StakeManagerProxy')}
  export MATIC_TOKEN_ADDRESS=${MATIC_TOKEN_ADDRESS:-$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')}

  # Commands.
  VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/staking/validator/${VALIDATOR_ID}" | jq ".result.power"'
}

# bats file_tags=pos,validator
@test "update validator stake" {
  initial_validator_power=$(eval "${VALIDATOR_POWER_CMD}")
  echo "Initial power of the validator (${VALIDATOR_ID}): ${initial_validator_power}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  stake_update_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${VALIDATOR_ADDRESS})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${STAKE_MANAGER_PROXY_ADDRESS}" "restakePOL(uint,uint,bool)" "${VALIDATOR_ID}" "${stake_update_amount}" false

  echo "Monitoring the power of the validator..."
  validator_power_update_amount=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_eventually_equal "${VALIDATOR_POWER_CMD}" $((initial_validator_power + validator_power_update_amount))
}
