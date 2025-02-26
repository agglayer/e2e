#!/bin/bash
set -euo pipefail

# 🚀 Set up Kurtosis Devnet & Export L2_RPC_URL

NETWORK="${1:-fork12-cdk-erigon-validium}"

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

# ✅ Check if the network is OP Stack and adjust setup accordingly
if [[ "${NETWORK}" == "op-stack" ]]; then
    echo "🔥 Deploying Kurtosis environment for OP Stack"

    # ✅ Run Kurtosis for OP Stack
    ENCLAVE="op"
    VERSION="main"
    ARGS_FILE="https://raw.githubusercontent.com/ethpandaops/optimism-package/${VERSION}/network_params.yaml"
    kurtosis run --enclave "${ENCLAVE}" --args-file="${ARGS_FILE}" \
        "github.com/ethpandaops/optimism-package@${VERSION}"

    # ✅ Fetch and export RPC URLs
    export_env_var "L2_RPC_URL" $(kurtosis port print "${ENCLAVE}" op-el-1-op-geth-op-node-op-kurtosis rpc)
    export_env_var "L2_SEQUENCER_RPC_URL" $(kurtosis port print "${ENCLAVE}" op-batcher-op-kurtosis http)

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
    export_env_var "L2_RPC_URL" $(kurtosis port print "${ENCLAVE}" l2-el-1-bor-heimdall-validator rpc)
    export_env_var "L2_CL_API_URL" $(kurtosis port print "${ENCLAVE}" l2-cl-1-heimdall-bor-validator http)
    export_env_var "L2_CL_NODE_TYPE" "heimdall"

    # ✅ Fetch and export contract addresses
    matic_contract_addresses=$(kurtosis files inspect ${ENCLAVE} matic-contract-addresses contractAddresses.json | tail -n +2 | jq)
    export_env_var "L1_DEPOSIT_MANAGER_PROXY_ADDRESS" $(echo "${matic_contract_addresses}" | jq --raw-output '.root.DepositManagerProxy')
    export_env_var "ERC20_TOKEN_ADDRESS" $(echo "${matic_contract_addresses}" | jq --raw-output '.root.tokens.MaticToken')
    export_env_var "L2_STATE_RECEIVER_ADDRESS" $(kurtosis files inspect "${ENCLAVE}" l2-el-genesis genesis.json | tail -n +2 | jq --raw-output '.config.bor.stateReceiverContract')
else
    echo "🔥 Deploying Kurtosis environment for Polygon CDK network: ${NETWORK}"

    # ✅ Run Kurtosis from GitHub (just like local)
    ENCLAVE="cdk"
    VERSION="v0.2.30"
    COMBINATIONS_FILE="https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/tags/${VERSION}/.github/tests/combinations/${NETWORK}.yml"
    echo "📄 Using combinations file: ${COMBINATIONS_FILE}"
    kurtosis run --enclave "${ENCLAVE}" --args-file="${COMBINATIONS_FILE}" \
        "github.com/0xPolygon/kurtosis-cdk@${VERSION}"

    # ✅ Fetch and export RPC URLs
    export_env_var "L2_RPC_URL" $(kurtosis port print "${ENCLAVE}" cdk-erigon-rpc-001 rpc)
    export_env_var "L2_SEQUENCER_RPC_URL" $(kurtosis port print "${ENCLAVE}" cdk-erigon-sequencer-001 rpc)
fi

export_env_var "ENCLAVE" "${ENCLAVE}"
