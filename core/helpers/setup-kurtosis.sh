#!/bin/bash
set -euo pipefail  

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL

BASE_FOLDER="$(dirname "$0")"
NETWORK="${1:-fork12-rollup}"

echo "🔥 Deploying Kurtosis environment for network: $NETWORK"

# Install Kurtosis if not available
if ! command -v kurtosis &> /dev/null; then
    echo "⚠️ Kurtosis CLI not found. "
fi

# Clean up old environments
kurtosis clean --all

# ✅ Deploy Kurtosis from GitHub (Same as local)
kurtosis run --enclave cdk \
            github.com/0xPolygon/kurtosis-cdk@v0.2.27 \
            --args-file="$BASE_FOLDER/combinations/${NETWORK}.yml"

# Get RPC URL
export L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
echo "✅ Exported L2_RPC_URL=$L2_RPC_URL"

# Output for CI consumption
echo "L2_RPC_URL=$L2_RPC_URL" >> "$GITHUB_ENV"
