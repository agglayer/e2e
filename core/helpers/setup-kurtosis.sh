#!/bin/bash
set -euo pipefail

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL
NETWORK="${1:-fork12-cdk-erigon-validium}"
CUSTOM_AGGLAYER_IMAGE="${CUSTOM_AGGLAYER_IMAGE:-""}"  # Allow optional override

# Export environment variables for CI consumption.
export_env_var() {
    name="$1"
    value="$2"
    export "${name}=${value}"
    echo "${name}=${value}" >>"${GITHUB_ENV}"
    echo "✅ Exported ${name}=${value}"
}

# ✅ Clean up old environments
kurtosis clean --all

# ✅ OP Stack Devnet Handling (No AggLayer Modifications Here)
if [[ "${NETWORK}" == "op-stack" ]]; then
    echo "🔥 Deploying Kurtosis environment for OP Stack"

    # ✅ Run Kurtosis for OP Stack
    ENCLAVE="op"
    VERSION="main"
    ARGS_FILE="https://raw.githubusercontent.com/ethpandaops/optimism-package/${VERSION}/network_params.yaml"
    kurtosis run --enclave "${ENCLAVE}" --args-file="${ARGS_FILE}" \
        "github.com/ethpandaops/optimism-package@${VERSION}"

    # ✅ Fetch and export RPC URLs
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" op-el-1-op-geth-op-node-op-kurtosis rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE}" op-batcher-op-kurtosis http)"

elif [[ "${NETWORK}" == "polygon-pos" ]]; then
    echo "🔥 Deploying Kurtosis environment for Polygon PoS"

    # ✅ Run Kurtosis for Polygon PoS
    ENCLAVE="pos"
    VERSION="v1.0.1"
    ARGS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-polygon-pos/refs/tags/${VERSION}/.github/tests/combinations/heimdall-bor-multi-validators.yml"
    kurtosis run --enclave "${ENCLAVE}" --args-file "${ARGS_FILE}" \
        "github.com/0xPolygon/kurtosis-polygon-pos@${VERSION}"

    # ✅ Fetch and export RPC URLs
    export_env_var "L1_RPC_URL" "http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" l2-el-1-bor-heimdall-validator rpc)"
    export_env_var "L2_CL_API_URL" "$(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)"
    export_env_var "L2_CL_NODE_TYPE" "heimdall"

    # ✅ Fetch and export contract addresses
    matic_contract_addresses=$(kurtosis files inspect ${ENCLAVE} matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export_env_var "L1_DEPOSIT_MANAGER_PROXY_ADDRESS" "$(echo "${matic_contract_addresses}" | jq --raw-output '.root.DepositManagerProxy')"
    export_env_var "ERC20_TOKEN_ADDRESS" "$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')"
    export_env_var "L2_STATE_RECEIVER_ADDRESS" "$(kurtosis files inspect "${ENCLAVE}" l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')"

else
    echo "🔥 Deploying Kurtosis environment for Polygon CDK network: ${NETWORK}"

    # ✅ Download the default config
    ENCLAVE="cdk"
    VERSION="main"
    COMBINATIONS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/${VERSION}/.github/tests/combinations/${NETWORK}.yml"
    
    CONFIG_FILE=$(mktemp)
    curl -sSL "${COMBINATIONS_FILE}" -o "${CONFIG_FILE}"

    # ✅ Modify AggLayer Image if Provided
    if [[ -n "${CUSTOM_AGGLAYER_IMAGE}" ]]; then
        echo "🛠 Overriding AggLayer image with: ${CUSTOM_AGGLAYER_IMAGE}"

        # Check if `agglayer_image` already exists
        if yq eval '.args.agglayer_image' "${CONFIG_FILE}" &>/dev/null; then
            echo "🔄 Updating existing agglayer_image entry..."
            yq -i -y ".args.agglayer_image = \"${CUSTOM_AGGLAYER_IMAGE}\"" "${CONFIG_FILE}"
        else
            echo "➕ Adding missing agglayer_image entry..."
            yq -i -y '.args += {"agglayer_image": "'"${CUSTOM_AGGLAYER_IMAGE}"'"}' "${CONFIG_FILE}"
        fi
    fi

    # ✅ Print final config for debugging
    echo "📄 Final Kurtosis Config (Sanity Check):"
    cat "${CONFIG_FILE}"

    # ✅ Run Kurtosis with modified config
    kurtosis run --enclave "${ENCLAVE}" --args-file="${CONFIG_FILE}" \
        "github.com/0xPolygon/kurtosis-cdk@${VERSION}"

    # ✅ Fetch and export RPC URLs
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" cdk-erigon-rpc-001 rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE}" cdk-erigon-sequencer-001 rpc)"
fi

export_env_var "ENCLAVE" "${ENCLAVE}"
