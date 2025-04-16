#!/usr/bin/env bash

function wait_for_claim() {
    local timeout="$1"         # timeout (in seconds)
    local claim_frequency="$2" # claim frequency (in seconds)
    local destination_rpc_url="$3" # destination rpc url
    local bridge_type="$4"        # bridgeAsset or bridgeMessage
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while true; do
        local current_time=$(date +%s)
        if ((current_time > end_time)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
            exit 1
        fi

        run claim $destination_rpc_url $bridge_type
        if [ $status -eq 0 ]; then
            break
        fi

        sleep "$claim_frequency"
    done
}
