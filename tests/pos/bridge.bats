#!/usr/bin/env bats
# bats file_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Define state sync count commands.
  HEIMDALL_STATE_SYNC_COUNT_CMD='curl "${L2_CL_API_URL}/clerk/event-records/count" | jq -r ".count"'
  BOR_STATE_SYNC_COUNT_CMD='cast call --gas-limit 15000000 --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'

  # Define timeout and interval for eventually commands.
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
}

function wait_for_heimdall_state_sync() {
  state_sync_count="$1"
  if [[ -z "${state_sync_count}" ]]; then
    echo "Error: state_sync_count is not set."
    exit 1
  fi
  if [[ -z "${HEIMDALL_STATE_SYNC_COUNT_CMD}" ]]; then
    echo "Error: HEIMDALL_STATE_SYNC_COUNT_CMD environment variable is not set."
    exit 1
  fi

  echo "Monitoring state syncs on Heimdall..."
  assert_command_eventually_greater_or_equal "${HEIMDALL_STATE_SYNC_COUNT_CMD}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

function wait_for_bor_state_sync() {
  state_sync_count="$1"
  if [[ -z "${state_sync_count}" ]]; then
    echo "Error: state_sync_count is not set."
    exit 1
  fi
  if [[ -z "${BOR_STATE_SYNC_COUNT_CMD}" ]]; then
    echo "Error: BOR_STATE_SYNC_COUNT_CMD environment variable is not set."
    exit 1
  fi

  echo "Monitoring state syncs on Bor..."
  assert_command_eventually_greater_or_equal "${BOR_STATE_SYNC_COUNT_CMD}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=bridge,transaction-pol
@test "bridge POL from L1 to L2 and confirm L2 native tokens balance increased" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")

  echo "Initial balances:"
  echo "- L1 POL balance: ${initial_l1_balance}"
  echo "- L2 native tokens balance: ${initial_l2_balance} wei"

  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

  # Bridge some POL tokens from L1 to L2 to trigger a state sync.
  # The DepositManager remaps POL to MATIC internally before the state sync,
  # so the L2 native token balance increases identically to bridging MATIC.
  bridge_amount=$(cast to-unit 1ether wei)

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
@test "bridge MATIC from L1 to L2 and confirm L2 native tokens balance increased" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")

  echo "Initial balances:"
  echo "- L1 MATIC balance: ${initial_l1_balance}"
  echo "- L2 native tokens balance: ${initial_l2_balance} wei"

  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

  # Bridge some MATIC tokens from L1 to L2 to trigger a state sync.
  # 1 MATIC token = 1000000000000000000 wei.
  bridge_amount=$(cast to-unit 1ether wei)

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
@test "withdraw native tokens from L2 and confirm L2 native balance decreased and checkpoint submitted" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial L2 native balance and latest checkpoint ID.
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")
  checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'
  initial_checkpoint_id=$(eval "${checkpoint_count_cmd}")

  echo "Initial balances and state:"
  echo "- L2 native balance: ${initial_l2_balance} wei"
  echo "- Latest checkpoint ID: ${initial_checkpoint_id}"

  # Burn native tokens on L2 to initiate the Plasma exit.
  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} wei on L2 (0x1010.withdraw)..."
  withdraw_receipt=$(cast send \
    --rpc-url "${L2_RPC_URL}" \
    --private-key "${PRIVATE_KEY}" \
    --value "${withdraw_amount}" \
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

  # TODO: Complete the Plasma exit on L1 to recover funds.
  # After the burn block is checkpointed, the remaining steps are:
  #   1. Build the exit payload: RLP-encoded receipt of the burn tx + Merkle
  #      proof of that receipt in the block's receipts trie + checkpoint proof.
  #   2. L1: WithdrawManagerProxy.startExitWithBurntTokens(bytes exitTx)
  #   3. L1: WithdrawManagerProxy.processExits(address token)
  #   4. Assert L1 POL balance increased by withdraw_amount.
  # Proof generation requires constructing the receipts MPT of the burn block,
  # which is not feasible in pure bash. A dedicated tool (e.g. matic.js or a
  # custom Go helper) is needed.
}

# bats test_tags=bridge,transaction-erc20
@test "bridge some ERC20 tokens from L1 to L2 and confirm L2 ERC20 balance increased" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial ERC20 balances:"
  echo "- L1: ${initial_l1_balance}"
  echo "- L2: ${initial_l2_balance}"

  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

  # Bridge some ERC20 tokens from L1 to L2.
  # 1 ERC20 token = 1000000000000000000 wei.
  bridge_amount=$(cast to-unit 1ether wei)

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
# @test "withdraw some ERC20 tokens from L2 to L1 and confirm L1 ERC20 balance increased" {
#   echo TODO
# }

# bats test_tags=bridge,transaction-erc721
@test "bridge an ERC721 token from L1 to L2 and confirm L2 ERC721 balance increased" {
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

  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

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
# @test "withdraw an ERC721 token from L2 to L1 and confirm L1 ERC721 balance increased" {
#   echo TODO
# }
