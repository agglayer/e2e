#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Validator under test (genesis validator 1).
  validator_private_key=${VALIDATOR_PRIVATE_KEY:-"0x2a4ae8c4c250917781d38d95dafbb0abe87ae2c9aea02ed7c7524685358e49c2"}
  validator_address=$(cast wallet address --private-key "${validator_private_key}")
  validator_id=${VALIDATOR_ID:-"1"}
  echo "validator_private_key=${validator_private_key}"
  echo "validator_address=${validator_address}"
  echo "validator_id=${validator_id}"

  # Delegator account (default foundry test address).
  delegator_private_key=${DELEGATOR_PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}
  delegator_address=$(cast wallet address --private-key "${delegator_private_key}")
  echo "delegator_private_key=${delegator_private_key}"
  echo "delegator_address=${delegator_address}"

  # Common polling commands.
  validator_count_cmd='curl -s "${L2_CL_API_URL}/stake/validators-set" | jq --raw-output ".validator_set.validators | length"'
  validator_power_cmd='curl -s "${L2_CL_API_URL}/stake/validator/${validator_id}" | jq --raw-output ".validator.voting_power"'
  validator_signer_cmd='curl -s "${L2_CL_API_URL}/stake/validator/${validator_id}" | jq --raw-output ".validator.signer"'
  top_up_fee_balance_cmd='curl -s "${L2_CL_API_URL}/cosmos/bank/v1beta1/balances/${validator_address}" | jq --raw-output ".balances[] | select(.denom == \"pol\") | .amount"'

  # Define timeout and interval for eventually commands.
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
}

function generate_new_keypair() {
  mnemonic=$(cast wallet new-mnemonic --json | jq --raw-output '.mnemonic')
  private_key=$(cast wallet derive-private-key "${mnemonic}" 0)
  address=$(cast wallet address "${private_key}")
  public_key=$(cast wallet public-key --raw-private-key "${private_key}")
  echo "${address} ${public_key} ${private_key}"
}

# bats test_tags=pos-validator
@test "add new validator" {
  initial_validator_count=$(eval "${validator_count_cmd}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Generating a new validator keypair..."
  read validator_address validator_public_key validator_private_key < <(generate_new_keypair)
  echo "Address: ${validator_address}"
  echo "Public key: ${validator_public_key}"

  echo "Funding the validator account with ETH..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value 1ether "${validator_address}"

  echo "Funding the validator account with POL tokens..."
  deposit_amount=$(cast to-unit 1ether wei)      # minimum deposit: 1000000000000000000 (1 ether)
  heimdall_fee_amount=$(cast to-unit 1ether wei) # minimum heimdall fee: 1000000000000000000 (1 ether)
  funding_amount=$((deposit_amount + heimdall_fee_amount))

  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_POL_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${funding_amount}"

  echo "Allowing the StakeManagerProxy contract to spend POL tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_POL_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${funding_amount}"

  echo "Adding new validator to the validator set..."
  accept_delegation=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "stakeForPOL(address,uint,uint,bool,bytes)" \
    "${validator_address}" "${deposit_amount}" "${heimdall_fee_amount}" "${accept_delegation}" "${validator_public_key}"

  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${validator_count_cmd}" $((initial_validator_count + 1)) "${timeout_seconds}"
}

# bats test_tags=pos-validator
@test "update validator stake" {
  initial_voting_power=$(eval "${validator_power_cmd}")
  echo "Initial voting power of the validator (${validator_id}): ${initial_voting_power}."

  echo "Funding the validator acount with POL tokens..."
  stake_update_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_POL_TOKEN_ADDRESS}" "transfer(address,uint)" "${validator_address}" "${stake_update_amount}"

  echo "Allowing the StakeManagerProxy contract to spend POL tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_POL_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${stake_update_amount}"

  echo "Updating the stake of the validator (${validator_id})..."
  stake_rewards=false
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "restakePOL(uint,uint,bool)" "${validator_id}" "${stake_update_amount}" "${stake_rewards}"

  echo "Monitoring the voting power of the validator..."
  voting_power_update=$(cast to-unit "${stake_update_amount}"wei ether)
  assert_command_eventually_equal "${validator_power_cmd}" $((initial_voting_power + voting_power_update)) "${timeout_seconds}"
}

# bats test_tags=pos-validator
@test "update validator top-up fee" {
  initial_top_up_balance=$(eval "${top_up_fee_balance_cmd}")
  echo "${validator_address} initial top-up balance: ${initial_top_up_balance}."

  echo "Allowing the StakeManagerProxy contract to spend POL tokens on our behalf..."
  top_up_amount=$(cast to-unit 1ether wei)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_POL_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${top_up_amount}"

  echo "Topping up the fee balance of the validator (${validator_address})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "topUpForFee(address,uint)" "${validator_address}" "${top_up_amount}"

  echo "Monitoring the top-up balance of the validator..."
  echo "Initial balance: ${initial_top_up_balance}"

  start_time=$(date +%s)
  end_time=$((start_time + timeout_seconds))

  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    current_balance=$(eval "${top_up_fee_balance_cmd}")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Current balance: ${current_balance}"

    if [[ $(echo "${current_balance} > ${initial_top_up_balance}" | bc) -eq 1 ]]; then
      echo "Balance check passed: ${current_balance} > ${initial_top_up_balance}"
      break
    fi

    sleep "${interval_seconds}"
  done
}

# bats test_tags=pos-validator
@test "update signer" {
  initial_signer=$(eval "${validator_signer_cmd}")
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
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "updateSigner(uint,bytes)" "${validator_id}" "${new_public_key}"

  echo "Monitoring signer change..."
  assert_command_eventually_equal "${validator_signer_cmd}" "0xd74c0d3dee45a0a9516fb66e31c01536e8756e2a" "${timeout_seconds}"
}

# bats test_tags=pos-validator,pos-delegate,transaction-pol
@test "delegate to a validator" {
  echo "L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS}"

  # Get validator's ValidatorShare contract address.
  validator_share_address=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "getValidatorContractAddress(uint)(address)" "${validator_id}")
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
  initial_total_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${validator_id}" | cut -d' ' -f1)" ether)
  echo "Initial total validator stake: ${initial_total_stake_eth} POL"

  # Check initial delegator stake in this validator.
  initial_delegator_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${delegator_address}" | head -1 | cut -d' ' -f1)" ether)
  echo "Initial delegator stake: ${initial_delegator_stake_eth} POL"

  echo "Transferring ETH from main address to foundry address for gas..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value 1ether "${delegator_address}"

  echo "Transferring POL tokens from main address to foundry address..."
  delegation_amount=$(cast to-unit 1ether wei)

  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_POL_TOKEN_ADDRESS}" "transfer(address,uint)" "${delegator_address}" "${delegation_amount}"

  echo "Verifying foundry address received the tokens..."
  delegator_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint256)" "${delegator_address}" | cut -d' ' -f1)
  delegator_eth_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${delegator_address}" --ether)
  echo "Foundry address POL balance: $(cast to-unit ${delegator_pol_balance} ether) POL"
  echo "Foundry address ETH balance: ${delegator_eth_balance} ETH"

  echo "Allowing the StakeManager to spend POL tokens on foundry address behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${delegator_private_key}" \
    "${L1_POL_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "${delegation_amount}"

  echo "Delegating ${delegation_amount} wei (1 POL) to validator ${validator_id}..."
  min_shares_to_mint=0
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${delegator_private_key}" \
    "${validator_share_address}" "buyVoucherPOL(uint,uint)" "${delegation_amount}" "${min_shares_to_mint}"

  echo "Verifying delegation was successful..."

  # Check that validator's total stake increased.
  final_total_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${validator_id}" | cut -d' ' -f1)" ether)
  echo "Final total stake: ${final_total_stake_eth} POL"
  [[ $(echo "${final_total_stake_eth} == ${initial_total_stake_eth} + 1" | bc) -eq 1 ]]

  # Check that delegator's stake in validator increased.
  final_delegator_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${delegator_address}" | head -1 | cut -d' ' -f1)" ether)
  echo "Final delegator stake: ${final_delegator_stake_eth} POL"
  [[ $(echo "${final_delegator_stake_eth} == ${initial_delegator_stake_eth} + 1" | bc) -eq 1 ]]

  # Verify L2 voting power matches the updated L1 stake.
  expected_voting_power=$(echo "${final_total_stake_eth}" | cut -d'.' -f1)
  echo "Monitoring L2 voting power sync for validator ${validator_id}..."
  assert_command_eventually_equal "${validator_power_cmd}" "${expected_voting_power}" "${timeout_seconds}"

  echo "Delegation test completed successfully!"
}

# bats test_tags=pos-validator,pos-undelegate,transaction-pol
@test "undelegate from a validator" {
  echo "L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS}"

  # Get validator's ValidatorShare contract address.
  validator_share_address=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "getValidatorContractAddress(uint)(address)" "${validator_id}")
  echo "validator_share_address=${validator_share_address}"

  # Check current delegator stake.
  current_delegator_stake_data=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${delegator_address}")
  current_delegator_stake_eth=$(cast to-unit "$(echo "${current_delegator_stake_data}" | head -1 | cut -d' ' -f1)" ether)
  echo "Current delegator stake: ${current_delegator_stake_eth} POL"

  # Skip test if delegator has no stake.
  if [[ $(echo "${current_delegator_stake_eth} == 0" | bc) -eq 1 ]]; then
    echo "Foundry address has no stake to undelegate, skipping test"
    echo "Run the delegation test first to create stake to undelegate"
    skip "No stake to undelegate"
  fi

  # Check current validator total stake.
  initial_total_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${validator_id}" | cut -d' ' -f1)" ether)
  echo "Initial total validator stake: ${initial_total_stake_eth} POL"

  # Undelegate the current stake.
  undelegation_amount=$(cast to-unit 1ether wei)
  echo "Undelegation amount: ${undelegation_amount}"

  # Get current unbond nonce for the delegator.
  current_unbond_nonce=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "unbondNonces(address)(uint)" "${delegator_address}")
  expected_unbond_nonce=$((current_unbond_nonce + 1))
  echo "Expected unbond nonce: ${expected_unbond_nonce}"

  echo "Initiating undelegation of ${undelegation_amount} wei POL from validator ${validator_id}..."
  max_shares_to_burn=$(cast --max-uint)
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${delegator_private_key}" \
    "${validator_share_address}" "sellVoucher_newPOL(uint,uint)" "${undelegation_amount}" "${max_shares_to_burn}"

  echo "Verifying undelegation initiation was successful..."

  # Check that validator's total stake decreased.
  new_total_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKING_INFO_ADDRESS}" "totalValidatorStake(uint)(uint)" "${validator_id}" | cut -d' ' -f1)" ether)
  echo "New total stake: ${new_total_stake_eth} POL"
  [[ $(echo "${new_total_stake_eth} == ${initial_total_stake_eth} - 1" | bc) -eq 1 ]]

  # Check that delegator's active stake decreased.
  new_delegator_stake_eth=$(cast to-unit "$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "getTotalStake(address)(uint,uint)" "${delegator_address}" | head -1 | cut -d' ' -f1)" ether)
  echo "New delegator stake: ${new_delegator_stake_eth} POL"
  [[ $(echo "${new_delegator_stake_eth} == ${current_delegator_stake_eth} - 1" | bc) -eq 1 ]]

  # Check that unbond nonce was incremented.
  final_unbond_nonce=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${validator_share_address}" "unbondNonces(address)(uint)" "${delegator_address}")
  echo "Final unbond nonce: ${final_unbond_nonce}"
  [[ "${final_unbond_nonce}" -eq "${expected_unbond_nonce}" ]]

  # Verify L2 voting power matches the updated L1 stake.
  expected_voting_power=$(echo "${new_total_stake_eth}" | cut -d'.' -f1)
  echo "Monitoring L2 voting power sync for validator ${validator_id}..."
  assert_command_eventually_equal "${validator_power_cmd}" "${expected_voting_power}" "${timeout_seconds}"

  echo "Undelegation test completed successfully!"
}

# bats test_tags=pos-validator,transaction-pol
@test "withdraw validator rewards" {
  initial_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json \
    "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint256)" "${validator_address}" | jq --raw-output '.[0]')
  claimable_reward=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "validatorReward(uint256)(uint256)" "${validator_id}" | cut -d' ' -f1)
  echo "Initial POL balance: ${initial_pol_balance}"
  echo "Claimable reward: ${claimable_reward}"

  echo "Withdrawing rewards for validator ${validator_id}..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "withdrawRewardsPOL(uint256)" "${validator_id}"

  final_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json \
    "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint256)" "${validator_address}" | jq --raw-output '.[0]')
  echo "Final POL balance: ${final_pol_balance}"

  # The balance must have increased by at least the claimable reward observed before withdrawal.
  # (It may be slightly higher since rewards accrue until the tx is mined.)
  [[ $(echo "${final_pol_balance} >= ${initial_pol_balance} + ${claimable_reward}" | bc) -eq 1 ]]
}

# bats test_tags=pos-validator
@test "remove validator" {
  initial_validator_count=$(eval "${validator_count_cmd}")
  echo "Initial validator count: ${initial_validator_count}"

  echo "Removing the validator from the validator set..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${validator_private_key}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" "unstakePOL(uint256)" "${validator_id}"

  # Verify the unstake was initiated on L1: deactivationEpoch must be greater than zero.
  # validators(uint256) returns (amount, reward, activationEpoch, deactivationEpoch, ...)
  # where deactivationEpoch is the 4th return value.
  deactivation_epoch=$(cast call --rpc-url "${L1_RPC_URL}" \
    "${L1_STAKE_MANAGER_PROXY_ADDRESS}" \
    "validators(uint256)(uint256,uint256,uint256,uint256,uint256,address,address,uint8)" \
    "${validator_id}" | sed -n '4p')
  echo "Validator ${validator_id} deactivationEpoch: ${deactivation_epoch}"
  [[ "${deactivation_epoch}" -gt "0" ]]

  # Wait for Heimdall to remove the validator at the epoch boundary.
  # 1 epoch ≈ 256 blocks (~256s at 1s/block), so a longer timeout than the default is needed;
  # set TIMEOUT_SECONDS >= 300 when running this test.
  echo "Monitoring the validator count on Heimdall..."
  assert_command_eventually_equal "${validator_count_cmd}" $((initial_validator_count - 1)) "${timeout_seconds}"
}
