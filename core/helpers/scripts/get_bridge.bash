#!/bin/bash
set -euo pipefail

function get_bridge() {
    local network_id="$1"
    local expected_tx_hash="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"

    local attempt=0
    local bridges_result=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching bridge, params: network_id = $network_id, tx_hash = $expected_tx_hash"

        # Capture both stdout (bridge result) and stderr (error message)
        bridges_result=$(cast rpc --rpc-url "$aggkit_url" "bridge_getBridges" "$network_id" 2>&1)
        log "------ bridges_result ------"
        log "$bridges_result"
        log "------ bridges_result ------"

        # Check if the response contains an error
        if [[ "$bridges_result" == *"error"* || "$bridges_result" == *"Error"* || "$bridges_result" == "" ]]; then
            log "⚠️ RPC Error: $bridges_result"
            sleep "$poll_frequency"
            continue
        fi

        # Extract the elements of the 'bridges' array one by one
        for row in $(echo "$bridges_result" | jq -c '.bridges[]'); do
            # Parse out the tx_hash from each element
            tx_hash=$(echo "$row" | jq -r '.tx_hash')

            if [[ "$tx_hash" == "$expected_tx_hash" ]]; then
                log "🎉 Found expected bridge with tx hash: $tx_hash"
                echo "$row"
                return 0
            fi
        done

        sleep "$poll_frequency"
    done

    log "❌ Failed to find bridge after $max_attempts attempts."
    return 1
}
