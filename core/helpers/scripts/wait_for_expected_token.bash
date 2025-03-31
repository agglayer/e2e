#!/bin/bash
set -euo pipefail

function wait_for_expected_token() {
    local expected_origin_token="$1"
    local max_attempts="$2"
    local poll_frequency="$3"
    local aggkit_url="$4"

    local attempt=0
    local token_mappings_result
    local origin_token_address

    while true; do
        ((attempt++))

        # Fetch token mappings from the RPC
        token_mappings_result=$(cast rpc --rpc-url "$aggkit_url" "bridge_getTokenMappings" "$l2_rpc_network_id")

        # Extract the first origin_token_address (if available)
        origin_token_address=$(echo "$token_mappings_result" | jq -r '.tokenMappings[0].origin_token_address')

        echo "Attempt $attempt: found origin_token_address = $origin_token_address (Expected: $expected_origin_token)" >&3

        # Break loop if the expected token is found
        if [[ "$origin_token_address" == "$expected_origin_token" ]]; then
            echo "Success: Expected origin_token_address '$expected_origin_token' found. Exiting loop." >&3
            echo "$token_mappings_result"
            return 0
        fi

        # Fail test if max attempts are reached
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            echo "Error: Reached max attempts ($max_attempts) without finding expected origin_token_address." >&2
            return 1
        fi

        # Sleep before the next attempt
        sleep "$poll_frequency"
    done
}
