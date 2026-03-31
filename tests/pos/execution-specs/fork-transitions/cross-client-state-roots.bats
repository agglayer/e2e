#!/usr/bin/env bats
# bats file_tags=pos,fork-activation,cross-client

# Cross-Client State Root Oracle
# ================================
# Verifies that Bor and Erigon agree on the canonical chain at every fork boundary.
#
# For each fork activation block this suite:
#   1. Waits for both clients to advance past the fork (timeout = Erigon stuck at fork)
#   2. Compares block hashes at fork-1, fork, and fork+1 between Bor and Erigon
#      Equal hashes ⟹ equal stateRoot, receiptsRoot, transactionsRoot by construction
#   3. Checks the chain-tip gap between Bor and Erigon stays ≤ 32 blocks
#
# A timeout waiting for Erigon is the primary symptom of a fork activation mismatch
# (e.g. a precompile or opcode activated at different block heights in the two clients).
#
# REQUIREMENTS:
#   - Same kurtosis enclave as parallel-fork-tests (staggered fork activation)
#   - An Erigon RPC node deployed in the enclave (auto-discovered or via L2_ERIGON_RPC_URL)
#   - FORK_* env vars matching the deployed fork schedule
#
# RUN: bats tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    export L2_ERIGON_RPC_URL
    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        echo "Discovering Erigon RPC service in enclave '${ENCLAVE_NAME}'..." >&3
        local erigon_port svc
        for i in $(seq 1 12); do
            svc="l2-el-${i}-erigon-heimdall-v2-rpc"
            if erigon_port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                erigon_port="${erigon_port#http://}"; erigon_port="${erigon_port#https://}"
                L2_ERIGON_RPC_URL="http://${erigon_port}"
                echo "Found Erigon at ${svc}: ${L2_ERIGON_RPC_URL}" >&3
                break
            fi
        done
    fi

    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        echo "WARNING: No Erigon RPC node found — cross-client tests will be skipped." >&3
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

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
    ERIGON_RPC_VERSION="${ERIGON_RPC_VERSION:-}"

    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        skip "No Erigon RPC URL available (no Erigon node in enclave)"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Return the current block number from a given RPC endpoint.
_block_number_on() {
    local rpc="$1"
    cast block-number --rpc-url "$rpc"
}

# Query a specific block from an RPC endpoint and return the requested JSON field.
_block_field_on() {
    local block="$1" field="$2" rpc="$3"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

# Wait for a specific RPC endpoint to reach target block. Timeout scales with distance.
# Stall detection: if the block number does not advance for STALL_LIMIT × 5s, the
# client is considered stuck (e.g. at a fork boundary) and the function returns 1
# immediately rather than burning the full timeout.
_wait_for_block_on() {
    local target="$1" rpc="$2"
    local current
    current=$(_block_number_on "${rpc}" 2>/dev/null || echo 0)
    [[ "$current" -ge "$target" ]] && return 0

    local remaining=$(( target - current ))
    # 3s per block + 5 min buffer, capped at 30 min
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
    # 6 consecutive 5-second polls without progress = 30s stall → stuck
    local STALL_LIMIT=6

    echo "  Waiting for block ${target} on ${rpc} (current: ${current}, timeout: ${timeout}s)..." >&3

    local start_time elapsed last_block stall_count
    start_time=$(date +%s)
    last_block="$current"
    stall_count=0

    while true; do
        elapsed=$(( $(date +%s) - start_time ))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "  Timeout reached waiting for block ${target} on ${rpc}." >&3
            return 1
        fi

        local rpc_ok
        current=$(_block_number_on "${rpc}" 2>/dev/null) && rpc_ok=1 || { rpc_ok=0; current="$last_block"; }
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Block: ${current} / ${target}" >&3
        [[ "$current" -ge "$target" ]] && return 0

        # Only count as a stall when the RPC succeeded but the block didn't advance.
        # Transient RPC failures (network blips) should not trigger the stall detector.
        if [[ "$rpc_ok" -eq 1 ]]; then
            if [[ "$current" -eq "$last_block" ]]; then
                stall_count=$(( stall_count + 1 ))
                if [[ "$stall_count" -ge "$STALL_LIMIT" ]]; then
                    echo "  STUCK: ${rpc} has not advanced from block ${current} for $(( stall_count * 5 ))s — likely stuck at a fork boundary." >&3
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

# Compare block hashes between Bor and Erigon for each block in the list.
# Equal block hash ⟹ equal stateRoot/receiptsRoot/transactionsRoot by construction.
# Prints diagnostic headers on mismatch and returns 1 if any block diverges.
_assert_clients_agree() {
    local -a blocks=("$@")
    local diverged=0

    for block in "${blocks[@]}"; do
        [[ "$block" -le 0 ]] && continue

        local bor_hash erigon_hash
        bor_hash=$(_block_field_on "${block}" "hash" "${L2_RPC_URL}")
        erigon_hash=$(_block_field_on "${block}" "hash" "${L2_ERIGON_RPC_URL}")

        if [[ -z "$bor_hash" || "$bor_hash" == "null" ]]; then
            echo "  WARN: Bor has no data yet for block ${block} — skipping" >&3
            continue
        fi

        if [[ -z "$erigon_hash" || "$erigon_hash" == "null" ]]; then
            echo "  FAIL: Erigon has no data for block ${block} (Bor: ${bor_hash})" >&2
            diverged=1
            continue
        fi

        if [[ "$bor_hash" != "$erigon_hash" ]]; then
            echo "CHAIN DIVERGENCE at block ${block}:" >&2
            echo "  Bor    blockHash: ${bor_hash}" >&2
            echo "  Erigon blockHash: ${erigon_hash}" >&2
            echo "  Bor    stateRoot: $(_block_field_on "${block}" "stateRoot" "${L2_RPC_URL}")" >&2
            echo "  Erigon stateRoot: $(_block_field_on "${block}" "stateRoot" "${L2_ERIGON_RPC_URL}")" >&2
            echo "  Bor    receiptsRoot: $(_block_field_on "${block}" "receiptsRoot" "${L2_RPC_URL}")" >&2
            echo "  Erigon receiptsRoot: $(_block_field_on "${block}" "receiptsRoot" "${L2_ERIGON_RPC_URL}")" >&2
            diverged=1
        else
            echo "  OK block ${block}: ${bor_hash}" >&3
        fi
    done

    return "${diverged}"
}

# Returns 0 if BOR_MIN_VERSION >= required, 1 otherwise. Never calls skip.
# Use in && chains where a skip would abort the entire test.
_version_gte() {
    local required="$1"
    local running="${BOR_MIN_VERSION:-}"
    [[ -z "$running" ]] && return 0
    local running_base required_base lower
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    [[ "$lower" == "$required_base" ]]
}

# Returns 0 if ERIGON_RPC_VERSION >= required, 1 otherwise. Never calls skip.
# Use in && chains where a skip would abort the entire test.
_erigon_gte() {
    local required="$1"
    local running="${ERIGON_RPC_VERSION:-}"
    [[ -z "$running" ]] && return 0
    running="${running#v}"  # strip leading v (e.g. v3.5.0 → 3.5.0)
    [[ ! "$running" =~ ^[0-9]+\.[0-9]+ ]] && return 0  # non-semver (e.g. "latest") — don't gate
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    [[ "$lower" == "$required_base" ]]
}

# Skip if ERIGON_RPC_VERSION is older than the required version.
# Erigon fork support lags bor by roughly one release cycle; use this to skip
# cross-client tests for forks the running Erigon image does not yet implement.
_require_min_erigon() {
    local required="$1"
    local running="${ERIGON_RPC_VERSION:-}"
    [[ -z "$running" ]] && return 0  # unknown version — don't skip
    running="${running#v}"  # strip leading v
    [[ ! "$running" =~ ^[0-9]+\.[0-9]+ ]] && return 0  # non-semver (e.g. "latest") — don't skip
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    if [[ "$lower" != "$required_base" ]]; then
        skip "requires erigon >= ${required} (running: ${ERIGON_RPC_VERSION})"
    fi
}

# Skip if BOR_MIN_VERSION is older than the required version.
_require_min_bor() {
    local required="$1"
    local running="${BOR_MIN_VERSION:-}"
    [[ -z "$running" ]] && return 0  # unknown version — don't skip
    local running_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local required_base
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    if [[ "$lower" != "$required_base" ]]; then
        skip "requires bor >= ${required} (oldest in mix: ${running})"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Tests — one per fork era, safe to run in parallel
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=cross-client,state-root
@test "cross-client: Erigon syncs through Rio and agrees with Bor at fork boundary" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    local target=$(( FORK_RIO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_clients_agree \
        "$(( FORK_RIO - 1 ))" \
        "${FORK_RIO}" \
        "$(( FORK_RIO + 1 ))" \
        "$(( FORK_RIO + 4 ))"
}

# bats test_tags=cross-client,state-root
@test "cross-client: Erigon syncs through Madhugiri forks and agrees with Bor" {
    _require_min_bor "2.5.0"
    [[ "${FORK_MADHUGIRI:-0}" -le 0 ]] && skip "Madhugiri at genesis"

    local target=$(( FORK_MADHUGIRI_PRO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_clients_agree \
        "$(( FORK_MADHUGIRI - 1 ))"   "${FORK_MADHUGIRI}"     "$(( FORK_MADHUGIRI + 1 ))" \
        "$(( FORK_MADHUGIRI_PRO - 1 ))" "${FORK_MADHUGIRI_PRO}" "$(( FORK_MADHUGIRI_PRO + 1 ))"
}

# bats test_tags=cross-client,state-root
@test "cross-client: Erigon syncs through Dandeli→Lisovo→LisovoPro and agrees with Bor" {
    _require_min_bor "2.5.6"
    [[ "${FORK_DANDELI:-0}" -le 0 ]] && skip "Dandeli at genesis"

    # Cap the target at what the running Erigon supports.
    # erigon < 3.5.0 supports up to Dandeli but not Lisovo/LisovoPro.
    local target
    if _erigon_gte "3.5.0"; then
        target=$(( FORK_LISOVO_PRO + 5 ))
    else
        target=$(( FORK_DANDELI + 5 ))
    fi
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    local -a blocks=(
        "$(( FORK_DANDELI - 1 ))" "${FORK_DANDELI}" "$(( FORK_DANDELI + 1 ))"
    )
    if _erigon_gte "3.5.0"; then
        blocks+=(
            "$(( FORK_LISOVO - 1 ))"     "${FORK_LISOVO}"     "$(( FORK_LISOVO + 1 ))"
            "$(( FORK_LISOVO_PRO - 1 ))" "${FORK_LISOVO_PRO}" "$(( FORK_LISOVO_PRO + 1 ))"
        )
    fi
    _assert_clients_agree "${blocks[@]}"
}

# bats test_tags=cross-client,state-root
@test "cross-client: Erigon syncs through Giugliano and agrees with Bor on block hash" {
    _require_min_bor "2.7.0"
    _require_min_erigon "3.5.0"
    [[ "${FORK_GIUGLIANO:-0}" -le 0 ]] && skip "Giugliano at genesis"

    local target=$(( FORK_GIUGLIANO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_clients_agree \
        "$(( FORK_GIUGLIANO - 1 ))" \
        "${FORK_GIUGLIANO}" \
        "$(( FORK_GIUGLIANO + 1 ))" \
        "$(( FORK_GIUGLIANO + 4 ))"
}

# bats test_tags=cross-client,state-root,chain-continuity
@test "cross-client: Bor and Erigon are on the same chain tip (gap ≤ 32 blocks)" {
    # This test measures live chain tips, which is only meaningful when Erigon can
    # sync through all supported forks without stalling. Erigon < 3.5.0 stalls at
    # the Lisovo fork boundary, so the gap will always be large — skip in that case.
    _require_min_erigon "3.5.0"
    # Wait for chain to pass all supported forks
    local last_fork="${FORK_RIO}"
    _version_gte "2.5.0" && last_fork="${FORK_MADHUGIRI_PRO}"
    _version_gte "2.5.6" && last_fork="${FORK_DANDELI}"
    _version_gte "2.6.0" && last_fork="${FORK_LISOVO_PRO}"
    _version_gte "2.7.0" && last_fork="${FORK_GIUGLIANO}"

    local target=$(( last_fork + 10 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    local bor_tip erigon_tip
    bor_tip=$(_block_number_on "${L2_RPC_URL}")
    erigon_tip=$(_block_number_on "${L2_ERIGON_RPC_URL}")
    local gap=$(( bor_tip - erigon_tip ))
    [[ "$gap" -lt 0 ]] && gap=$(( -gap ))

    echo "Bor tip: ${bor_tip}, Erigon tip: ${erigon_tip}, gap: ${gap}" >&3

    if [[ "$gap" -gt 32 ]]; then
        echo "FAIL: chain tip gap ${gap} blocks (Bor: ${bor_tip}, Erigon: ${erigon_tip}) — likely stuck at a fork boundary" >&2
        echo "  Expected gap ≤ 32 (1 sprint). This indicates a fork activation mismatch." >&2
        return 1
    fi

    # Verify they agree on the blocks they share
    local common=$(( erigon_tip < bor_tip ? erigon_tip : bor_tip ))
    _assert_clients_agree "${common}" "$(( common - 1 ))"
}
