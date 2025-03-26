#!/bin/bash
set -euo pipefail

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
        echo "executing: $*"
        run $*
        echo "output: $output"
        echo "result: $status"
        if [ $status -eq 0 ]; then
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Executed successfully! [$name] " >&3
            break
        fi
        echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ⏳ Sleep [$name] for period: $run_frequency" >&3
        sleep "$run_frequency"
    done
}
