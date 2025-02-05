#!/bin/bash
set -euo pipefail

# Default Values
FILTER_TAGS=""
BATS_TESTS=""
DEPLOY_INFRA="false"

# Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

# Load shared env vars
export $(cat $PROJECT_ROOT/tests/.env | grep = | xargs) 
echo -e "✅ Loaded $PROJECT_ROOT/tests/.env"

# Set BATS Library Path
export BATS_LIB_PATH="$PROJECT_ROOT/core/helpers/lib"
echo "📂 Resolved PROJECT_ROOT: $PROJECT_ROOT"
echo "📦 BATS_LIB_PATH set to: $BATS_LIB_PATH"

# Help Message
if [[ "${1:-}" == "--help" ]]; then
    echo "🛠️ polygon-test-runner CLI"
    echo ""
    echo "Usage: polygon-test-runner --filter-tags <tags>"
    echo ""
    echo "Options:"
    echo "  --filter-tags  Run tests with specific BATS tags (e.g., light, heavy, danger)."
    echo "  --help         Show this help message."
    echo ""
    echo "Examples:"
    echo "  polygon-test-runner --filter-tags 'light'"
    echo "  polygon-test-runner --filter-tags 'batch-verification,heavy'"
    exit 0
fi

#DEFAULT ARGUMENTS


# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --filter-tags) FILTER_TAGS="$2"; shift;;
        --deploy-infra) DEPLOY_INFRA="$2"; shift;;
        --network) NETWORK="$2"; shift;;
        --bats-tests) BATS_TESTS="$2"; shift;;
        --kurtosis-folder) KURTOSIS_FOLDER="$2"; shift;;
        *) echo "❌ Unknown parameter: $1"; exit 1;;
    esac
    shift
done

# 🔍 Set infra
if [[ "$DEPLOY_INFRA" == "true" ]]; then
    echo "⏳ Deploying infrastructure using Kurtosis..."

    if [[ -z "${NETWORK:-}" ]]; then
        echo "❌ Error: --network is required when --deploy-infra is set to true. Please set it before running this script."
        exit 1
    fi

    if [[ -z "${KURTOSIS_FOLDER:-}" ]]; then
        echo "❌ Error: --kurtosis-folder is required when --deploy-infra is set to true. Please set it before running this script."
        exit 1
    fi

    # Validate the Kurtosis CLI is installed
    if ! command -v kurtosis &> /dev/null; then
        echo "❌ Error: Kurtosis CLI not found. Please install it before running this script."
        exit 1
    fi

    kurtosis clean --all

    echo "🧪 Overriding cdk config file..."
    cp "$PROJECT_ROOT/core/helpers/config/kurtosis-cdk-node-config.toml.template" "$KURTOSIS_FOLDER/templates/trusted-node/cdk-node-config.toml"

    kurtosis run --enclave cdk --args-file "$PROJECT_ROOT/core/helpers/combinations/${NETWORK}.yml" --image-download always "$KURTOSIS_FOLDER"
    L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
else
    echo "⏩ Skipping infrastructure deployment. Ensure the required services are already running!"
fi

# Check if L2_RPC_URL is empty or not set
if [[ -z "$L2_RPC_URL" ]]; then
    echo "Error: L2_RPC_URL is a required environment variable. Please update the .env file."
    exit 1  # Exit the script with an error code
fi

# 🔍 Set BATS test files
echo "🚀 Running tests with tags: $FILTER_TAGS"
if [[ "${BATS_TESTS:-}" == "all" ]] || [[ -z "${BATS_TESTS:-}" ]]; then 
    BATS_TESTS_LIST=$(find tests -type f -name "*.bats")
else
    # Ensure proper space separation & trimming
    BATS_TESTS_LIST=$(echo "$BATS_TESTS" | tr ',' '\n' | xargs -I {} echo "./tests/{}" | tr '\n' ' ')
fi

# ✅ Run BATS tests with --filter-tags support
echo -e "🧪 Running tests: \n$BATS_TESTS_LIST"
filter_tags_flag="--filter-tags "$FILTER_TAGS""
if [[ -z "$FILTER_TAGS" ]]; then
    filter_tags_flag=""
fi

env bats $filter_tags_flag $BATS_TESTS_LIST
