#!/bin/bash
set -euo pipefail  

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL

BASE_FOLDER="$(dirname "$(dirname "$0")")"
KURTOSIS_FOLDER="${GITHUB_WORKSPACE}/kurtosis-cdk"
NETWORK="${1:-fork12-rollup}"

echo "🔥 Deploying Kurtosis environment for network: $NETWORK"

# Install Kurtosis if not available
if ! command -v kurtosis &> /dev/null; then
    echo "⚠️ Kurtosis CLI not found. "
fi

# Clean up old environments
kurtosis clean --all

mkdir -p "$KURTOSIS_FOLDER/templates/trusted-node"
cp "$BASE_FOLDER/config/kurtosis-cdk-node-config.toml.template" "$KURTOSIS_FOLDER/templates/trusted-node/cdk-node-config.toml"
cat "$KURTOSIS_FOLDER/templates/trusted-node/cdk-node-config.toml"
kurtosis run --enclave cdk --args-file "$BASE_FOLDER/combinations/${NETWORK}.yml" --image-download always "$KURTOSIS_FOLDER"

# Get RPC URL
export L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
echo "✅ Exported L2_RPC_URL=$L2_RPC_URL"

# Output for CI consumption
echo "L2_RPC_URL=$L2_RPC_URL" >> "$GITHUB_ENV"
