#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
}

function generate_new_keypair() {
  mnemonic=$(cast wallet new-mnemonic --json | jq --raw-output '.mnemonic')
  private_key=$(cast wallet derive-private-key "${mnemonic}" 0)
  address=$(cast wallet address "${private_key}")
  public_key=$(cast wallet public-key --raw-private-key "${private_key}")
  echo "${address} ${public_key} ${private_key}"
}

# bats file_tags=pos,validator
@test "add new validator" {
  VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/stake/validators-set" | jq --raw-output ".validator_set.validators | length"'
  echo "VALIDATOR_COUNT_CMD=${VALIDATOR_COUNT_CMD}"

  initial_validator_count=$(eval "${VALIDATOR_COUNT_CMD}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Generating a new validator keypair..."
  # Note: We're using the `generate_new_keypair` function defined below instead of `cast wallet new`
  # because we need to generate a public key.
  read validator_address validator_public_key validator_private_key < <(generate_new_keypair)
  echo "Address: ${validator_address}"
  echo "Public key: ${validator_public_key}"

  echo "Funding the validator account with ETH..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value 1ether "${validator_address}"

  echo "Funding the validator account with MATIC tokens..."
  deposit_amount=$(cast to-unit 1ether wei)      # minimum deposit: 1000000000000000000 (1 ether)
  heimdall_fee_amount=$(cast to-unit 1ether wei) # minimum heimdall fee: 1000000000000000000 (1 ether)
  funding_amount=$((deposit_amount + heimdall_fee_amount))

  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${funding_amount}"

  echo "Allowing the StakeManagerProxy contract to spend MATIC tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${funding_amount}"

  echo "Adding new validator to the validator set..."
  accept_delegation=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "stakeForPOL(address,uint,uint,bool,bytes)" \
    "${validator_address}" "${deposit_amount}" "${heimdall_fee_amount}" "${accept_delegation}" "${validator_public_key}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count + 1)) 180
}

# bats file_tags=pos,validator
@test "update validator stake" {
  # First validator.
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"

  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.voting_power"'
  echo "VALIDATOR_POWER_CMD=${VALIDATOR_POWER_CMD}"

  validator_address=$(cast wallet address --private-key "${VALIDATOR_PRIVATE_KEY}")
  echo "validator_address=${validator_address}"

  initial_voting_power=$(eval "${VALIDATOR_POWER_CMD}")
  echo "Initial voting power of the validator (${VALIDATOR_ID}): ${initial_voting_power}."

  echo "Funding the validator acount with MATIC/POL tokens..."
  stake_update_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${stake_update_amount}"

  echo "Allowing the StakeManagerProxy contract to spend MATIC/POL tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${VALIDATOR_ID})..."
  stake_rewards=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "restakePOL(uint,uint,bool)" "${VALIDATOR_ID}" "${stake_update_amount}" "${stake_rewards}"

  echo "Monitoring the voting power of the validator..."
  voting_power_update=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_command_eventually_equal "${VALIDATOR_POWER_CMD}" $((initial_voting_power + voting_power_update)) 180
}

# bats file_tags=pos,validator
@test "update validator top-up fee" {
  # First validator.
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"

  VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:-"0x97538585a02A3f1B1297EB9979cE1b34ff953f1E"}
  echo "VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS}"

  TOP_UP_FEE_BALANCE_CMD='curl --silent "${L2_CL_API_URL}/cosmos/bank/v1beta1/balances/${VALIDATOR_ADDRESS}" | jq --raw-output ".balances[] | select(.denom == \"pol\") | .amount"'
  echo "TOP_UP_FEE_BALANCE_CMD=${TOP_UP_FEE_BALANCE_CMD}"

  initial_top_up_balance=$(eval "${TOP_UP_FEE_BALANCE_CMD}")
  echo "${VALIDATOR_ADDRESS} initial top-up balance: ${initial_top_up_balance}."

  echo "Allowing the StakeManagerProxy contract to spend MATIC/POL tokens on our behalf..."
  top_up_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${top_up_amount}"

  echo "Topping up the fee balance of the validator (${VALIDATOR_ADDRESS})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "topUpForFee(address,uint)" "${VALIDATOR_ADDRESS}" "${top_up_amount}"

  echo "Monitoring the top-up balance of the validator..."
  echo "Initial balance: ${initial_top_up_balance}"

  timeout=180
  interval=10
  start_time=$(date +%s)
  end_time=$((start_time + timeout))

  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    current_balance=$(eval "${TOP_UP_FEE_BALANCE_CMD}")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Current balance: ${current_balance}"

    if [[ $(echo "${current_balance} > ${initial_top_up_balance}" | bc) -eq 1 ]]; then
      echo "Balance check passed: ${current_balance} > ${initial_top_up_balance}"
      break
    fi

    sleep "${interval}"
  done
}

# bats file_tags=pos,validator
@test "update signer" {
  # First validator.
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"

  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  VALIDATOR_SIGNER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.signer"'

  initial_signer=$(eval "${VALIDATOR_SIGNER_CMD}")
  echo "Initial signer: ${initial_signer}"

  # New account:
  # - address: 0xd74c0D3dEe45a0a9516fB66E31C01536e8756e2A
  # - public key: 0x125925a928ac0c6c2aea9005ebaf358098ecdf6f6c455b041056dfb89f4ac8eda42f1d72a1274b88d8b9989c3e4bfabf0775d574a9f3b0d53002f8ff4c9d9908
  # - private-key: 0xf118c1f07cd6e1a417175f6316a5a36707da7be07cf5e360a9397e8a52bc690f
  new_public_key="0x125925a928ac0c6c2aea9005ebaf358098ecdf6f6c455b041056dfb89f4ac8eda42f1d72a1274b88d8b9989c3e4bfabf0775d574a9f3b0d53002f8ff4c9d9908"

  echo "Updating signer update limit..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_GOVERNANCE_PROXY_ADDRESS}" "update(address,bytes)" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" \
    "$(cast calldata "updateSignerUpdateLimit(uint256)" "1")"

  echo "Updating signer..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "updateSigner(uint,bytes)" "${VALIDATOR_ID}" "${new_public_key}"

  echo "Monitoring signer change..."
  assert_command_eventually_equal "${VALIDATOR_SIGNER_CMD}" "0xd74c0d3dee45a0a9516fb66e31c01536e8756e2a" 180
}

# bats file_tags=pos,validator,delegate
@test "delegate MATIC/POL to a validator" {
  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  # Use the default foundry test address as the delegator.
  DELEGATOR_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  DELEGATOR_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  echo "DELEGATOR_PRIVATE_KEY=${DELEGATOR_PRIVATE_KEY}"
  echo "DELEGATOR_ADDRESS=${DELEGATOR_ADDRESS}"

  echo "L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS}"

  # Get validator's ValidatorShare contract address.
  validator_share_address=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "getValidatorContractAddress(uint)(address)" "${VALIDATOR_ID}")
  echo "validator_share_address=${validator_share_address}"

  # Check if validator accepts delegation.
  accepts_delegation=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "delegation()(bool)")
  echo "accepts_delegation=${accepts_delegation}"
  if [[ "${accepts_delegation}" != "true" ]]; then
    echo "Validator does not accept delegation, skipping test"
    skip "Validator does not accept delegation"
  fi

  # Check initial validator total stake (own stake + delegated amount).
  initial_total_stake=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${VALIDATOR_ID}" | cut -d' ' -f1)
  echo "Initial total validator stake: ${initial_total_stake}"

  # Check initial delegator stake in this validator.
  initial_delegator_stake_data=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${DELEGATOR_ADDRESS}")
  initial_delegator_stake=$(echo "${initial_delegator_stake_data}" | head -1 | cut -d' ' -f1)
  echo "Initial delegator stake: ${initial_delegator_stake}"

  echo "Transferring ETH from main address to foundry address for gas..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value 1ether "${DELEGATOR_ADDRESS}"

  echo "Transferring MATIC/POL tokens from main address to foundry address..."
  delegation_amount=$(cast to-unit 1ether wei)

  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "transfer(address,uint)" "${DELEGATOR_ADDRESS}" "${delegation_amount}"

  echo "Verifying foundry address received the tokens..."
  delegator_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint256)" "${DELEGATOR_ADDRESS}" | cut -d' ' -f1)
  delegator_eth_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${DELEGATOR_ADDRESS}" --ether)
  echo "Foundry address MATIC/POL balance: $(cast to-unit ${delegator_pol_balance} ether) POL"
  echo "Foundry address ETH balance: ${delegator_eth_balance} ETH"

  echo "Allowing the StakeManager to spend MATIC/POL tokens on foundry address behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${DELEGATOR_PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${delegation_amount}"

  echo "Delegating ${delegation_amount} wei (1 MATIC/POL) to validator ${VALIDATOR_ID}..."
  min_shares_to_mint=0
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${DELEGATOR_PRIVATE_KEY}" \
    "${validator_share_address}" "buyVoucherPOL(uint,uint)" "${delegation_amount}" "${min_shares_to_mint}"

  echo "Verifying delegation was successful..."

  # Check that validator's total stake increased.
  expected_total_stake=$((initial_total_stake + delegation_amount))
  final_total_stake=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${VALIDATOR_ID}" | cut -d' ' -f1)
  echo "Expected total stake: ${expected_total_stake}"
  echo "Final total stake: ${final_total_stake}"

  # Check that delegator's stake in validator increased.
  final_delegator_stake_data=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${DELEGATOR_ADDRESS}")
  final_delegator_stake=$(echo "${final_delegator_stake_data}" | head -1 | cut -d' ' -f1)
  expected_delegator_stake=$((initial_delegator_stake + delegation_amount))
  echo "Expected delegator stake: ${expected_delegator_stake}"
  echo "Final delegator stake: ${final_delegator_stake}"

  # Verify the stakes match expectations.
  [[ "${final_total_stake}" -eq "${expected_total_stake}" ]]
  [[ "${final_delegator_stake}" -eq "${expected_delegator_stake}" ]]

  # Verify L2 voting power matches the updated L1 stake.
  VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.voting_power"'

  expected_voting_power=$(cast to-unit "${final_total_stake}" ether | cut -d'.' -f1)
  echo "Monitoring L2 voting power sync for validator ${VALIDATOR_ID}..."
  assert_command_eventually_equal "${VALIDATOR_POWER_CMD}" "${expected_voting_power}" 180

  echo "Delegation test completed successfully!"
}

# bats file_tags=pos,validator,undelegate
@test "undelegate MATIC/POL from a validator" {
  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  # Use same foundry test address as delegator (consistent with delegation test).
  DELEGATOR_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  DELEGATOR_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  echo "DELEGATOR_PRIVATE_KEY=${DELEGATOR_PRIVATE_KEY}"
  echo "DELEGATOR_ADDRESS=${DELEGATOR_ADDRESS}"

  echo "L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS}"

  # Get validator's ValidatorShare contract address.
  validator_share_address=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "getValidatorContractAddress(uint)(address)" "${VALIDATOR_ID}")
  echo "validator_share_address=${validator_share_address}"

  # Check current delegator stake.
  current_delegator_stake_data=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${DELEGATOR_ADDRESS}")
  current_delegator_stake=$(echo "${current_delegator_stake_data}" | head -1 | cut -d' ' -f1)
  echo "Current delegator stake: ${current_delegator_stake}"

  # Skip test if delegator has no stake.
  if [[ "${current_delegator_stake}" == "0" ]]; then
    echo "Foundry address has no stake to undelegate, skipping test"
    echo "Run the delegation test first to create stake to undelegate"
    skip "No stake to undelegate"
  fi

  # Check current validator total stake.
  initial_total_stake=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${VALIDATOR_ID}" | cut -d' ' -f1)
  echo "Initial total validator stake: ${initial_total_stake}"

  # Undelegate the current stake.
  undelegation_amount=$(cast to-unit 1ether wei)
  echo "Undelegation amount: ${undelegation_amount}"

  # Get current unbond nonce for the delegator.
  current_unbond_nonce=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "unbondNonces(address)(uint)" "${DELEGATOR_ADDRESS}")
  expected_unbond_nonce=$((current_unbond_nonce + 1))
  echo "Expected unbond nonce: ${expected_unbond_nonce}"

  echo "Initiating undelegation of ${undelegation_amount} wei POL from validator ${VALIDATOR_ID}..."
  max_shares_to_burn=$(cast --max-uint)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${DELEGATOR_PRIVATE_KEY}" \
    "${validator_share_address}" "sellVoucher_newPOL(uint,uint)" "${undelegation_amount}" "${max_shares_to_burn}"

  echo "Verifying undelegation initiation was successful..."

  # Check that validator's total stake decreased.
  expected_total_stake=$((initial_total_stake - undelegation_amount))
  new_total_stake=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${VALIDATOR_ID}" | cut -d' ' -f1)
  echo "Expected total stake: ${expected_total_stake}"
  echo "New total stake: ${new_total_stake}"

  # Check that delegator's active stake decreased.
  new_delegator_stake_data=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${DELEGATOR_ADDRESS}")
  new_delegator_stake=$(echo "${new_delegator_stake_data}" | head -1 | cut -d' ' -f1)
  expected_delegator_stake=$((current_delegator_stake - undelegation_amount))
  echo "Expected delegator_stake: ${expected_delegator_stake}"
  echo "New delegator stake: ${new_delegator_stake}"

  # Verify the stakes match expectations.
  [[ "${new_total_stake}" -eq "${expected_total_stake}" ]]
  [[ "${new_delegator_stake}" -eq "${expected_delegator_stake}" ]]

  # Check that unbond nonce was incremented.
  final_unbond_nonce=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "unbondNonces(address)(uint)" "${DELEGATOR_ADDRESS}")
  echo "Final unbond nonce: ${final_unbond_nonce}"
  [[ "${final_unbond_nonce}" -eq "${expected_unbond_nonce}" ]]

  # Verify L2 voting power matches the updated L1 stake.
  VALIDATOR_POWER_CMD='curl --silent "${L2_CL_API_URL}/stake/validator/${VALIDATOR_ID}" | jq --raw-output ".validator.voting_power"'

  expected_voting_power=$(cast to-unit "${new_total_stake}" ether | cut -d'.' -f1)
  echo "Monitoring L2 voting power sync for validator ${VALIDATOR_ID}..."
  assert_command_eventually_equal "${VALIDATOR_POWER_CMD}" "${expected_voting_power}" 180

  echo "Undelegation test completed successfully!"
}

# bats file_tags=pos,validator
@test "remove validator" {
  # First validator.
  VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  echo "VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}"

  VALIDATOR_ID=${VALIDATOR_ID:-"1"}
  echo "VALIDATOR_ID=${VALIDATOR_ID}"

  VALIDATOR_COUNT_CMD='curl --silent "${L2_CL_API_URL}/stake/validators-set" | jq --raw-output ".validator_set.validators | length"'

  initial_validator_count=$(eval "${VALIDATOR_COUNT_CMD}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Removing the validator from the validator set..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${VALIDATOR_PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "unstakePOL(uint)" "${VALIDATOR_ID}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${VALIDATOR_COUNT_CMD}" $((initial_validator_count - 1)) 180
}
