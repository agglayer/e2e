#!/usr/bin/env bats
# bats file_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Define state sync count commands.
  heimdall_state_sync_count_cmd='curl "${L2_CL_API_URL}/clerk/event-records/count" | jq -r ".count"'
  bor_state_sync_count_cmd='cast call --gas-limit 15000000 --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'

  # Define timeout and interval for eventually commands.
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}

  # Amount to bridge in each test.
  bridge_amount=$(cast to-unit 1ether wei)
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

# bats test_tags=bridge,transaction-eth
@test "bridge native token from L1 to L2 and confirm WETH balance increased on L2" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_WETH_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial balances:"
  echo "- L1 ETH balance: ${initial_l1_balance}"
  echo "- L2 WETH balance: ${initial_l2_balance}"

  heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")

  # Bridge some ETH from L1 to L2 to trigger a state sync.
  # The DepositManager wraps ETH into WETH (MaticWeth) on L1, so the L2
  # WETH balance increases rather than the native gas balance.
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

  echo "Monitoring WETH balance on L2..."
  assert_token_balance_eventually_greater_or_equal "${L2_WETH_TOKEN_ADDRESS}" "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-pol
@test "withdraw native tokens from L2 and confirm native balance decreased on L2 and checkpoint was submitted" {
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
# @test "withdraw ERC20 tokens from L2 to L1 and confirm ERC20 balance increased on L1" {
#   echo TODO
# }

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
# @test "withdraw ERC721 token from L2 to L1 and confirm ERC721 balance increased on L1" {
#   echo TODO
# }
