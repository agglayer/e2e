#!/usr/bin/env bash
# compute-golden-state.sh — Capture block hashes at fork boundaries as a regression anchor.
#
# Queries a running devnet and records the blockHash (which commits stateRoot, receiptsRoot,
# transactionsRoot, and all other header fields) at each fork activation block.
#
# Usage:
#   ./scripts/compute-golden-state.sh [OPTIONS]
#
# Options:
#   --rpc-url URL        Bor RPC URL (default: $L2_RPC_URL or auto-discovered from kurtosis)
#   --enclave NAME       Kurtosis enclave name (default: $ENCLAVE_NAME or "pos")
#   --bor-version VER    Version tag for the output file (default: queried from web3_clientVersion)
#   --output-dir DIR     Where to write the JSON file (default: tests/pos/golden/)
#   --fork-rio N         Override fork block numbers (default: standard staggered schedule)
#   --fork-madhugiri N
#   --fork-madhugiri-pro N
#   --fork-dandeli N
#   --fork-lisovo N
#   --fork-lisovo-pro N
#   --fork-giugliano N
#
# Output: tests/pos/golden/state-roots-<bor-version>.json
#
# The golden file is committed to the repo. When a new release changes state at a fork
# boundary (intentionally or not), the diff is visible in the PR and requires explicit
# acknowledgement via updating the file.
#
# Example:
#   # After running the fork-transition devnet:
#   export ENCLAVE_NAME=pos
#   ./scripts/compute-golden-state.sh --bor-version 2.7.0
#
# To regenerate for a new release:
#   ./scripts/compute-golden-state.sh --bor-version 2.8.0
#   git add tests/pos/golden/state-roots-2.8.0.json
#   git commit -m "pos: update golden state for Bor v2.8.0 (new fork: <name>)"

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Defaults
# ────────────────────────────────────────────────────────────────────────────

RPC_URL="${L2_RPC_URL:-}"
ENCLAVE="${ENCLAVE_NAME:-pos}"
BOR_VERSION=""
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/tests/pos/golden"

# Standard staggered fork schedule (matches pos-e2e.yml fork-transition job)
FORK_RIO=256
FORK_MADHUGIRI=320
FORK_MADHUGIRI_PRO=384
FORK_DANDELI=448
FORK_LISOVO=512
FORK_LISOVO_PRO=576
FORK_GIUGLIANO=640

# ────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rpc-url)          RPC_URL="$2"; shift 2 ;;
        --enclave)          ENCLAVE="$2"; shift 2 ;;
        --bor-version)      BOR_VERSION="$2"; shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
        --fork-rio)         FORK_RIO="$2"; shift 2 ;;
        --fork-madhugiri)   FORK_MADHUGIRI="$2"; shift 2 ;;
        --fork-madhugiri-pro) FORK_MADHUGIRI_PRO="$2"; shift 2 ;;
        --fork-dandeli)     FORK_DANDELI="$2"; shift 2 ;;
        --fork-lisovo)      FORK_LISOVO="$2"; shift 2 ;;
        --fork-lisovo-pro)  FORK_LISOVO_PRO="$2"; shift 2 ;;
        --fork-giugliano)   FORK_GIUGLIANO="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,2\}//'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ────────────────────────────────────────────────────────────────────────────
# Resolve RPC URL
# ────────────────────────────────────────────────────────────────────────────

if [[ -z "$RPC_URL" ]]; then
    if ! RPC_URL=$(kurtosis port print "${ENCLAVE}" l2-el-1-bor-heimdall-v2-validator rpc 2>/dev/null); then
        echo "ERROR: Could not auto-discover RPC URL. Set --rpc-url or L2_RPC_URL." >&2
        exit 1
    fi
    RPC_URL="${RPC_URL#http://}"; RPC_URL="${RPC_URL#https://}"
    RPC_URL="http://${RPC_URL}"
fi
echo "Using RPC: ${RPC_URL}"

# ────────────────────────────────────────────────────────────────────────────
# Resolve Bor version
# ────────────────────────────────────────────────────────────────────────────

if [[ -z "$BOR_VERSION" ]]; then
    raw_version=$(curl -s -m 30 --connect-timeout 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        | jq -r '.result // empty')
    BOR_VERSION=$(echo "$raw_version" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]*)?' | head -1 | sed 's/^v//')
    if [[ -z "$BOR_VERSION" ]]; then
        echo "ERROR: Could not determine Bor version from RPC. Use --bor-version." >&2
        exit 1
    fi
    echo "Detected Bor version: ${BOR_VERSION}"
fi
# Validate version string: digits/dots/pre-release only (prevents path traversal via filename)
if [[ ! "$BOR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]*)?$ ]]; then
    echo "ERROR: Invalid bor version format '${BOR_VERSION}'. Expected X.Y.Z[-betaN|-rcN]." >&2
    exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

query_block() {
    local block="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    local response
    response=$(curl -s -m 30 --connect-timeout 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}")

    # Extract hex fields separately so bash arithmetic can do correct hex→decimal.
    # jq's tonumber only handles decimal; 0x-prefixed values must go through bash $(( )).
    local hash stateRoot receiptsRoot transactionsRoot
    local hex_number hex_gas hex_ts
    hash=$(echo "$response" | jq -r '.result.hash // empty')
    stateRoot=$(echo "$response" | jq -r '.result.stateRoot // empty')
    receiptsRoot=$(echo "$response" | jq -r '.result.receiptsRoot // empty')
    transactionsRoot=$(echo "$response" | jq -r '.result.transactionsRoot // empty')
    hex_number=$(echo "$response" | jq -r '.result.number // "0x0"')
    hex_gas=$(echo "$response" | jq -r '.result.gasUsed // "0x0"')
    hex_ts=$(echo "$response" | jq -r '.result.timestamp // "0x0"')

    local number gasUsed timestamp
    number=$(( hex_number )) 2>/dev/null || number=0
    gasUsed=$(( hex_gas )) 2>/dev/null || gasUsed=0
    timestamp=$(( hex_ts )) 2>/dev/null || timestamp=0

    jq -n \
        --argjson number "$number" \
        --arg hash "$hash" \
        --arg stateRoot "$stateRoot" \
        --arg receiptsRoot "$receiptsRoot" \
        --arg transactionsRoot "$transactionsRoot" \
        --argjson gasUsed "$gasUsed" \
        --argjson timestamp "$timestamp" \
        '{number: $number, hash: $hash, stateRoot: $stateRoot, receiptsRoot: $receiptsRoot,
          transactionsRoot: $transactionsRoot, gasUsed: $gasUsed, timestamp: $timestamp}'
}

wait_for_block() {
    local target="$1"
    local elapsed=0
    echo "Waiting for block ${target}..."
    while true; do
        local hex current
        hex=$(curl -s -m 30 --connect-timeout 5 -X POST "${RPC_URL}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -r '.result // "0x0"')
        # bash arithmetic handles 0x prefixed hex natively
        current=$(( hex )) 2>/dev/null || current=0
        [[ "$current" -ge "$target" ]] && break
        sleep 3
        elapsed=$(( elapsed + 3 ))
        if [[ "$elapsed" -ge 600 ]]; then
            echo "ERROR: Timed out waiting for block ${target} (current: ${current})" >&2
            exit 1
        fi
    done
}

# ────────────────────────────────────────────────────────────────────────────
# Capture golden state
# ────────────────────────────────────────────────────────────────────────────

# Wait for chain to pass the last fork + a few blocks for stability
LAST_FORK="${FORK_GIUGLIANO}"
wait_for_block $(( LAST_FORK + 10 ))

echo "Capturing block data at fork boundaries..."

# Capture blocks: each fork-1, fork, fork+1 plus a stable anchor (fork+5)
BLOCKS_JSON=$(jq -n \
    --argjson rio "$FORK_RIO" \
    --argjson madhugiri "$FORK_MADHUGIRI" \
    --argjson madhugiriPro "$FORK_MADHUGIRI_PRO" \
    --argjson dandeli "$FORK_DANDELI" \
    --argjson lisovo "$FORK_LISOVO" \
    --argjson lisovoPro "$FORK_LISOVO_PRO" \
    --argjson giugliano "$FORK_GIUGLIANO" \
    '{
        rio: $rio,
        madhugiri: $madhugiri,
        madhugiriPro: $madhugiriPro,
        dandeli: $dandeli,
        lisovo: $lisovo,
        lisovoPro: $lisovoPro,
        giugliano: $giugliano
    }')

capture_fork_blocks() {
    local fork_name="$1" fork_block="$2"
    [[ "$fork_block" -le 0 ]] && return

    local pre fork post
    pre=$(query_block "$(( fork_block - 1 ))")
    fork=$(query_block "${fork_block}")
    post=$(query_block "$(( fork_block + 1 ))")

    jq -n \
        --arg fork_name "${fork_name}" \
        --argjson fork_block "${fork_block}" \
        --argjson pre "$pre" \
        --argjson at "$fork" \
        --argjson post "$post" \
        '{
            fork_name: $fork_name,
            fork_block: $fork_block,
            "fork-1": $pre,
            "fork":   $at,
            "fork+1": $post
        }'
}

ENTRIES=()
ENTRIES+=("$(capture_fork_blocks "rio"          "${FORK_RIO}")")
ENTRIES+=("$(capture_fork_blocks "madhugiri"    "${FORK_MADHUGIRI}")")
ENTRIES+=("$(capture_fork_blocks "madhugiriPro" "${FORK_MADHUGIRI_PRO}")")
ENTRIES+=("$(capture_fork_blocks "dandeli"      "${FORK_DANDELI}")")
ENTRIES+=("$(capture_fork_blocks "lisovo"       "${FORK_LISOVO}")")
ENTRIES+=("$(capture_fork_blocks "lisovoPro"    "${FORK_LISOVO_PRO}")")
ENTRIES+=("$(capture_fork_blocks "giugliano"    "${FORK_GIUGLIANO}")")

# Filter empty entries and build JSON array
ARRAY="["
FIRST=1
for entry in "${ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue
    [[ "$FIRST" -eq 0 ]] && ARRAY+=","
    ARRAY+="$entry"
    FIRST=0
done
ARRAY+="]"

# Build final JSON
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUTPUT=$(jq -n \
    --arg bor_version "${BOR_VERSION}" \
    --arg generated_at "${GENERATED_AT}" \
    --arg rpc_url "${RPC_URL}" \
    --argjson fork_schedule "${BLOCKS_JSON}" \
    --argjson blocks "${ARRAY}" \
    '{
        bor_version: $bor_version,
        generated_at: $generated_at,
        description: "Block hashes at fork boundaries. Update this file intentionally when a new release changes on-chain state at fork activation blocks.",
        fork_schedule: $fork_schedule,
        blocks: $blocks
    }')

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/state-roots-${BOR_VERSION}.json"
echo "${OUTPUT}" > "${OUTPUT_FILE}"
echo "Written: ${OUTPUT_FILE}"
echo ""
echo "To use this as a regression anchor:"
echo "  git add ${OUTPUT_FILE}"
echo "  git commit -m 'pos: golden state for Bor v${BOR_VERSION}'"
