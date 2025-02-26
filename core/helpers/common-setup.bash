_common_setup() {
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'

    # ✅ Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    PATH="$PROJECT_ROOT/src:$PATH"

    # ✅ Standard contract addresses
    export GAS_TOKEN_ADDR="${GAS_TOKEN_ADDR:-0x72ae2643518179cF01bcA3278a37ceAD408DE8b2}"
    export DEPLOY_SALT="${DEPLOY_SALT:-0x0000000000000000000000000000000000000000000000000000000000000000}"

    # ✅ Standard function signatures
    export MINT_FN_SIG="function mint(address,uint256)"
    export BALANCE_OF_FN_SIG="function balanceOf(address) (uint256)"
    export APPROVE_FN_SIG="function approve(address,uint256)"

    # ✅ Kurtosis service setup
    export ENCLAVE="${ENCLAVE:-cdk}"
    export CONTRACTS_CONTAINER="${KURTOSIS_CONTRACTS:-contracts-001}"
    export CONTRACTS_SERVICE_WRAPPER="${KURTOSIS_CONTRACTS_WRAPPER:-"kurtosis service exec $ENCLAVE $CONTRACTS_CONTAINER"}"
    export ERIGON_RPC_NODE="${KURTOSIS_ERIGON_RPC:-cdk-erigon-rpc-001}"
    export ERIGON_SEQUENCER_RPC_NODE="${KURTOSIS_ERIGON_SEQUENCER_RPC:-cdk-erigon-sequencer-001}"

    # ✅ Standardized L2 RPC URL Handling
    L2_RPC_URL_CMD=$(kurtosis port print "$ENCLAVE" "$ERIGON_RPC_NODE" rpc)
    export L2_RPC_URL="$L2_RPC_URL_CMD"
    echo "🔧 Using L2 RPC URL: $L2_RPC_URL"

    # ✅ Standardized L2 SEQUENCER RPC URL Handling
    if [[ "$ENCLAVE" == "cdk" ]]; then
        L2_SEQUENCER_RPC_URL_CMD=$(kurtosis port print "$ENCLAVE" "$ERIGON_SEQUENCER_RPC_NODE" rpc)
        export L2_SEQUENCER_RPC_URL="$L2_SEQUENCER_RPC_URL_CMD"
    elif [[ "$ENCLAVE" == "op" ]]; then
        echo "🔥 Detected OP Stack, using op-batcher-op-kurtosis"
        L2_SEQUENCER_RPC_URL_CMD=$(kurtosis port print "$ENCLAVE" op-batcher-op-kurtosis http)
        export L2_SEQUENCER_RPC_URL="$L2_SEQUENCER_RPC_URL_CMD"
    fi
    echo "🔧 Using L2 SEQUENCER RPC URL: $L2_SEQUENCER_RPC_URL"

    # ✅ Generate a fresh wallet
    wallet_json=$(cast wallet new --json)

    echo "🛠 Raw wallet JSON output:"
    echo "$wallet_json"

    PRIVATE_KEY_VALUE=$(echo "$wallet_json" | jq -r '.[0].private_key')
    PUBLIC_ADDRESS_VALUE=$(echo "$wallet_json" | jq -r '.[0].address')

    echo "🛠 Extracted PRIVATE_KEY: $PRIVATE_KEY_VALUE"
    echo "🛠 Extracted PUBLIC_ADDRESS: $PUBLIC_ADDRESS_VALUE"

    export PRIVATE_KEY="$PRIVATE_KEY_VALUE"
    export PUBLIC_ADDRESS="$PUBLIC_ADDRESS_VALUE"

    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_ADDRESS" ]]; then
        echo "❌ ERROR: Failed to generate wallet."
        exit 1
    fi
    echo "🆕 Generated wallet: $PUBLIC_ADDRESS"

    # ✅ Wallet Funding Configuration
    if [[ "${DISABLE_FUNDING:-false}" == "true" ]]; then
        echo "⚠️ Wallet funding is disabled. Skipping..."
        return 0
    fi

    # ✅ Set funding amount dynamically
    FUNDING_AMOUNT_ETH="${FUNDING_AMOUNT_ETH:-50}" # Default to 50 ETH if not provided
    FUNDING_AMOUNT_WEI=$(cast to-wei "$FUNDING_AMOUNT_ETH" ether)

    echo "🛠 Raw L2_SENDER_PRIVATE_KEY: '$L2_SENDER_PRIVATE_KEY'"
    echo "🛠 Length: ${#L2_SENDER_PRIVATE_KEY} characters"

    # ✅ Check Admin Wallet Balance Before Sending Funds
    export ADMIN_PRIVATE_KEY="${L2_SENDER_PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    ADMIN_ADDRESS=$(cast wallet address --private-key "$ADMIN_PRIVATE_KEY")

    echo "🛠 ADMIN_ADDRESS: $ADMIN_ADDRESS"
    admin_balance=$(cast balance "$ADMIN_ADDRESS" --ether --rpc-url "$L2_RPC_URL")

    if (($(echo "$admin_balance < 1" | bc -l))); then
        echo "❌ ERROR: Admin wallet is out of funds! Current balance: $admin_balance ETH"
        exit 1
    fi

    # ✅ Prefund Test Wallet (Retry if Needed)
    retries=3
    while [[ "$retries" -gt 0 ]]; do
        funding_tx_hash=$(cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$ADMIN_PRIVATE_KEY" --value "$FUNDING_AMOUNT_WEI" "$PUBLIC_ADDRESS") && break
        echo "⚠️ Prefunding failed, retrying..."
        sleep 5
        ((retries--))
    done

    if [[ "$retries" -eq 0 ]]; then
        echo "❌ ERROR: Failed to fund test wallet after multiple attempts!"
        exit 1
    fi

    echo "💰 Sent $FUNDING_AMOUNT_ETH ETH to $PUBLIC_ADDRESS. TX: $funding_tx_hash"

    # ✅ Wait for funds to be available
    sleep 10
    sender_balance=$(cast balance "$PUBLIC_ADDRESS" --ether --rpc-url "$L2_RPC_URL")

    if (($(echo "$sender_balance < 1" | bc -l))); then
        echo "❌ ERROR: Wallet did not receive test funds!"
        exit 1
    fi
}
