#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/pos-setup.bash"
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"
  pos_setup

  # Test parameters.
  export VALIDATOR_ID=${VALIDATOR_ID:="1"}
  export VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/staking/validator/${VALIDATOR_ID}" | jq --raw-output ".result.power"'
}

# bats file_tags=pos,validator
@test "update validator stake" {
  initial_validator_power=$(eval "${VALIDATOR_POWER_CMD}")
  echo "Initial power of the validator (${VALIDATOR_ID}): ${initial_validator_power}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  stake_update_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${VALIDATOR_ID})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "restakePOL(uint,uint,bool)" "${VALIDATOR_ID}" "${stake_update_amount}" false

  echo "Monitoring the power of the validator..."
  validator_power_update_amount=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_eventually_equal "${VALIDATOR_POWER_CMD}" $((initial_validator_power + validator_power_update_amount))
}
