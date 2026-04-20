#!/usr/bin/env bash
# Poll an Ethereum JSON-RPC endpoint until eth_blockNumber >= TARGET_BLOCK,
# or exit 1 with a GitHub Actions ::error:: annotation when MAX_WAIT elapses.
#
# Usage: wait-for-block.sh <rpc_url> <target_block> [max_wait=900] [poll_interval=5] [context_msg]
#
# Arguments:
#   rpc_url         JSON-RPC endpoint (http[s]://host:port).
#   target_block    Decimal block number to wait for.
#   max_wait        Seconds before giving up (default 900).
#   poll_interval   Seconds between polls (default 5).
#   context_msg     Optional human-readable context shown in the initial and
#                   success logs (e.g. "span 6 starts at 768").  Pure output;
#                   has no effect on control flow.
set -euo pipefail

RPC_URL="${1:?rpc_url is required}"
TARGET_BLOCK="${2:?target_block is required}"
MAX_WAIT="${3:-900}"
POLL_INTERVAL="${4:-5}"
CONTEXT_MSG="${5:-}"

if [[ -n "$CONTEXT_MSG" ]]; then
  echo "Waiting for block ${TARGET_BLOCK} (${CONTEXT_MSG})..."
else
  echo "Waiting for block ${TARGET_BLOCK}..."
fi

elapsed=0
block=0
while [[ "$elapsed" -lt "$MAX_WAIT" ]]; do
  block=$(curl -sf -X POST "${RPC_URL}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // empty' | xargs printf "%d" 2>/dev/null) || block=0
  if [[ "$block" -ge "$TARGET_BLOCK" ]]; then
    if [[ -n "$CONTEXT_MSG" ]]; then
      echo "Block ${block} — ${CONTEXT_MSG}."
    else
      echo "Block ${block} — target reached."
    fi
    exit 0
  fi
  echo "[${elapsed}s] Block: ${block} / ${TARGET_BLOCK}"
  sleep "$POLL_INTERVAL"
  elapsed=$(( elapsed + POLL_INTERVAL ))
done

echo "::error::Chain stuck at block ${block}${CONTEXT_MSG:+ — ${CONTEXT_MSG}}."
exit 1
