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
ENCLAVE_NAME=${4:-"cdk"}
CUSTOM_AGGLAYER_IMAGE=${CUSTOM_AGGLAYER_IMAGE:-""} # Allow optional override.
echo "PACKAGE=${PACKAGE}"
echo "VERSION=${VERSION}"
echo "ARGS_FILE=${ARGS_FILE}"
echo "CUSTOM_AGGLAYER_IMAGE=${CUSTOM_AGGLAYER_IMAGE}"

if [[ "${PACKAGE}" == "kurtosis-cdk" ]]; then
    ARGS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/tags/${VERSION}/${ARGS_FILE}"
    echo "ENCLAVE_NAME=${ENCLAVE_NAME}"
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
    kurtosis run --enclave "${ENCLAVE_NAME}" --args-file="${CONFIG_FILE}" "github.com/0xPolygon/kurtosis-cdk@${VERSION}"

    # Export environment variables.
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE_NAME}" cdk-erigon-rpc-001 rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE_NAME}" cdk-erigon-sequencer-001 rpc)"

elif [[ "${PACKAGE}" == "kurtosis-polygon-pos" ]]; then
    ENCLAVE_NAME="pos"
    ARGS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-polygon-pos/refs/tags/${VERSION}/${ARGS_FILE}"
    echo "ENCLAVE_NAME=${ENCLAVE_NAME}"
    echo "ARGS_FILE=${ARGS_FILE}"

    # Deploy the package.
    kurtosis run --enclave "${ENCLAVE_NAME}" --args-file "${ARGS_FILE}" "github.com/0xPolygon/kurtosis-polygon-pos@${VERSION}"

    export_env_var "L1_RPC_URL" "http://$(kurtosis port print "${ENCLAVE_NAME}" el-1-geth-lighthouse rpc)"

elif [[ "${PACKAGE}" == "optimism-package" ]]; then
    ENCLAVE_NAME="op"
    ARGS_FILE="https://raw.githubusercontent.com/ethpandaops/optimism-package/${VERSION}/${ARGS_FILE}"
    echo "ENCLAVE_NAME=${ENCLAVE_NAME}"
    echo "ARGS_FILE=${ARGS_FILE}"

    # Deploy the package.
    kurtosis run --enclave "${ENCLAVE_NAME}" --args-file="${ARGS_FILE}" "github.com/ethpandaops/optimism-package@${VERSION}"

    # Export environment variables.
    export_env_var "L2_RPC_URL" "$(kurtosis port print "${ENCLAVE_NAME}" op-el-1-op-geth-op-node-op-kurtosis rpc)"
    export_env_var "L2_SEQUENCER_RPC_URL" "$(kurtosis port print "${ENCLAVE_NAME}" op-batcher-op-kurtosis http)"
else
    echo "❌ Unsupported package: ${PACKAGE}"
    exit 1
fi

export_env_var "ENCLAVE_NAME" "${ENCLAVE_NAME}"
