#!/usr/bin/env bash
set -euo pipefail

# These get replaced by the host helper script
ROLLUP_MANAGER="__ROLLUP_MANAGER__"   # from combined.json: polygonRollupManagerAddress


RPC_URL="${RPC_URL:-http://el-1-geth-lighthouse:8545}"
LOOKBACK="${LOOKBACK:-100}" # set the look back for event to be 100 blocks

EVENT="VerifyBatchesTrustedAggregator(uint32,uint64,bytes32,bytes32,address)"

CURRENT="$(cast block-number --rpc-url "$RPC_URL")" # gets the lates blocknumber captured by CURRENT variable
FROM=$(( CURRENT - LOOKBACK )) # set the start of scan window
if (( FROM < 0 )); then FROM=0; fi # if the scan range is less than 0 we set it to begin from 0

echo "Scanning blocks $FROM → $CURRENT on $RPC_URL"
echo "  contract (rollup manager): $ROLLUP_MANAGER"
echo "  event: $EVENT"
echo "  lookback: $LOOKBACK blocks"

TMP_JSON="$(mktemp -t verify-logs.XXXXXX.json)"

# Stream logs as pretty JSON to terminal (if jq is installed) and save raw JSON to file
if command -v jq >/dev/null 2>&1; then
  cast logs \
    --address "$ROLLUP_MANAGER" "$EVENT" \
    --from-block "$FROM" --to-block "$CURRENT" \
    --rpc-url "$RPC_URL" \
    --json \
  | tee "$TMP_JSON" | jq -C .
else
  echo "(jq not found — showing raw JSON)"
  cast logs \
    --address "$ROLLUP_MANAGER" "$EVENT" \
    --from-block "$FROM" --to-block "$CURRENT" \
    --rpc-url "$RPC_URL" \
    --json | tee "$TMP_JSON"
fi

FOUND=0
if command -v jq >/dev/null 2>&1; then
  FOUND="$(jq 'length' "$TMP_JSON")" # count how many item are in the json file
else
  # crude fallback: count '[' then subtract brackets; if it's "[]", FOUND stays 0
  # (safe enough for our purpose when jq isn't available)
  if grep -q '"address"' "$TMP_JSON"; then # checks is tem_json contains substring address
    FOUND="$(grep -c '"address"' "$TMP_JSON" || true)" # counts lines that contains the address substring
  fi
fi

if (( FOUND > 0 )); then
  echo "[SUCCESS---] Found ${FOUND} verification event(s) for $ROLLUP_MANAGER in the last $LOOKBACK blocks."
  if command -v jq >/dev/null 2>&1; then
    echo "--- summary ---"
    # Show a compact, human-readable list
    jq -r '.[] | "block=\(.blockNumber) tx=\(.transactionHash) logIndex=\(.logIndex) rollupIdTopic=\(.topics[1]) aggregatorTopic=\(.topics[2])"' "$TMP_JSON"
  fi
  exit 0
else
  echo "[ERROR---] No verification events found for $ROLLUP_MANAGER in the last $LOOKBACK blocks."
  exit 2
fi
