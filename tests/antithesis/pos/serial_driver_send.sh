#!/usr/bin/env bash

# Script timeout duration, in seconds.
timeout_seconds=30

# Retry loop to avoid issues with network partitions.
start_time=$(date +%s)
end_time=$((start_time + timeout_seconds))
while (($(date +%s) < end_time)); do
  if cast send --rpc-url "${L2_RPC_URL}" --legacy --private-key "${PRIVATE_KEY}" --value 0.001ether "$(cast address-zero)"; then
    exit 0
  fi
  sleep 5
done

echo "Script failed after ${timeout_seconds} seconds. Exiting."
exit 1
