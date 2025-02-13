#!/bin/bash
set -euo pipefail

# Default Values
FILTER_TAGS=()  # Initialize as an empty array

# Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

<<<<<<< HEAD
# Load shared env vars safely
if [[ -f "$PROJECT_ROOT/tests/.env" ]]; then
    export $(grep -v '^#' "$PROJECT_ROOT/tests/.env" | xargs)
    echo -e "✅ Loaded $PROJECT_ROOT/tests/.env"
else
    echo "⚠️ WARNING: No .env file found at $PROJECT_ROOT/tests/.env"
fi
=======
# Load shared env vars
export $(cat $PROJECT_ROOT/tests/.env | grep -v "#" | grep = | xargs) 
echo -e "✅ Loaded $PROJECT_ROOT/tests/.env"
>>>>>>> main

# Set BATS Library Path (Absolute Path)
export BATS_LIB_PATH="$PROJECT_ROOT/core/helpers/lib"
echo "📂 Resolved PROJECT_ROOT: $PROJECT_ROOT"
echo "📦 BATS_LIB_PATH set to: $BATS_LIB_PATH"

# Help Message
if [[ "${1:-}" == "--help" ]]; then
    echo "🛠️ polygon-test-runner CLI"
    echo ""
    echo "Usage: polygon-test-runner [--filter-tags <tag1,tag2,...>] | [--all]"
    exit 0
fi

# 🔍 Parse CLI Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --filter-tags)
            if [[ -n "${2:-}" ]]; then
                IFS=',' read -r -a FILTER_TAGS <<< "$2"  # Split by comma into array
                shift
            fi
            ;;
        --all)
            FILTER_TAGS=()  # Explicitly clear tags to run all tests
            ;;
        "")
            echo "⚠️ Ignoring empty argument"
            ;;
        *)
            echo "❌ Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

<<<<<<< HEAD
# Build multiple --filter-tags arguments (only if tags exist)
FILTER_ARGS=()
if [[ ${#FILTER_TAGS[@]} -gt 0 ]]; then
    for tag in "${FILTER_TAGS[@]}"; do
        FILTER_ARGS+=(--filter-tags "$tag")
    done
    echo "🚀 Running tests with tags: ${FILTER_TAGS[*]}"
=======
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
    # if L2_RPC_URL is not specified, get it from Kurtosis
    if [[ -z "${L2_RPC_URL:-}" ]]; then
        L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
        export L2_RPC_URL
        echo "L2_RPC_URL" $L2_RPC_URL
    fi
    # if L2_SEQUENCER_RPC_URL is not specified, get it from Kurtosis
    if [[ -z "${L2_SEQUENCER_RPC_URL:-}" ]]; then
        L2_SEQUENCER_RPC_URL="$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"
        export L2_SEQUENCER_RPC_URL
        echo "L2_SEQUENCER_RPC_URL" $L2_SEQUENCER_RPC_URL
    fi
>>>>>>> main
else
    echo "🚀 Running all tests (no filter applied)"
fi

<<<<<<< HEAD
# Select BATS test files
BATS_TESTS_LIST=$(find tests -type f -name "*.bats")

# ✅ Run BATS tests with **correct** `--filter-tags` format
if [[ ${#FILTER_ARGS[@]} -gt 0 ]]; then
    env bats --show-output-of-passing-tests "${FILTER_ARGS[@]}" $BATS_TESTS_LIST
=======
# 🔍 Set BATS test files
echo "🚀 Running tests with tags: $FILTER_TAGS"
if [[ "${BATS_TESTS:-}" == "all" ]] || [[ -z "${BATS_TESTS:-}" ]]; then
    BATS_TESTS_LIST=$(find tests -type f -name "*.bats")
>>>>>>> main
else
    env bats --show-output-of-passing-tests $BATS_TESTS_LIST
fi
