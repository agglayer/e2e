#!/bin/bash
set -euo pipefail

# Default Values
BATS_TESTS=""
ENV_VARS=""
TAGS=""

# Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

# Set BATS Library Path
export BATS_LIB_PATH="$PROJECT_ROOT/core/helpers/lib"
echo "📂 Resolved PROJECT_ROOT: $PROJECT_ROOT"
echo "📦 BATS_LIB_PATH set to: $BATS_LIB_PATH"

# Help Message
if [[ "${1:-}" == "--help" ]]; then
    echo "🛠️ polygon-test-runner CLI"
    echo ""
    echo "Usage: polygon-test-runner --tags <tags> --env-vars <key=value,key=value>"
    echo ""
    echo "Options:"
    echo "  --tags       Specify test categories (light, heavy, danger) OR specific .bats files."
    echo "  --env-vars   Pass environment variables needed for the tests (e.g. L2_RPC_URL, L2_SENDER_PRIVATE_KEY)."
    echo "  --help       Show this help message."
    echo ""
    echo "Examples:"
    echo "  polygon-test-runner --tags 'light' --env-vars 'L2_RPC_URL=http://127.0.0.1:50504,L2_SENDER_PRIVATE_KEY=xyz'"
    exit 0
fi

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tags) TAGS="$2"; shift;;
        --env-vars) ENV_VARS="$2"; shift;;
        *) echo "❌ Unknown parameter: $1"; exit 1;;
    esac
    shift
done

# Validate Required Arguments
if [[ -z "$TAGS" ]]; then
    echo "❌ Error: --tags is required. Use --help for usage."
    exit 1
fi

echo "🚀 Running tests with: $TAGS"
echo "📦 Extra ENV Vars: $ENV_VARS"

# ✅ **Explicitly Export ENV Vars for BATS**
if [[ -n "$ENV_VARS" ]]; then
    IFS=',' read -ra KV_PAIRS <<< "$ENV_VARS"
    for pair in "${KV_PAIRS[@]}"; do
        export "$pair"
        echo "🔑 Exported: $pair"
    done
fi

# Convert Tags to Test Selection
BATS_TESTS=""
IFS=',' read -ra TAG_ARRAY <<< "$TAGS"
for tag in "${TAG_ARRAY[@]}"; do
    if [[ -f "$tag" ]]; then
        BATS_TESTS+=" $tag "
    elif [[ -d "tests/$tag" ]]; then
        BATS_TESTS+=" tests/$tag/* "
    else
        echo "❌ Warning: '$tag' is neither a test file nor a valid tag. Skipping."
    fi
done

# Ensure Tests Exist
if [[ -z "$(ls -A $BATS_TESTS 2>/dev/null)" ]]; then
    echo "❌ No valid tests found for: $TAGS"
    exit 1
fi

# Run BATS Tests with Exported ENV Vars
echo "🧪 Running tests: $BATS_TESTS"
env bats $BATS_TESTS
