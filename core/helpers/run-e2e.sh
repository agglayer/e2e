#!/bin/bash
set -euo pipefail  

# Load shared env vars
. $(dirname $0)/scripts/.env

# Allow users to specify variables dynamically
export NETWORK="${NETWORK:-fork12-rollup}"
export BATS_TESTS="${BATS_TESTS:-all}"
export TAGS="${TAGS:-light}"
export DEPLOY_INFRA="${DEPLOY_INFRA:-true}"  # New flag
export L2_SENDER_PRIVATE_KEY="$L2_SENDER_PRIVATE_KEY"

# Allow env var inputs (including L2_ETH_RPC_URL)
export GAS_TOKEN_ADDR="${GAS_TOKEN_ADDR:-0x72ae2643518179cF01bcA3278a37ceAD408DE8b2}"
export BATS_LIB_PATH="${BATS_LIB_PATH:-/usr/lib}"

# Define the base folder
BASE_FOLDER=$(dirname $0)

# Detect if we are already in the `test/` folder in CI
if [[ "$(basename $PWD)" == "test" ]]; then
    echo "Detected CI working directory is already 'test/'"
    TEST_DIR="."
else
    TEST_DIR="test"
fi

echo "Running tests for network: $NETWORK"
echo "Using GAS_TOKEN_ADDR: $GAS_TOKEN_ADDR"

if [[ "$DEPLOY_INFRA" == "true" ]]; then
    echo "Deploying infrastructure using Kurtosis..."

    # Validate the Kurtosis CLI is installed
    if ! command -v kurtosis &> /dev/null; then
        echo "Error: Kurtosis CLI not found. Please install it before running this script."
        exit 1
    fi

    kurtosis clean --all

    echo "Overriding cdk config file..."
    cp "$BASE_FOLDER/config/kurtosis-cdk-node-config.toml.template" "$KURTOSIS_FOLDER/templates/trusted-node/cdk-node-config.toml"

    kurtosis run --enclave cdk --args-file "combinations/${NETWORK}.yml" --image-download always "$KURTOSIS_FOLDER"
    kurtosis_l2_rpc_url="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
else
    echo "Skipping infrastructure deployment. Ensure the required services are already running!"
fi

export L2_RPC_URL="${L2_RPC_URL:-$kurtosis_l2_rpc_url}"

# Check if L2_RPC_URL is empty or not set
if [[ -z "$L2_RPC_URL" ]]; then
    echo "Error: L2_RPC_URL is a required environment variable. Please update the .env file."
    exit 1  # Exit the script with an error code
fi

# Run selected tests with exported environment variables
if [[ "$BATS_TESTS" == "all" ]]; then
    echo "Running all tests from $TEST_DIR/"
    env bats "$TEST_DIR/"
else
    # Ensure proper space separation & trimming
    BATS_TESTS_LIST=$(echo "$BATS_TESTS" | tr ',' '\n' | xargs -I {} echo "$TEST_DIR/{}" | tr '\n' ' ')
    echo "Running BATS tests: $BATS_TESTS_LIST"
    
    # Execute tests with `env`
    env bats $BATS_TESTS_LIST
fi
