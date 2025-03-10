#!/bin/bash
set -euo pipefail

# Export environment variables for CI consumption.
export_env_var() {
    name="$1"
    value="$2"
    export "${name}=${value}"
    echo "${name}=${value}" >>"${GITHUB_ENV}"
    echo "✅ Exported ${name}=${value}"
}

PACKAGE=${1:-"kurtosis-cdk"}
VERSION=${2:-"v0.3.2"}
ARGS_FILE=${3:-".github/tests/combinations/fork12-cdk-erigon-validium.yml"}
CUSTOM_AGGLAYER_IMAGE=${CUSTOM_AGGLAYER_IMAGE:-""} # Allow optional override.
echo "PACKAGE=${PACKAGE}"
echo "VERSION=${VERSION}"
echo "ARGS_FILE=${ARGS_FILE}"
echo "CUSTOM_AGGLAYER_IMAGE=${CUSTOM_AGGLAYER_IMAGE}"

if [[ "${PACKAGE}" == "kurtosis-cdk" ]]; then
    ENCLAVE="cdk"
    ARGS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/tags/${VERSION}/${ARGS_FILE}"
    echo "ENCALVE=${ENCLAVE}"
    echo "ARGS_FILE=${ARGS_FILE}"

    # If provided, add custom agglayer image to the args file.
    CONFIG_FILE=$(mktemp)
    curl -sSL "${ARGS_FILE}" -o "${CONFIG_FILE}"

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
    echo "CONFIG_FILE=${CONFIG_FILE}"
    cat "${CONFIG_FILE}"

    # Deploy the package.
    kurtosis run --enclave "${ENCLAVE}" --args-file="${CONFIG_FILE}" "github.com/0xPolygon/kurtosis-cdk@${VERSION}"

    # Export environment variables.
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" cdk-erigon-rpc-001 rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE}" cdk-erigon-sequencer-001 rpc)"

elif [[ "${PACKAGE}" == "kurtosis-polygon-pos" ]]; then
    ENCLAVE="pos"
    ARGS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-polygon-pos/refs/tags/${VERSION}/${ARGS_FILE}"
    echo "ENCLAVE=${ENCLAVE}"
    echo "ARGS_FILE=${ARGS_FILE}"

    # Deploy the package.
    kurtosis run --enclave "${ENCLAVE}" --args-file "${ARGS_FILE}" "github.com/0xPolygon/kurtosis-polygon-pos@${VERSION}"

    # Export environment variables.
    export_env_var "L1_RPC_URL" "http://$(kurtosis port print "${ENCLAVE}" el-1-geth-lighthouse rpc)"
    if [[ "${ARGS_FILE}" == "*heimdall-v2*" ]]; then
        export_env_var "L2_CL_NODE_TYPE" "heimdall-v2"
    else
        export_env_var "L2_CL_NODE_TYPE" "heimdall"
    fi
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" "l2-el-1-bor-${L2_CL_NODE_TYPE}-validator" rpc)"
    export_env_var "L2_CL_API_URL" "$(kurtosis port print "${ENCLAVE}" "l2-cl-1-${L2_CL_NODE_TYPE}-bor-validator" http)"

    matic_contract_addresses=$(kurtosis files inspect ${ENCLAVE} matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export_env_var "L1_DEPOSIT_MANAGER_PROXY_ADDRESS" "$(echo "${matic_contract_addresses}" | jq --raw-output '.root.DepositManagerProxy')"
    export_env_var "ERC20_TOKEN_ADDRESS" "$(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')"
    export_env_var "L2_STATE_RECEIVER_ADDRESS" "$(kurtosis files inspect "${ENCLAVE}" l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')"

elif [[ "${PACKAGE}" == "optimism-package" ]]; then
    ENCLAVE="op"
    ARGS_FILE="https://raw.githubusercontent.com/ethpandaops/optimism-package/${VERSION}/${ARGS_FILE}"
    echo "ENCLAVE=${ENCLAVE}"
    echo "ARGS_FILE=${ARGS_FILE}"

    # Deploy the package.
    kurtosis run --enclave "${ENCLAVE}" --args-file="${ARGS_FILE}" "github.com/ethpandaops/optimism-package@${VERSION}"

    # Export environment variables.
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE}" op-el-1-op-geth-op-node-op-kurtosis rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE}" op-batcher-op-kurtosis http)"
else
    echo "❌ Unsupported package: ${PACKAGE}"
    exit 1
fi

export_env_var "ENCLAVE" "${ENCLAVE}"
