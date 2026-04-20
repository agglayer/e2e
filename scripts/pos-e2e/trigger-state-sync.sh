#!/usr/bin/env bash
# Trigger an L1→L2 state sync event on a running kurtosis-pos enclave.
#
# In the kurtosis devnet no deposits happen automatically, so without this
# the clerk event record list stays empty and all state-sync tests skip.
# A single depositEther() triggers a StateSynced event that Heimdall's
# clerk picks up within ~60 s (we poll up to 120 s).
#
# Failure modes are downgraded to ::warning::  — the downstream BATS suite
# will skip clerk/bridge tests cleanly rather than fail the whole job.
#
# Environment:
#   ENCLAVE_NAME      kurtosis enclave name (required).
#   L1_RPC_URL        override L1 RPC endpoint (optional; default: resolve
#                     from kurtosis via geth-lighthouse / reth-lighthouse).
#   DEPOSITOR_PK      private key for the depositor (optional; default: the
#                     well-known kurtosis-pos test key).
set -euo pipefail

: "${ENCLAVE_NAME:?ENCLAVE_NAME must be set}"

PK="${DEPOSITOR_PK:-0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea}"

if [[ -z "${L1_RPC_URL:-}" ]]; then
  # Accept either geth-lighthouse or reth-lighthouse L1 flavour.
  L1_PORT=$(kurtosis port print "${ENCLAVE_NAME}" el-1-geth-lighthouse rpc 2>/dev/null \
         || kurtosis port print "${ENCLAVE_NAME}" el-1-reth-lighthouse rpc 2>/dev/null)
  L1_PORT="${L1_PORT#http://}" ; L1_PORT="${L1_PORT#https://}"
  L1_RPC_URL="http://${L1_PORT}"
fi

MATIC_ADDR=$(kurtosis files inspect "${ENCLAVE_NAME}" matic-contract-addresses contractAddresses.json | jq)
DEPOSIT_MGR=$(echo "$MATIC_ADDR" | jq -r '.root.DepositManagerProxy')

echo "Triggering L1→L2 state sync via depositEther()..."
echo "  L1_RPC=${L1_RPC_URL}  DEPOSIT_MGR=${DEPOSIT_MGR}"

cast send --rpc-url "${L1_RPC_URL}" --private-key "${PK}" \
  --value 0.01ether "${DEPOSIT_MGR}" "depositEther()" || {
  echo "::warning::depositEther() failed — clerk/bridge tests may skip"
}

# Wait for Heimdall's clerk to relay the StateSynced event.
CL_PORT=$(kurtosis port print "${ENCLAVE_NAME}" l2-cl-1-heimdall-v2-bor-validator http)
CL_PORT="${CL_PORT#http://}" ; CL_PORT="${CL_PORT#https://}"
L2_CL_API="http://${CL_PORT}"
echo "Waiting for clerk to pick up the state sync event..."
for i in $(seq 1 24); do
  rid=$(curl -sf -m 10 "${L2_CL_API}/clerk/event-records/latest-id" \
    | jq -r '.latest_record_id // "0"' 2>/dev/null) || rid=0
  if [[ "$rid" -gt 0 ]]; then
    echo "Clerk has event records (latest_record_id=${rid}) after $((i*5))s."
    exit 0
  fi
  sleep 5
done
echo "::warning::No clerk events after 120s — tests will poll further on their own"
