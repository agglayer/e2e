#!/bin/bash
set -euo pipefail

function find_l1_info_tree_index_for_bridge() {
    local network_id="$1"
    local expected_deposit_count="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"

    local attempt=0
    local index=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: Fetching L1 info tree index for bridge with deposit count $expected_deposit_count"

        # Capture both stdout (index) and stderr (error message)
        index=$(cast rpc --rpc-url "$aggkit_url" "bridge_l1InfoTreeIndexForBridge" "$network_id" "$expected_deposit_count" 2>&1)
        log "------ index ------"
        log "$index"
        log "------ index ------"

        # Check if the response contains an error
        if [[ "$index" == *"error"* || "$index" == *"Error"* || "$index" == "" ]]; then
            log "⚠️ RPC Error: $index"
            sleep "$poll_frequency"
            continue
        fi

        echo "$index"
        return 0
    done

    log "❌ Failed to find L1 info tree index after $max_attempts attempts"
    return 1
}
