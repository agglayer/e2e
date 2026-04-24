#!/usr/bin/env bats
# bats file_tags=pos
# shellcheck disable=SC2154  # heimdall_state_sync_count_cmd/bor_state_sync_count_cmd are defined by pos-bridge.bash

# Plasma bridge tests — see ./README.md for how plasma relates to pos bridge.

setup() {
  load "../../../core/helpers/pos-setup.bash"
  load "../../../core/helpers/scripts/eventually.bash"
  load "../../../core/helpers/scripts/pos-bridge.bash"
  pos_setup

  bridge_amount=$(cast to-unit 1ether wei)
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
}

# process_plasma_exit queues → waits for the exit window → calls processExits once.
# Plasma-specific (no equivalent in pos bridge).
#
# Instead of a blind retry loop, reads exitableAt from the on-chain priority queue
# (WithdrawManager.exitsQueues(token).getMin()) and sleeps precisely until the exit
# window opens (HALF_EXIT_PERIOD = 1s on devnet, ~7 days on mainnet), then calls
# processExits with an explicit gas limit.
process_plasma_exit() {
  local token="$1"

  local queue
  queue=$(cast call --rpc-url "${L1_RPC_URL}" "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" \
    "exitsQueues(address)(address)" "${token}")
  echo "Exit queue for ${token}: ${queue}"

  local exitable_at
  exitable_at=$(cast call --rpc-url "${L1_RPC_URL}" "${queue}" "getMin()(uint256,uint256)" \
    | awk 'NR==1{print $1}')
  echo "exitableAt: ${exitable_at}"

  local current_ts
  current_ts=$(cast block --rpc-url "${L1_RPC_URL}" --json | jq -r '.timestamp' | xargs printf "%d\n")
  local wait_secs=$(( exitable_at - current_ts + 2 ))
  if [[ $wait_secs -gt 0 ]]; then
    echo "Exit window opens in ${wait_secs}s (now=${current_ts}, exitableAt=${exitable_at}), sleeping..."
    sleep "$wait_secs"
  fi

  # processExits must use --gas-limit: without it cast send auto-estimates gas at the time
  # of the eth_estimateGas call (which may see a short early-return path when exitableAt has
  # not elapsed yet), producing a gas estimate too low for the actual ~125K execution.
  echo "Calling processExits(${token})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "processExits(address)" "${token}"
}

##############################################################################
# POL / MATIC <-> Native L2
##############################################################################

# bats test_tags=bridge,transaction-pol
@test "bridge POL from L1 to L2 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")

  echo "Initial balances:"
  echo "- L1 POL balance: ${initial_l1_balance}"
  echo "- L2 native tokens balance: ${initial_l2_balance} wei"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge some POL tokens from L1 to L2 to trigger a state sync.
  # The DepositManager remaps POL to MATIC internally before the state sync,
  # so the L2 native token balance increases identically to bridging MATIC.
  echo "Approving the DepositManager contract to spend POL tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_POL_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing POL tokens to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_POL_TOKEN_ADDRESS}" "${bridge_amount}"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  echo "Monitoring POL balance on L1..."
  assert_token_balance_eventually_lower_or_equal "${L1_POL_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l1_balance} - ${bridge_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring native tokens balance on L2..."
  assert_ether_balance_eventually_greater_or_equal "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=bridge,transaction-matic
@test "bridge MATIC from L1 to L2 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")

  echo "Initial balances:"
  echo "- L1 MATIC balance: ${initial_l1_balance}"
  echo "- L2 native tokens balance: ${initial_l2_balance} wei"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge some MATIC tokens from L1 to L2 to trigger a state sync.
  # 1 MATIC token = 1000000000000000000 wei.
  echo "Approving the DepositManager contract to spend MATIC tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing MATIC tokens to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_MATIC_TOKEN_ADDRESS}" "${bridge_amount}"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  echo "Monitoring MATIC balance on L1..."
  assert_token_balance_eventually_lower_or_equal "${L1_MATIC_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l1_balance} - ${bridge_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring native tokens balance on L2..."
  assert_ether_balance_eventually_greater_or_equal "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-pol
@test "withdraw native tokens from L2 to L1 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")
  initial_checkpoint_id=$(latest_checkpoint_id)

  echo "Initial balances and state:"
  echo "- L1 POL balance: ${initial_l1_pol_balance}"
  echo "- L2 native balance: ${initial_l2_balance} wei"
  echo "- Latest checkpoint ID: ${initial_checkpoint_id}"

  # Burn native tokens on L2 to initiate the Plasma exit.
  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} wei on L2..."
  withdraw_receipt=$(cast send \
    --rpc-url "${L2_RPC_URL}" \
    --private-key "${PRIVATE_KEY}" \
    --value "${withdraw_amount}" \
    --gas-price 30gwei \
    --priority-gas-price 30gwei \
    --gas-limit 200000 \
    --json \
    "0x0000000000000000000000000000000000001010" \
    "withdraw(uint256)" "${withdraw_amount}")
  withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq --raw-output ".transactionHash")
  withdraw_block_hex=$(echo "${withdraw_receipt}" | jq --raw-output ".blockNumber")
  withdraw_block=$(printf "%d" "${withdraw_block_hex}")
  echo "Withdraw tx: ${withdraw_tx_hash} (block ${withdraw_block})"

  # Verify L2 native balance decreased.
  echo "Verifying L2 native balance decreased..."
  assert_ether_balance_eventually_lower_or_equal "${address}" "$(echo "${initial_l2_balance} - ${withdraw_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  # Wait for a new checkpoint on L1 that covers the withdrawal block.
  # This confirms validators have attested to the burn, which is a prerequisite for building a valid exit Merkle proof.
  echo "Waiting for a new checkpoint to cover L2 block ${withdraw_block}..."
  wait_for_new_checkpoint "${initial_checkpoint_id}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  # The native token (0x1010) emits LogTransfer at log index 0 and Withdraw at log index 1, so we pass --log-index 1.
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_pos_exit_payload "${withdraw_tx_hash}" 1 $((2 * timeout_seconds)))

  # Start the exit on L1 via the ERC20Predicate contract.
  # Note: startExitWithBurntTokens is on ERC20Predicate, not on WithdrawManagerProxy.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-limit 500000 \
    "${L1_ERC20_PREDICATE_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  # Exits are queued under MATIC (the rootToken in the Withdraw event topic[1]).
  # WithdrawManager converts MATIC exits to POL when releasing funds.
  echo "Processing the exit on L1..."
  process_plasma_exit "${L1_MATIC_TOKEN_ADDRESS}"

  # Verify L1 POL balance increased by the withdrawn amount.
  echo "Verifying L1 POL balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_POL_TOKEN_ADDRESS}" "${address}" \
    "$(echo "${initial_l1_pol_balance} + ${withdraw_amount}" | bc)" \
    "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ETH (Native L1) / MaticWeth
##############################################################################

# bats test_tags=bridge,transaction-eth
@test "bridge ETH from L1 to L2 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_WETH_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial balances:"
  echo "- L1 ETH balance: ${initial_l1_balance}"
  echo "- L2 MaticWeth balance: ${initial_l2_balance}"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge some ETH from L1 to L2 to trigger a state sync.
  # The DepositManager wraps ETH into MaticWeth on L1, so the L2
  # MaticWeth balance increases rather than the native gas balance.
  echo "Depositing ETH to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --value "${bridge_amount}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositEther()"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  # L1 ETH decreases by at least bridge_amount (gas costs make it decrease further).
  echo "Monitoring ETH balance on L1..."
  assert_ether_balance_eventually_lower_or_equal "${address}" "$(echo "${initial_l1_balance} - ${bridge_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring MaticWeth balance on L2..."
  assert_token_balance_eventually_greater_or_equal "${L2_WETH_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-eth
@test "withdraw MaticWeth from L2 to L1 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_WETH_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_checkpoint_id=$(latest_checkpoint_id)

  echo "Initial balances and state:"
  echo "- L1 ETH balance: ${initial_l1_balance}"
  echo "- L2 MaticWeth balance: ${initial_l2_balance}"
  echo "- Latest checkpoint ID: ${initial_checkpoint_id}"

  # Burn MaticWeth on L2 to initiate the Plasma exit.
  # The WithdrawManager will release the corresponding ETH locked on L1.
  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} MaticWeth on L2..."
  withdraw_receipt=$(cast send \
    --rpc-url "${L2_RPC_URL}" \
    --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei \
    --priority-gas-price 30gwei \
    --gas-limit 200000 \
    --json \
    "${L2_WETH_TOKEN_ADDRESS}" \
    "withdraw(uint256)" "${withdraw_amount}")
  withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq --raw-output ".transactionHash")
  withdraw_block_hex=$(echo "${withdraw_receipt}" | jq --raw-output ".blockNumber")
  withdraw_block=$(printf "%d" "${withdraw_block_hex}")
  echo "Withdraw tx: ${withdraw_tx_hash} (block ${withdraw_block})"

  # Verify L2 MaticWeth balance decreased.
  echo "Verifying L2 MaticWeth balance decreased..."
  assert_token_balance_eventually_lower_or_equal "${L2_WETH_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l2_balance} - ${withdraw_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  # Wait for a new checkpoint on L1 that covers the withdrawal block.
  # This confirms validators have attested to the burn, which is a prerequisite for building a valid exit Merkle proof.
  echo "Waiting for a new checkpoint to cover L2 block ${withdraw_block}..."
  wait_for_new_checkpoint "${initial_checkpoint_id}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  # The MaticWeth contract emits: log 0 = Transfer, log 1 = Withdraw(rootToken=WETH, from, ...).
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_pos_exit_payload "${withdraw_tx_hash}" 1 $((2 * timeout_seconds)))

  # Start the exit on L1 with the generated payload.
  # ERC20Predicate handles WETH exits: it reads rootToken=WETH from the Withdraw event and queues
  # the exit. processExits(WETH) then calls DepositManager which unwraps WETH and sends ETH to user.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ERC20_PREDICATE_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  # WETH is queued under L1_WETH_TOKEN_ADDRESS; processExits unwraps WETH to ETH internally.
  echo "Processing the exit on L1..."
  process_plasma_exit "${L1_WETH_TOKEN_ADDRESS}"

  # Verify L1 ETH balance increased by the withdrawn amount minus gas.
  # ETH is the gas token: startExitWithBurntTokens and processExits both consume ETH as gas.
  # We allow up to 0.01 ETH (10^16 wei) to cover gas across both transactions.
  echo "Verifying L1 ETH balance increased..."
  local gas_allowance=10000000000000000
  assert_ether_balance_eventually_greater_or_equal "${address}" \
    "$(echo "${initial_l1_balance} + ${withdraw_amount} - ${gas_allowance}" | bc)" \
    "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC20
##############################################################################

# bats test_tags=bridge,transaction-erc20
@test "bridge ERC20 from L1 to L2 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial ERC20 balances:"
  echo "- L1: ${initial_l1_balance}"
  echo "- L2: ${initial_l2_balance}"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge some ERC20 tokens from L1 to L2.
  # 1 ERC20 token = 1000000000000000000 wei.
  echo "Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC20_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing ERC20 tokens..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_ERC20_TOKEN_ADDRESS}" "${bridge_amount}"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  echo "Monitoring ERC20 balance on L1..."
  assert_token_balance_eventually_lower_or_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l1_balance} - ${bridge_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring ERC20 balance on L2..."
  assert_token_balance_eventually_greater_or_equal "${L2_ERC20_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-erc20
@test "withdraw ERC20 from L2 to L1 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_checkpoint_id=$(latest_checkpoint_id)

  echo "Initial balances and state:"
  echo "- L1 ERC20 balance: ${initial_l1_balance}"
  echo "- L2 ERC20 balance: ${initial_l2_balance}"
  echo "- Latest checkpoint ID: ${initial_checkpoint_id}"

  # Burn ERC20 tokens on L2 to initiate the Plasma exit.
  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} ERC20 tokens on L2..."
  withdraw_receipt=$(cast send \
    --rpc-url "${L2_RPC_URL}" \
    --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei \
    --priority-gas-price 30gwei \
    --gas-limit 200000 \
    --json \
    "${L2_ERC20_TOKEN_ADDRESS}" \
    "withdraw(uint256)" "${withdraw_amount}")
  withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq --raw-output ".transactionHash")
  withdraw_block_hex=$(echo "${withdraw_receipt}" | jq --raw-output ".blockNumber")
  withdraw_block=$(printf "%d" "${withdraw_block_hex}")
  echo "Withdraw tx: ${withdraw_tx_hash} (block ${withdraw_block})"

  # Verify L2 ERC20 balance decreased.
  echo "Verifying L2 ERC20 balance decreased..."
  assert_token_balance_eventually_lower_or_equal "${L2_ERC20_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l2_balance} - ${withdraw_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  # Wait for a new checkpoint on L1 that covers the withdrawal block.
  # This confirms validators have attested to the burn, which is a prerequisite for building a valid exit Merkle proof.
  echo "Waiting for a new checkpoint to cover L2 block ${withdraw_block}..."
  wait_for_new_checkpoint "${initial_checkpoint_id}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  # The ERC20 contract emits: log 0 = Transfer, log 1 = Withdraw(rootToken=ERC20, from, ...).
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_pos_exit_payload "${withdraw_tx_hash}" 1 $((2 * timeout_seconds)))

  # Start the exit on L1 with the generated payload.
  # ERC20Predicate handles ERC20 exits: reads rootToken from the Withdraw event and queues the exit.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ERC20_PREDICATE_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  echo "Processing the exit on L1..."
  process_plasma_exit "${L1_ERC20_TOKEN_ADDRESS}"

  # Verify L1 ERC20 balance increased by the withdrawn amount.
  echo "Verifying L1 ERC20 balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" \
    "$(echo "${initial_l1_balance} + ${withdraw_amount}" | bc)" \
    "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC721
##############################################################################

# bats test_tags=bridge,transaction-erc721
@test "bridge ERC721 from L1 to L2 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Mint an ERC721 token.
  total_supply=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "totalSupply()(uint)" | jq --raw-output '.[0]')
  token_id=$((total_supply + 1))

  echo "Minting the ERC721 token (id: ${token_id})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "mint(uint)" "${token_id}"

  # Get the initial values.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial ERC721 balances:"
  echo "- L1: ${initial_l1_balance}"
  echo "- L2: ${initial_l2_balance}"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge the ERC721 token from L1 to L2.
  echo "Approving the DepositManager contract to spend ERC721 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${token_id}"

  echo "Depositing ERC721 tokens..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC721(address,uint)" "${L1_ERC721_TOKEN_ADDRESS}" "${token_id}"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  echo "Monitoring ERC721 balance on L1..."
  assert_token_balance_eventually_lower_or_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - 1)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring ERC721 balance on L2..."
  assert_token_balance_eventually_greater_or_equal "${L2_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance + 1)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-erc721
@test "withdraw ERC721 from L2 to L1 via plasma bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get a token ID owned by the address on L2.
  token_id=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "tokenOfOwnerByIndex(address,uint256)(uint256)" "${address}" 0 | jq --raw-output '.[0]')
  echo "Withdrawing ERC721 token ID: ${token_id}"

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_checkpoint_id=$(latest_checkpoint_id)

  echo "Initial balances and state:"
  echo "- L1 ERC721 balance: ${initial_l1_balance}"
  echo "- L2 ERC721 balance: ${initial_l2_balance}"
  echo "- Latest checkpoint ID: ${initial_checkpoint_id}"

  # Burn the ERC721 token on L2 to initiate the Plasma exit.
  echo "Burning ERC721 token (id: ${token_id}) on L2..."
  withdraw_receipt=$(cast send \
    --rpc-url "${L2_RPC_URL}" \
    --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei \
    --priority-gas-price 30gwei \
    --gas-limit 200000 \
    --json \
    "${L2_ERC721_TOKEN_ADDRESS}" \
    "withdraw(uint256)" "${token_id}")
  withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq --raw-output ".transactionHash")
  withdraw_block_hex=$(echo "${withdraw_receipt}" | jq --raw-output ".blockNumber")
  withdraw_block=$(printf "%d" "${withdraw_block_hex}")
  echo "Withdraw tx: ${withdraw_tx_hash} (block ${withdraw_block})"

  # Verify L2 ERC721 balance decreased.
  echo "Verifying L2 ERC721 balance decreased..."
  assert_token_balance_eventually_lower_or_equal "${L2_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance - 1)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  # Wait for a new checkpoint on L1 that covers the withdrawal block.
  # This confirms validators have attested to the burn, which is a prerequisite for building a valid exit Merkle proof.
  echo "Waiting for a new checkpoint to cover L2 block ${withdraw_block}..."
  wait_for_new_checkpoint "${initial_checkpoint_id}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  # The ERC721 contract emits: log 0 = Transfer, log 1 = Withdraw(rootToken=ERC721, tokenId).
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_pos_exit_payload "${withdraw_tx_hash}" 1 $((2 * timeout_seconds)))

  # Start the exit on L1 with the generated payload.
  # ERC721Predicate handles ERC721 exits: reads rootToken from the Withdraw event and queues the exit.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ERC721_PREDICATE_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  echo "Processing the exit on L1..."
  process_plasma_exit "${L1_ERC721_TOKEN_ADDRESS}"

  # Verify L1 ERC721 balance increased.
  echo "Verifying L1 ERC721 balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" \
    $((initial_l1_balance + 1)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}
