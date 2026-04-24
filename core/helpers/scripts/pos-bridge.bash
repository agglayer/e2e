#!/bin/bash
# Shared helpers for Polygon PoS bridge tests (both plasma and pos bridge).
# Sourced from tests/pos/bridge/*.bats via `load` in setup().
#
# Assumes pos_setup() has already been called (defines L1/L2 env vars, timeout_seconds,
# interval_seconds).

# Variables set by test environment setup functions - disable shellcheck warnings
# shellcheck disable=SC2154
declare timeout_seconds interval_seconds

# Commands that read the current state-sync counter on each side. Re-evaluated via
# `eval` by the eventually helpers so ${L2_CL_API_URL} / ${L2_RPC_URL} are picked up
# at the time of the call.
heimdall_state_sync_count_cmd='curl "${L2_CL_API_URL}/clerk/event-records/count" | jq -r ".count"'
bor_state_sync_count_cmd='cast call --gas-limit 15000000 --rpc-url "${L2_RPC_URL}" "${L2_STATE_RECEIVER_ADDRESS}" "lastStateId()(uint)"'
checkpoint_count_cmd='curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq --raw-output ".checkpoint.id"'

# Wait for Heimdall to observe at least one new state sync since `state_sync_count`.
wait_for_heimdall_state_sync() {
  local state_sync_count="$1"
  echo "Monitoring state syncs on Heimdall..."
  assert_command_eventually_greater_or_equal "${heimdall_state_sync_count_cmd}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

# Wait for Bor to observe at least one new state sync since `state_sync_count`.
wait_for_bor_state_sync() {
  local state_sync_count="$1"
  echo "Monitoring state syncs on Bor..."
  assert_command_eventually_greater_or_equal "${bor_state_sync_count_cmd}" $((state_sync_count + 1)) "${timeout_seconds}" "${interval_seconds}"
}

# Convenience: snapshot both counters, run $1 (a command), then wait for both counters
# to increment. Used by tests that trigger an L1 deposit and need the full state-sync
# round-trip to complete before asserting on L2 state.
wait_for_state_sync_after_deposit() {
  local initial_hm="$1"
  local initial_bor="$2"
  wait_for_heimdall_state_sync "${initial_hm}"
  wait_for_bor_state_sync "${initial_bor}"
}

# Read the latest checkpoint id (0 if none yet).
latest_checkpoint_id() {
  local id
  id=$(eval "${checkpoint_count_cmd}")
  [[ "${id}" == "null" ]] && id=0
  echo "${id}"
}

# Block until a checkpoint with id > ${initial_id} exists on Heimdall.
wait_for_new_checkpoint() {
  local initial_id="$1"
  echo "Waiting for a new checkpoint on L1..."
  assert_command_eventually_greater_or_equal "${checkpoint_count_cmd}" $((initial_id + 1)) "${timeout_seconds}" "${interval_seconds}"
}

# Generate the ABI-encoded exit payload for a burn tx on L2 via polycli. Both the plasma
# bridge's ERC20PredicateBurnOnly.startExitWithBurntTokens(bytes) and the pos bridge's
# RootChainManager.exit(bytes) consume the same format.
#
# Usage: generate_pos_exit_payload <tx_hash> [log_index=0] [timeout=${timeout_seconds}]
generate_pos_exit_payload() {
  local tx_hash="$1"
  local log_index="${2:-0}"
  local timeout="${3:-${timeout_seconds}}"
  local deadline=$((SECONDS + timeout))
  local payload=""
  while [[ $SECONDS -lt $deadline ]]; do
    echo "Trying to generate exit payload for tx ${tx_hash} (log-index=${log_index})..." >&2
    if payload=$(polycli pos exit-proof \
      --l1-rpc-url "${L1_RPC_URL}" \
      --l2-rpc-url "${L2_RPC_URL}" \
      --root-chain-address "${L1_ROOT_CHAIN_PROXY_ADDRESS}" \
      --tx-hash "${tx_hash}" \
      --log-index "${log_index}"); then
      echo "${payload}"
      return 0
    fi
    echo "Checkpoint not yet indexed, retrying in ${interval_seconds}s..." >&2
    sleep "${interval_seconds}"
  done
  echo "Error: failed to generate exit payload for tx ${tx_hash} within ${timeout} seconds." >&2
  return 1
}
