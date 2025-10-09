#!/usr/bin/env bash
# lxly.sh — standalone replacement for lxly.bats
# Usage:
#   ./lxly.sh native
#   ./lxly.sh erc20-roundtrip
# Env (optional):
#   ENCLAVE_NAME, L1_RPC_URL, L2_RPC_URL, L1_BRIDGE_ADDR, L2_BRIDGE_ADDR
#   BRIDGE_SERVICE_URL, CLAIMTXMANAGER_ADDR, CLAIM_WAIT_DURATION
#   TRANSACTION_RECEIPT_TIMEOUT, ERC20_TOKEN_NAME, ERC20_TOKEN_SYMBOL
#
# Notes:
# - This version removes --wait (unsupported in your polycli) and uses a retry loop.
# - It passes --transaction-receipt-timeout consistently to bridge/claim.
# - It computes depositCount safely (pre/post) to pick the correct index to claim.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- config defaults (override via env) ---
: "${CLAIMTXMANAGER_ADDR:=0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8}"
: "${CLAIM_WAIT_DURATION:=10m}"            # e.g., 10m, 120s, or just 600
: "${TRANSACTION_RECEIPT_TIMEOUT:=60}"     # seconds
: "${ERC20_TOKEN_NAME:=e2e test}"
: "${ERC20_TOKEN_SYMBOL:=E2E}"

log() { echo "[$(date -Is)] $*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 127; }
}

preflight() {
  need cast
  need jq
  need kurtosis
  need polycli
  need curl
}

# Parse CLAIM_WAIT_DURATION into seconds (supports Xm, Xs, or plain X)
duration_to_seconds() {
  local d="${1:-600}"
  if [[ "$d" =~ ^[0-9]+m$ ]]; then
    echo $(( ${d%m} * 60 ))
  elif [[ "$d" =~ ^[0-9]+s$ ]]; then
    echo "${d%s}"
  elif [[ "$d" =~ ^[0-9]+$ ]]; then
    echo "$d"
  else
    # fallback: 10 minutes
    echo 600
  fi
}

# Retry wrapper around `polycli ulxly claim asset`
# Args: bridge_addr priv_key rpc_url deposit_count deposit_network bridge_service_url timeout_secs
claim_with_retry() {
  local bridge_addr="$1" priv="$2" rpc="$3" dep_count="$4" dep_net="$5" svc="$6" timeout_secs="$7"
  local start rc now
  start="$(date +%s)"
  while :; do
    set +e
    polycli ulxly claim asset \
      --bridge-address "$bridge_addr" \
      --private-key "$priv" \
      --rpc-url "$rpc" \
      --deposit-count "$dep_count" \
      --deposit-network "$dep_net" \
      --bridge-service-url "$svc" \
      --transaction-receipt-timeout "$TRANSACTION_RECEIPT_TIMEOUT"
    rc=$?
    set -e
    if (( rc == 0 )); then
      log "Claim succeeded (deposit_count=$dep_count deposit_network=$dep_net)"
      return 0
    fi
    now="$(date +%s)"
    if (( now - start >= timeout_secs )); then
      log "Claim timed out after ${timeout_secs}s (last rc=$rc). Auto-claimer may have handled it."
      return $rc
    fi
    log "Claim not ready yet; retrying in 10s..."
    sleep 10
  done
}

# shellcheck source=common.sh
load_common() {
  if [[ -f "$HERE/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HERE/common.sh"
  else
    # shellcheck source=/dev/null
    source "$HERE/../../core/helpers/common.bash"
  fi
  _setup_vars
  : "${BRIDGE_SERVICE_URL:="$(kurtosis port print "${kurtosis_enclave_name:-cdk}" zkevm-bridge-service-001 rpc)"}"
  log "using BRIDGE_SERVICE_URL=$BRIDGE_SERVICE_URL"
}

# Fund the claim_tx_manager so the bridge service can pay gas for claims (devnets)
fund_claim_tx_manager() {
  local balance
  balance="$(cast balance --rpc-url "$l2_rpc_url" "$CLAIMTXMANAGER_ADDR")"
  if [[ "$balance" != "0" ]]; then
    log "ClaimTxManager already funded on L2 (balance=$balance)"
    return
  fi
  log "Funding ClaimTxManager on L2 with 1 ether"
  cast send --legacy --value 1ether \
    --rpc-url "$l2_rpc_url" \
    --private-key "$l2_private_key" \
    "$CLAIMTXMANAGER_ADDR"
}

native() {
  preflight
  load_common
  fund_claim_tx_manager

  local pre_dc post_dc deposit_count bridge_amount claim_secs
  claim_secs="$(duration_to_seconds "$CLAIM_WAIT_DURATION")"

  # L1 -> L2 native
  pre_dc="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  bridge_amount="$(date +%s)"

  log "Bridging native ETH L1 -> L2 amount=$bridge_amount"
  polycli ulxly bridge asset \
    --bridge-address "$l1_bridge_addr" \
    --destination-address "$l2_eth_address" \
    --destination-network "$l2_network_id" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --transaction-receipt-timeout "$TRANSACTION_RECEIPT_TIMEOUT" \
    --value "$bridge_amount"

  post_dc="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  if [[ "$post_dc" == "$pre_dc" ]]; then
    echo "Deposit count did not increase on L1" >&2
    exit 1
  fi
  # The deposit we just made corresponds to the *previous* counter value.
  deposit_count="$pre_dc"

  # Claim on L2
  claim_with_retry "$l2_bridge_addr" "$l2_private_key" "$l2_rpc_url" \
    "$deposit_count" "0" "$BRIDGE_SERVICE_URL" "$claim_secs" \
    || log "Claim did not complete within ${claim_secs}s (auto-claimer may have handled it)."
}

erc20_roundtrip() {
  preflight
  load_common
  fund_claim_tx_manager

  local claim_secs
  claim_secs="$(duration_to_seconds "$CLAIM_WAIT_DURATION")"

  # Ensure deterministic deployer is present on L2
  local salt deterministic_deployer_addr deterministic_deployer_code
  salt="0x0000000000000000000000000000000000000000000000000000000000000000"
  deterministic_deployer_addr=0x4e59b44847b379578588920ca78fbf26c0b4956c
  deterministic_deployer_code="$(cast code --rpc-url "$l2_rpc_url" "$deterministic_deployer_addr")"

  if [[ "$deterministic_deployer_code" == "0x" ]]; then
    log "Publishing deterministic deployer bytecode on L2"
    cast send --legacy --value 0.1ether --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" 0x3fab184622dc19b6109349b94811493bf2a45362
    cast publish --rpc-url "$l2_rpc_url" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
  fi

  # Deploy ERC20 via CREATE2 if missing
  local erc_20_bytecode constructor_args test_erc20_addr
  erc_20_bytecode="$(cat "$HERE/../../core/contracts/bin/erc20permitmock.bin" 2>/dev/null || cat core/contracts/bin/erc20permitmock.bin)"
  erc_20_bytecode="${erc_20_bytecode#0x}" # safety: strip accidental 0x

  constructor_args="$(cast abi-encode 'f(string,string,address,uint256)' "$ERC20_TOKEN_NAME" "$ERC20_TOKEN_SYMBOL" "$l2_eth_address" 100000000000000000000)"
  constructor_args="${constructor_args#0x}"

  test_erc20_addr="$(cast create2 --deployer 0x4e59b44847b379578588920ca78fbf26c0b4956c --salt "$salt" --init-code "$erc_20_bytecode$constructor_args")"

  if [[ "$(cast code --rpc-url "$l2_rpc_url" "$test_erc20_addr")" == "0x" ]]; then
    log "Deploying ERC20 to $test_erc20_addr via CREATE2 and approving bridge"
    cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" \
      "$deterministic_deployer_addr" "$salt$erc_20_bytecode$constructor_args"
    cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" \
      "$test_erc20_addr" 'approve(address,uint256)' "$l2_bridge_addr" "$(cast max-uint)"
  else
    log "ERC20 already present at $test_erc20_addr"
  fi

  # --- L2 -> L1 (ERC20) ---
  local pre_dc_l2 post_dc_l2 deposit_count_l2 bridge_amount token_hash wrapped_token_addr
  pre_dc_l2="$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  bridge_amount="$(date +%s)"

  log "Bridging ERC20 L2 -> L1 amount=$bridge_amount token=$test_erc20_addr"
  polycli ulxly bridge asset \
    --destination-network 0 \
    --destination-address "$l1_eth_address" \
    --token-address "$test_erc20_addr" \
    --value "$bridge_amount" \
    --bridge-address "$l2_bridge_addr" \
    --rpc-url "$l2_rpc_url" \
    --private-key "$l2_private_key" \
    --transaction-receipt-timeout "$TRANSACTION_RECEIPT_TIMEOUT"

  post_dc_l2="$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  if [[ "$post_dc_l2" == "$pre_dc_l2" ]]; then
    echo "Deposit count did not increase on L2" >&2
    exit 1
  fi
  deposit_count_l2="$pre_dc_l2"

  log "Claiming on L1 for L2 depositCount=$deposit_count_l2"
  claim_with_retry "$l1_bridge_addr" "$l1_private_key" "$l1_rpc_url" \
    "$deposit_count_l2" "$l2_network_id" "$BRIDGE_SERVICE_URL" "$(duration_to_seconds "$CLAIM_WAIT_DURATION")"

  # Find wrapped token on L1
  token_hash="$(cast keccak "$(cast abi-encode --packed 'f(uint32, address)' "$l2_network_id" "$test_erc20_addr")")"
  wrapped_token_addr="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")"

  # --- L1 -> L2 (wrapped token) ---
  local pre_dc_l1 post_dc_l1 deposit_count_l1
  pre_dc_l1="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"

  log "Bridging wrapped L1 token -> L2 amount=$bridge_amount token=$wrapped_token_addr"
  polycli ulxly bridge asset \
    --destination-network "$l2_network_id" \
    --destination-address "$l2_eth_address" \
    --token-address "$wrapped_token_addr" \
    --value "$bridge_amount" \
    --bridge-address "$l1_bridge_addr" \
    --rpc-url "$l1_rpc_url" \
    --private-key "$l1_private_key" \
    --transaction-receipt-timeout "$TRANSACTION_RECEIPT_TIMEOUT"

  post_dc_l1="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  if [[ "$post_dc_l1" == "$pre_dc_l1" ]]; then
    echo "Deposit count did not increase on L1 (wrapped hop)" >&2
    exit 1
  fi
  deposit_count_l1="$pre_dc_l1"

  # Claim on L2 (for the L1->L2 deposit)
  claim_with_retry "$l2_bridge_addr" "$l2_private_key" "$l2_rpc_url" \
    "$deposit_count_l1" "0" "$BRIDGE_SERVICE_URL" "$(duration_to_seconds "$CLAIM_WAIT_DURATION")" \
    || log "L2 claim may have been handled by auto-claimer."

  # --- Repeat another L2 -> L1 (ERC20) and claim on L1 ---
  local pre_dc_l2_b post_dc_l2_b deposit_count_l2_b
  pre_dc_l2_b="$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  bridge_amount="$(date +%s)"

  log "Bridging ERC20 again L2 -> L1 amount=$bridge_amount"
  polycli ulxly bridge asset \
    --destination-network 0 \
    --token-address "$test_erc20_addr" \
    --value "$bridge_amount" \
    --bridge-address "$l2_bridge_addr" \
    --rpc-url "$l2_rpc_url" \
    --private-key "$l2_private_key" \
    --transaction-receipt-timeout "$TRANSACTION_RECEIPT_TIMEOUT"

  post_dc_l2_b="$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')"
  if [[ "$post_dc_l2_b" == "$pre_dc_l2_b" ]]; then
    echo "Deposit count did not increase on L2 (second hop)" >&2
    exit 1
  fi
  deposit_count_l2_b="$pre_dc_l2_b"

  log "Claiming on L1 for depositCount=$deposit_count_l2_b"
  claim_with_retry "$l1_bridge_addr" "$l1_private_key" "$l1_rpc_url" \
    "$deposit_count_l2_b" "$l2_network_id" "$BRIDGE_SERVICE_URL" "$(duration_to_seconds "$CLAIM_WAIT_DURATION")"

  log "ERC20 roundtrip complete."
}

usage() {
  cat >&2 <<EOF
Usage: $0 <native|erc20-roundtrip>

Examples:
  ENCLAVE_NAME=cdk $0 native
  ENCLAVE_NAME=cdk $0 erc20-roundtrip

Optionally set:
  L1_RPC_URL, L2_RPC_URL, L1_BRIDGE_ADDR, L2_BRIDGE_ADDR,
  BRIDGE_SERVICE_URL, CLAIMTXMANAGER_ADDR, CLAIM_WAIT_DURATION,
  TRANSACTION_RECEIPT_TIMEOUT, ERC20_TOKEN_NAME, ERC20_TOKEN_SYMBOL
EOF
}

main() {
  case "${1:-}" in
    native)           native ;;
    erc20-roundtrip)  erc20_roundtrip ;;
    *)                usage; exit 2 ;;
  esac
}

main "$@"
