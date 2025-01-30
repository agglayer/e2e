#!/bin/bash
set -euo pipefail  

source $(dirname $0)/scripts/env.sh  # Load shared env vars

# Allow users to specify variables dynamically
export NETWORK="${NETWORK:-fork12-rollup}"
export BATS_TESTS="${BATS_TESTS:-all}"
export DEPLOY_INFRA="${DEPLOY_INFRA:-true}"  # New flag

# Allow env var inputs (including L2_ETH_RPC_URL)
export GAS_TOKEN_ADDR="${GAS_TOKEN_ADDR:-0x72ae2643518179cF01bcA3278a37ceAD408DE8b2}"
export L2_RPC_URL="${L2_RPC_URL:-http://127.0.0.1:59761}"
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
else
    echo "Skipping infrastructure deployment. Ensure the required services are already running!"
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

# Run Tests with Go
go test -v $TEST_DIR/...