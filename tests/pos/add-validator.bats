#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "$PROJECT_ROOT/core/helpers/pos-setup.bash"
  load "$PROJECT_ROOT/core/helpers/scripts/async.bash"
  pos_setup

  # Test parameters.
  export VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators.length"'
}

generate_new_keypair() {
  # Generate a new public/private keypair.
  # For reference: https://gist.github.com/miguelmota/3793b160992b4ea0b616497b8e5aee2f
  openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout >key
  public_key=$(cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//')
  private_key=$(cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//')
  address=$(echo "${public_key}" | keccak-256sum -x -l | tr -d ' -' | tail -c 41)
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
