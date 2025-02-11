_common_setup() {
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'
    
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    PATH="$PROJECT_ROOT/src:$PATH"
    
    # Standard contract addresses
    export GAS_TOKEN_ADDR="${GAS_TOKEN_ADDR:-0x72ae2643518179cF01bcA3278a37ceAD408DE8b2}"

    # Standard function signatures
    export mint_fn_sig="function mint(address,uint256)"
    export balance_of_fn_sig="function balanceOf(address) (uint256)"
    export approve_fn_sig="function approve(address,uint256)"

    # Kurtosis service setup
    export enclave=${KURTOSIS_ENCLAVE:-cdk}
    export contracts_container=${KURTOSIS_CONTRACTS:-contracts-001}
    export contracts_service_wrapper=${KURTOSIS_CONTRACTS_WRAPPER:-"kurtosis service exec $enclave $contracts_container"}
    export erigon_rpc_node=${KURTOSIS_ERIGON_RPC:-cdk-erigon-rpc-001}
  
    # ✅ Standardized L2 RPC URL Handling
    if [[ -n "${L2_RPC_URL:-}" ]]; then
        export l2_rpc_url="$L2_RPC_URL"
    elif [[ -n "${KURTOSIS_ENCLAVE:-}" ]]; then
        export l2_rpc_url="$(kurtosis port print "$enclave" "$erigon_rpc_node" rpc)"
    else
        echo "❌ ERROR: No valid RPC URL found!"
        exit 1
    fi

    echo "🔧 Using L2 RPC URL: $l2_rpc_url"

    # ✅ Generate a fresh wallet
    wallet_json=$(cast wallet new --json)
    export private_key=$(echo "$wallet_json" | jq -r '.[0].private_key')
    export public_address=$(echo "$wallet_json" | jq -r '.[0].address')

    if [[ -z "$private_key" || -z "$public_address" ]]; then
        echo "❌ Failed to generate wallet."
        exit 1
    fi

    echo "🆕 Generated wallet: $public_address"

    # ✅ Check Admin Wallet Balance Before Sending Funds
    export admin_private_key="${L2_SENDER_PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    admin_balance=$(cast balance "$(cast wallet address --private-key "$admin_private_key")" --ether --rpc-url "$l2_rpc_url")

    if (( $(echo "$admin_balance < 1" | bc -l) )); then
        echo "❌ ERROR: Admin wallet is out of funds! Current balance: $admin_balance ETH"
        exit 1
    fi

    # ✅ Prefund Test Wallet (Retry if Needed)
    retries=3
    while [[ "$retries" -gt 0 ]]; do
        funding_tx_hash=$(cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$admin_private_key" --value 50000000000000000000 "$public_address") && break
        echo "⚠️ Prefunding failed, retrying..."
        sleep 5
        ((retries--))
    done

    if [[ "$retries" -eq 0 ]]; then
        echo "❌ ERROR: Failed to fund test wallet after multiple attempts!"
        exit 1
    fi

    echo "💰 Sent 50 ETH to $public_address. TX: $funding_tx_hash"

    # ✅ Wait for funds to be available
    sleep 10
    sender_balance=$(cast balance "$public_address" --ether --rpc-url "$l2_rpc_url")

    if (( $(echo "$sender_balance < 1" | bc -l) )); then
        echo "❌ ERROR: Wallet did not receive test funds!"
        exit 1
    fi
}
