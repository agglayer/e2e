#!/bin/bash
set -euo pipefail

# Initialize your token:
#     erc20_init "$gas_token_address" "$rpc_url"
# Call functions for your token:
#     token_balance=$(erc20_balance "$eth_address")
#     erc20_approve "$private_key" "$spender_address" "$wei_amount"

# If you have more than one ERC20 token, you can use the third argument to differentiate them:
#     erc20_init "$gas_token_address_0" "$rpc_url" "0"
#     erc20_init "$gas_token_address_1" "$rpc_url" "1
# And then call the functions adding that identifier:
#     token_balance=$(erc20_balance "$eth_address" "0")
#     erc20_approve "$private_key" "$spender_address" "$wei_amount" "1"

# Function to initialize ERC20-related variables
function erc20_init() {
    local erc20_id="${3:-0}"  # Use third arg if provided, else default to "0"

    export "ERC20_${erc20_id}_ADDR=$1"
    export "ERC20_${erc20_id}_RPC_URL=$2"
    export "ERC20_${erc20_id}_INIT=1"
}

# Function to get the balance of an ERC20 token for a given address
function erc20_balance() {
    local account_addr="$1"
    local erc20_id="${2:-0}"

    # Check that erc20_init was called
    local init_var="ERC20_${erc20_id}_INIT"
    if [[ -z "${!init_var}" ]]; then
        echo "❌ Error: ERC20_$erc20_id not initialized. Run erc20_init first."
        exit 1
    fi

    # Dynamically resolve all required variables
    local rpc_var="ERC20_${erc20_id}_RPC_URL"
    local addr_var="ERC20_${erc20_id}_ADDR"

    local rpc_url="${!rpc_var}"
    local contract_addr="${!addr_var}"

    # Query balance using cast
    local balance_wei=$(cast call --rpc-url "$rpc_url" "$contract_addr" 'balanceOf(address)' "$account_addr" | awk '{print $1}' | cast to-dec)

    # Return via stdout (not return code!)
    echo "$balance_wei"
}

function erc20_approve() {
    local sender_key="$1"
    local spender_addr="$2"
    local amount="$3"
    local erc20_id="${4:-0}"

    # Check that erc20_init was called
    local init_var="ERC20_${erc20_id}_INIT"
    if [[ -z "${!init_var}" ]]; then
        echo "❌ Error: ERC20_$erc20_id not initialized. Run erc20_init first."
        exit 1
    fi

    # Dynamically resolve all required variables
    local rpc_var="ERC20_${erc20_id}_RPC_URL"
    local addr_var="ERC20_${erc20_id}_ADDR"

    local rpc_url="${!rpc_var}"
    local contract_addr="${!addr_var}"

    # Approve the spender to spend the specified amount
    cast send --rpc-url "$rpc_url" "$contract_addr" 'approve(address,uint256)' "$spender_addr" "$amount" --private-key "$sender_key" >&2
    if [ $? -ne 0 ]; then
        echo "❌ Failed to approve $spender_addr to spend $amount of ERC20 token at $contract_addr"
        exit 1
    fi
    echo "✅ Approved $spender_addr to spend $amount of ERC20 token at $contract_addr"
}
