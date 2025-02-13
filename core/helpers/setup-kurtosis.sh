#!/bin/bash
set -euo pipefail

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL

NETWORK="${1:-fork12-cdk-erigon-validium}"
COMBINATIONS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/tags/v0.2.30/.github/tests/combinations/${NETWORK}.yml"

echo "🔥 Deploying Kurtosis environment for network: $NETWORK"
echo "📄 Using combinations file: $COMBINATIONS_FILE"

# ✅ Ensure Kurtosis is installed
if ! command -v kurtosis &> /dev/null; then
    echo "⚠️ Kurtosis CLI not found. Installing..."
    curl -fsSL https://get.kurtosis.com | bash
fi

# ✅ Clean up old environments
kurtosis clean --all

# ✅ Run Kurtosis from GitHub (just like local)
kurtosis run --enclave cdk \
            github.com/0xPolygon/kurtosis-cdk@v0.2.30 \
            --args-file="$COMBINATIONS_FILE"

# ✅ Fetch and export RPC URL
export L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
echo "✅ Exported L2_RPC_URL=$L2_RPC_URL"
export L2_SEQUENCER_RPC_URL="$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"
echo "✅ Exported L2_SEQUENCER_RPC_URL=$L2_SEQUENCER_RPC_URL"

# ✅ Output for CI consumption
echo "L2_RPC_URL=$L2_RPC_URL" >> "$GITHUB_ENV"
echo "L2_SEQUENCER_RPC_URL=$L2_SEQUENCER_RPC_URL" >> "$GITHUB_ENV"
