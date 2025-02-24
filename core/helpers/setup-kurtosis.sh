#!/bin/bash
set -euo pipefail

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL
NETWORK="${1:-fork12-cdk-erigon-validium}"
CUSTOM_AGGLAYER_IMAGE="${CUSTOM_AGGLAYER_IMAGE:-""}"  # Allow custom image override

# ✅ OP Stack Devnet Handling (No AggLayer Modifications Here)
if [[ "$NETWORK" == "op-stack" ]]; then
    echo "🔥 Deploying Kurtosis environment for OP Stack"
    OP_STACK_ARGS_FILE="https://raw.githubusercontent.com/ethpandaops/optimism-package/main/network_params.yaml"

    # ✅ Clean up old environments
    kurtosis clean --all

    # ✅ Run Kurtosis for OP Stack
    kurtosis run --enclave op \
        github.com/ethpandaops/optimism-package \
        --args-file="$OP_STACK_ARGS_FILE"

    # ✅ Fetch and export RPC URLs
    export L2_RPC_URL="$(kurtosis port print op op-el-1-op-geth-op-node-op-kurtosis rpc)"
    export L2_SEQUENCER_RPC_URL="$(kurtosis port print op op-batcher-op-kurtosis http)"

    echo "✅ Exported L2_RPC_URL=$L2_RPC_URL"
    echo "✅ Exported L2_SEQUENCER_RPC_URL=$L2_SEQUENCER_RPC_URL"

else
    echo "🔥 Deploying Kurtosis environment for network: $NETWORK"
    COMBINATIONS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/tags/v0.2.30/.github/tests/combinations/${NETWORK}.yml"

    # ✅ Download the default config
    CONFIG_FILE=$(mktemp)
    curl -sSL "$COMBINATIONS_FILE" -o "$CONFIG_FILE"

    # ✅ Modify AggLayer Image if Needed
    if [[ -n "$CUSTOM_AGGLAYER_IMAGE" ]]; then
        echo "🛠 Overriding AggLayer image with: $CUSTOM_AGGLAYER_IMAGE"
        
        # Check if `agglayer_image` exists in the file
        if yq eval '.args.agglayer_image' "$CONFIG_FILE" &>/dev/null; then
            echo "🔄 Updating existing agglayer_image entry..."
            yq -i ".args.agglayer_image = \"$CUSTOM_AGGLAYER_IMAGE\"" "$CONFIG_FILE"
        else
            echo "➕ Adding missing agglayer_image entry..."
            yq -i '.args.agglayer_image = "'"$CUSTOM_AGGLAYER_IMAGE"'"' "$CONFIG_FILE"
        fi
    fi

    # ✅ Print final config for debugging
    echo "📄 Final Kurtosis Config (Sanity Check):"
    cat "$CONFIG_FILE"

    # ✅ Clean up old environments
    kurtosis clean --all

    # ✅ Run Kurtosis with modified config
    kurtosis run --enclave cdk \
                github.com/0xPolygon/kurtosis-cdk@v0.2.30 \
                --args-file="$CONFIG_FILE"

    # ✅ Fetch and export RPC URLs
    export L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
    export L2_SEQUENCER_RPC_URL="$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"
fi

# ✅ Output for CI consumption
echo "L2_RPC_URL=$L2_RPC_URL" >> "$GITHUB_ENV"
echo "L2_SEQUENCER_RPC_URL=$L2_SEQUENCER_RPC_URL" >> "$GITHUB_ENV"
