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
  rm key.json
  echo "${address} ${public_key} ${private_key}"
}

# bats file_tags=pos,validator
@test "update validator stake" {
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"} # first validator
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"
  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/staking/validator/${VALIDATOR_ID}" | jq --raw-output ".result.power"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.voting_power"'
  fi
  echo "VALIDATOR_POWER_CMD=${VALIDATOR_POWER_CMD}"

  validator_address=$(cast wallet address --private-key "${VALIDATOR_PRIVATE_KEY}")
  echo "validator_address=${validator_address}"

  initial_validator_power=$(eval "${VALIDATOR_POWER_CMD}")
  echo "Initial power of the validator (${VALIDATOR_ID}): ${initial_validator_power}."

  echo "Funding the validator acount with MATIC tokens..."
  stake_update_amount=$(cast to-unit 10ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${stake_update_amount}"

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."

  # TODO: Find out why the call is reverting
  # Error: server returned an error response: error code -32000: execution reverted
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${VALIDATOR_ID})..."
  stake_rewards=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "restake(uint,uint,bool)" "${VALIDATOR_ID}" "${stake_update_amount}" "${stake_rewards}"

  echo "Monitoring the power of the validator..."
  validator_power_update_amount=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_command_eventually_equal "${VALIDATOR_POWER_CMD}" $((initial_validator_power + validator_power_update_amount))
}

# bats file_tags=pos,validator
@test "update validator top-up fee" {
  VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:-"0x97538585a02A3f1B1297EB9979cE1b34ff953f1E"} # first validator
  echo "VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS}"

  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".result[] | select(.denom == \"matic\") | .amount"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/bank/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".result[] | select(.denom == \"pol\") | .amount"'
  fi
  echo "TOP_UP_FEE_BALANCE_CMD=${TOP_UP_FEE_BALANCE_CMD}"

  initial_top_up_balance=$(eval "${TOP_UP_FEE_BALANCE_CMD}")
  echo "${VALIDATOR_ADDRESS} initial top-up balance: ${initial_top_up_balance}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  top_up_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${top_up_amount}"

  echo "Topping up the fee balance of the validator (${VALIDATOR_ADDRESS})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "topUpForFee(address,uint)" "${VALIDATOR_ADDRESS}" "${top_up_amount}"

  # TODO: Find out why the target is wrong here.
  # Monitoring the top-up balance of the validator...
  # [2025-03-31 13:39:35] Target: -5930898827444486144
  # [2025-03-31 13:39:35] Result: 1000000000000000000000000000
  # [2025-03-31 13:39:45] Result: 1000000000000000000000000000
  # [2025-03-31 13:39:55] Result: 1000000000000000000000000000
  # [2025-03-31 13:40:05] Result: 1000000000000000000000000000
  # [2025-03-31 13:40:15] Result: 999999999999000000000000000
  # [2025-03-31 13:40:25] Result: 1000000000999000000000000000
  # [2025-03-31 13:40:35] Result: 1000000000999000000000000000
  # [2025-03-31 13:40:45] Result: 1000000000999000000000000000
  # [2025-03-31 13:40:55] Result: 1000000000999000000000000000
  # Timeout reached.
  echo "Monitoring the top-up balance of the validator..."
  assert_command_eventually_equal "${TOP_UP_FEE_BALANCE_CMD}" $((initial_top_up_balance + top_up_amount))
}

# bats file_tags=pos,validator
@test "add new validator" {
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/stake/validators-set" | jq --raw-output ".validator_set.validators | length"'
  fi
  echo "VALIDATOR_COUNT_CMD=${VALIDATOR_COUNT_CMD}"

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

  # TODO: Find out why the call is reverting
  # Error: server returned an error response: error code -32000: execution reverted
  echo "Adding the new validator to the validator set..."
  accept_delegation=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "stakeFor(address,uint,uint,bool,bytes)" \
    "${validator_address}" "${deposit_amount}" "${heimdall_fee_amount}" "${accept_delegation}" "${validator_public_key}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count + 1))
}

# bats file_tags=pos,validator
@test "remove validator" {
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"} # first validator
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"
  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/staking/validator-set" | jq --raw-output ".result.validators | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/stake/validators-set" | jq --raw-output ".validator_set.validators | length"'
  fi

  initial_validator_count=$(eval "${VALIDATOR_COUNT_CMD}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Removing the validator from the validator set..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "unstakePOL(uint)" "${VALIDATOR_ID}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count - 1))
}

# bats file_tags=pos,validator
@test "update signer" {
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"} # first validator
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"
  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    VALIDATOR_SIGNER_CMD='curl --silent "${L2_CL_API_URL}/staking/validator/${VALIDATOR_ID}" | jq --raw-output ".result.signer"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    VALIDATOR_SIGNER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.signer"'
  fi

  initial_signer=$(eval "${VALIDATOR_SIGNER_CMD}")
  echo "Initial signer: ${initial_signer}"

  # New account:
  # - address: 0xd74c0D3dEe45a0a9516fB66E31C01536e8756e2A
  # - public key: 0x125925a928ac0c6c2aea9005ebaf358098ecdf6f6c455b041056dfb89f4ac8eda42f1d72a1274b88d8b9989c3e4bfabf0775d574a9f3b0d53002f8ff4c9d9908
  # - private-key: f118c1f07cd6e1a417175f6316a5a36707da7be07cf5e360a9397e8a52bc690f
  new_public_key="0x125925a928ac0c6c2aea9005ebaf358098ecdf6f6c455b041056dfb89f4ac8eda42f1d72a1274b88d8b9989c3e4bfabf0775d574a9f3b0d53002f8ff4c9d9908"

  echo "Updating signer..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "updateSigner(uint,bytes)" "${VALIDATOR_ID}" "${new_public_key}"
  
  echo "Monitoring signer change..."
  assert_command_eventually_equal "${VALIDATOR_SIGNER_CMD}" "0xd74c0D3dEe45a0a9516fB66E31C01536e8756e2A"
}
