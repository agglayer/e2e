#!/bin/bash
set -euo pipefail

# Default Values
FILTER_TAGS=""

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
    exit 0
fi

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --filter-tags) FILTER_TAGS="$2"; shift;;
        *) echo "❌ Unknown parameter: $1"; exit 1;;
    esac
    shift
done

# 🔍 Set BATS test files
echo "🚀 Running tests with tags: $FILTER_TAGS"
BATS_TESTS_LIST=$(find tests -type f -name "*.bats")

# ✅ Run BATS tests
echo -e "🧪 Running tests: \n$BATS_TESTS_LIST"
filter_tags_flag="--filter-tags $FILTER_TAGS"
if [[ -z "$FILTER_TAGS" ]]; then
    filter_tags_flag=""
fi

env bats --show-output-of-passing-tests $filter_tags_flag $BATS_TESTS_LIST
