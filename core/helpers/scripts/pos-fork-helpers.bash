# Shared helpers for PoS fork-related BATS tests.
#
# Provides common utilities that were previously duplicated across test files:
#   - _bor_version / _ver_gte / _require_min_bor  — version detection and gating
#   - _wait_for_block_on                           — block waiter with stall detection
#   - _discover_erigon_rpc / _discover_bor_nodes   — kurtosis service discovery
#   - _setup_fork_env                              — fork schedule env var defaults
#   - _is_mixed_kzg / _skip_if_mixed_kzg           — KZG precompile divergence detection
#
# Usage: load this file in setup() or setup_file() after pos_setup:
#   load "path/to/core/helpers/scripts/pos-fork-helpers.bash"

# ─────────────────────────────────────────────────────────────────────────────
# Version detection
# ─────────────────────────────────────────────────────────────────────────────

# Query the bor version from the L2 RPC node. Caches in BOR_VERSION.
_bor_version() {
    if [[ -n "${BOR_VERSION:-}" ]]; then
        echo "$BOR_VERSION"
        return
    fi
    local result
    result=$(curl -s -m 10 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null || true)
    local raw
    raw=$(echo "$result" | jq -r '.result // empty' 2>/dev/null || true)
    BOR_VERSION=$(echo "$raw" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]*)?' | head -1 | sed 's/^v//')
    if [[ -z "$BOR_VERSION" ]]; then
        BOR_VERSION="unknown"
    fi
    echo "$BOR_VERSION"
}

# Returns 0 if version $1 >= $2, 1 otherwise. Pure comparison, no skip.
_ver_gte() {
    local running="$1" required="$2"
    local lower
    lower=$(printf '%s\n%s' "$running" "$required" | sort -V | head -1)
    [[ "$lower" == "$required" ]]
}

# Skip the current test if the minimum bor version in the mix is older than required.
# Uses BOR_MIN_VERSION (from CI) or falls back to _bor_version (RPC query).
_require_min_bor() {
    local required="$1"
    local running="${BOR_MIN_VERSION:-$(_bor_version)}"
    [[ "$running" == "unknown" ]] && return 0
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    if [[ "$lower" != "$required_base" ]]; then
        skip "requires bor >= ${required} (oldest in mix: ${running})"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Block number helpers
# ─────────────────────────────────────────────────────────────────────────────

# Return the current block number from a given RPC endpoint (decimal).
_block_number_on() {
    local rpc="$1"
    local hex
    hex=$(curl -s -m 15 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null || true)
    [[ -z "$hex" || "$hex" == "null" ]] && return 1
    [[ "$hex" =~ ^0x[0-9a-fA-F]{1,16}$ ]] || return 1
    printf '%d' "$hex"
}

# Wait for a specific RPC endpoint to reach a target block.
# Includes stall detection: if block doesn't advance for STALL_LIMIT * 5s, returns 1.
_wait_for_block_on() {
    local target="$1" rpc="${2:-$L2_RPC_URL}" label="${3:-${2:-L2_RPC_URL}}"
    local current
    current=$(_block_number_on "${rpc}" 2>/dev/null || echo 0)
    [[ "$current" -ge "$target" ]] && return 0

    local remaining=$(( target - current ))
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
    local STALL_LIMIT=24

    echo "  Waiting for block ${target} on ${label} (current: ${current}, timeout: ${timeout}s)..." >&3

    local start_time elapsed last_block stall_count
    start_time=$(date +%s)
    last_block="$current"
    stall_count=0

    while true; do
        elapsed=$(( $(date +%s) - start_time ))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "  TIMEOUT waiting for block ${target} on ${label} (stuck at ${current})" >&2
            return 1
        fi

        local rpc_ok
        current=$(_block_number_on "${rpc}" 2>/dev/null) && rpc_ok=1 || { rpc_ok=0; current="$last_block"; }
        [[ "$current" -ge "$target" ]] && return 0

        if [[ "$rpc_ok" -eq 1 ]]; then
            if [[ "$current" -eq "$last_block" ]]; then
                stall_count=$(( stall_count + 1 ))
                if [[ "$stall_count" -ge "$STALL_LIMIT" ]]; then
                    echo "  STUCK: ${label} has not advanced from block ${current} for $(( stall_count * 5 ))s" >&2
                    return 1
                fi
            else
                stall_count=0
            fi
        fi
        last_block="$current"
        sleep 5
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Service discovery
# ─────────────────────────────────────────────────────────────────────────────

# Discover erigon RPC URL from kurtosis enclave. Sets L2_ERIGON_RPC_URL.
# Returns 0 if found, 1 if not.
_discover_erigon_rpc() {
    if [[ -n "${L2_ERIGON_RPC_URL:-}" ]]; then
        return 0
    fi
    local erigon_port svc
    for i in $(seq 1 12); do
        svc="l2-el-${i}-erigon-heimdall-v2-rpc"
        if erigon_port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
            erigon_port="${erigon_port#http://}"; erigon_port="${erigon_port#https://}"
            L2_ERIGON_RPC_URL="http://${erigon_port}"
            echo "Found Erigon at ${svc}: ${L2_ERIGON_RPC_URL}" >&3
            return 0
        fi
    done
    return 1
}

# Discover all bor RPC endpoints in the enclave.
# Writes URL and label arrays to the specified BATS_FILE_TMPDIR files.
# Args: $1 = urls output file, $2 = labels output file
_discover_bor_nodes() {
    local urls_file="${1:-${BATS_FILE_TMPDIR}/bor_rpc_urls}"
    local labels_file="${2:-${BATS_FILE_TMPDIR}/bor_rpc_labels}"
    : > "${urls_file}"
    : > "${labels_file}"
    local count=0
    for i in $(seq 1 12); do
        for role in validator rpc; do
            local svc="l2-el-${i}-bor-heimdall-v2-${role}"
            local port
            if port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                port="${port#http://}"; port="${port#https://}"
                echo "http://${port}" >> "${urls_file}"
                echo "${svc}" >> "${labels_file}"
                count=$(( count + 1 ))
            fi
        done
    done
    echo "Discovered ${count} Bor node(s)" >&3
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Fork environment
# ─────────────────────────────────────────────────────────────────────────────

# Set fork env var defaults matching the kurtosis-pos staggered schedule.
_setup_fork_env() {
    FORK_JAIPUR="${FORK_JAIPUR:-0}"
    FORK_DELHI="${FORK_DELHI:-0}"
    FORK_INDORE="${FORK_INDORE:-0}"
    FORK_AGRA="${FORK_AGRA:-0}"
    FORK_NAPOLI="${FORK_NAPOLI:-0}"
    FORK_AHMEDABAD="${FORK_AHMEDABAD:-0}"
    FORK_BHILAI="${FORK_BHILAI:-0}"
    FORK_RIO="${FORK_RIO:-256}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-320}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-384}"
    FORK_DANDELI="${FORK_DANDELI:-448}"
    FORK_LISOVO="${FORK_LISOVO:-512}"
    FORK_LISOVO_PRO="${FORK_LISOVO_PRO:-576}"
    FORK_GIUGLIANO="${FORK_GIUGLIANO:-640}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Historical state availability
# ─────────────────────────────────────────────────────────────────────────────

# Check if historical state is queryable at a specific block number.
# Bor nodes with pruning enabled cannot serve eth_call/eth_getCode for blocks
# older than the retention window (~128 blocks). This helper uses a lightweight
# eth_getBalance probe on the zero address to detect whether state is available.
# Returns 0 if state is available, 1 if pruned/unavailable.
_state_available_at() {
    local block="$1" rpc="${2:-$L2_RPC_URL}"
    local result
    result=$(cast balance "0x0000000000000000000000000000000000000000" \
        --rpc-url "$rpc" --block "$block" 2>/dev/null) && [[ -n "$result" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Mixed-version KZG detection
# ─────────────────────────────────────────────────────────────────────────────

# Detect mixed-version KZG precompile divergence: bor v2.7.0 backported the
# KZG point-evaluation precompile (0x0a) to Madhugiri, but older versions only
# have it from Lisovo onwards.
_is_mixed_kzg() {
    local min="${BOR_MIN_VERSION:-}" max="${BOR_MAX_VERSION:-}"
    [[ -z "$min" || -z "$max" ]] && return 1
    local min_base max_base
    min_base=$(echo "$min" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    max_base=$(echo "$max" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    _ver_gte "$max_base" "2.7.0" && ! _ver_gte "$min_base" "2.7.0"
}

_skip_if_mixed_kzg() {
    _is_mixed_kzg && skip "mixed KZG precompile divergence (${BOR_MIN_VERSION} vs ${BOR_MAX_VERSION}) — older node may be stuck"
    return 0
}
