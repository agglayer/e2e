#!/bin/bash

# ✅ Configurable Bash Error Handling
if [[ "${ALLOW_PARTIAL_FAILURES:-false}" == "true" ]]; then
    set -uo pipefail
else
    set -euo pipefail
fi

# ✅ Default Variables
SHOW_OUTPUT="false"
FILTER_TAGS=()  # Initialize empty array

# ✅ Detect Project Root
PROJECT_ROOT="$(pwd)"
export PROJECT_ROOT

# ✅ Load shared env vars (Cross-Platform Fix)
if [[ -f "$PROJECT_ROOT/tests/.env" ]]; then
    set -a  # Enable export of all variables
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        if [[ -n "$key" && -n "$value" ]]; then
            eval "export $key=\"$value\""
        fi
    done < <(grep -v '^#' "$PROJECT_ROOT/tests/.env")
    set +a  # Disable auto-export
    echo -e "✅ Loaded $PROJECT_ROOT/tests/.env"
else
    echo "⚠️ WARNING: No .env file found at $PROJECT_ROOT/tests/.env"
fi

# ✅ Set BATS Library Path
export BATS_LIB_PATH="$PROJECT_ROOT/core/helpers/lib"
echo "📂 Resolved PROJECT_ROOT: $PROJECT_ROOT"
echo "📦 BATS_LIB_PATH set to: $BATS_LIB_PATH"

# ✅ Help Message
if [[ "${1:-}" == "--help" ]]; then
    echo "🛠️ polygon-test-runner CLI"
    echo ""
    echo "Usage: polygon-test-runner [--filter-tags <tag1,tag2,...>] | [--all] [--allow-failures] [--verbose]"
    echo ""
    echo "  --filter-tags   Run specific tests by comma-separated tags (e.g. light,uniswap)"
    echo "  --all           Run all tests (default if no filter is provided)"
    echo "  --allow-failures Allow partial test failures without stopping execution"
    echo "  --verbose       Show output of passing tests (default is off for readability)"
    exit 0
fi

# ✅ Parse CLI Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --filter-tags)
            if [[ -n "${2:-}" ]]; then
                IFS=',' read -r -a FILTER_TAGS <<< "$2"  # Split by comma into array
                shift
            fi
            ;;
        --all)
            FILTER_TAGS=()  # Run all tests
            ;;
        --allow-failures)
            export ALLOW_PARTIAL_FAILURES="true"
            ;;
        --verbose)
            SHOW_OUTPUT="true"
            ;;
        *)
            echo "❌ Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

# ✅ Build `--filter-tags` Arguments
FILTER_ARGS=()
if [[ ${#FILTER_TAGS[@]} -gt 0 ]]; then
    for tag in "${FILTER_TAGS[@]}"; do
        FILTER_ARGS+=(--filter-tags "$tag")
    done
    echo "🚀 Running tests with tags: ${FILTER_TAGS[*]}"
else
    echo "🚀 Running all tests (no filter applied)"
fi

# ✅ Select BATS test files (Fixed Bash Compatibility)
BATS_TESTS_LIST=()
while IFS= read -r file; do
    BATS_TESTS_LIST+=("$file")
done < <(find tests -type f -name "*.bats" 2>/dev/null)

# ✅ Check if any tests were found
if [[ ${#BATS_TESTS_LIST[@]} -eq 0 ]]; then
    echo "❌ ERROR: No test files found!"
    exit 1
fi

# ✅ Run BATS Tests (Minimal Output by Default)
if [[ "$SHOW_OUTPUT" == "true" ]]; then
    echo "📢 Verbose Mode Enabled: Showing output of passing tests"
    env bats --show-output-of-passing-tests "${FILTER_ARGS[@]}" "${BATS_TESTS_LIST[@]}"
else
    env bats "${FILTER_ARGS[@]}" "${BATS_TESTS_LIST[@]}"
fi
