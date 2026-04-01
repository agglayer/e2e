#!/usr/bin/env bats
# bats file_tags=pos,fork-activation,state-consistency,regression

# Fork-Boundary State Consistency Tests
# =======================================
# Verifies that all Bor nodes in the devnet agree on block hashes at every
# fork activation boundary.
#
# How it works:
#   1. Discovers all Bor RPC endpoints in the kurtosis enclave
#   2. Waits for all nodes to advance past each fork boundary
#   3. Compares block hashes at fork-1, fork, fork+1 across all nodes
#   4. Equal blockHash ⟹ equal stateRoot, receiptsRoot, transactionsRoot
#
# This catches:
#   - Cross-version state divergence (different Bor versions produce
#     different state at the same fork boundary)
#   - Fork activation bugs (wrong block height, missing precompile)
#   - State transition regressions introduced in new releases
#
# Fully self-contained: no pre-committed reference files, no manual script
# runs. Verifies consensus directly across the running devnet nodes.
#
# REQUIREMENTS:
#   - Kurtosis enclave deployed with the fork-transition devnet
#   - FORK_* env vars matching the deployed fork schedule
#   - BOR_MIN_VERSION env var (for version gating)
#
# RUN: bats tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Discover all Bor RPC endpoints in the enclave (validators + RPCs)
    local urls=() labels=()
    for i in $(seq 1 12); do
        for role in validator rpc; do
            local svc="l2-el-${i}-bor-heimdall-v2-${role}"
            local port
            if port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                port="${port#http://}"; port="${port#https://}"
                urls+=("http://${port}")
                labels+=("${svc}")
            fi
        done
    done

    # Persist for per-test setup (bash arrays can't be exported across processes)
    : > "${BATS_FILE_TMPDIR}/bor_rpc_urls"
    : > "${BATS_FILE_TMPDIR}/bor_rpc_labels"
    for idx in "${!urls[@]}"; do
        echo "${urls[$idx]}" >> "${BATS_FILE_TMPDIR}/bor_rpc_urls"
        echo "${labels[$idx]}" >> "${BATS_FILE_TMPDIR}/bor_rpc_labels"
    done

    echo "Discovered ${#urls[@]} Bor node(s): ${labels[*]}" >&3
    if [[ ${#urls[@]} -lt 2 ]]; then
        echo "WARNING: Need >=2 Bor nodes for cross-node consistency checks" >&3
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Load discovered Bor endpoints
    mapfile -t BOR_RPC_URLS < "${BATS_FILE_TMPDIR}/bor_rpc_urls"
    mapfile -t BOR_RPC_LABELS < "${BATS_FILE_TMPDIR}/bor_rpc_labels"

    [[ ${#BOR_RPC_URLS[@]} -ge 1 ]] || skip "No Bor RPC endpoints discovered in enclave"

    # Fork schedule from env vars (matches CI)
    FORK_RIO="${FORK_RIO:-256}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-320}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-384}"
    FORK_DANDELI="${FORK_DANDELI:-448}"
    FORK_LISOVO="${FORK_LISOVO:-512}"
    FORK_LISOVO_PRO="${FORK_LISOVO_PRO:-576}"
    FORK_GIUGLIANO="${FORK_GIUGLIANO:-640}"
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Query a block field from a specific RPC endpoint.
_block_field_on() {
    local block="$1" field="$2" rpc="$3"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

# Return the current block number from a given RPC endpoint.
_block_number_on() {
    local rpc="$1"
    cast block-number --rpc-url "$rpc"
}

# Wait for a specific RPC endpoint to reach target block.
# Includes stall detection: if block doesn't advance for 6 x 5s = 30s, returns 1.
_wait_for_block_on() {
    local target="$1" rpc="$2" label="${3:-$2}"
    local current
    current=$(_block_number_on "${rpc}" 2>/dev/null || echo 0)
    [[ "$current" -ge "$target" ]] && return 0

    local remaining=$(( target - current ))
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
    local STALL_LIMIT=6

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

        # Only count stalls when RPC succeeded but block didn't advance
        if [[ "$rpc_ok" -eq 1 ]]; then
            if [[ "$current" -eq "$last_block" ]]; then
                stall_count=$(( stall_count + 1 ))
                if [[ "$stall_count" -ge "$STALL_LIMIT" ]]; then
                    echo "  STUCK: ${label} has not advanced from block ${current} for $(( stall_count * 5 ))s — likely stuck at a fork boundary" >&2
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

# Returns 0 if version $1 >= $2, 1 otherwise. Does not call skip.
_ver_gte() {
    local running="$1" required="$2"
    local lower
    lower=$(printf '%s\n%s' "$running" "$required" | sort -V | head -1)
    [[ "$lower" == "$required" ]]
}

# Skip if BOR_MIN_VERSION is older than the required version.
_require_min_bor() {
    local required="$1"
    local running="${BOR_MIN_VERSION:-}"
    [[ -z "$running" ]] && return 0  # unknown version — don't skip
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    if [[ "$lower" != "$required_base" ]]; then
        skip "requires bor >= ${required} (oldest in mix: ${running})"
    fi
}

# Assert all discovered Bor nodes agree on block hashes at a fork boundary.
# Checks fork-1, fork, and fork+1 across every node.
_assert_all_nodes_agree_at_fork() {
    local fork_name="$1" fork_block="$2"
    [[ "$fork_block" -le 0 ]] && skip "${fork_name} fork is at genesis (block 0)"

    local target=$(( fork_block + 3 ))

    # Wait for all nodes to reach past the fork
    for idx in "${!BOR_RPC_URLS[@]}"; do
        _wait_for_block_on "${target}" "${BOR_RPC_URLS[$idx]}" "${BOR_RPC_LABELS[$idx]}" || {
            echo "FAIL: ${BOR_RPC_LABELS[$idx]} could not reach block ${target}" >&2
            return 1
        }
    done

    local diverged=0
    local check_blocks=("$(( fork_block - 1 ))" "${fork_block}" "$(( fork_block + 1 ))")
    local block_labels=("fork-1" "fork" "fork+1")

    for bi in "${!check_blocks[@]}"; do
        local block="${check_blocks[$bi]}"
        local label="${block_labels[$bi]}"
        local ref_hash="" ref_idx=0

        for idx in "${!BOR_RPC_URLS[@]}"; do
            local hash
            hash=$(_block_field_on "${block}" "hash" "${BOR_RPC_URLS[$idx]}")

            if [[ -z "$hash" || "$hash" == "null" ]]; then
                echo "  WARN: ${BOR_RPC_LABELS[$idx]} returned no data for block ${block}" >&3
                continue
            fi

            # Validate block has a non-empty state root (structural sanity check)
            if [[ "$idx" -eq 0 ]]; then
                local state_root
                state_root=$(_block_field_on "${block}" "stateRoot" "${BOR_RPC_URLS[$idx]}")
                if [[ -z "$state_root" || "$state_root" == "null" || "$state_root" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
                    echo "  WARN: block ${block} has empty stateRoot on ${BOR_RPC_LABELS[$idx]}" >&3
                fi
            fi

            if [[ -z "$ref_hash" ]]; then
                ref_hash="$hash"
                ref_idx="$idx"
                continue
            fi

            if [[ "$hash" != "$ref_hash" ]]; then
                echo "DIVERGENCE at ${fork_name} ${label} (block ${block}):" >&2
                echo "  ${BOR_RPC_LABELS[$ref_idx]}: ${ref_hash}" >&2
                echo "  ${BOR_RPC_LABELS[$idx]}: ${hash}" >&2
                echo "  stateRoot (${BOR_RPC_LABELS[$ref_idx]}): $(_block_field_on "${block}" "stateRoot" "${BOR_RPC_URLS[$ref_idx]}")" >&2
                echo "  stateRoot (${BOR_RPC_LABELS[$idx]}): $(_block_field_on "${block}" "stateRoot" "${BOR_RPC_URLS[$idx]}")" >&2
                diverged=1
            fi
        done

        if [[ "$diverged" -eq 0 && -n "$ref_hash" ]]; then
            echo "  OK ${fork_name} ${label} (block ${block}): ${ref_hash} — ${#BOR_RPC_URLS[@]} node(s) agree" >&3
        fi
    done

    [[ "$diverged" -eq 0 ]] || {
        echo "" >&2
        echo "State divergence detected at ${fork_name} fork boundary." >&2
        echo "This indicates different Bor versions/nodes produce different state at block ${fork_block}." >&2
        echo "Investigate: compare genesis config, fork schedule, and state transitions." >&2
        return 1
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=state-consistency,health
@test "state-consistency: all Bor nodes are reachable and producing blocks" {
    for idx in "${!BOR_RPC_URLS[@]}"; do
        local block
        block=$(_block_number_on "${BOR_RPC_URLS[$idx]}" 2>/dev/null || echo "")
        [[ -n "$block" && "$block" -gt 0 ]] || {
            echo "FAIL: ${BOR_RPC_LABELS[$idx]} is not reachable or at block 0" >&2
            return 1
        }
        echo "  ${BOR_RPC_LABELS[$idx]}: block ${block}" >&3
    done
    echo "  All ${#BOR_RPC_URLS[@]} Bor nodes are healthy" >&3
}

# bats test_tags=state-consistency,liveness
@test "state-consistency: devnet has advanced past the last supported fork" {
    # Determine the highest fork block supported by the minimum bor version
    local last_fork="${FORK_RIO}"
    local running="${BOR_MIN_VERSION:-}"
    if [[ -n "$running" ]]; then
        local base
        base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
        _ver_gte "$base" "2.5.0" && last_fork="${FORK_MADHUGIRI_PRO}"
        _ver_gte "$base" "2.5.6" && last_fork="${FORK_DANDELI}"
        _ver_gte "$base" "2.6.0" && last_fork="${FORK_LISOVO_PRO}"
        _ver_gte "$base" "2.7.0" && last_fork="${FORK_GIUGLIANO}"
    fi

    local target=$(( last_fork + 5 ))
    echo "  Waiting for all nodes to reach block ${target} (last fork: ${last_fork})..." >&3

    for idx in "${!BOR_RPC_URLS[@]}"; do
        _wait_for_block_on "${target}" "${BOR_RPC_URLS[$idx]}" "${BOR_RPC_LABELS[$idx]}" || {
            echo "FAIL: ${BOR_RPC_LABELS[$idx]} could not reach block ${target}" >&2
            return 1
        }
    done
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at Rio fork boundary" {
    _assert_all_nodes_agree_at_fork "rio" "${FORK_RIO}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at Madhugiri fork boundary" {
    _require_min_bor "2.5.0"
    _assert_all_nodes_agree_at_fork "madhugiri" "${FORK_MADHUGIRI}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at MadhugiriPro fork boundary" {
    _require_min_bor "2.5.0"
    _assert_all_nodes_agree_at_fork "madhugiriPro" "${FORK_MADHUGIRI_PRO}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at Dandeli fork boundary" {
    _require_min_bor "2.5.6"
    _assert_all_nodes_agree_at_fork "dandeli" "${FORK_DANDELI}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at Lisovo fork boundary" {
    _require_min_bor "2.6.0"
    _assert_all_nodes_agree_at_fork "lisovo" "${FORK_LISOVO}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at LisovoPro fork boundary" {
    _require_min_bor "2.6.0"
    _assert_all_nodes_agree_at_fork "lisovoPro" "${FORK_LISOVO_PRO}"
}

# bats test_tags=state-consistency,fork-transition
@test "state-consistency: all nodes agree on block hashes at Giugliano fork boundary" {
    _require_min_bor "2.7.0"
    _assert_all_nodes_agree_at_fork "giugliano" "${FORK_GIUGLIANO}"
}

# bats test_tags=state-consistency,fork-transition,sweep
@test "state-consistency: all supported fork boundaries pass cross-node comparison" {
    local running="${BOR_MIN_VERSION:-}"
    local base=""
    [[ -n "$running" ]] && base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')

    local total=0 passed=0 failed=0

    # Build list of forks to check based on version
    local -a fork_names=("rio")
    local -a fork_blocks=("${FORK_RIO}")

    if [[ -z "$base" ]] || _ver_gte "$base" "2.5.0"; then
        fork_names+=("madhugiri" "madhugiriPro")
        fork_blocks+=("${FORK_MADHUGIRI}" "${FORK_MADHUGIRI_PRO}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.5.6"; then
        fork_names+=("dandeli")
        fork_blocks+=("${FORK_DANDELI}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.6.0"; then
        fork_names+=("lisovo" "lisovoPro")
        fork_blocks+=("${FORK_LISOVO}" "${FORK_LISOVO_PRO}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.7.0"; then
        fork_names+=("giugliano")
        fork_blocks+=("${FORK_GIUGLIANO}")
    fi

    # Wait for all nodes to pass the last fork
    local last_fork="${fork_blocks[-1]}"
    local target=$(( last_fork + 5 ))
    for idx in "${!BOR_RPC_URLS[@]}"; do
        _wait_for_block_on "${target}" "${BOR_RPC_URLS[$idx]}" "${BOR_RPC_LABELS[$idx]}" || {
            echo "FAIL: ${BOR_RPC_LABELS[$idx]} could not reach block ${target}" >&2
            return 1
        }
    done

    # Check each fork
    for fi_idx in "${!fork_names[@]}"; do
        local fname="${fork_names[$fi_idx]}"
        local fblock="${fork_blocks[$fi_idx]}"
        [[ "$fblock" -le 0 ]] && continue
        (( total++ )) || true

        if _assert_all_nodes_agree_at_fork "$fname" "$fblock"; then
            (( passed++ )) || true
        else
            (( failed++ )) || true
        fi
    done

    echo "  Cross-node state check: ${passed}/${total} forks consistent, ${failed} diverged" >&3

    [[ "$failed" -eq 0 ]] || {
        echo "" >&2
        echo "SUMMARY: ${failed} fork(s) showed state divergence across nodes." >&2
        echo "Review the per-fork test output above for details." >&2
        return 1
    }
}
