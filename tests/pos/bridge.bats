#!/usr/bin/env bats

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/async.bash"
  pos_setup

  # Test parameters.
  if [[ "${L2_CL_NODE_TYPE}" == "heimdall" ]]; then
    HEIMDALL_STATE_SYNC_COUNT_CMD='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".result | length"'
  elif [[ "${L2_CL_NODE_TYPE}" == "heimdall-v2" ]]; then
    HEIMDALL_STATE_SYNC_COUNT_CMD='curl --silent "${L2_CL_API_URL}/clerk/event-record/list" | jq ".event_records | length"'
  fi
  export HEIMDALL_STATE_SYNC_COUNT_CMD="${HEIMDALL_STATE_SYNC_COUNT_CMD}"

  BOR_STATE_SYNC_COUNT_CMD='cast call --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'
  export BOR_STATE_SYNC_COUNT_CMD="${BOR_STATE_SYNC_COUNT_CMD}"
}

# bats file_tags=pos,bridge
@test "bridge ERC20 token from L1 to L2" {
  # TODO
}

# bats file_tags=pos,bridge
@test "bridge ERC721 token from L1 to L2" {
  # TODO
}

# bats file_tags=pos,state-sync
@test "bridge native L2 eth from L1 to L2 to trigger state sync" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Get initial values.
  initial_balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${address}")
  initial_heimdall_state_sync_count=$(eval "${HEIMDALL_STATE_SYNC_COUNT_CMD}")
  initial_bor_state_sync_count=$(eval "${BOR_STATE_SYNC_COUNT_CMD}")
  echo "Initial values:"
  echo "- ${address} L2 balance: ${initial_balance} ether."
  echo "- Heimdall state sync count: ${initial_heimdall_state_sync_count}."
  echo "- Bor state sync count: ${initial_bor_state_sync_count}."

  # Bridge some ERC20 tokens from L1 to L2 to trigger a state sync.
  echo "Approving the DepositManager contract to spend ERC20 tokens on our behalf..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_MATIC_TOKEN_ADDRESS}" "approve(address,uint)" "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" 10

  echo "Depositing tokens to trigger a state sync..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}" "depositERC20(address,uint)" "${L1_MATIC_TOKEN_ADDRESS}" 10

  # Monitor state syncs on Heimdall and Bor.
  timeout="180" # seconds
  interval="10" # seconds
  echo "Monitoring state syncs on Heimdall..."
  assert_eventually_greater_than "${HEIMDALL_STATE_SYNC_COUNT_CMD}" "${initial_heimdall_state_sync_count}" "${timeout}" "${interval}"

  echo "Monitoring state syncs on Bor..."
  assert_eventually_greater_than "${BOR_STATE_SYNC_COUNT_CMD}" "${initial_bor_state_sync_count}" "${timeout}" "${interval}"

  # Check new account balance on L2.
  new_balance=$(cast balance --rpc-url "${L2_RPC_URL}" --ether "${address}")
  if [[ "${new_balance}" -lt "${initial_balance}" ]]; then
    echo "❌ ${address} balance has not changed."
    exit 1
  fi
  echo "✅ ${address} balance has increased: ${new_balance} ether."
}
