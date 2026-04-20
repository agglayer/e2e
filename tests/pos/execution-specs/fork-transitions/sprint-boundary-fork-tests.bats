#!/usr/bin/env bats
# bats file_tags=pos,fork-activation,sprint-boundary

# Sprint-Boundary Fork Transition Tests
# =======================================
# Tests fork activation when fork blocks are EXACTLY aligned with sprint boundaries.
#
# Why this matters: When IsSprintStart(fork_block, sprint_length) is true,
# Bor executes both "end of sprint" logic (validator set rotation, span fetch)
# AND "fork activation" logic (new rules, new precompiles) in the SAME block.
# Ordering errors between these two operations can cause:
#   - Wrong producer selected for the first post-fork sprint
#   - Validator set applied with new-fork rules to an old-fork block (or vice versa)
#   - State divergence between nodes that hit the intersection differently
#
# These tests pair with cross-client-state-roots.bats: that test checks stateRoot
# equality; this test checks PRODUCER SELECTION and VALIDATOR SET correctness.
#
# REQUIREMENTS:
#   - Kurtosis enclave deployed from scenarios/pos/fork-transition-sprint-aligned/params.yml
#   - Fork blocks set to sprint boundaries (rio=64, madhugiri=128, ..., giugliano=448)
#   - An Erigon RPC node for cross-client signer verification
#
# RUN: bats tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    export L2_ERIGON_RPC_URL
    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        local erigon_port
        for i in $(seq 1 12); do
            local svc="l2-el-${i}-erigon-heimdall-v2-rpc"
            if erigon_port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                erigon_port="${erigon_port#http://}"; erigon_port="${erigon_port#https://}"
                L2_ERIGON_RPC_URL="http://${erigon_port}"
                echo "Found Erigon at ${svc}: ${L2_ERIGON_RPC_URL}" >&3
                break
            fi
        done
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Default fork blocks for the sprint-aligned scenario
    # Override via env if running with a different devnet config.
    FORK_JAIPUR="${FORK_JAIPUR:-0}"
    FORK_DELHI="${FORK_DELHI:-0}"
    FORK_INDORE="${FORK_INDORE:-0}"
    FORK_AGRA="${FORK_AGRA:-0}"
    FORK_NAPOLI="${FORK_NAPOLI:-0}"
    FORK_AHMEDABAD="${FORK_AHMEDABAD:-0}"
    FORK_BHILAI="${FORK_BHILAI:-0}"
    # Sprint-aligned schedule (all multiples of sprint=16)
    FORK_RIO="${FORK_RIO:-64}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-128}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-192}"
    FORK_DANDELI="${FORK_DANDELI:-256}"
    FORK_LISOVO="${FORK_LISOVO:-320}"
    FORK_LISOVO_PRO="${FORK_LISOVO_PRO:-384}"
    FORK_GIUGLIANO="${FORK_GIUGLIANO:-448}"
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

_block_field_on() {
    local block="$1" field="$2" rpc="$3"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

_block_field() {
    _block_field_on "$1" "$2" "${L2_RPC_URL}"
}

_current_block() {
    cast block-number --rpc-url "${L2_RPC_URL}"
}

_wait_for_block() {
    local target="$1"

    if [[ "$target" -ge 999999999 ]]; then
        skip "Fork not active in this version (target block ${target})"
    fi

    local current
    current=$(_current_block)
    [[ "$current" -ge "$target" ]] && return 0
    local remaining=$(( target - current ))
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
    assert_command_eventually_greater_or_equal \
        "cast block-number --rpc-url ${L2_RPC_URL}" \
        "${target}" "${timeout}" 5
}

# Get the actual block producer for a given block.
# Bor's consensus engine unconditionally sets header.Coinbase = 0x0000...000 in Prepare()
# (consensus/bor/bor.go — rewards are state-sync transfers, not coinbase).
# The miner field in eth_getBlockByNumber is therefore always the zero address.
# bor_getAuthor recovers the signer by ecrecover on the 65-byte seal in header.Extra.
_producer_at() {
    local block="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"bor_getAuthor\",\"params\":[\"${block_hex}\"],\"id\":1}" \
        | jq -r '.result // empty'
}

# Get the bor signers set at a given block hash from Bor RPC.
_signers_at_block() {
    local block="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    local block_hash
    block_hash=$(_block_field "$block" "hash")
    [[ -z "$block_hash" || "$block_hash" == "null" ]] && return 1
    curl -s -m 30 --connect-timeout 5 -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"bor_getSignersAtHash\",\"params\":[\"${block_hash}\"],\"id\":1}" \
        | jq -c '.result // empty'
}

# Assert the parent hash chain is unbroken around a block.
_assert_no_reorg_at() {
    local fork_block="$1"
    local parent_hash
    parent_hash=$(_block_field "$(( fork_block - 1 ))" "hash")
    local reported_parent
    reported_parent=$(_block_field "${fork_block}" "parentHash")

    if [[ "$parent_hash" != "$reported_parent" ]]; then
        echo "REORG at fork block ${fork_block}:" >&2
        echo "  block $(( fork_block - 1 )) hash:        ${parent_hash}" >&2
        echo "  block ${fork_block} parentHash: ${reported_parent}" >&2
        return 1
    fi
    echo "  OK: no reorg at block ${fork_block}" >&3
}

# Assert block hashes match between Bor and Erigon.
_assert_cross_client_agree_at() {
    [[ -z "${L2_ERIGON_RPC_URL:-}" ]] && return 0  # skip if no Erigon
    local block="$1"
    local bor_hash erigon_hash
    bor_hash=$(_block_field_on "${block}" "hash" "${L2_RPC_URL}")
    erigon_hash=$(_block_field_on "${block}" "hash" "${L2_ERIGON_RPC_URL}")
    if [[ -z "$bor_hash" || "$bor_hash" == "null" ]]; then
        echo "  WARN: Bor has no data for block ${block} — block not yet produced?" >&3
        return 0
    fi
    if [[ -z "$erigon_hash" || "$erigon_hash" == "null" ]]; then
        echo "FAIL: Erigon has no data for block ${block} (Bor: ${bor_hash}) — Erigon may be stuck at a fork boundary" >&2
        return 1
    fi
    if [[ "$bor_hash" != "$erigon_hash" ]]; then
        echo "CROSS-CLIENT DIVERGENCE at block ${block}:" >&2
        echo "  Bor:    ${bor_hash}" >&2
        echo "  Erigon: ${erigon_hash}" >&2
        return 1
    fi
    echo "  OK cross-client block ${block}: ${bor_hash}" >&3
}

_require_min_bor() {
    local required="$1"
    local running="${BOR_MIN_VERSION:-}"
    [[ -z "$running" ]] && return 0
    local running_base required_base lower
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    [[ "$lower" == "$required_base" ]] || skip "requires bor >= ${required} (oldest: ${running})"
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=sprint-boundary,fork-transition,no-reorg
@test "sprint-boundary: no reorg at Rio fork (exact sprint boundary)" {
    # Verify fork block is a sprint boundary
    local sprint=16
    local remainder=$(( FORK_RIO % sprint ))
    if [[ "$remainder" -ne 0 ]]; then
        skip "FORK_RIO=${FORK_RIO} is not a sprint boundary (sprint=${sprint})"
    fi

    _wait_for_block $(( FORK_RIO + 2 ))
    _assert_no_reorg_at "${FORK_RIO}"
    _assert_cross_client_agree_at "$(( FORK_RIO - 1 ))"
    _assert_cross_client_agree_at "${FORK_RIO}"
    _assert_cross_client_agree_at "$(( FORK_RIO + 1 ))"
}

# bats test_tags=sprint-boundary,fork-transition,producer-selection
@test "sprint-boundary: producer at fork block matches bor_getSignersAtHash" {
    _wait_for_block $(( FORK_RIO + 1 ))

    local producer signers
    producer=$(_producer_at "${FORK_RIO}")
    signers=$(_signers_at_block "${FORK_RIO}")

    [[ -n "$producer" && "$producer" != "null" ]] || {
        echo "FAIL: could not get producer for block ${FORK_RIO}" >&2
        return 1
    }
    [[ -n "$signers" ]] || {
        echo "FAIL: bor_getSignersAtHash returned empty for block ${FORK_RIO}" >&2
        return 1
    }

    echo "  Block ${FORK_RIO}: producer=${producer}" >&3
    echo "  Block ${FORK_RIO}: signers=${signers}" >&3

    # Producer must appear in the signer set
    echo "$signers" | grep -qi "${producer#0x}" || {
        echo "FAIL: producer ${producer} not in signers ${signers}" >&2
        return 1
    }
}

# bats test_tags=sprint-boundary,fork-transition,no-reorg
@test "sprint-boundary: no reorg at Giugliano fork (sprint+span boundary)" {
    _require_min_bor "2.7.0"
    local sprint=16
    local remainder=$(( FORK_GIUGLIANO % sprint ))
    if [[ "$remainder" -ne 0 ]]; then
        skip "FORK_GIUGLIANO=${FORK_GIUGLIANO} is not a sprint boundary"
    fi

    _wait_for_block $(( FORK_GIUGLIANO + 3 ))
    _assert_no_reorg_at "${FORK_GIUGLIANO}"
    _assert_cross_client_agree_at "$(( FORK_GIUGLIANO - 1 ))"
    _assert_cross_client_agree_at "${FORK_GIUGLIANO}"
    _assert_cross_client_agree_at "$(( FORK_GIUGLIANO + 1 ))"
}

# bats test_tags=sprint-boundary,fork-transition,validator-set
@test "sprint-boundary: validator set is consistent on Bor and Erigon at each sprint-aligned fork" {
    _require_min_bor "2.7.0"
    [[ -z "${L2_ERIGON_RPC_URL:-}" ]] && skip "No Erigon RPC available"

    local last_fork="${FORK_GIUGLIANO}"
    _wait_for_block $(( last_fork + 3 ))

    # For each fork block, check Bor and Erigon agree on the block hash.
    # Equal block hash means equal validator set (it's part of the block header extra data).
    local -a fork_blocks=(
        "${FORK_RIO}" "${FORK_MADHUGIRI}" "${FORK_MADHUGIRI_PRO}"
        "${FORK_DANDELI}" "${FORK_LISOVO}" "${FORK_LISOVO_PRO}" "${FORK_GIUGLIANO}"
    )
    local failed=0
    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 0 ]] && continue
        _assert_cross_client_agree_at "${fb}" || failed=1
        _assert_cross_client_agree_at "$(( fb + 1 ))" || failed=1
    done
    return "$failed"
}

# bats test_tags=sprint-boundary,chain-continuity
@test "sprint-boundary: timestamps strictly increasing across all sprint-aligned fork boundaries" {
    _require_min_bor "2.7.0"
    local last_fork="${FORK_GIUGLIANO}"
    _wait_for_block $(( last_fork + 2 ))

    local -a fork_blocks=(
        "${FORK_RIO}" "${FORK_MADHUGIRI}" "${FORK_MADHUGIRI_PRO}"
        "${FORK_DANDELI}" "${FORK_LISOVO}" "${FORK_LISOVO_PRO}" "${FORK_GIUGLIANO}"
    )
    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 1 ]] && continue
        local ts_before ts_at ts_after raw
        raw=$(_block_field "$(( fb - 1 ))" "timestamp")
        [[ -n "$raw" && "$raw" != "null" ]] || { echo "FAIL: no timestamp for block $(( fb - 1 ))" >&2; return 1; }
        ts_before=$(printf "%d" "$raw")
        raw=$(_block_field "${fb}" "timestamp")
        [[ -n "$raw" && "$raw" != "null" ]] || { echo "FAIL: no timestamp for block ${fb}" >&2; return 1; }
        ts_at=$(printf "%d" "$raw")
        raw=$(_block_field "$(( fb + 1 ))" "timestamp")
        [[ -n "$raw" && "$raw" != "null" ]] || { echo "FAIL: no timestamp for block $(( fb + 1 ))" >&2; return 1; }
        ts_after=$(printf "%d" "$raw")
        [[ "$ts_at" -gt "$ts_before" ]] || { echo "FAIL: timestamp not increasing at fork block ${fb}" >&2; return 1; }
        [[ "$ts_after" -gt "$ts_at" ]] || { echo "FAIL: timestamp not increasing at fork block ${fb}+1" >&2; return 1; }
    done
}
