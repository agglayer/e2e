#!/bin/bash
set -euo pipefail

DEFAULT_TIMEOUT=60 # in seconds
DEFAULT_INTERVAL=5 # in seconds

# Asynchronous tests.
# Eventually checks that an assertion eventually passes.
# It will attempt an assertion periodically until it passes or a timeout occurs.

function assert_eventually_equal() {
  local command="$1"
  local target="$2"
  local timeout="${3:-"${DEFAULT_TIMEOUT}"}"
  local interval="${4:-"${DEFAULT_INTERVAL}"}"

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
  local timeout="${3:-"${DEFAULT_TIMEOUT}"}"
  local interval="${4:-"${DEFAULT_INTERVAL}"}"

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
