#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Define state sync count commands.
  HEIMDALL_STATE_SYNC_COUNT_CMD='curl --silent "${L2_CL_API_URL}/clerk/event-records/count" | jq -r ".count"'
  BOR_STATE_SYNC_COUNT_CMD='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'

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
  assert_command_eventually_equal "${HEIMDALL_STATE_SYNC_COUNT_CMD}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
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
  assert_command_eventually_equal "${BOR_STATE_SYNC_COUNT_CMD}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

# bats file_tags=pos,bridge,matic,pol
@test "bridge MATIC/POL from L1 to L2 and confirm L2 MATIC/POL balance increased" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")

  echo "Initial balances:"
  echo "- L1 balance: ${initial_l1_balance} MATIC"
  echo "- L2 balance: ${initial_l2_balance} wei"

  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

  # Bridge some MATIC/POL tokens from L1 to L2 to trigger a state sync.
  # 1 MATIC/POL token = 1000000000000000000 wei.
  bridge_amount=$(cast to-unit 1ether wei)

  echo "Approving the DepositManager contract to spend MATIC/POL tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"

  echo "Depositing MATIC/POL tokens to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_MATIC_TOKEN_ADDRESS}" "${bridge_amount}"

  # Wait for Heimdall and Bor to process the bridge event.
  wait_for_heimdall_state_sync "${heimdall_state_sync_count}"
  wait_for_bor_state_sync "${bor_state_sync_count}"

  # Monitor the balances on L1 and L2.
  echo "Monitoring MATIC/POL balance on L1..."
  assert_token_balance_eventually_equal "${L1_MATIC_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - bridge_amount)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring MATIC/POL balance on L2..."
  assert_ether_balance_eventually_equal "${address}" $((initial_l2_balance + bridge_amount)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats file_tags=pos,bridge,matic,pol
# @test "bridge MATIC/POL from L2 to L1 and confirm L1 MATIC/POL balance increased" {
#   echo TODO
# }

# bats file_tags=pos,bridge,erc20
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
  assert_token_balance_eventually_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - bridge_amount)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring ERC20 balance on L2..."
  assert_token_balance_eventually_equal "${L2_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance + bridge_amount)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats file_tags=pos,bridge,erc20
# @test "bridge some ERC20 tokens from L2 to L1 and confirm L1 ERC20 balance increased" {
#   echo TODO
# }

# bats file_tags=pos,bridge,erc721
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
  assert_token_balance_eventually_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l1_balance - 1)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring ERC721 balance on L2..."
  assert_token_balance_eventually_equal "${L2_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l2_balance + 1)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats file_tags=pos,bridge,erc721
# @test "bridge an ERC721 token from L2 to L1 and confirm L1 ERC721 balance increased" {
#   echo TODO
# }

# bats file_tags=pos,bridge,l1,l2
@test "bridge MATIC/POL, ERC20, and ERC721 from L1 to L2 and confirm L2 balances increased" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get the initial balances.
  initial_l1_matic_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_MATIC_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_native_balance=$(cast balance --rpc-url "${L2_RPC_URL}" "${address}")
  initial_l1_erc20_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_erc20_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC20_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  # Mint a new ERC721 token.
  total_supply=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "totalSupply()(uint)" | jq --raw-output '.[0]')
  token_id=$((total_supply + 1))

  echo "Minting ERC721 token (id: ${token_id})..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "mint(uint)" "${token_id}"

  initial_l1_erc721_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_erc721_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_ERC721_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')

  echo "Initial balances:"
  echo "- L1 MATIC/POL: ${initial_l1_matic_balance}"
  echo "- L2 MATIC/POL: ${initial_l2_native_balance} wei"
  echo "- L1 ERC20: ${initial_l1_erc20_balance}"
  echo "- L2 ERC20: ${initial_l2_erc20_balance}"
  echo "- L1 ERC721: ${initial_l1_erc721_balance}"
  echo "- L2 ERC721: ${initial_l2_erc721_balance}"

  # Get the initial state sync count.
  heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")

  echo "Initial state sync counts:"
  echo "- Heimdall: ${heimdall_state_sync_count}"
  echo "- Bor: ${bor_state_sync_count}"

  # Bridge amount.
  bridge_amount=$(cast to-unit 1ether wei)

  # Bridge MATIC/POL.
  echo "Bridging MATIC/POL from L1 to L2..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_MATIC_TOKEN_ADDRESS}" "${bridge_amount}"

  # Bridge ERC20.
  echo "Bridging ERC20 from L1 to L2..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC20_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${bridge_amount}"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_ERC20_TOKEN_ADDRESS}" "${bridge_amount}"

  # Bridge ERC721.
  echo "Bridging ERC721 from L1 to L2..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ERC721_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "${token_id}"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC721(address,uint)" "${L1_ERC721_TOKEN_ADDRESS}" "${token_id}"

  # Wait for Heimdall and Bor to process the bridge events.
  assert_command_eventually_equal "${HEIMDALL_STATE_SYNC_COUNT_CMD}" $((heimdall_state_sync_count + 3)) "${timeout_seconds}" "${interval_seconds}"

  echo "Waiting for Bor to process all bridge events..."
  assert_command_eventually_equal "${BOR_STATE_SYNC_COUNT_CMD}" $((bor_state_sync_count + 3)) "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L1 MATIC/POL balance decreased..."
  assert_token_balance_eventually_equal "${L1_MATIC_TOKEN_ADDRESS}" "${address}" $((initial_l1_matic_balance - bridge_amount)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L1 ERC20 balance decreased..."
  assert_token_balance_eventually_equal "${L1_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l1_erc20_balance - bridge_amount)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L1 ERC721 balance decreased..."
  assert_token_balance_eventually_equal "${L1_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l1_erc721_balance - 1)) "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L2 native balance increased..."
  assert_ether_balance_eventually_equal "${address}" $((initial_l2_native_balance + bridge_amount)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L2 ERC20 balance increased..."
  assert_token_balance_eventually_equal "${L2_ERC20_TOKEN_ADDRESS}" "${address}" $((initial_l2_erc20_balance + bridge_amount)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Verifying L2 ERC721 balance increased..."
  assert_token_balance_eventually_equal "${L2_ERC721_TOKEN_ADDRESS}" "${address}" $((initial_l2_erc721_balance + 1)) "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "✅ MATIC/POL, ERC20, and ERC721 bridge operations completed successfully!"
  echo "Summary:"
  echo "- 1 MATIC/POL bridged from L1 to L2"
  echo "- 1 ERC20 token bridged from L1 to L2"
  echo "- 1 ERC721 token (id: ${token_id}) bridged from L1 to L2"
}
