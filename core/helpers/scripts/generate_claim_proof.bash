#!/bin/bash
set -euo pipefail

function generate_claim_proof() {
    local network_id="$1"
    local deposit_count="$2"
    local l1_info_tree_index="$3"
    local max_attempts="$4"
    local poll_frequency="$5"
    local aggkit_url="$6"

    local attempt=0
    local proof=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching proof, params: network_id = $network_id, deposit_count = $deposit_count, l1_info_tree_index = $l1_info_tree_index"

        # Capture both stdout (proof) and stderr (error message)
        proof=$(cast rpc --rpc-url "$aggkit_url" "bridge_claimProof" "$network_id" "$deposit_count" "$l1_info_tree_index" 2>&1)
        log "------ proof ------"
        log "$proof"
        log "------ proof ------"

        # Check if the response contains an error
        if [[ "$proof" == *"error"* || "$proof" == *"Error"* || "$proof" == "" ]]; then
            log "⚠️ RPC Error: $proof"
            sleep "$poll_frequency"
            continue
        fi

        echo "$proof"
        return 0
    done

    log "❌ Failed to generate a claim proof for $deposit_count after $max_attempts attempts."
    return 1
}
