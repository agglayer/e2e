#!/bin/bash
set -euo pipefail

assert_block_production() {
    local rpc_url="${L2_RPC_URL}"  # Ensure correct variable usage
    local sleep_duration="${2:-12}"  # Default to 12 seconds if not explicitly passed

    echo "🔍 Checking block production over $sleep_duration seconds..."

    # ✅ Capture starting block number
    local start_bn
    start_bn=$(cast block-number --rpc-url "$rpc_url")
    echo "📌 Starting block number: $start_bn"

    sleep "$sleep_duration"

    # ✅ Capture ending block number
    local end_bn
    end_bn=$(cast block-number --rpc-url "$rpc_url")
    echo "📌 Ending block number: $end_bn"

    if [[ "$end_bn" -le "$start_bn" ]]; then
        echo "❌ ERROR: The RPC seems halted! Block number did not increase." >&2
        exit 1
    fi

    echo "✅ SUCCESS: RPC is live. Block production confirmed."
}
