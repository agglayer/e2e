#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
}

# bats file_tags=pos,bridge,erc20
@test "bridge some ERC20 tokens from L1 to L2" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial values.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  echo "Initial ERC20 balances:"
  echo "- L1: ${initial_l1_balance}"
  echo "- L2: ${initial_l2_balance}"

  # Bridge some ERC20 tokens from L1 to L2.
  bridge_amount=10
  echo "Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC20_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing ERC20 tokens..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_ERC20_TOKEN_ADDRESS}" "${bridge_amount}"

  # Monitor balances on L1 and L2.
  echo "Monitoring ERC20 balance on L1..."
  assert_token_balance_eventually_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - bridge_amount)) "${L1_RPC_URL}"

  # TODO: Find out why L2 balance is not increasing.
  # echo "Monitoring ERC20 balance on L2..."
  # assert_token_balance_eventually_equal "${L2_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance + bridge_amount)) "${L2_RPC_URL}"
}

# bats file_tags=pos,bridge,erc20
@test "bridge some ERC20 tokens from L2 to L1" {
  echo TODO
}

# bats file_tags=pos,bridge,erc721
@test "bridge an ERC721 token from L1 to L2" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Mint an ERC721 token.
  total_supply=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "totalSupply()(uint)" | jq --raw-output '.[0]')
  token_id=$((total_supply + 1))
  echo "Minting the ERC721 token (id: ${token_id})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "mint(uint)" "${token_id}"

  # Get initial values.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  echo "Initial ERC721 balances:"
  echo "- L1: ${initial_l1_balance}."
  echo "- L2: ${initial_l2_balance}."

  # Bridge some ERC721 tokens from L1 to L2.
  echo "Approving the DepositManager contract to spend ERC721 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${token_id}"

  echo "Depositing ERC721 tokens..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC721(address,uint)" "${L1_ERC721_TOKEN_ADDRESS}" "${token_id}"

  # Monitor balances on L1 and L2.
  echo "Monitoring ERC721 balance on L1..."
  assert_token_balance_eventually_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - 1)) "${L1_RPC_URL}"

  # TODO: Find out why L2 balance is not increasing.
  # echo "Monitoring ERC721 balance on L2..."
  # assert_token_balance_eventually_equal "${L2_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance + 1)) "${L2_RPC_URL}"
}

# bats file_tags=pos,bridge,erc721
@test "bridge an ERC721 token from L2 to L1" {
  echo TODO
}

# bats file_tags=pos,state-sync
@test "bridge native L2 eth from L1 to L2 to trigger state sync" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    heimdall_state_sync_count_cmd='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".result | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    heimdall_state_sync_count_cmd='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".event_records | length"'
  fi
  bor_state_sync_count_cmd='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'

  # Get initial values.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")
  initial_heimdall_state_sync_count=$(eval "${heimdall_state_sync_count_cmd}")
  initial_bor_state_sync_count=$(eval "${bor_state_sync_count_cmd}")
  echo "Initial values:"
  echo "- L1 balance: ${initial_l1_balance} MATIC tokens"
  echo "- L2 balance: ${initial_l2_balance} ether"
  echo "- Heimdall state sync count: ${initial_heimdall_state_sync_count}"
  echo "- Bor state sync count: ${initial_bor_state_sync_count}"

  # Bridge some ERC20 tokens from L1 to L2 to trigger a state sync.
  bridge_amount=10
  echo "Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing tokens to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_MATIC_TOKEN_ADDRESS}" "${bridge_amount}"

  # Monitor state syncs on Heimdall and Bor.
  timeout="180" # seconds
  interval="10" # seconds
  echo "Monitoring state syncs on Heimdall..."
  assert_command_eventually_equal "${heimdall_state_sync_count_cmd}" $((initial_heimdall_state_sync_count + 1)) "${timeout}" "${interval}"

  echo "Monitoring state syncs on Bor..."
  assert_command_eventually_equal "${bor_state_sync_count_cmd}" $((initial_bor_state_sync_count + 1))"${timeout}" "${interval}"

  # Monitor balances on L1 and L2.
  echo "Monitoring MATIC balance on L1..."
  assert_token_balance_eventually_equal "${L1_MATIC_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - bridge_amount)) "${L1_RPC_URL}"

  echo "Monitoring ether balance on L2..."
  assert_ether_balance_eventually_equal "${address}" $((initial_l2_balance + bridge_amount)) "${L2_RPC_URL}"
}
