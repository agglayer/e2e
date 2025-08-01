#!/bin/bash

# This script monitors the verification progress of zkEVM batches.

# Check if the required arguments are provided.
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <verified_batches_target> <timeout>"
  exit 1
fi

# The number of batches to be verified.
verified_batches_target="$1"

# The script timeout (in seconds).
timeout="$2"

start_time=$(date +%s)
end_time=$((start_time + timeout))

rpc_url="$L2_RPC_URL"
private_key="$L2_PRIVATE_KEY"

while true; do
  verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

  # The aim is to take up some space in the batch, so that the number of batches actually increases during the test.
  cast send \
    --legacy \
    --rpc-url "$rpc_url" \
    --private-key "$private_key" \
    --gas-limit 100_000 \
    --create 0x600160015B810190630000000456 \
    >/dev/null 2>&1

  current_time=$(date +%s)
  if ((current_time > end_time)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  if ((verified_batches > verified_batches_target)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... $verified_batches batches were verified!"
    exit 0
  fi

  sleep 10
done
