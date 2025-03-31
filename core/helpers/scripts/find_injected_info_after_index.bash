#!/bin/bash
set -euo pipefail

function find_injected_info_after_index() {
    local network_id="$1"
    local index="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"

    local attempt=0
    local injected_info=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching injected info after index, params: network_id = $network_id, index = $index"

        # Capture both stdout (injected_info) and stderr (error message)
        injected_info=$(cast rpc --rpc-url "$aggkit_url" "bridge_injectedInfoAfterIndex" "$network_id" "$index" 2>&1)
        log "------ injected_info ------"
        log "$injected_info"
        log "------ injected_info ------"

        # Check if the response contains an error
        if [[ "$injected_info" == *"error"* || "$injected_info" == *"Error"* || "$injected_info" == "" ]]; then
            log "⚠️ RPC Error: $injected_info"
            sleep "$poll_frequency"
            continue
        fi

        echo "$injected_info"
        return 0
    done

    log "❌ Failed to find injected info after index $index after $max_attempts attempts."
    return 1
}
