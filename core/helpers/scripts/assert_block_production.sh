#!/bin/bash
set -euo pipefail

assert_block_production() {
    local rpc_url="$1"
    local sleep_duration="${2:-12}"  # Default to 12 seconds if not provided

    echo "🔍 Checking block production over $sleep_duration seconds..."

    local start_bn
    start_bn=$(cast block-number --rpc-url "$rpc_url")

    sleep "$sleep_duration"

    local end_bn
    end_bn=$(cast block-number --rpc-url "$rpc_url")

    if [[ $end_bn -le $start_bn ]]; then
        echo "❌ The RPC seems to be halted! Block number did not increase." >&2
        exit 1
    fi

    echo "✅ RPC is live. Block production confirmed."
}
