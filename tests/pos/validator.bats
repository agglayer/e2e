#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
}

function generate_new_keypair() {
  mnemonic=$(cast wallet new-mnemonic --json | jq --raw-output '.mnemonic')
  polycli wallet inspect --mnemonic "${mnemonic}" --addresses 1 >key.json
  address=$(jq --raw-output '.Addresses[0].ETHAddress' key.json)
  public_key=0x$(jq --raw-output '.Addresses[0].HexFullPublicKey' key.json)
  private_key=$(jq --raw-output '.Addresses[0].HexPrivateKey' key.json)
  echo "${address} ${public_key} ${private_key}"
}

# bats file_tags=pos,validator
@test "update validator stake" {
  VALIDATOR_ID=${VALIDATOR_ID:="1"}
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:="0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/staking/validator/${VALIDATOR_ID}" | jq --raw-output ".result.power"'

  initial_validator_power=$(eval "${VALIDATOR_POWER_CMD}")
  echo "Initial power of the validator (${VALIDATOR_ID}): ${initial_validator_power}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  stake_update_amount = $(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${VALIDATOR_ID})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "restakePOL(uint,uint,bool)" "${VALIDATOR_ID}" "${stake_update_amount}" false

  echo "Monitoring the power of the validator..."
  validator_power_update_amount=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_command_eventually_equal "${VALIDATOR_POWER_CMD}" $((initial_validator_power + validator_power_update_amount))
}

# bats file_tags=pos,validator
@test "update validator top-up fee" {
  VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:="0x97538585a02A3f1B1297EB9979cE1b34ff953f1E"} # first validator
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".result[] | select(.denom == \"matic\") | .amount"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".result[] | select(.denom == \"pol\") | .amount"'
  fi

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
  assert_command_eventually_equal "${TOP_UP_FEE_BALANCE_CMD}" $((initial_top_up_balance + top_up_amount))
}

# bats file_tags=pos,validator
@test "add new validator" {
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators.length"'
  fi

  initial_validator_count=$(eval "${VALIDATOR_COUNT_CMD}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Generating a new validator keypair..."
  # Note: We're using the `generate_new_keypair` function defined below instead of `cast wallet new`
  # because we need to generate a public key.
  read validator_address validator_public_key validator_private_key < <(generate_new_keypair)
  echo "address: ${validator_address}"
  echo "public key: ${validator_public_key}"

  echo "Funding the validator account with ETH..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value 1ether "${validator_address}"

  echo "Funding the validator acount with MATIC tokens..."
  deposit_amount=$(cast to-unit 10ether wei)      # minimal deposit: 1000000000000000000 (1 ether)
  heimdall_fee_amount=$(cast to-unit 10ether wei) # minimal heimdall fee: 1000000000000000000 (1 ether)
  funding_amount=$((deposit_amount + heimdall_fee_amount))
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${funding_amount}"

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${funding_amount}"

  echo "Adding the new validator to the validator set..."
  accept_delegation=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "stakeForPOL(address,uint,uint,bool,bytes)" \
    "${validator_address}" "${deposit_amount}" "${heimdall_fee_amount}" "${accept_delegation}" "${validator_public_key}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count + 1))
}
