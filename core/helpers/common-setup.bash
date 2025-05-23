_common_setup() {
    bats_load_library 'bats-support'
    if [ $? -ne 0 ]; then return 1; fi
    bats_load_library 'bats-assert'
    if [ $? -ne 0 ]; then return 1; fi

    load '../../core/helpers/scripts/aggkit_bridge_service'
    load '../../core/helpers/scripts/fund'
    load '../../core/helpers/scripts/get_token_balance'
    load '../../core/helpers/scripts/mint_token_helpers'
    load '../../core/helpers/scripts/query_contract'
    load '../../core/helpers/scripts/send_tx'
    load '../../core/helpers/scripts/verify_balance'
    load '../../core/helpers/scripts/wait_to_settled_certificate_containing_global_index'

    load '../../core/helpers/scripts/assert_block_production'
    load '../../core/helpers/scripts/check_balances'
    load '../../core/helpers/scripts/deploy_contract'
    load '../../core/helpers/scripts/deploy_test_contracts'
    load '../../core/helpers/scripts/send_eoa_tx'
    load '../../core/helpers/scripts/send_smart_contract_tx'
    load '../../core/helpers/scripts/zkevm_bridge_service'

    load '../../core/helpers/scripts/kurtosis-helpers'

    # ✅ Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    PATH="$PROJECT_ROOT/src:$PATH"

    export DEPLOY_SALT="${DEPLOY_SALT:-0x0000000000000000000000000000000000000000000000000000000000000000}"

    # ✅ Standard function signatures
    export MINT_FN_SIG="function mint(address,uint256)"
    export BALANCE_OF_FN_SIG="function balanceOf(address) (uint256)"
    export APPROVE_FN_SIG="function approve(address,uint256)"

    # ✅ Kurtosis service setup
    export CONTRACTS_CONTAINER="${KURTOSIS_CONTRACTS:-contracts-001}"

    local fallback_nodes=("op-el-1-op-geth-op-node-001" "cdk-erigon-rpc-001")
    local resolved_url=""
    for node in "${fallback_nodes[@]}"; do
        # Need to invoke the command this way, otherwise it would fail the entire test
        # if the node is not running, but this is just a sanity check
        kurtosis service inspect "$ENCLAVE" "$node" || {
            echo "⚠️ Node $node is not running in the "$ENCLAVE" enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node" rpc)
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved L2 RPC URL ("$resolved_url") from "$node"" >&3
            break
        fi
    done
    if [ -z "$resolved_url" ]; then
        echo "❌ Failed to resolve L2 RPC URL from all fallback nodes" >&2
        return 1
    fi
    export L2_RPC_URL="$resolved_url"

    local fallback_nodes=(
        "op-batcher-001" "http"
        "cdk-erigon-sequencer-001" "rpc"
    )
    local resolved_url=""
    local num_nodes=${#fallback_nodes[@]}

    for ((i = 0; i < num_nodes; i += 2)); do
        local node_name="${fallback_nodes[i]}"
        local node_port_type="${fallback_nodes[i+1]}"

        kurtosis service inspect "$ENCLAVE" "$node_name" || {
            echo "⚠️ Node $node_name is not running in the $ENCLAVE enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node_name" "$node_port_type")
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved L2 SEQUENCER RPC URL ($resolved_url) from $node_name" >&3
            break
        fi
    done

    if [ -z "$resolved_url" ]; then
        echo "❌ Failed to resolve L2 SEQUENCER RPC URL from all fallback nodes" >&2
        return 1
    fi
    export L2_SEQUENCER_RPC_URL="$resolved_url"

    local fallback_nodes=("aggkit-001" "cdk-node-001")
    local resolved_url=""
    for node in "${fallback_nodes[@]}"; do
        # Need to invoke the command this way, otherwise it would fail the entire test
        # if the node is not running, but this is just a sanity check
        kurtosis service inspect "$ENCLAVE" "$node" || {
            echo "⚠️ Node $node is not running in the "$ENCLAVE" enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node" rest)
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved aggkit node url ("$resolved_url") from "$node"" >&3
            break
        fi
    done
    if [ -z "$resolved_url" ]; then
        echo "❌ Failed to resolve aggkit node url from all fallback nodes" >&2
        return 1
    fi
    readonly aggkit_bridge_url="$resolved_url"

    local fallback_nodes=("zkevm-bridge-service-001")
    local resolved_url=""
    for node in "${fallback_nodes[@]}"; do
        # Need to invoke the command this way, otherwise it would fail the entire test
        # if the node is not running, but this is just a sanity check
        kurtosis service inspect "$ENCLAVE" "$node" || {
            echo "⚠️ Node $node is not running in the "$ENCLAVE" enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node" rpc)
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved bridge api url ("$resolved_url") from "$node"" >&3
            break
        fi
    done
    if [ -z "$resolved_url" ]; then
        echo "zkevm-bridge-service isnt running" >&3
    fi
    readonly bridge_api_url="$resolved_url"

    echo "🔧 Using L2 RPC URL: $L2_RPC_URL"
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
    FUNDING_AMOUNT_ETH="${FUNDING_AMOUNT_ETH:-10}" # Default to 10 ETH if not provided
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

    if [[ -z "${DISABLE_L2_FUND}" || "${DISABLE_L2_FUND}" == "false" ]]; then
        readonly test_account_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
        readonly test_account_addr="$(cast wallet address --private-key $test_account_key)"

        local token_balance
        token_balance=$(cast balance --rpc-url "$L2_RPC_URL" "$test_account_addr" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "⚠️ Failed to fetch token balance for $test_account_addr on $L2_RPC_URL" >&2
            token_balance=0
        fi

        # Threshold: 0.1 ether in wei
        local threshold=100000000000000000

        # Only fund if balance is less than or equal to 0.1 ether
        # (it's a real big number, so we compare the length of strings)
        if [[ ${#token_balance} -le ${#threshold} ]]; then
            local l2_coinbase_key=${L2_COINBASE_KEY:-"ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}
            local amt="10ether"

            echo "💸 $test_account_addr L2 balance ($token_balance) is low (≤ 0.1 ETH), funding with amt=$amt..." >&3
            fund "$l2_coinbase_key" "$test_account_addr" "$amt" "$L2_RPC_URL"
            if [ $? -ne 0 ]; then
                echo "❌ Funding L2 receiver $test_account_addr failed" >&2
                return 1
            fi
            echo "✅ Successfully funded $test_account_addr with $amt on L2" >&3
        else
            echo "✅ Receiver $test_account_addr already has $(cast --from-wei "$token_balance") ETH on L2" >&3
        fi
    else
        echo "🚫 Skipping L2 funding since DISABLE_L2_FUND is set to true" >&3
    fi

    local combined_json_file="/opt/zkevm/combined.json"
    kurtosis_download_file_exec_method $ENCLAVE $CONTRACTS_CONTAINER "$combined_json_file" | jq '.' >combined.json
    local combined_json_output=$(cat combined.json)
    if echo "$combined_json_output" | jq empty >/dev/null 2>&1; then
        l1_bridge_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVMBridgeAddress)
        l2_bridge_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVML2BridgeAddress)
        pol_address=$(echo "$combined_json_output" | jq -r .polTokenAddress)
        l2_ger_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVMGlobalExitRootL2Address)
    else
        l1_bridge_addr=$(echo "$combined_json_output" | tail -n +2 | jq -r .polygonZkEVMBridgeAddress)
        l2_bridge_addr=$(echo "$combined_json_output" | tail -n +2 | jq -r .polygonZkEVML2BridgeAddress)
        pol_address=$(echo "$combined_json_output" | tail -n +2 | jq -r .polTokenAddress)
        l2_ger_addr=$(echo "$combined_json_output" | tail -n +2 | jq -r .polygonZkEVMGlobalExitRootL2Address)
    fi
    echo "L1 Bridge address=$l1_bridge_addr" >&3
    echo "L2 Bridge address=$l2_bridge_addr" >&3
    echo "POL address=$pol_address" >&3
    echo "L2 GER address=$l2_ger_addr" >&3

    readonly sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    readonly sender_addr="$(cast wallet address --private-key $sender_private_key)"
    readonly dry_run=${DRY_RUN:-"false"}
    ether_value=${ETHER_VALUE:-"0.0200000054"}
    amount=$(cast to-wei $ether_value ether)
    destination_net=${DESTINATION_NET:-"1"}
    destination_addr=${DESTINATION_ADDRESS:-"0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"}
    readonly native_token_addr=${NATIVE_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}
    readonly l1_rpc_url=${L1_ETH_RPC_URL:-"$(kurtosis port print $ENCLAVE el-1-geth-lighthouse rpc)"}
    if [[ "$ENCLAVE" == "cdk" || "$ENCLAVE" == "aggkit" ]]; then
        local rollup_params_file="/opt/zkevm/create_rollup_parameters.json"
    elif [[ "$ENCLAVE" == "op" ]]; then
        local rollup_params_file="/opt/zkevm/create_rollup_output.json"
    fi

    kurtosis_download_file_exec_method "$ENCLAVE" "$CONTRACTS_CONTAINER" "$rollup_params_file" | jq '.' >"rollup_params.json"
    local rollup_params_output=$(cat rollup_params.json)
    if echo "$rollup_params_output" | jq empty >/dev/null 2>&1; then
        readonly gas_token_addr=$(echo "$rollup_params_output" | jq -r .gasTokenAddress)
    else
        readonly gas_token_addr=$(echo "$rollup_params_output" | tail -n +2 | jq -r .gasTokenAddress)
    fi
    echo "Gas token address=$gas_token_addr" >&3

    readonly l1_rpc_network_id=$(cast call --rpc-url $l1_rpc_url $l1_bridge_addr 'networkID() (uint32)')
    readonly l2_rpc_network_id=$(cast call --rpc-url $L2_RPC_URL $l2_bridge_addr 'networkID() (uint32)')
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    readonly erc20_artifact_path="$PROJECT_ROOT/core/contracts/erc20mock/ERC20Mock.json"
    readonly weth_token_addr=$(cast call --rpc-url $L2_RPC_URL $l2_bridge_addr 'WETHToken() (address)')
    readonly receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
}
