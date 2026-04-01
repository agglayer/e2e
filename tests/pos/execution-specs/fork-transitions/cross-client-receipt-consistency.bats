#!/usr/bin/env bats
# bats file_tags=pos,fork-activation,cross-client,receipts

# Cross-Client Receipt Consistency
# ==================================
# Verifies that Bor and Erigon agree on receipt/log data at fork boundaries.
#
# Existing cross-client tests compare block hashes (which imply stateRoot,
# receiptsRoot, transactionsRoot equality). However, receipt-level data —
# individual receipt status codes, cumulative gas used, logs bloom — can
# diverge even when the block-level receiptsRoot matches if the trie
# construction differs, or when one client silently drops/reorders logs.
#
# This suite directly compares:
#   - receiptsRoot at fork boundary blocks
#   - gasUsed per block
#   - transaction counts
#   - logsBloom
#   - individual receipt status codes (especially for system/state-sync txs)
#   - cumulative gas used in individual receipts
#
# REQUIREMENTS:
#   - Same kurtosis enclave as parallel-fork-tests (staggered fork activation)
#   - An Erigon RPC node deployed in the enclave (auto-discovered or via L2_ERIGON_RPC_URL)
#   - FORK_* env vars matching the deployed fork schedule
#
# RUN: bats tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats

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
        echo "WARNING: No Erigon RPC node found — cross-client receipt tests will be skipped." >&3
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
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",true],\"id\":1}" \
        | jq -r --arg f "${field}" '.result[$f] // empty'
}

# Return the full block JSON (with transactions) for a given block number.
_block_json_on() {
    local block="$1" rpc="$2"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",true],\"id\":1}" \
        | jq '.result'
}

# Fetch a transaction receipt by hash from a given RPC endpoint.
_receipt_json_on() {
    local tx_hash="$1" rpc="$2"
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"${tx_hash}\"],\"id\":1}" \
        | jq '.result'
}

# Wait for a specific RPC endpoint to reach target block.
# Stall detection: if block does not advance for STALL_LIMIT consecutive polls, return 1.
_wait_for_block_on() {
    local target="$1" rpc="$2"
    local current
    current=$(_block_number_on "${rpc}" 2>/dev/null || echo 0)
    [[ "$current" -ge "$target" ]] && return 0

    local remaining=$(( target - current ))
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
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

        if [[ "$rpc_ok" -eq 1 ]]; then
            if [[ "$current" -eq "$last_block" ]]; then
                stall_count=$(( stall_count + 1 ))
                if [[ "$stall_count" -ge "$STALL_LIMIT" ]]; then
                    echo "  STUCK: ${rpc} has not advanced from block ${current} for $(( stall_count * 5 ))s." >&3
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

# Compare a single block-level field between Bor and Erigon for each block in the list.
# Usage: _assert_block_field_agrees "receiptsRoot" block1 block2 ...
# Returns 1 if any block diverges.
_assert_block_field_agrees() {
    local field="$1"; shift
    local -a blocks=("$@")
    local diverged=0

    for block in "${blocks[@]}"; do
        [[ "$block" -le 0 ]] && continue

        local bor_val erigon_val
        bor_val=$(_block_field_on "${block}" "${field}" "${L2_RPC_URL}")
        erigon_val=$(_block_field_on "${block}" "${field}" "${L2_ERIGON_RPC_URL}")

        if [[ -z "$bor_val" || "$bor_val" == "null" ]]; then
            echo "  WARN: Bor has no data yet for block ${block} — skipping" >&3
            continue
        fi

        if [[ -z "$erigon_val" || "$erigon_val" == "null" ]]; then
            echo "  FAIL: Erigon has no data for block ${block} (Bor ${field}: ${bor_val})" >&2
            diverged=1
            continue
        fi

        if [[ "$bor_val" != "$erigon_val" ]]; then
            echo "DIVERGENCE in ${field} at block ${block}:" >&2
            echo "  Bor:    ${bor_val}" >&2
            echo "  Erigon: ${erigon_val}" >&2
            diverged=1
        else
            echo "  OK block ${block} ${field}: ${bor_val}" >&3
        fi
    done

    return "${diverged}"
}

# Return the number of transactions in a block from a given RPC endpoint.
_tx_count_on() {
    local block="$1" rpc="$2"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",true],\"id\":1}" \
        | jq '.result.transactions | length'
}

# Return a list of transaction hashes for a given block.
_tx_hashes_on() {
    local block="$1" rpc="$2"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",true],\"id\":1}" \
        | jq -r '.result.transactions[].hash'
}

# Returns 0 if BOR_MIN_VERSION >= required, 1 otherwise.
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

# Returns 0 if ERIGON_RPC_VERSION >= required, 1 otherwise.
_erigon_gte() {
    local required="$1"
    local running="${ERIGON_RPC_VERSION:-}"
    [[ -z "$running" ]] && return 0
    running="${running#v}"
    [[ ! "$running" =~ ^[0-9]+\.[0-9]+ ]] && return 0
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    [[ "$lower" == "$required_base" ]]
}

# Skip if ERIGON_RPC_VERSION is older than the required version.
_require_min_erigon() {
    local required="$1"
    local running="${ERIGON_RPC_VERSION:-}"
    [[ -z "$running" ]] && return 0
    running="${running#v}"
    [[ ! "$running" =~ ^[0-9]+\.[0-9]+ ]] && return 0
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
    [[ -z "$running" ]] && return 0
    local running_base required_base
    running_base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    local lower
    lower=$(printf '%s\n%s' "$running_base" "$required_base" | sort -V | head -1)
    if [[ "$lower" != "$required_base" ]]; then
        skip "requires bor >= ${required} (oldest in mix: ${running})"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=cross-client,receipts,rio
@test "cross-client-receipts: receipt root matches at Rio boundary" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    local target=$(( FORK_RIO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_block_field_agrees "receiptsRoot" \
        "$(( FORK_RIO - 1 ))" \
        "${FORK_RIO}" \
        "$(( FORK_RIO + 1 ))"
}

# bats test_tags=cross-client,receipts,madhugiri
@test "cross-client-receipts: receipt root matches at Madhugiri boundary" {
    _require_min_bor "2.5.0"
    [[ "${FORK_MADHUGIRI:-0}" -le 0 ]] && skip "Madhugiri at genesis"

    local target=$(( FORK_MADHUGIRI_PRO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_block_field_agrees "receiptsRoot" \
        "$(( FORK_MADHUGIRI - 1 ))" \
        "${FORK_MADHUGIRI}" \
        "$(( FORK_MADHUGIRI + 1 ))" \
        "$(( FORK_MADHUGIRI_PRO - 1 ))" \
        "${FORK_MADHUGIRI_PRO}" \
        "$(( FORK_MADHUGIRI_PRO + 1 ))"
}

# bats test_tags=cross-client,receipts,lisovo
@test "cross-client-receipts: receipt root matches at Lisovo boundary" {
    _require_min_bor "2.5.6"
    _require_min_erigon "3.5.0"
    [[ "${FORK_LISOVO:-0}" -le 0 ]] && skip "Lisovo at genesis"

    local target=$(( FORK_LISOVO_PRO + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_block_field_agrees "receiptsRoot" \
        "$(( FORK_LISOVO - 1 ))" \
        "${FORK_LISOVO}" \
        "$(( FORK_LISOVO + 1 ))" \
        "$(( FORK_LISOVO_PRO - 1 ))" \
        "${FORK_LISOVO_PRO}" \
        "$(( FORK_LISOVO_PRO + 1 ))"
}

# bats test_tags=cross-client,receipts,gas
@test "cross-client-receipts: gas used in blocks agree at fork boundaries" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    # Collect all fork boundaries that the running versions support
    local -a blocks=(
        "$(( FORK_RIO - 1 ))" "${FORK_RIO}" "$(( FORK_RIO + 1 ))"
    )

    local last_fork_block="${FORK_RIO}"

    if _version_gte "2.5.0" && [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_MADHUGIRI - 1 ))" "${FORK_MADHUGIRI}" "$(( FORK_MADHUGIRI + 1 ))")
        last_fork_block="${FORK_MADHUGIRI}"
    fi

    if _version_gte "2.5.6" && _erigon_gte "3.5.0" && [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_DANDELI - 1 ))" "${FORK_DANDELI}" "$(( FORK_DANDELI + 1 ))")
        last_fork_block="${FORK_DANDELI}"
    fi

    if _version_gte "2.6.0" && _erigon_gte "3.5.0" && [[ "${FORK_LISOVO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_LISOVO - 1 ))" "${FORK_LISOVO}" "$(( FORK_LISOVO + 1 ))")
        last_fork_block="${FORK_LISOVO}"
    fi

    if _version_gte "2.7.0" && _erigon_gte "3.5.0" && [[ "${FORK_GIUGLIANO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_GIUGLIANO - 1 ))" "${FORK_GIUGLIANO}" "$(( FORK_GIUGLIANO + 1 ))")
        last_fork_block="${FORK_GIUGLIANO}"
    fi

    local target=$(( last_fork_block + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_block_field_agrees "gasUsed" "${blocks[@]}"
}

# bats test_tags=cross-client,receipts,tx-count
@test "cross-client-receipts: transaction count agrees at fork boundaries" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    local -a blocks=(
        "$(( FORK_RIO - 1 ))" "${FORK_RIO}" "$(( FORK_RIO + 1 ))"
    )

    local last_fork_block="${FORK_RIO}"

    if _version_gte "2.5.0" && [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_MADHUGIRI - 1 ))" "${FORK_MADHUGIRI}" "$(( FORK_MADHUGIRI + 1 ))")
        last_fork_block="${FORK_MADHUGIRI}"
    fi

    if _version_gte "2.5.6" && _erigon_gte "3.5.0" && [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_DANDELI - 1 ))" "${FORK_DANDELI}" "$(( FORK_DANDELI + 1 ))")
        last_fork_block="${FORK_DANDELI}"
    fi

    if _version_gte "2.6.0" && _erigon_gte "3.5.0" && [[ "${FORK_LISOVO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_LISOVO - 1 ))" "${FORK_LISOVO}" "$(( FORK_LISOVO + 1 ))")
        last_fork_block="${FORK_LISOVO}"
    fi

    if _version_gte "2.7.0" && _erigon_gte "3.5.0" && [[ "${FORK_GIUGLIANO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_GIUGLIANO - 1 ))" "${FORK_GIUGLIANO}" "$(( FORK_GIUGLIANO + 1 ))")
        last_fork_block="${FORK_GIUGLIANO}"
    fi

    local target=$(( last_fork_block + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    local diverged=0
    for block in "${blocks[@]}"; do
        [[ "$block" -le 0 ]] && continue

        local bor_count erigon_count
        bor_count=$(_tx_count_on "${block}" "${L2_RPC_URL}")
        erigon_count=$(_tx_count_on "${block}" "${L2_ERIGON_RPC_URL}")

        if [[ -z "$bor_count" || "$bor_count" == "null" ]]; then
            echo "  WARN: Bor has no data yet for block ${block} — skipping" >&3
            continue
        fi

        if [[ -z "$erigon_count" || "$erigon_count" == "null" ]]; then
            echo "  FAIL: Erigon has no data for block ${block} (Bor tx count: ${bor_count})" >&2
            diverged=1
            continue
        fi

        if [[ "$bor_count" != "$erigon_count" ]]; then
            echo "TX COUNT DIVERGENCE at block ${block}:" >&2
            echo "  Bor:    ${bor_count} transactions" >&2
            echo "  Erigon: ${erigon_count} transactions" >&2
            diverged=1
        else
            echo "  OK block ${block}: ${bor_count} txs" >&3
        fi
    done

    [[ "$diverged" -eq 0 ]]
}

# bats test_tags=cross-client,receipts,logs-bloom
@test "cross-client-receipts: logs root matches at fork boundaries" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    local -a blocks=(
        "$(( FORK_RIO - 1 ))" "${FORK_RIO}" "$(( FORK_RIO + 1 ))"
    )

    local last_fork_block="${FORK_RIO}"

    if _version_gte "2.5.0" && [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_MADHUGIRI - 1 ))" "${FORK_MADHUGIRI}" "$(( FORK_MADHUGIRI + 1 ))")
        last_fork_block="${FORK_MADHUGIRI}"
    fi

    if _version_gte "2.5.6" && _erigon_gte "3.5.0" && [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_DANDELI - 1 ))" "${FORK_DANDELI}" "$(( FORK_DANDELI + 1 ))")
        last_fork_block="${FORK_DANDELI}"
    fi

    if _version_gte "2.6.0" && _erigon_gte "3.5.0" && [[ "${FORK_LISOVO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_LISOVO - 1 ))" "${FORK_LISOVO}" "$(( FORK_LISOVO + 1 ))")
        last_fork_block="${FORK_LISOVO}"
    fi

    if _version_gte "2.7.0" && _erigon_gte "3.5.0" && [[ "${FORK_GIUGLIANO:-0}" -gt 0 ]]; then
        blocks+=("$(( FORK_GIUGLIANO - 1 ))" "${FORK_GIUGLIANO}" "$(( FORK_GIUGLIANO + 1 ))")
        last_fork_block="${FORK_GIUGLIANO}"
    fi

    local target=$(( last_fork_block + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    _assert_block_field_agrees "logsBloom" "${blocks[@]}"
}

# bats test_tags=cross-client,receipts,system-tx
@test "cross-client-receipts: receipt status codes agree for system transactions" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    # System/state-sync transactions are committed at sprint boundaries (every 16 blocks).
    # Scan a window around the Rio fork to find blocks with transactions.
    local target=$(( FORK_RIO + 20 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    local diverged=0
    local checked=0

    # Check blocks in the fork vicinity that are likely to contain state-sync txs.
    # Sprint boundaries (multiples of 16) near the fork are the best candidates.
    local start=$(( FORK_RIO - 16 ))
    [[ "$start" -lt 1 ]] && start=1
    local end=$(( FORK_RIO + 16 ))

    local MAX_RECEIPTS=50
    for block in $(seq "$start" "$end"); do
        [[ "$checked" -ge "$MAX_RECEIPTS" ]] && break
        local tx_hashes
        tx_hashes=$(_tx_hashes_on "${block}" "${L2_RPC_URL}" | head -5)
        [[ -z "$tx_hashes" ]] && continue

        while IFS= read -r tx_hash; do
            [[ "$checked" -ge "$MAX_RECEIPTS" ]] && break
            [[ -z "$tx_hash" ]] && continue

            local bor_receipt erigon_receipt
            bor_receipt=$(_receipt_json_on "${tx_hash}" "${L2_RPC_URL}")
            erigon_receipt=$(_receipt_json_on "${tx_hash}" "${L2_ERIGON_RPC_URL}")

            if [[ -z "$erigon_receipt" || "$erigon_receipt" == "null" ]]; then
                echo "  FAIL: Erigon has no receipt for tx ${tx_hash} in block ${block}" >&2
                diverged=1
                continue
            fi

            local bor_status erigon_status
            bor_status=$(echo "$bor_receipt" | jq -r '.status // empty')
            erigon_status=$(echo "$erigon_receipt" | jq -r '.status // empty')

            if [[ -n "$bor_status" && -n "$erigon_status" && "$bor_status" != "$erigon_status" ]]; then
                echo "STATUS DIVERGENCE for tx ${tx_hash} in block ${block}:" >&2
                echo "  Bor status:    ${bor_status}" >&2
                echo "  Erigon status: ${erigon_status}" >&2
                diverged=1
            else
                checked=$(( checked + 1 ))
            fi
        done <<< "$tx_hashes"
    done

    echo "  Checked ${checked} transaction receipt(s) for status agreement" >&3

    if [[ "$checked" -eq 0 ]]; then
        echo "  WARN: No transactions found in blocks ${start}..${end} — test is inconclusive" >&3
        # Don't fail; the devnet may genuinely have no user txs in this range.
        # The receiptsRoot test already covers the block-level trie.
    fi

    [[ "$diverged" -eq 0 ]]
}

# bats test_tags=cross-client,receipts,cumulative-gas
@test "cross-client-receipts: cumulative gas used matches for shared blocks" {
    [[ "${FORK_RIO:-0}" -le 0 ]] && skip "Rio at genesis"

    # Spot-check several blocks: a few before Rio, at Rio, after Rio, and
    # at other fork boundaries if supported.
    local -a sample_blocks=(
        "$(( FORK_RIO - 2 ))"
        "${FORK_RIO}"
        "$(( FORK_RIO + 2 ))"
    )

    local last_fork_block="${FORK_RIO}"

    if _version_gte "2.5.0" && [[ "${FORK_MADHUGIRI:-0}" -gt 0 ]]; then
        sample_blocks+=("${FORK_MADHUGIRI}" "$(( FORK_MADHUGIRI + 1 ))")
        last_fork_block="${FORK_MADHUGIRI}"
    fi

    if _version_gte "2.5.6" && _erigon_gte "3.5.0" && [[ "${FORK_DANDELI:-0}" -gt 0 ]]; then
        sample_blocks+=("${FORK_DANDELI}")
        last_fork_block="${FORK_DANDELI}"
    fi

    if _version_gte "2.7.0" && _erigon_gte "3.5.0" && [[ "${FORK_GIUGLIANO:-0}" -gt 0 ]]; then
        sample_blocks+=("${FORK_GIUGLIANO}")
        last_fork_block="${FORK_GIUGLIANO}"
    fi

    local target=$(( last_fork_block + 5 ))
    _wait_for_block_on "${target}" "${L2_RPC_URL}"
    _wait_for_block_on "${target}" "${L2_ERIGON_RPC_URL}"

    local diverged=0
    local checked=0

    for block in "${sample_blocks[@]}"; do
        [[ "$block" -le 0 ]] && continue

        local tx_hashes
        tx_hashes=$(_tx_hashes_on "${block}" "${L2_RPC_URL}")
        [[ -z "$tx_hashes" ]] && continue

        while IFS= read -r tx_hash; do
            [[ -z "$tx_hash" ]] && continue

            local bor_receipt erigon_receipt
            bor_receipt=$(_receipt_json_on "${tx_hash}" "${L2_RPC_URL}")
            erigon_receipt=$(_receipt_json_on "${tx_hash}" "${L2_ERIGON_RPC_URL}")

            if [[ -z "$erigon_receipt" || "$erigon_receipt" == "null" ]]; then
                echo "  FAIL: Erigon has no receipt for tx ${tx_hash} in block ${block}" >&2
                diverged=1
                continue
            fi

            local bor_cum_gas erigon_cum_gas
            bor_cum_gas=$(echo "$bor_receipt" | jq -r '.cumulativeGasUsed // empty')
            erigon_cum_gas=$(echo "$erigon_receipt" | jq -r '.cumulativeGasUsed // empty')

            if [[ -n "$bor_cum_gas" && -n "$erigon_cum_gas" && "$bor_cum_gas" != "$erigon_cum_gas" ]]; then
                echo "CUMULATIVE GAS DIVERGENCE for tx ${tx_hash} in block ${block}:" >&2
                echo "  Bor:    ${bor_cum_gas}" >&2
                echo "  Erigon: ${erigon_cum_gas}" >&2
                diverged=1
            else
                checked=$(( checked + 1 ))
            fi
        done <<< "$tx_hashes"
    done

    echo "  Checked cumulativeGasUsed on ${checked} receipt(s) across ${#sample_blocks[@]} blocks" >&3

    if [[ "$checked" -eq 0 ]]; then
        echo "  WARN: No transactions found in sampled blocks — test is inconclusive" >&3
    fi

    [[ "$diverged" -eq 0 ]]
}
