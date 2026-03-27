#!/usr/bin/env bats
# bats file_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Amount to bridge in each test.
  bridge_amount=$(cast to-unit 1ether wei)
  echo "bridge_amount=${bridge_amount}"

  # Define state sync count commands.
  heimdall_state_sync_count_cmd='curl "${L2_CL_API_URL}/clerk/event-records/count" | jq -r ".count"'
  bor_state_sync_count_cmd='cast call --gas-limit 15000000 --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'

  # Define timeout and interval for eventually commands.
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
  echo "timeout_seconds=${timeout_seconds}"
  echo "interval_seconds=${interval_seconds}"
}

function wait_for_heimdall_state_sync() {
  state_sync_count="$1"
  if [[ -z "${state_sync_count}" ]]; then
    echo "Error: state_sync_count is not set."
    exit 1
  fi
  if [[ -z "${heimdall_state_sync_count_cmd}" ]]; then
    echo "Error: heimdall_state_sync_count_cmd is not set."
    exit 1
  fi

  echo "Monitoring state syncs on Heimdall..."
  assert_command_eventually_greater_or_equal "${heimdall_state_sync_count_cmd}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

function wait_for_bor_state_sync() {
  state_sync_count="$1"
  if [[ -z "${state_sync_count}" ]]; then
    echo "Error: state_sync_count is not set."
    exit 1
  fi
  if [[ -z "${bor_state_sync_count_cmd}" ]]; then
    echo "Error: bor_state_sync_count_cmd is not set."
    exit 1
  fi

  echo "Monitoring state syncs on Bor..."
  assert_command_eventually_greater_or_equal "${bor_state_sync_count_cmd}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

function generate_exit_payload() {
  local tx_hash="$1"
  local log_index="${2:-0}"
  local deadline=$((SECONDS + timeout_seconds))
  local payload=""
  while [[ $SECONDS -lt $deadline ]]; do
    echo "Trying to generate exit payload for tx ${tx_hash} (log-index=${log_index})..." >&2
    if payload=$(polycli pos exit-proof \
      --l1-rpc-url "${L1_RPC_URL}" \
      --l2-rpc-url "${L2_RPC_URL}" \
      --root-chain-address "${L1_ROOT_CHAIN_PROXY_ADDRESS}" \
      --tx-hash "${tx_hash}" \
      --log-index "${log_index}" 2>/dev/null); then
      echo "${payload}"
      return 0
    fi
    echo "Checkpoint not yet indexed, retrying in ${interval_seconds}s..." >&2
    sleep "${interval_seconds}"
  done
  echo "Error: failed to generate exit payload for tx ${tx_hash} within ${timeout_seconds} seconds." >&2
  return 1
}

##############################################################################
# POL / MATIC <-> Native L2
##############################################################################

# bats test_tags=bridge,transaction-pol
@test "bridge POL from L1 to L2 and confirm native tokens balance increased on L2" {
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
@test "bridge MATIC from L1 to L2 and confirm native tokens balance increased on L2" {
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
@test "withdraw native tokens from L2 and confirm POL balance increased on L1" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_pol_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")
  checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'
  initial_checkpoint_id=$(eval "${checkpoint_count_cmd}")
  # Default to 0 if no checkpoint has been produced yet (fresh enclave).
  [[ "${initial_checkpoint_id}" == "null" ]] && initial_checkpoint_id=0

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
  assert_command_eventually_greater_or_equal "${checkpoint_count_cmd}" $((initial_checkpoint_id + 1)) "${timeout_seconds}" "${interval_seconds}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  # The native token (0x1010) emits LogTransfer at log index 0 and Withdraw at log index 1, so we pass --log-index 1.
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_exit_payload "${withdraw_tx_hash}" 1)

  # Start the exit on L1 via the ERC20Predicate contract.
  # Note: startExitWithBurntTokens is on ERC20Predicate, not on WithdrawManagerProxy.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-limit 500000 \
    "${L1_ERC20_PREDICATE_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1 and verify the POL balance increased.
  # Exits are queued under MATIC (the rootToken in the Withdraw event topic[1]).
  # WithdrawManager converts MATIC exits to POL when releasing funds.
  # processExits is retried in a loop because it may return without processing if the
  # exit window (HALF_EXIT_PERIOD=1s) has not elapsed yet at the time of the first call.
  echo "Processing the exit on L1 and verifying POL balance increased..."
  target_l1_pol_balance="$(echo "${initial_l1_pol_balance} + ${withdraw_amount}" | bc)"
  deadline=$((SECONDS + timeout_seconds))
  while [[ $SECONDS -lt $deadline ]]; do
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
      "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "processExits(address)" "${L1_MATIC_TOKEN_ADDRESS}" >/dev/null 2>&1 || true
    balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] L1 POL balance: ${balance} (target: ${target_l1_pol_balance})"
    if [ "$(echo "${balance} >= ${target_l1_pol_balance}" | bc)" -eq 1 ]; then
      break
    fi
    sleep "${interval_seconds}"
  done
  if [ "$(echo "${balance} >= ${target_l1_pol_balance}" | bc)" -ne 1 ]; then
    echo "Timeout: L1 POL balance did not reach target within ${timeout_seconds} seconds."
    exit 1
  fi
}

##############################################################################
# ETH (Native L1) / MaticWeth
##############################################################################

# bats test_tags=bridge,transaction-eth
@test "bridge ETH from L1 to L2 and confirm MaticWeth balance increased on L2" {
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
@test "withdraw MaticWeth from L2 and confirm ETH balance increased on L1" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_WETH_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'
  initial_checkpoint_id=$(eval "${checkpoint_count_cmd}")
  # Default to 0 if no checkpoint has been produced yet (fresh enclave).
  [[ "${initial_checkpoint_id}" == "null" ]] && initial_checkpoint_id=0

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
  assert_command_eventually_greater_or_equal "${checkpoint_count_cmd}" $((initial_checkpoint_id + 1)) "${timeout_seconds}" "${interval_seconds}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_exit_payload "${withdraw_tx_hash}")

  # Start the exit on L1 with the generated payload.
  # MaticWeth is a mintable token on L2, so it uses startExitForMintableBurntTokens.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "startExitForMintableBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  echo "Processing the exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "processExits(address)" "${L1_WETH_TOKEN_ADDRESS}"

  # Verify L1 ETH balance increased by the withdrawn amount (gas costs excluded).
  echo "Verifying L1 ETH balance increased..."
  assert_ether_balance_eventually_greater_or_equal "${address}" "$(echo "${initial_l1_balance} + ${withdraw_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC20
##############################################################################

# bats test_tags=bridge,transaction-erc20
@test "bridge ERC20 tokens from L1 to L2 and confirm ERC20 balance increased on L2" {
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
@test "withdraw ERC20 tokens from L2 to L1 and confirm ERC20 balance increased on L1" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'
  initial_checkpoint_id=$(eval "${checkpoint_count_cmd}")
  # Default to 0 if no checkpoint has been produced yet (fresh enclave).
  [[ "${initial_checkpoint_id}" == "null" ]] && initial_checkpoint_id=0

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
  assert_command_eventually_greater_or_equal "${checkpoint_count_cmd}" $((initial_checkpoint_id + 1)) "${timeout_seconds}" "${interval_seconds}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_exit_payload "${withdraw_tx_hash}")

  # Start the exit on L1 with the generated payload.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  echo "Processing the exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "processExits(address)" "${L1_ERC20_TOKEN_ADDRESS}"

  # Verify L1 ERC20 balance increased by the withdrawn amount.
  echo "Verifying L1 ERC20 balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l1_balance} + ${withdraw_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC721
##############################################################################

# bats test_tags=bridge,transaction-erc721
@test "bridge ERC721 token from L1 to L2 and confirm ERC721 balance increased on L2" {
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
@test "withdraw ERC721 token from L2 to L1 and confirm ERC721 balance increased on L1" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get a token ID owned by the address on L2.
  token_id=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "tokenOfOwnerByIndex(address,uint256)(uint256)" "${address}" 0 | jq --raw-output '.[0]')
  echo "Withdrawing ERC721 token ID: ${token_id}"

  # Get initial balances and latest checkpoint ID.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'
  initial_checkpoint_id=$(eval "${checkpoint_count_cmd}")
  # Default to 0 if no checkpoint has been produced yet (fresh enclave).
  [[ "${initial_checkpoint_id}" == "null" ]] && initial_checkpoint_id=0

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
  assert_command_eventually_greater_or_equal "${checkpoint_count_cmd}" $((initial_checkpoint_id + 1)) "${timeout_seconds}" "${interval_seconds}"

  # Generate the exit payload for the burn transaction.
  # It includes the burn tx receipt, a Merkle proof of that receipt in the block's receipts trie, and a checkpoint proof.
  # Retried in a loop because the checkpoint may not yet be indexed by polycli even after being confirmed on L1.
  echo "Generating the exit payload for the burn transaction..."
  payload=$(generate_exit_payload "${withdraw_tx_hash}")

  # Start the exit on L1 with the generated payload.
  echo "Starting the exit on L1 with the generated payload..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "startExitWithBurntTokens(bytes)" "${payload}"

  # Process the exit on L1.
  echo "Processing the exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}" "processExits(address)" "${L1_ERC721_TOKEN_ADDRESS}"

  # Verify L1 ERC721 balance increased.
  echo "Verifying L1 ERC721 balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance + 1)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}
