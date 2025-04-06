_common_setup() {
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'

    load '../../core/helpers/scripts/bridge_message'
    load '../../core/helpers/scripts/bridge_asset'
    load '../../core/helpers/scripts/get_bridge'
    load '../../core/helpers/scripts/find_l1_info_tree_index_for_bridge'
    load '../../core/helpers/scripts/find_injected_info_after_index'
    load '../../core/helpers/scripts/generate_claim_proof'
    load '../../core/helpers/scripts/claim_bridge'
    load '../../core/helpers/scripts/log'
    load '../../core/helpers/scripts/query_contract'
    load '../../core/helpers/scripts/send_tx'
    load '../../core/helpers/scripts/mint_erc20_tokens'
    load '../../core/helpers/scripts/get_claim'
    load '../../core/helpers/scripts/verify_balance'
    load '../../core/helpers/scripts/wait_for_expected_token'
    load '../../core/helpers/scripts/check_claim_revert_code'
    load '../../core/helpers/scripts/add_network2_to_agglayer'
    load '../../core/helpers/scripts/fund_claim_tx_manager'
    load '../../core/helpers/scripts/mint_pol_token'
    load '../../core/helpers/scripts/run_with_timeout'
    load '../../core/helpers/scripts/wait_to_settled_certificate_containing_global_index'

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
    export CONTRACTS_CONTAINER="${KURTOSIS_CONTRACTS:-contracts-001}"
    export CONTRACTS_SERVICE_WRAPPER="${KURTOSIS_CONTRACTS_WRAPPER:-"kurtosis service exec $ENCLAVE $CONTRACTS_CONTAINER"}"
    export ERIGON_RPC_NODE="${KURTOSIS_ERIGON_RPC:-cdk-erigon-rpc-001}"
    export ERIGON_SEQUENCER_RPC_NODE="${KURTOSIS_ERIGON_SEQUENCER_RPC:-cdk-erigon-sequencer-001}"

    # ✅ Standardized L2 RPC and SEQUENCER URL Handling
    if [[ "$ENCLAVE" == "cdk" || "$ENCLAVE" == "aggkit" ]]; then
        L2_RPC_URL=$(kurtosis port print "$ENCLAVE" "$ERIGON_RPC_NODE" rpc)
        L2_SEQUENCER_RPC_URL=$(kurtosis port print "$ENCLAVE" "$ERIGON_SEQUENCER_RPC_NODE" rpc)

    elif [[ "$ENCLAVE" == "op" ]]; then
        echo "🔥 Detected OP Stack"
        L2_RPC_URL=$(kurtosis port print "$ENCLAVE" op-el-1-op-geth-op-node-op-kurtosis rpc)
        L2_SEQUENCER_RPC_URL=$(kurtosis port print "$ENCLAVE" op-batcher-op-kurtosis http)
    fi
    export L2_RPC_URL="$L2_RPC_URL"
    echo "🔧 Using L2 RPC URL: $L2_RPC_URL"
    export L2_SEQUENCER_RPC_URL="$L2_SEQUENCER_RPC_URL"
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

    readonly is_forced=${IS_FORCED:-"true"}
    meta_bytes=${META_BYTES:-"0x1234"}

    local combined_json_file="/opt/zkevm/combined.json"
    combined_json_output=$($CONTRACTS_SERVICE_WRAPPER "cat $combined_json_file")
    echo "Combined JSON output:"
    echo "$combined_json_output"
    echo "echo "$combined_json_output" | grep '^{.*}$'"
    echo "$combined_json_output" | grep '^{.*}$'
    bridge_addr=$(echo "$combined_json_output" | grep '^{.*}$' | jq -r .polygonZkEVMBridgeAddress)
    echo "Bridge address=$bridge_addr" >&3

    local rollup_params_file="/opt/zkevm/create_rollup_parameters.json"
    rollup_params_output=$($CONTRACTS_SERVICE_WRAPPER "cat $rollup_params_file")
    gas_token_addr=$(echo "$rollup_params_output" | grep '^{.*}$' | jq -r .gasTokenAddress)
    echo "Gas token address=$gas_token_addr" >&3

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    readonly sender_addr="$(cast wallet address --private-key $sender_private_key)"
    readonly dry_run=${DRY_RUN:-"false"}
    ether_value=${ETHER_VALUE:-"0.0200000054"}
    amount=$(cast to-wei $ether_value ether)
    destination_net=${DESTINATION_NET:-"1"}
    destination_addr=${DESTINATION_ADDRESS:-"0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"}
    readonly native_token_addr=${NATIVE_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}
    readonly l1_rpc_url=${L1_ETH_RPC_URL:-"$(kurtosis port print $ENCLAVE el-1-geth-lighthouse rpc)"}
    readonly aggkit_node_url=${AGGKIT_NODE_URL:-"$(kurtosis port print $ENCLAVE cdk-node-001 rpc)"}
    readonly l1_rpc_network_id=$(cast call --rpc-url $l1_rpc_url $bridge_addr 'networkID() (uint32)')
    readonly l2_rpc_network_id=$(cast call --rpc-url $L2_RPC_URL $bridge_addr 'networkID() (uint32)')
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    readonly erc20_artifact_path="$PROJECT_ROOT/core/contracts/erc20mock/ERC20Mock.json"
}
