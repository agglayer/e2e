#!/bin/bash
set -euo pipefail

# Asynchronous tests.
# Eventually checks that an assertion eventually passes.
# It will attempt an assertion periodically until it passes or a timeout occurs.

function assert_eventually_equal() {
  local command="$1"
  local target="$2"
  local timeout="${3:-60}"
  local interval="${4:-5}"

  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  echo "Checking if '${command}' will eventually be equal to '${target}' within ${timeout} seconds."
  while [[ "$(date +%s)" -ne "${end_time}" ]]; do
    result=$(eval "$command")
    if [[ "${result}" -eq "${target}" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Result '${result}' is equal to '${target}'!"
      return 0
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Result '${result}' is not equal to '${target}'. Waiting ${interval} seconds..."
    sleep "${interval}"
  done

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Timeout reached."
  return 1
}

function assert_eventually_greater_than() {
  local command="$1"
  local threshold="$2"
  local timeout="${3:-60}"
  local interval="${4:-5}"

  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  echo "Checking if '${command}' will eventually be greater than '${threshold}' within ${timeout} seconds."
  while [[ "$(date +%s)" -lt "${end_time}" ]]; do
    result=$(eval "$command")
    if [[ "${result}" -gt "${threshold}" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Result '${result}' is greater than '${threshold}'!"
      return 0
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Result '${result}' is not greater than '${threshold}'. Waiting ${interval} seconds..."
    sleep "${interval}"
  done

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Timeout reached."
  return 1
}

function assert_token_balance_eventually_equal() {
  local contract_address="$1"
  local eoa_address="$2"
  local target="$3"
  local rpc_url="$4"
  local timeout="${5:-60}"
  local interval="${6:-5}"

  start_time=$(date +%s)
  end_time=$((start_time + timeout))
  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    balance=$(cast call --json --rpc-url "${rpc_url}" "${contract_address}" "balanceOf(address)(uint)" "${eoa_address}" | jq --raw-output ".[0]")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Balance: ${balance}."
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

  start_time=$(date +%s)
  end_time=$((start_time + timeout))
  while true; do
    if [[ "$(date +%s)" -ge "${end_time}" ]]; then
      echo "Timeout reached."
      exit 1
    fi

    balance=$(cast balance --rpc-url "${rpc_url}" "${address}")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Balance: ${balance}."
    if [[ "${balance}" -eq "${target}" ]]; then
      break
    fi

    sleep "${interval}"
  done
}
