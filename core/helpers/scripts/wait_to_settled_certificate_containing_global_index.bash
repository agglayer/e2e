#!/bin/bash
set -euo pipefail

function wait_to_settled_certificate_containing_global_index() {
    local rpc_url=$1
    local global_index=$2
    local check_frequency=${3:-60}
    local timeout=${4:-1200}
    log "Waiting for certificate with global index $global_index" >&3
    run_with_timeout "wait certificate settle for $global_index" $check_frequency $timeout $AGGSENDER_IMPORTED_BRIDGE_PATH $rpc_url $global_index
}

function run_with_timeout() {
    local name="$1"
    local run_frequency=$2
    local timeout=$3
    shift 3
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    while true; do
        local current_time=$(date +%s)
        if ((current_time > end_time)); then
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting [$name]... Timeout reached!" >&3
            exit 1
        fi
        echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ⏳ Running [$name]..." >&3
        echo "executing: $*" >&3
        run $*
        echo "output: $output" >&3
        echo "result: $status" >&3
        if [ $status -eq 0 ]; then
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Executed successfully! [$name] " >&3
            break
        fi
        echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ⏳ Sleep [$name] for period: $run_frequency" >&3
        sleep "$run_frequency"
    done
}
