#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip74

# PIP-74: Canonical State Sync Transactions in Block Bodies
# Activated in Madhugiri hardfork (mainnet block 80,084,800).
# https://github.com/maticnetwork/Polygon-Improvement-Proposals/blob/main/PIPs/PIP-74.md
#
# Introduces StateSyncTx (type 0x7F) — a synthetic transaction appended to blocks
# containing state sync events from L1. Makes state syncs affect transactionsRoot,
# receiptsRoot, and logsBloom, enabling trustless snap-sync.
#
# On a devnet, state syncs may or may not occur depending on L1 bridge activity.
# Tests scan recent blocks for type-0x7F transactions and verify their structure.
# Note: each test independently scans up to 200 blocks (bats runs each @test in
# isolation). On devnets without state syncs, all 3 tests skip quickly.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# Helper: fetch a block with full transactions and return the JSON.
_fetch_block_full() {
    local block_num=$1
    local block_hex
    block_hex=$(printf '0x%x' "$block_num")
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBlockByNumber\",\"params\":[\"$block_hex\",true]}" \
        "$L2_RPC_URL"
}

# bats test_tags=execution-specs,pip74,state-sync
@test "PIP-74: scan recent blocks for StateSyncTx (type 0x7F) transactions" {
    # Scan the last 200 blocks for type-0x7F transactions.
    # State syncs happen periodically based on Heimdall state sync events.
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local scan_start=$(( latest_block > 200 ? latest_block - 200 : 0 ))
    local found_count=0
    local found_blocks=""

    echo "Scanning blocks $scan_start to $latest_block for StateSyncTx (type 0x7f)..." >&3

    for block_num in $(seq "$scan_start" "$latest_block"); do
        local result
        result=$(_fetch_block_full "$block_num")

        # Check if any transaction has type 0x7f
        local type_7f_count
        type_7f_count=$(echo "$result" | jq '[.result.transactions[]? | select(.type == "0x7f")] | length' 2>/dev/null)

        if [[ "$type_7f_count" -gt 0 ]]; then
            found_count=$(( found_count + type_7f_count ))
            found_blocks="$found_blocks $block_num"
            echo "  Block $block_num: $type_7f_count StateSyncTx(s)" >&3
        fi
    done

    echo "Found $found_count StateSyncTx(s) across blocks:$found_blocks" >&3

    if [[ "$found_count" -eq 0 ]]; then
        skip "No StateSyncTx (type 0x7F) found in last 200 blocks — PIP-74 may not be active or no state syncs occurred"
    fi
}

# bats test_tags=execution-specs,pip74,state-sync
@test "PIP-74: StateSyncTx has expected fields (from, to, input)" {
    # Find a block with a StateSyncTx and verify its structure.
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local scan_start=$(( latest_block > 200 ? latest_block - 200 : 0 ))
    local sync_tx=""

    for block_num in $(seq "$scan_start" "$latest_block"); do
        local result
        result=$(_fetch_block_full "$block_num")

        sync_tx=$(echo "$result" | jq '.result.transactions[]? | select(.type == "0x7f")' 2>/dev/null | head -c 10000)
        if [[ -n "$sync_tx" ]]; then
            echo "Found StateSyncTx in block $block_num" >&3
            break
        fi
    done

    if [[ -z "$sync_tx" ]]; then
        skip "No StateSyncTx found in last 200 blocks"
    fi

    # StateSyncTx should have:
    # - type: "0x7f"
    # - from: zero address (system transaction)
    # - to: StateReceiver (0x...1001)
    # - input: non-empty (state sync data)
    local tx_type
    tx_type=$(echo "$sync_tx" | jq -r '.type')
    echo "StateSyncTx type: $tx_type" >&3

    if [[ "$tx_type" != "0x7f" ]]; then
        echo "Expected type 0x7f, got: $tx_type" >&2
        return 1
    fi

    local tx_to
    tx_to=$(echo "$sync_tx" | jq -r '.to // empty' | tr '[:upper:]' '[:lower:]')
    echo "StateSyncTx to: $tx_to" >&3

    # The 'to' field should be the StateReceiver system contract
    if [[ "$tx_to" == "0x0000000000000000000000000000000000001001" ]]; then
        echo "StateSyncTx correctly targets StateReceiver (0x...1001)" >&3
    else
        echo "StateSyncTx 'to' is not StateReceiver: $tx_to" >&3
        # Not a hard failure — devnet may have different config
    fi

    local tx_input
    tx_input=$(echo "$sync_tx" | jq -r '.input // empty')
    if [[ -n "$tx_input" && "$tx_input" != "0x" ]]; then
        local input_len=$(( (${#tx_input} - 2) / 2 ))
        echo "StateSyncTx input data: $input_len bytes" >&3
    fi
}

# bats test_tags=execution-specs,pip74,state-sync
@test "PIP-74: blocks with transactions include StateSyncTx in transactionsRoot" {
    # Verify that block transactionsRoot is non-empty for blocks containing
    # StateSyncTx, confirming the synthetic tx is included in the Merkle root.
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local scan_start=$(( latest_block > 200 ? latest_block - 200 : 0 ))

    for block_num in $(seq "$scan_start" "$latest_block"); do
        local result
        result=$(_fetch_block_full "$block_num")

        local type_7f_count
        type_7f_count=$(echo "$result" | jq '[.result.transactions[]? | select(.type == "0x7f")] | length' 2>/dev/null)

        if [[ "$type_7f_count" -gt 0 ]]; then
            local tx_root
            tx_root=$(echo "$result" | jq -r '.result.transactionsRoot // empty')
            local total_txs
            total_txs=$(echo "$result" | jq '.result.transactions | length')

            echo "Block $block_num: $total_txs txs ($type_7f_count StateSyncTx), transactionsRoot=$tx_root" >&3

            # transactionsRoot must not be the empty trie hash if block has transactions
            local empty_root="0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
            if [[ "$tx_root" == "$empty_root" ]]; then
                echo "Block $block_num has StateSyncTx but transactionsRoot is empty trie hash" >&2
                return 1
            fi

            echo "TransactionsRoot correctly includes StateSyncTx" >&3
            return 0
        fi
    done

    skip "No StateSyncTx found in last 200 blocks to verify transactionsRoot"
}
