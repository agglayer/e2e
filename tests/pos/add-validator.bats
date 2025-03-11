#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/pos-setup.bash"
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"
  pos_setup

  # Test parameters.
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators.length"'
  fi
  export VALIDATOR_COUNT_CMD="${VALIDATOR_COUNT_CMD}"
}

generate_new_keypair() {
  mnemonic=$(cast wallet new-mnemonic --json | jq --raw-output '.mnemonic')
  polycli wallet inspect --mnemonic "${mnemonic}" --addresses 1 >key.json
  address=$(cat key.json | jq --raw-output '.Addresses[0].ETHAddress')
  public_key=0x$(cat key.json | jq --raw-output '.Addresses[0].HexFullPublicKey')
  private_key=$(cat key.json | jq --raw-output '.Addresses[0].HexPrivateKey')
  echo "${address}"
  echo "${public_key}"
  echo "${private_key}"
}

# bats file_tags=pos,validator
@test "add new validator to the validator set on L1" {
  initial_validator_count=$(eval "${VALIDATOR_COUNT_CMD}")
  echo "Initial validator count: ${initial_validator_count}."

  echo "Generating a new validator keypair..."
  # Note: We're using the `generate_new_keypair` function defined below instead of cast wallet new
  # because we need to generate a public key.
  read -r validator_address validator_public_key _ < <(generate_new_keypair)

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  validator_balance=$(cast to-unit 1000000000ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${validator_balance}"

  echo "Staking the validator..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "stakeForPOL(address,uint,uint,bool,bytes)" "${validator_address}" 10 10 false "${validator_public_key}"

  echo "Monitoring the validator count..."
  assert_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count + 1))
}
