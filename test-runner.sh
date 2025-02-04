#!/bin/bash
set -euo pipefail

# Default Values
FILTER_TAGS=""

# Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

# Load shared env vars
. "$PROJECT_ROOT/tests/.env"

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

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --filter-tags) FILTER_TAGS="$2"; shift;;
        *) echo "❌ Unknown parameter: $1"; exit 1;;
    esac
    shift
done

echo "🚀 Running tests with tags: $FILTER_TAGS"

# 🔍 Set BATS test files
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
