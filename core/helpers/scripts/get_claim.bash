#!/bin/bash
set -euo pipefail

function get_claim() {
    local network_id="$1"
    local expected_global_index="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"
    local attempt=0

    log "🔍 Searching for claim with global_index: "$expected_global_index" (bridge indexer RPC: "$aggkit_url")..."

    while true; do
        ((attempt++))
        log "🔍 Attempt $attempt"
        claims_result=$(cast rpc --rpc-url "$aggkit_url" "bridge_getClaims" "$network_id")

        log "------ claims_result ------"
        log "$claims_result"
        log "------ claims_result ------"

        for row in $(echo "$claims_result" | jq -c '.claims[]'); do
            global_index=$(jq -r '.global_index' <<<"$row")

            if [[ "$global_index" == "$expected_global_index" ]]; then
                log "🎉 Success: Expected global_index '$expected_global_index' found. Exiting loop."
                required_fields=(
                    "block_num"
                    "block_timestamp"
                    "tx_hash"
                    "global_index"
                    "origin_address"
                    "origin_network"
                    "destination_address"
                    "destination_network"
                    "amount"
                    "from_address"
                )
                # Check that all required fields exist (and are not null) in claims[0]
                for field in "${required_fields[@]}"; do
                    value=$(jq -r --arg fld "$field" '.[$fld]' <<<"$row")
                    if [ "$value" = "null" ] || [ -z "$value" ]; then
                        log "🔍 Claims result:"
                        log "$claims_result"

                        echo "❌ Error: Assertion failed missing or null '$field' in the claim object." >&2
                        return 1
                    fi
                done

                echo "$row"
                return 0
            fi
        done

        # Fail test if max attempts are reached
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            log "🔍 Claims result:"
            log "$claims_result"

            echo "❌ Error: Reached max attempts ($max_attempts) without finding expected claim with global index ($expected_global_index)." >&2
            return 1
        fi

        # Sleep before the next attempt
        sleep "$poll_frequency"
    done
}
