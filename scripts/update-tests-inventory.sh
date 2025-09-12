#!/usr/bin/env bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INVENTORY_FILE="${PROJECT_ROOT}/TESTSINVENTORY.md"

echo -e "${GREEN}Updating Tests Inventory...${NC}"

# Function to check if a file is a user test file (not helper/library)
is_user_test_file() {
    local file="$1"
    
    # Exclude core helper files and libraries
    case "$file" in
        */core/helpers/*) return 1 ;;
        */node_modules/*) return 1 ;;
        */lib/*) return 1 ;;
        *test_helper*) return 1 ;;
        *helper*) return 1 ;;
        */bats-*/*) return 1 ;;
        *) return 0 ;;
    esac
}

# Function to extract test info from bats files
extract_test_info() {
    local file="$1"
    local relative_path="${file#${PROJECT_ROOT}/}"
    
    # Extract test names from @test lines
    grep -n "^@test" "$file" | while IFS=: read -r line_num content; do
        # Extract test name from @test "test name"
        test_name=$(echo "$content" | sed -n 's/@test "\([^"]*\)".*/\1/p')
        if [[ -n "$test_name" ]]; then
            echo "| $test_name | [Link](./$relative_path#L$line_num) | |"
        fi
    done
}

# Function to categorize tests based on file path
categorize_test() {
    local file="$1"
    case "$file" in
        */tests/lxly/*) echo "LxLy Tests" ;;
        */tests/agglayer/*) echo "AggLayer Tests" ;;
        */tests/cdk-erigon/*) echo "CDK Erigon Tests" ;;
        */tests/execution/*) echo "Execution Layer Tests" ;;
        */tests/op/*) echo "CDK OP Geth Tests" ;;
        */tests/cdk/*) echo "CDK Tests" ;;
        */tests/pectra/*) echo "Pectra Tests" ;;
        */tests/dapps/*) echo "DApps Tests" ;;
        */tests/ethereum-test-cases/*) echo "Ethereum Test Cases" ;;
        */tests/polycli-loadtests/*) echo "Load Tests" ;;
        */scenarios/*) echo "Full System Tests" ;;
        */tests/*) echo "Other Tests" ;;
        *) echo "Miscellaneous Tests" ;;
    esac
}

# Create temporary file for new inventory
TEMP_INVENTORY=$(mktemp)

# Write header
cat > "$TEMP_INVENTORY" << 'EOF'
# Tests Inventory

Table of tests currently implemented or being implemented in the E2E repository.

EOF

# Categories and their test files
declare -A categories
categories["LxLy Tests"]=""
categories["AggLayer Tests"]=""
categories["CDK Erigon Tests"]=""
categories["CDK Tests"]=""
categories["Pectra Tests"]=""
categories["DApps Tests"]=""
categories["Ethereum Test Cases"]=""
categories["Execution Layer Tests"]=""
categories["Load Tests"]=""
categories["CDK OP Geth Tests"]=""
categories["Full System Tests"]=""
categories["Other Tests"]=""
categories["Miscellaneous Tests"]=""

# Find all .bats files and categorize (only user test files)
while IFS= read -r file; do
    if [[ -f "$file" ]] && is_user_test_file "$file"; then
        category=$(categorize_test "$file")
        if [[ -n "${categories[$category]+isset}" ]]; then
            categories["$category"]+="$file"$'\n'
        fi
    fi
done < <(find "$PROJECT_ROOT" -name "*.bats" -type f | sort)

# Generate inventory for each category (only if it has files)
for category in "LxLy Tests" "AggLayer Tests" "CDK Erigon Tests" "CDK Tests" "Pectra Tests" "DApps Tests" "Ethereum Test Cases" "Execution Layer Tests" "Load Tests" "CDK OP Geth Tests" "Full System Tests" "Other Tests" "Miscellaneous Tests"; do
    if [[ -n "${categories[$category]}" ]]; then
        echo "" >> "$TEMP_INVENTORY"
        echo "## $category" >> "$TEMP_INVENTORY"
        echo "" >> "$TEMP_INVENTORY"
        echo "| Test Name | Reference | Notes |" >> "$TEMP_INVENTORY"
        echo "|-----------|-----------|-------|" >> "$TEMP_INVENTORY"
        
        # Create temp file for this category's tests
        CATEGORY_TEMP=$(mktemp)
        
        # Process each file in this category and collect all tests (preserve file order, sort tests within files)
        while IFS= read -r file; do
            if [[ -n "$file" && -f "$file" ]]; then
                extract_test_info "$file" >> "$CATEGORY_TEMP"
            fi
        done <<< "${categories[$category]}"
        
        # Sort the tests within this category and append to main inventory
        sort "$CATEGORY_TEMP" >> "$TEMP_INVENTORY"
        rm "$CATEGORY_TEMP"
    fi
done

# Add Kurtosis Tests section (these are external references)
echo "" >> "$TEMP_INVENTORY"
echo "## Kurtosis Tests" >> "$TEMP_INVENTORY"
echo "" >> "$TEMP_INVENTORY"
echo "| Test Name | Reference | Notes |" >> "$TEMP_INVENTORY"
echo "|-----------|-----------|-------|" >> "$TEMP_INVENTORY"
cat >> "$TEMP_INVENTORY" << 'EOF'
| Fork 9 validium w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-validium.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-rollup.yml) | |
| Fork 9 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-validium.yml) | |
| Fork 11 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-rollup.yml) | |
| Fork 11 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 11 validium w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork11-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 12 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-rollup.yml) | |
| Fork 12 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 12 soverign w/ erigon stack and SP1 | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-sovereign.yml) | |
| Fork 13 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-rollup.yml) | |
| Fork 13 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-validium.yml) | |
| CDK-OP-Stack wit network SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct-real-prover.yml) | |
| CDK-OP-Stack with mock SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct.yml) | |
| CDK-OP-Stack without SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/nightly/op-rollup/op-default.yml) | |
EOF

# Add External Test References section
echo "" >> "$TEMP_INVENTORY"
echo "## External Test References" >> "$TEMP_INVENTORY"
echo "" >> "$TEMP_INVENTORY"
echo "| Test Name | Reference | Notes |" >> "$TEMP_INVENTORY"
echo "|-----------|-----------|-------|" >> "$TEMP_INVENTORY"
cat >> "$TEMP_INVENTORY" << 'EOF'
| Manual acceptance criteria | [Link](https://www.notion.so/polygontechnology/9dc3c0e78e7940a39c7cfda5fd3ede8f?v=4dfc351d725c4792adb989a4aad8b69e) | |
| Access list tests | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/main/tests/berlin/eip2930_access_list) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Same block deployment and execution | [Link](https://github.com/jhkimqd/execution-spec-tests/blob/jihwan/cdk-op-geth/tests/custom/same_block_deploy_and_call.py) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-1559 Implementation | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/static/state_tests/stEIP1559) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-6780 Implementation | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/cancun/eip6780_selfdestruct) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Every known opcode | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/frontier/opcodes) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Blob, Accesslist, EIP-1559, EIP-7702 | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Smooth crypto test cases | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/smoothcrypto/tasks/main.yml) | Some functions with [libSCL_eddsaUtils.sol](https://github.com/get-smooth/crypto-lib/blob/main/src/lib/libSCL_eddsaUtils.sol) does not work |
| Ethereum test suite stress tests | [Link](https://github.com/0xPolygon/jhilliard/blob/main/evm-rpc-tests/misc/run-retest-with-cast.sh) | |
EOF

# Check if there are differences
if ! diff -q "$INVENTORY_FILE" "$TEMP_INVENTORY" > /dev/null 2>&1; then
    echo -e "${YELLOW}Differences found between current and generated inventory.${NC}"
    echo "Updating $INVENTORY_FILE..."
    
    # Replace with new content
    mv "$TEMP_INVENTORY" "$INVENTORY_FILE"
    echo -e "${GREEN}Tests inventory updated successfully!${NC}"
    
    # Show summary of changes
    echo -e "${YELLOW}Summary of changes:${NC}"
    user_bats_count=$(find "$PROJECT_ROOT" -name "*.bats" -type f | while read -r file; do is_user_test_file "$file" && echo "$file"; done | wc -l)
    echo "- User .bats files found: $user_bats_count"
    echo "- Categories with tests: $(grep -c "^## " "$INVENTORY_FILE")"
else
    echo -e "${GREEN}Tests inventory is already up to date.${NC}"
    rm "$TEMP_INVENTORY"
fi

echo -e "${GREEN}Done!${NC}"