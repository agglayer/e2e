_agglayer_cdk_common_setup() {
    bats_load_library 'bats-support'
    if [ $? -ne 0 ]; then return 1; fi
    bats_load_library 'bats-assert'
    if [ $? -ne 0 ]; then return 1; fi

    load '../../core/helpers/scripts/agglayer_network_setup'
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

    # Resolve L2 RPC URL
    _resolve_url_or_use_env L2_RPC_URL \
        "op-el-1-op-geth-op-node-001" "rpc" "cdk-erigon-rpc-001" "rpc" \
        "Failed to resolve L2 RPC URL" true

    # Resolve L2_SEQUENCER_RPC_URL
    _resolve_url_or_use_env L2_SEQUENCER_RPC_URL \
        "op-batcher-001" "http" "cdk-erigon-sequencer-001" "rpc" \
        "Failed to resolve L2 SEQUENCER RPC URL from all fallback nodes" true

    # Resolve Aggkit bridge URL
    _resolve_url_or_use_env aggkit_bridge_url \
        "aggkit-001" "rest" "cdk-node-001" "rest" \
        "Failed to resolve aggkit bridge url from all fallback nodes" true

    # Resolve Aggkit RPC URL
    _resolve_url_or_use_env aggkit_rpc_url \
        "aggkit-001" "rpc" "cdk-node-001" "rpc" \
        "Failed to resolve aggkit rpc url from all fallback nodes" true

    # Resolve zkevm_bridge_url
    _resolve_url_or_use_env zkevm_bridge_url \
        "zkevm-bridge-service-001" "rpc" \
        "Zk EVM Bridge service is not running" false

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

    is_forced=${IS_FORCED:-"true"}
    export is_forced
    meta_bytes=${META_BYTES:-"0x1234"}
    export meta_bytes

    # ✅ Resolve smart contract addresses
    _resolve_contract_addresses

    sender_private_key=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export sender_private_key
    sender_addr="$(cast wallet address --private-key $sender_private_key)"
    export sender_addr
    dry_run=${DRY_RUN:-"false"}
    export dry_run
    ether_value=${ETHER_VALUE:-"0.0200000054"}
    amount=$(cast to-wei $ether_value ether)
    export amount
    destination_net=${DESTINATION_NET:-"1"}
    export destination_net
    destination_addr=${DESTINATION_ADDRESS:-"0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"}
    export destination_addr
    native_token_addr=${NATIVE_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}
    export native_token_addr
    l1_rpc_url=${L1_RPC_URL:-"$(kurtosis port print $ENCLAVE_NAME el-1-geth-lighthouse rpc)"}
    export l1_rpc_url
    l1_rpc_network_id=$(cast call --rpc-url $l1_rpc_url $l1_bridge_addr 'networkID() (uint32)')
    export l1_rpc_network_id
    l2_rpc_network_id=$(cast call --rpc-url $L2_RPC_URL $l2_bridge_addr 'networkID() (uint32)')
    export l2_rpc_network_id
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    export gas_price
    erc20_artifact_path="$PROJECT_ROOT/core/contracts/erc20mock/ERC20Mock.json"
    export erc20_artifact_path
    weth_token_addr=$(cast call --rpc-url $L2_RPC_URL $l2_bridge_addr 'WETHToken() (address)')
    export weth_token_addr
    receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    export receiver
}

# _resolve_url_from_nodes
# Attempts to resolve a reachable URL from a list of node/port pairs using Kurtosis.
# 
# Arguments:
#   node1 port1 node2 port2 ... error_msg required
#   - node/port pairs (alternating)
#   - error_msg: string to print to stderr if resolution fails
#   - required: "true" to exit 1 on failure, anything else to continue
#
# Outputs:
#   - Prints the resolved URL to stdout if successful
#   - Prints errors to stderr
#   - Exits with code 1 if requirrequireded_flag is "true" and no URL is found
#
# Example:
#   _resolve_url_from_nodes "node1" "rpc" "node2" "rest" "Could not resolve URL" true
#
_resolve_url_from_nodes() {
    local -a args=("$@")
    local -a nodes=("${args[@]:0:$#-2}")  # All args except last two
    local error_msg="${args[$#-2]}"       # Second-to-last
    local required="${args[$#-1]}"        # Last

    local resolved_url=""
    local num_nodes=${#nodes[@]}

    for ((i = 0; i < num_nodes; i += 2)); do
        local node_name="${nodes[i]}"
        local node_port_type="${nodes[i+1]}"

        kurtosis service inspect "$ENCLAVE_NAME" "$node_name" || {
            echo "⚠️ Node $node_name is not running in the $ENCLAVE_NAME enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE_NAME" "$node_name" "$node_port_type")
        if [[ -n "$resolved_url" ]]; then
            echo "$resolved_url"
            break
        fi
    done

    if [[ -z "$resolved_url" ]]; then
        echo "❌ $error_msg" >&2
        if [[ "$required" == "true" ]]; then
            exit 1
        fi
    fi
}

# _resolve_url_or_use_env <target_var_name> <node1> <port1> ... <error_msg> <required>
# - If the env var with name <target_var_name> is set, use it
# - Otherwise, resolve via fallback nodes using _resolve_url_from_nodes
# - Sets and exports the result to a variable named <target_var_name>
_resolve_url_or_use_env() {
    local target_var_name="$1"
    shift

    local -a args=("$@")
    local num_args=$#
    local error_msg="${args[num_args-2]}"
    local required="${args[num_args-1]}"
    local -a nodes=("${args[@]:0:$num_args-2}")

    # Get value of env var if it exists
    local env_val="${!target_var_name:-}"

    if [[ -n "$env_val" ]]; then
        printf -v "$target_var_name" '%s' "$env_val"
        echo "$target_var_name: ${!target_var_name} (from environment)" >&3
    else
        local resolved
        resolved=$(_resolve_url_from_nodes "${nodes[@]}" "$error_msg" "$required" | tail -1)
        printf -v "$target_var_name" '%s' "$resolved"
        echo "$target_var_name: ${!target_var_name}" >&3
    fi

    declare -gx "$target_var_name=${!target_var_name}"
}

# _resolve_contract_addresses <enclave_name>
# Exports the following lowercase readonly vars:
#   l1_bridge_addr, l2_bridge_addr, pol_address, l2_ger_addr, gas_token_addr
# If any are set via env, all must be set. Otherwise fetches from combined.json.
_resolve_contract_addresses() {
    export contracts_container="${KURTOSIS_CONTRACTS:-contracts-001}"

    local l1="${L1_BRIDGE_ADDRESS:-}"
    local l2="${L2_BRIDGE_ADDRESS:-}"
    local pol="${POL_TOKEN_ADDRESS:-}"
    local ger="${L2_GER_ADDRESS:-}"
    local gas="${GAS_TOKEN_ADDRESS:-}"

    if [[ -n "$l1" || -n "$l2" || -n "$pol" || -n "$ger" || -n "$gas" ]]; then
        [[ -z "$l1" ]] && { echo "Error: L1_BRIDGE_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$l2" ]] && { echo "Error: L2_BRIDGE_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$pol" ]] && { echo "Error: POL_TOKEN_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$ger" ]] && { echo "Error: L2_GER_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$gas" ]] && { echo "Error: GAS_TOKEN_ADDRESS is required but not set." >&2; exit 1; }

        echo "Using contract addresses from environment."
    else
        echo "Downloading combined.json to extract contract addresses..."
        local combined_json_file="/opt/zkevm/combined.json"
        kurtosis_download_file_exec_method "$ENCLAVE_NAME" "$contracts_container" "$combined_json_file" | jq '.' > combined.json

        local json_output
        json_output=$(<combined.json)
        readonly json_output

        if ! echo "$json_output" | jq empty >/dev/null 2>&1; then
            json_output=$(echo "$json_output" | tail -n +2)
        fi

        l1=$(echo "$json_output" | jq -r .polygonZkEVMBridgeAddress)
        l2=$(echo "$json_output" | jq -r .polygonZkEVML2BridgeAddress)
        pol=$(echo "$json_output" | jq -r .polTokenAddress)
        ger=$(echo "$json_output" | jq -r .polygonZkEVMGlobalExitRootL2Address)
        gas=$(echo "$json_output" | jq -r .gasTokenAddress)
    fi

    # Export and mark as readonly
    export l1_bridge_addr="$l1"; readonly l1_bridge_addr
    export l2_bridge_addr="$l2"; readonly l2_bridge_addr
    export pol_address="$pol"; readonly pol_address
    export l2_ger_addr="$ger"; readonly l2_ger_addr
    export gas_token_addr="$gas"; readonly gas_token_addr

    # Debug output
    {
        echo "Resolved contract addresses:"
        echo "  l1_bridge_addr = $l1_bridge_addr"
        echo "  l2_bridge_addr = $l2_bridge_addr"
        echo "  pol_address     = $pol_address"
        echo "  l2_ger_addr     = $l2_ger_addr"
        echo "  gas_token_addr  = $gas_token_addr"
    } >&3
}

_get_gas_token_address() {
    local chain_number=$1
    local combined_json_file="/opt/zkevm/combined-${chain_number}.json"
    kurtosis_download_file_exec_method $ENCLAVE_NAME $CONTRACTS_CONTAINER "$combined_json_file" | jq '.' >"combined-${chain_number}.json"
    local chain_combined_output
    chain_combined_output=$(cat "combined-${chain_number}.json")
    if echo "$chain_combined_output" | jq empty >/dev/null 2>&1; then
        echo "$(echo "$chain_combined_output" | jq -r .gasTokenAddress)"
    else
        echo "$(echo "$chain_combined_output" | tail -n +2 | jq -r .gasTokenAddress)"
    fi
}

_agglayer_cdk_common_multi_setup() {
    local number_of_chains=$1

    private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
    readonly private_key
    eth_address=$(cast wallet address --private-key $private_key)
    export eth_address
    l2_pp1_url=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-rpc-001 rpc)
    readonly l2_pp1_url
    l2_pp2_url=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-rpc-002 rpc)
    readonly l2_pp2_url
    if [[ $number_of_chains -eq 3 ]]; then
        l2_pp3_url=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-rpc-003 rpc)
        readonly l2_pp3_url
    fi

    # Resolve Aggkit RPC URL
    if [[ -z "${AGGKIT_PP1_RPC_URL:-}" ]]; then
        local aggkit_nodes=("aggkit-001" "rpc" "cdk-node-001" "rpc")
        aggkit_pp1_rpc_url=$(_resolve_url_from_nodes "${aggkit_nodes[@]}" "Failed to resolve PP1 aggkit rpc url from all fallback nodes" true | tail -1)
        echo "aggkit_pp1_rpc_url: $aggkit_pp1_rpc_url" >&3
    else
        aggkit_pp1_rpc_url="$AGGKIT_PP1_RPC_URL"
        echo "aggkit_pp1_rpc_url: $aggkit_pp1_rpc_url (from environment)" >&3
    fi
    readonly aggkit_pp1_rpc_url

    if [[ -z "${AGGKIT_PP2_RPC_URL:-}" ]]; then
        local aggkit_nodes=("aggkit-002" "rpc" "cdk-node-002" "rpc")
        aggkit_pp2_rpc_url=$(_resolve_url_from_nodes "${aggkit_nodes[@]}" "Failed to resolve PP2 aggkit rpc url from all fallback nodes" true | tail -1)
        echo "aggkit_pp2_rpc_url: $aggkit_pp2_rpc_url" >&3
    else
        aggkit_pp2_rpc_url="$AGGKIT_PP2_RPC_URL"
        echo "aggkit_pp2_rpc_url: $aggkit_pp2_rpc_url (from environment)" >&3
    fi
    readonly aggkit_pp2_rpc_url

    if [[ $number_of_chains -eq 3 ]]; then
        if [[ -z "${AGGKIT_PP3_RPC_URL:-}" ]]; then
            local aggkit_nodes_3=("aggkit-003" "rpc" "cdk-node-003" "rpc")
            aggkit_pp3_rpc_url=$(_resolve_url_from_nodes "${aggkit_nodes_3[@]}" "Failed to resolve PP3 aggkit rpc url from all fallback nodes" true | tail -1)
            echo "aggkit_pp3_rpc_url: $aggkit_pp3_rpc_url" >&3
        else
            aggkit_pp3_rpc_url="$AGGKIT_PP3_RPC_URL"
            echo "aggkit_pp3_rpc_url: $aggkit_pp3_rpc_url (from environment)" >&3
        fi
        readonly aggkit_pp3_rpc_url
    fi

    l2_pp1_network_id=$(cast call --rpc-url $l2_pp1_url $l1_bridge_addr 'networkID() (uint32)')
    readonly l2_pp1_network_id
    l2_pp2_network_id=$(cast call --rpc-url $l2_pp2_url $l2_bridge_addr 'networkID() (uint32)')
    readonly l2_pp2_network_id
    if [[ $number_of_chains -eq 3 ]]; then
        l2_pp3_network_id=$(cast call --rpc-url $l2_pp3_url $l2_bridge_addr 'networkID() (uint32)')
        readonly l2_pp3_network_id
    fi

    # Resolve Aggkit Bridge URLs for both nodes
    if [[ -z "${AGGKIT_PP1_BRIDGE_URL:-}" ]]; then
        local aggkit_nodes_1=("aggkit-001" "rest" "cdk-node-001" "rest")
        aggkit_bridge_1_url=$(_resolve_url_from_nodes "${aggkit_nodes_1[@]}" "Failed to resolve PP1 aggkit bridge url from all fallback nodes" true | tail -1)
        readonly aggkit_bridge_1_url
        echo "aggkit_bridge_1_url: $aggkit_bridge_1_url" >&3
    else
        aggkit_bridge_1_url="$AGGKIT_PP1_BRIDGE_URL"
        readonly aggkit_bridge_1_url
        echo "aggkit_bridge_1_url: $aggkit_bridge_1_url (from environment)" >&3
    fi

    if [[ -z "${AGGKIT_PP2_BRIDGE_URL:-}" ]]; then
        local aggkit_nodes_2=("aggkit-002" "rest" "cdk-node-002" "rest")
        aggkit_bridge_2_url=$(_resolve_url_from_nodes "${aggkit_nodes_2[@]}" "Failed to resolve PP2 aggkit bridge url from all fallback nodes" true | tail -1)
        readonly aggkit_bridge_2_url
        echo "aggkit_bridge_2_url: $aggkit_bridge_2_url" >&3
    else
        aggkit_bridge_2_url="$AGGKIT_PP2_BRIDGE_URL"
        readonly aggkit_bridge_2_url
        echo "aggkit_bridge_2_url: $aggkit_bridge_2_url (from environment)" >&3
    fi

    if [[ $number_of_chains -eq 3 ]]; then
        if [[ -z "${AGGKIT_PP3_BRIDGE_URL:-}" ]]; then
            local aggkit_nodes_3=("aggkit-003" "rest" "cdk-node-003" "rest")
            aggkit_bridge_3_url=$(_resolve_url_from_nodes "${aggkit_nodes_3[@]}" "Failed to resolve PP3 aggkit bridge url from all fallback nodes" true | tail -1)
            readonly aggkit_bridge_3_url
            echo "aggkit_bridge_3_url: $aggkit_bridge_3_url" >&3
        else
            aggkit_bridge_3_url="$AGGKIT_PP3_BRIDGE_URL"
            readonly aggkit_bridge_3_url
            echo "aggkit_bridge_3_url: $aggkit_bridge_3_url (from environment)" >&3
        fi
    fi

    weth_token_addr_pp1=$(cast call --rpc-url $l2_pp1_url $l2_bridge_addr 'WETHToken() (address)')
    readonly weth_token_addr_pp1
    weth_token_addr_pp2=$(cast call --rpc-url $l2_pp2_url $l2_bridge_addr 'WETHToken() (address)')
    readonly weth_token_addr_pp2
    if [[ $number_of_chains -eq 3 ]]; then
        weth_token_addr_pp3=$(cast call --rpc-url $l2_pp3_url $l2_bridge_addr 'WETHToken() (address)')
        readonly weth_token_addr_pp3
    fi
    echo "weth_token_addr_pp1: $weth_token_addr_pp1" >&3
    echo "weth_token_addr_pp2: $weth_token_addr_pp2" >&3
    if [[ $number_of_chains -eq 3 ]]; then
        echo "weth_token_addr_pp3: $weth_token_addr_pp3" >&3
    fi

    gas_token_addr_pp1=$(_get_gas_token_address "001")
    echo "Gas token address on PP1=$gas_token_addr_pp1" >&3
    gas_token_addr_pp2=$(_get_gas_token_address "002")
    echo "Gas token address on PP2=$gas_token_addr_pp2" >&3
    if [[ $number_of_chains -eq 3 ]]; then
        gas_token_addr_pp3=$(_get_gas_token_address "003")
        echo "Gas token address on PP3=$gas_token_addr_pp3" >&3
    fi

    echo "=== L1 network id=$l1_rpc_network_id ===" >&3
    echo "=== L2 PP1 network id=$l2_pp1_network_id ===" >&3
    echo "=== L2 PP2 network id=$l2_pp2_network_id ===" >&3
    echo "=== L1 RPC URL=$l1_rpc_url ===" >&3
    echo "=== L2 PP1 URL=$l2_pp1_url ===" >&3
    echo "=== L2 PP2 URL=$l2_pp2_url ===" >&3
    echo "=== Aggkit Bridge 1 URL=$aggkit_bridge_1_url ===" >&3
    echo "=== Aggkit Bridge 2 URL=$aggkit_bridge_2_url ===" >&3
    if [[ $number_of_chains -eq 3 ]]; then
        echo "=== L2 PP3 network id=$l2_pp3_network_id ===" >&3
        echo "=== L2 PP3 URL=$l2_pp3_url ===" >&3
        echo "=== Aggkit Bridge 3 URL=$aggkit_bridge_3_url ===" >&3
    fi

    receiver1_private_key="0x9eece9566497455837334ad4d2cc1f81e24ea4fc532c5d9ac2c471df8560f5dd"
    readonly receiver1_private_key
    receiver1_addr="$(cast wallet address --private-key $receiver1_private_key)"
    export receiver1_addr
}
