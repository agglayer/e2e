#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,evm-rpc,state-sync

# State-Sync eth_getLogs Address Index Consistency
# ====================================================
# Verifies that logs emitted inside Bor state-sync transactions are properly
# indexed by contract address in eth_getLogs.
#
# Background:
#   State-sync transactions have a very specific on-chain fingerprint:
#     - type:     0x7f  (StateSyncTx, introduced in PIP-74 / Madhugiri)
#     - from:     0x0000000000000000000000000000000000000000
#     - to:       0x0000000000000000000000000000000000000000
#     - value:    0x0
#     - gas:      0x0
#     - gasPrice: 0x0
#     - nonce:    0x0
#   These are synthetic transactions injected by Bor to deliver L1→L2
#   cross-chain messages via the StateReceiver system contract (0x...1001).
#
#   The events emitted during execution of these transactions are real on-chain
#   logs that appear in eth_getTransactionReceipt. However, some RPC nodes or
#   middleware layers fail to include them in their eth_getLogs address index,
#   causing queries with an address filter to silently return zero results
#   for events that genuinely belong to that contract.
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with state-sync activity (PIP-74 / Madhugiri active)
#   - Bor RPC reachable at L2_RPC_URL
#   - At least one StateSyncTx in the last 300 blocks
#
# RUN: bats tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats

# ────────────────────────────────────────────────────────────────────────────
# Constants — the exact fingerprint of a Bor state-sync transaction
# ────────────────────────────────────────────────────────────────────────────

ZERO_ADDR="0x0000000000000000000000000000000000000000"
STATESYNC_TX_TYPE="0x7f"

# ────────────────────────────────────────────────────────────────────────────
# File-level setup: scan for state-sync transactions once, cache results
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL" 2>/dev/null) || {
        echo "WARNING: Cannot reach L2 RPC at ${L2_RPC_URL}" >&3
        echo "1" > "${BATS_FILE_TMPDIR}/rpc_unavailable"
        return
    }
    echo "0" > "${BATS_FILE_TMPDIR}/rpc_unavailable"

    local scan_depth=300
    local scan_start=$(( latest_block > scan_depth ? latest_block - scan_depth : 0 ))
    local found_tx=""
    local found_block_hex=""
    local found_block_num=""

    echo "Scanning blocks ${scan_start}..${latest_block} for StateSyncTx (type 0x7f, from: 0x0, to: 0x0)..." >&3

    for block_num in $(seq "$scan_start" "$latest_block"); do
        local block_hex
        block_hex=$(printf '0x%x' "$block_num")
        local block_json
        block_json=$(curl -s -m 10 --connect-timeout 5 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",true]}" 2>/dev/null)

        # Match the EXACT state-sync transaction fingerprint:
        #   type == 0x7f AND from == 0x0 AND to == 0x0
        local sync_tx
        sync_tx=$(echo "$block_json" | jq -c '
            [.result.transactions[]? | select(
                .type == "0x7f" and
                (.from | ascii_downcase) == "0x0000000000000000000000000000000000000000" and
                (.to | ascii_downcase) == "0x0000000000000000000000000000000000000000"
            )] | .[0] // empty
        ' 2>/dev/null)

        if [[ -n "$sync_tx" && "$sync_tx" != "null" ]]; then
            found_tx="$sync_tx"
            found_block_hex="$block_hex"
            found_block_num="$block_num"
            local tx_hash
            tx_hash=$(echo "$sync_tx" | jq -r '.hash')
            echo "Found StateSyncTx in block ${block_num}: ${tx_hash}" >&3
            break
        fi
    done

    if [[ -z "$found_tx" ]]; then
        echo "0" > "${BATS_FILE_TMPDIR}/has_statesync"
        echo "No StateSyncTx (type=0x7f, from=0x0, to=0x0) found in last ${scan_depth} blocks" >&3
        return
    fi

    echo "1" > "${BATS_FILE_TMPDIR}/has_statesync"
    echo "$found_tx" > "${BATS_FILE_TMPDIR}/statesync_tx.json"
    echo "$found_block_hex" > "${BATS_FILE_TMPDIR}/statesync_block_hex"
    echo "$found_block_num" > "${BATS_FILE_TMPDIR}/statesync_block_num"

    local found_tx_hash
    found_tx_hash=$(echo "$found_tx" | jq -r '.hash')
    echo "$found_tx_hash" > "${BATS_FILE_TMPDIR}/statesync_tx_hash"

    # Fetch the receipt for this state-sync tx
    local receipt_json
    receipt_json=$(curl -s -m 15 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"${found_tx_hash}\"]}" 2>/dev/null)

    echo "$receipt_json" > "${BATS_FILE_TMPDIR}/statesync_receipt.json"

    local log_count
    log_count=$(echo "$receipt_json" | jq '.result.logs | length' 2>/dev/null)
    echo "StateSyncTx receipt has ${log_count} logs" >&3

    # Extract unique contract addresses from the receipt logs
    echo "$receipt_json" | jq -r '[.result.logs[].address] | unique | .[]' \
        > "${BATS_FILE_TMPDIR}/statesync_log_addresses.txt" 2>/dev/null

    local unique_addrs
    unique_addrs=$(wc -l < "${BATS_FILE_TMPDIR}/statesync_log_addresses.txt" | tr -d ' ')
    echo "Logs span ${unique_addrs} unique contract address(es)" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    ZERO_ADDR="0x0000000000000000000000000000000000000000"
    STATESYNC_TX_TYPE="0x7f"

    if [[ "$(cat "${BATS_FILE_TMPDIR}/rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "L2 RPC not reachable at ${L2_RPC_URL}"
    fi

    if [[ "$(cat "${BATS_FILE_TMPDIR}/has_statesync" 2>/dev/null)" != "1" ]]; then
        skip "No StateSyncTx (type=0x7f, from=0x0, to=0x0) found in recent blocks"
    fi

    STATESYNC_TX_JSON=$(cat "${BATS_FILE_TMPDIR}/statesync_tx.json")
    STATESYNC_TX_HASH=$(cat "${BATS_FILE_TMPDIR}/statesync_tx_hash")
    STATESYNC_BLOCK_HEX=$(cat "${BATS_FILE_TMPDIR}/statesync_block_hex")
    STATESYNC_BLOCK_NUM=$(cat "${BATS_FILE_TMPDIR}/statesync_block_num")
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Query eth_getLogs for a single block with optional address and topic filter.
# Usage: _get_logs <block_hex> [address] [topic0]
_get_logs() {
    local block_hex="$1"
    local address="${2:-}"
    local topic0="${3:-}"

    local params="{\"fromBlock\":\"${block_hex}\",\"toBlock\":\"${block_hex}\""
    if [[ -n "$address" ]]; then
        params="${params},\"address\":\"${address}\""
    fi
    if [[ -n "$topic0" ]]; then
        params="${params},\"topics\":[\"${topic0}\"]"
    fi
    params="${params}}"

    curl -s -m 15 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[${params}]}"
}

# ────────────────────────────────────────────────────────────────────────────
# Tests — Transaction structure validation
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "state-sync tx: type is 0x7f (StateSyncTx / PIP-74)" {
    local tx_type
    tx_type=$(echo "$STATESYNC_TX_JSON" | jq -r '.type')

    if [[ "$tx_type" != "$STATESYNC_TX_TYPE" ]]; then
        echo "Expected type ${STATESYNC_TX_TYPE}, got: ${tx_type}" >&2
        return 1
    fi
    echo "type: ${tx_type} ✓" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "state-sync tx: from is zero address (0x0)" {
    local tx_from
    tx_from=$(echo "$STATESYNC_TX_JSON" | jq -r '.from' | tr '[:upper:]' '[:lower:]')

    if [[ "$tx_from" != "$ZERO_ADDR" ]]; then
        echo "Expected from=${ZERO_ADDR}, got: ${tx_from}" >&2
        return 1
    fi
    echo "from: ${tx_from} ✓" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "state-sync tx: to is zero address (0x0)" {
    local tx_to
    tx_to=$(echo "$STATESYNC_TX_JSON" | jq -r '.to' | tr '[:upper:]' '[:lower:]')

    if [[ "$tx_to" != "$ZERO_ADDR" ]]; then
        echo "Expected to=${ZERO_ADDR}, got: ${tx_to}" >&2
        return 1
    fi
    echo "to: ${tx_to} ✓" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "state-sync tx: gas, gasPrice, value, and nonce are all zero" {
    local tx_gas tx_gas_price tx_value tx_nonce
    tx_gas=$(echo "$STATESYNC_TX_JSON" | jq -r '.gas // "0x0"')
    tx_gas_price=$(echo "$STATESYNC_TX_JSON" | jq -r '.gasPrice // "0x0"')
    tx_value=$(echo "$STATESYNC_TX_JSON" | jq -r '.value // "0x0"')
    tx_nonce=$(echo "$STATESYNC_TX_JSON" | jq -r '.nonce // "0x0"')

    local failed=0
    for field_name in gas gasPrice value nonce; do
        local field_val
        eval "field_val=\$tx_${field_name/P/_p}"
        case "$field_name" in
            gas)      field_val="$tx_gas" ;;
            gasPrice) field_val="$tx_gas_price" ;;
            value)    field_val="$tx_value" ;;
            nonce)    field_val="$tx_nonce" ;;
        esac
        # Accept "0x0" or "0x" as zero
        if [[ "$field_val" != "0x0" && "$field_val" != "0x" ]]; then
            echo "FAIL: ${field_name}=${field_val}, expected 0x0" >&2
            failed=$(( failed + 1 ))
        fi
    done

    if [[ "$failed" -gt 0 ]]; then
        return 1
    fi
    echo "gas=0x0, gasPrice=0x0, value=0x0, nonce=0x0 ✓" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "state-sync tx: receipt exists and has at least one log" {
    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    local status
    status=$(echo "$receipt_json" | jq -r '.result.status // empty' 2>/dev/null)
    if [[ -z "$status" ]]; then
        echo "FAIL: eth_getTransactionReceipt returned no result for state-sync tx ${STATESYNC_TX_HASH}" >&2
        return 1
    fi

    local log_count
    log_count=$(echo "$receipt_json" | jq '.result.logs | length' 2>/dev/null)
    if [[ "$log_count" -eq 0 ]]; then
        echo "FAIL: state-sync receipt has 0 logs — cannot test log indexing" >&2
        return 1
    fi

    local unique_addrs
    unique_addrs=$(cat "${BATS_FILE_TMPDIR}/statesync_log_addresses.txt" | wc -l | tr -d ' ')
    echo "Receipt: status=${status}, ${log_count} log(s) across ${unique_addrs} contract(s) ✓" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Tests — eth_getLogs address index consistency
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: state-sync logs appear when filtering by contract address" {
    # For each unique contract address that emitted a log inside the state-sync
    # transaction, verify that eth_getLogs with that address filter returns
    # at least one log.

    local addresses
    addresses=$(cat "${BATS_FILE_TMPDIR}/statesync_log_addresses.txt")

    local failed=0
    local tested=0

    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        tested=$(( tested + 1 ))

        local response
        response=$(_get_logs "$STATESYNC_BLOCK_HEX" "$addr")

        local result_count
        result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

        if [[ -z "$result_count" || "$result_count" == "null" ]]; then
            echo "FAIL: eth_getLogs returned error for address ${addr}: $(echo "$response" | jq -c '.error' 2>/dev/null)" >&2
            failed=$(( failed + 1 ))
            continue
        fi

        if [[ "$result_count" -eq 0 ]]; then
            echo "FAIL: eth_getLogs with address=${addr} returned 0 logs, but receipt shows logs from this address" >&2
            failed=$(( failed + 1 ))
        else
            echo "  OK: address=${addr} → ${result_count} log(s)" >&3
        fi
    done <<< "$addresses"

    echo "Tested ${tested} addresses, ${failed} failures" >&3

    if [[ "$failed" -gt 0 ]]; then
        echo "eth_getLogs address index is missing logs from state-sync transactions" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: state-sync logs appear when filtering by topic only (no address)" {
    # Baseline test: eth_getLogs without address filter should return state-sync logs.
    # This confirms logs exist in the bloom/topic index even if the address index is broken.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    # Pick the first topic0 from the receipt logs
    local topic0
    topic0=$(echo "$receipt_json" | jq -r '.result.logs[0].topics[0] // empty' 2>/dev/null)

    if [[ -z "$topic0" ]]; then
        skip "Receipt has no logs with topics"
    fi

    local response
    response=$(_get_logs "$STATESYNC_BLOCK_HEX" "" "$topic0")

    local result_count
    result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

    if [[ -z "$result_count" || "$result_count" == "null" || "$result_count" -eq 0 ]]; then
        echo "eth_getLogs with topic filter returned 0 logs — topic index may be broken too" >&2
        echo "topic0: $topic0" >&2
        echo "response: $(echo "$response" | jq -c '.' 2>/dev/null)" >&2
        return 1
    fi

    echo "topic-only filter returned ${result_count} log(s) for topic ${topic0}" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: address-filtered log count matches receipt log count per address" {
    # For each contract address in the state-sync receipt, the number of logs
    # returned by eth_getLogs (address + block filter) must match the number
    # of logs from that address in the receipt.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    local addresses
    addresses=$(cat "${BATS_FILE_TMPDIR}/statesync_log_addresses.txt")

    local failed=0

    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue

        # Count logs from this address in the receipt
        local addr_lower
        addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
        local receipt_count
        receipt_count=$(echo "$receipt_json" | jq --arg a "$addr_lower" '
            [.result.logs[] | select(.address | ascii_downcase == $a)] | length
        ' 2>/dev/null)

        # Count logs from eth_getLogs with address filter for this single block
        local response
        response=$(_get_logs "$STATESYNC_BLOCK_HEX" "$addr")

        # Filter to only logs from the state-sync transaction
        local getlogs_count
        getlogs_count=$(echo "$response" | jq --arg txh "$STATESYNC_TX_HASH" '
            [.result[]? | select(.transactionHash | ascii_downcase == ($txh | ascii_downcase))] | length
        ' 2>/dev/null)

        if [[ "$receipt_count" != "$getlogs_count" ]]; then
            echo "FAIL: address=${addr}: receipt has ${receipt_count} logs, eth_getLogs returned ${getlogs_count}" >&2
            failed=$(( failed + 1 ))
        else
            echo "  OK: address=${addr}: ${receipt_count} log(s) match" >&3
        fi
    done <<< "$addresses"

    if [[ "$failed" -gt 0 ]]; then
        return 1
    fi
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: StateReceiver (0x1001) events are address-indexed in state-sync blocks" {
    # The StateReceiver system contract (0x...1001) always emits a StateCommitted
    # event during state-sync processing. This event MUST be discoverable via
    # eth_getLogs with the StateReceiver address.

    local state_receiver="0x0000000000000000000000000000000000001001"

    # Check receipt has a log from StateReceiver
    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    local sr_log_count
    sr_log_count=$(echo "$receipt_json" | jq '
        [.result.logs[] | select(.address | ascii_downcase == "0x0000000000000000000000000000000000001001")] | length
    ' 2>/dev/null)

    if [[ "$sr_log_count" -eq 0 ]]; then
        skip "No StateReceiver logs in this state-sync receipt"
    fi

    # Query eth_getLogs with StateReceiver address
    local response
    response=$(_get_logs "$STATESYNC_BLOCK_HEX" "$state_receiver")

    local getlogs_count
    getlogs_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

    if [[ -z "$getlogs_count" || "$getlogs_count" == "null" || "$getlogs_count" -eq 0 ]]; then
        echo "FAIL: eth_getLogs for StateReceiver (0x1001) returned 0 logs" >&2
        echo "Receipt shows ${sr_log_count} logs from StateReceiver" >&2
        return 1
    fi

    echo "StateReceiver address filter: ${getlogs_count} log(s) from eth_getLogs, ${sr_log_count} in receipt" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: MRC20 (0x1010) events are address-indexed in state-sync blocks" {
    # The MRC20 native token contract (0x...1010) frequently emits transfer events
    # during state-sync processing. Verify address-index consistency.

    local mrc20="0x0000000000000000000000000000000000001010"

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    local mrc20_log_count
    mrc20_log_count=$(echo "$receipt_json" | jq '
        [.result.logs[] | select(.address | ascii_downcase == "0x0000000000000000000000000000000000001010")] | length
    ' 2>/dev/null)

    if [[ "$mrc20_log_count" -eq 0 ]]; then
        skip "No MRC20 logs in this state-sync receipt"
    fi

    local response
    response=$(_get_logs "$STATESYNC_BLOCK_HEX" "$mrc20")

    # Filter to state-sync tx logs only
    local getlogs_count
    getlogs_count=$(echo "$response" | jq --arg txh "$STATESYNC_TX_HASH" '
        [.result[]? | select(.transactionHash | ascii_downcase == ($txh | ascii_downcase))] | length
    ' 2>/dev/null)

    if [[ -z "$getlogs_count" || "$getlogs_count" == "null" || "$getlogs_count" -eq 0 ]]; then
        echo "FAIL: eth_getLogs for MRC20 (0x1010) returned 0 state-sync logs" >&2
        echo "Receipt shows ${mrc20_log_count} logs from MRC20" >&2
        return 1
    fi

    echo "MRC20 address filter: ${getlogs_count} log(s) match receipt (${mrc20_log_count})" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: log ordering in address-filtered results matches receipt order" {
    # Verify that the logIndex ordering from eth_getLogs matches the receipt.
    # A broken index could return logs in the wrong order.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    # Get receipt log indices for this tx
    local receipt_indices
    receipt_indices=$(echo "$receipt_json" | jq -c '[.result.logs[].logIndex]' 2>/dev/null)

    # Get all logs for this block without address filter
    local response
    response=$(_get_logs "$STATESYNC_BLOCK_HEX")

    local getlogs_indices
    getlogs_indices=$(echo "$response" | jq -c --arg txh "$STATESYNC_TX_HASH" '
        [.result[]? | select(.transactionHash | ascii_downcase == ($txh | ascii_downcase)) | .logIndex]
    ' 2>/dev/null)

    if [[ "$receipt_indices" != "$getlogs_indices" ]]; then
        echo "FAIL: log indices differ between receipt and eth_getLogs" >&2
        echo "  Receipt:     $receipt_indices" >&2
        echo "  eth_getLogs: $getlogs_indices" >&2
        return 1
    fi

    echo "Log ordering matches: $receipt_indices" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: combined address+topic filter returns state-sync logs" {
    # The most specific query pattern: both address AND topic filters together.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    # Pick a log entry that has both a non-system address and a topic
    local target
    target=$(echo "$receipt_json" | jq -r '
        [.result.logs[] |
         select(.address != "0x0000000000000000000000000000000000001001" and
                .address != "0x0000000000000000000000000000000000001010" and
                (.topics | length) > 0)] | .[0] // empty
    ' 2>/dev/null)

    if [[ -z "$target" || "$target" == "null" ]]; then
        # Fall back to any log with topics
        target=$(echo "$receipt_json" | jq -r '
            [.result.logs[] | select((.topics | length) > 0)] | .[0] // empty
        ' 2>/dev/null)
    fi

    if [[ -z "$target" || "$target" == "null" ]]; then
        skip "No logs with topics in state-sync receipt"
    fi

    local addr topic0
    addr=$(echo "$target" | jq -r '.address')
    topic0=$(echo "$target" | jq -r '.topics[0]')

    echo "Testing address=${addr} + topic=${topic0}" >&3

    # Build query with both address and topic filter
    local params
    params="{\"fromBlock\":\"${STATESYNC_BLOCK_HEX}\",\"toBlock\":\"${STATESYNC_BLOCK_HEX}\",\"address\":\"${addr}\",\"topics\":[\"${topic0}\"]}"

    local response
    response=$(curl -s -m 15 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[${params}]}")

    local result_count
    result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

    if [[ -z "$result_count" || "$result_count" == "null" || "$result_count" -eq 0 ]]; then
        echo "FAIL: eth_getLogs with address+topic filter returned 0 logs" >&2
        echo "Address: $addr" >&2
        echo "Topic0:  $topic0" >&2
        echo "This is the exact pattern that breaks when address index drops state-sync logs" >&2
        return 1
    fi

    # Verify the returned log matches
    local returned_addr
    returned_addr=$(echo "$response" | jq -r '.result[0].address' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local expected_addr
    expected_addr=$(echo "$addr" | tr '[:upper:]' '[:lower:]')

    if [[ "$returned_addr" != "$expected_addr" ]]; then
        echo "FAIL: returned log address (${returned_addr}) != expected (${expected_addr})" >&2
        return 1
    fi

    echo "address+topic filter returned ${result_count} log(s) — address index is correct" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: multi-block range with address filter includes state-sync logs" {
    # Test that address filtering works across a block range, not just single-block.
    # Some implementations handle single-block queries differently from ranges.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    # Pick any address from the receipt
    local addr
    addr=$(echo "$receipt_json" | jq -r '.result.logs[0].address // empty' 2>/dev/null)
    [[ -z "$addr" ]] && skip "No logs in state-sync receipt"

    # Build a 10-block range around the state-sync block
    local range_start=$(( STATESYNC_BLOCK_NUM - 5 ))
    [[ "$range_start" -lt 0 ]] && range_start=0
    local range_end=$(( STATESYNC_BLOCK_NUM + 5 ))

    local from_hex to_hex
    from_hex=$(printf '0x%x' "$range_start")
    to_hex=$(printf '0x%x' "$range_end")

    local response
    response=$(curl -s -m 15 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"${from_hex}\",\"toBlock\":\"${to_hex}\",\"address\":\"${addr}\"}]}")

    local result_count
    result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

    # Check for error response (block range too large etc.)
    local has_error
    has_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
    if [[ -n "$has_error" ]]; then
        echo "Node returned error for range query (may be expected): $(echo "$has_error" | head -c 200)" >&3
        skip "Node rejected block range query — cannot test multi-block address filter"
    fi

    if [[ -z "$result_count" || "$result_count" == "null" || "$result_count" -eq 0 ]]; then
        echo "FAIL: eth_getLogs with address ${addr} over range ${from_hex}..${to_hex} returned 0 logs" >&2
        echo "The state-sync block ${STATESYNC_BLOCK_HEX} is within this range" >&2
        return 1
    fi

    # Verify at least one of the returned logs is from our state-sync block
    local matched
    matched=$(echo "$response" | jq --arg bh "$STATESYNC_BLOCK_HEX" '
        [.result[]? | select(.blockNumber == $bh)] | length
    ' 2>/dev/null)

    if [[ "$matched" -eq 0 ]]; then
        echo "FAIL: range query returned ${result_count} logs but none from state-sync block ${STATESYNC_BLOCK_HEX}" >&2
        return 1
    fi

    echo "Multi-block range returned ${result_count} total logs, ${matched} from state-sync block" >&3
}

# bats test_tags=execution-specs,evm-rpc,state-sync,getlogs
@test "eth_getLogs: all receipt logs are discoverable via eth_getLogs for the same block" {
    # Ultimate consistency check: every single log in the state-sync receipt must
    # appear in the unfiltered eth_getLogs result for the same block.
    # This catches cases where the bloom filter or log storage is incomplete.

    local receipt_json
    receipt_json=$(cat "${BATS_FILE_TMPDIR}/statesync_receipt.json")

    local receipt_log_count
    receipt_log_count=$(echo "$receipt_json" | jq '.result.logs | length' 2>/dev/null)

    # Get all logs from the block
    local response
    response=$(_get_logs "$STATESYNC_BLOCK_HEX")

    local missing=0

    for idx in $(seq 0 $(( receipt_log_count - 1 ))); do
        local expected_log_index
        expected_log_index=$(echo "$receipt_json" | jq -r ".result.logs[$idx].logIndex" 2>/dev/null)
        local expected_tx_hash
        expected_tx_hash=$(echo "$receipt_json" | jq -r ".result.logs[$idx].transactionHash" 2>/dev/null)

        local found
        found=$(echo "$response" | jq --arg li "$expected_log_index" --arg txh "$expected_tx_hash" '
            [.result[]? | select(.logIndex == $li and (.transactionHash | ascii_downcase) == ($txh | ascii_downcase))] | length
        ' 2>/dev/null)

        if [[ "$found" -eq 0 ]]; then
            local log_addr
            log_addr=$(echo "$receipt_json" | jq -r ".result.logs[$idx].address" 2>/dev/null)
            echo "MISSING: logIndex=${expected_log_index} address=${log_addr} txHash=${expected_tx_hash}" >&2
            missing=$(( missing + 1 ))
        fi
    done

    if [[ "$missing" -gt 0 ]]; then
        echo "FAIL: ${missing} out of ${receipt_log_count} receipt logs not found in eth_getLogs" >&2
        return 1
    fi

    echo "All ${receipt_log_count} receipt logs present in eth_getLogs" >&3
}
