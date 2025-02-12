#!/bin/bash
set -euo pipefail

# Default Values
FILTER_TAGS=()  # Initialize as an empty array

# Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

# Load shared env vars safely
if [[ -f "$PROJECT_ROOT/tests/.env" ]]; then
    export $(grep -v '^#' "$PROJECT_ROOT/tests/.env" | xargs)
    echo -e "✅ Loaded $PROJECT_ROOT/tests/.env"
else
    echo "⚠️ WARNING: No .env file found at $PROJECT_ROOT/tests/.env"
fi

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

# Build multiple --filter-tags arguments (only if tags exist)
FILTER_ARGS=()
if [[ ${#FILTER_TAGS[@]} -gt 0 ]]; then
    for tag in "${FILTER_TAGS[@]}"; do
        FILTER_ARGS+=(--filter-tags "$tag")
    done
    echo "🚀 Running tests with tags: ${FILTER_TAGS[*]}"
else
    echo "🚀 Running all tests (no filter applied)"
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

# ✅ Run BATS tests with **correct** `--filter-tags` format
if [[ ${#FILTER_ARGS[@]} -gt 0 ]]; then
    env bats --show-output-of-passing-tests "${FILTER_ARGS[@]}" $BATS_TESTS_LIST
else
    env bats --show-output-of-passing-tests $BATS_TESTS_LIST
fi
