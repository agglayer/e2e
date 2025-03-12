#!/bin/bash
set -euo pipefail

# Eventually checks that an assertion passes within a given timeout.
# It will repeatedly attempt the assertion at regular intervals until it passes or the timeout is reached.

# Please note that this function does not handle piped commands!
function assert_command_eventually_equal() {
  local command="$1"
  local target="$2"
  local timeout="${3:-60}"
  local interval="${4:-5}"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${target}"

  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    result=$(eval "$command")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Result: ${result}"
    if [[ "${result}" -eq "${target}" ]]; then
      break
    fi

    sleep "${interval}"
  done
}

function assert_token_balance_eventually_equal() {
  local contract_address="$1"
  local eoa_address="$2"
  local target="$3"
  local rpc_url="$4"
  local timeout="${5:-60}"
  local interval="${6:-5}"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${target}"

  start_time=$(date +%s)
  end_time=$((start_time + timeout))
  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    balance=$(cast call --json --rpc-url "${rpc_url}" "${contract_address}" "balanceOf(address)(uint)" "${eoa_address}" | jq --raw-output ".[0]")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Balance: ${balance} tokens"
    if [[ "${balance}" -eq "${target}" ]]; then
      break
    fi

    sleep "${interval}"
  done
}

function assert_ether_balance_eventually_equal() {
  local address="$1"
  local target="$2"
  local rpc_url="$3"
  local timeout="${4:-60}"
  local interval="${5:-5}"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${target}"

  start_time=$(date +%s)
  end_time=$((start_time + timeout))
  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    balance=$(cast balance --rpc-url "${rpc_url}" "${address}")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Balance: ${balance} wei"
    if [[ "${balance}" -eq "${target}" ]]; then
      break
    fi

    sleep "${interval}"
  done
}
