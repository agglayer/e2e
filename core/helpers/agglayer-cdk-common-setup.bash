HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_LIB_PATH=$BATS_LIB_PATH:$HERE/lib
PROJECT_ROOT=${PROJECT_ROOT:-$HERE/../..}

L2_PRIVATE_KEY="${L2_PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"

_agglayer_cdk_common_setup() {
    _load_bats_libraries || return 1
    _load_helper_scripts

    # ✅ Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    PATH="$PROJECT_ROOT/src:$PATH"

    export DEPLOY_SALT="${DEPLOY_SALT:-0x0000000000000000000000000000000000000000000000000000000000000000}"

    # ✅ ERC20 function signatures
    export MINT_FN_SIG="function mint(address,uint256)"
    export BALANCE_OF_FN_SIG="function balanceOf(address) (uint256)"
    export APPROVE_FN_SIG="function approve(address,uint256)"

    # ✅ Bridge contract function signatures
    export BRIDGE_ASSET_FN_SIG="function bridgeAsset(uint32,address,uint256,address,bool,bytes)"
    export BRIDGE_MSG_FN_SIG="function bridgeMessage(uint32,address,bool,bytes)"
    export CLAIM_ASSET_FN_SIG="function claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    export CLAIM_MSG_FN_SIG="function claimMessage(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"

    # ✅ Resolve URLs
    _resolve_required_urls

    # ✅ Generate and fund wallet
    _generate_and_fund_wallet

    # ✅ Resolve smart contract addresses
    _resolve_contract_addresses

    # ✅ Set and export variables
    _set_and_export_bridge_vars

    # ✅ Resolve aggsender mode and expport aggsender_mode
    _resolve_aggsender_mode

    test_log_prefix="$(basename $BATS_TEST_FILENAME) - $BATS_TEST_NAME"
    export test_log_prefix
}

# Loads required BATS testing libraries, such as bats-support and bats-assert.
# Returns 1 if any of the libraries fail to load.
_load_bats_libraries() {
  for lib in 'bats-support' 'bats-assert'; do
    bats_load_library "$lib" || return 1
  done
}

# Loads all helper script files used across BATS tests.
# These helpers provide reusable functions for things like funding accounts,
# deploying contracts, sending transactions, and checking balances.
_load_helper_scripts() {
  local scripts=(
    'agglayer_network_setup'
    'aggkit_bridge_service'
    'fund'
    'get_token_balance'
    'mint_token_helpers'
    'query_contract'
    'send_tx'
    'verify_balance'
    'wait_to_settle_certificate_containing_global_index'
    'assert_block_production'
    'check_balances'
    'deploy_contract'
    'deploy_test_contracts'
    'send_eoa_tx'
    'send_smart_contract_tx'
    'zkevm_bridge_service'
    'kurtosis-helpers'
  )
  for script in "${scripts[@]}"; do
    load "../../core/helpers/scripts/$script"
  done
}

# Resolves and exports required service URLs for the test environment by attempting to
# discover them from a set of fallback node names. If the URLs are not found in the environment
# variables, this function will attempt to resolve them using the _resolve_url_or_use_env helper.
#
# The function handles:
# - L1_RPC_URL: L1 execution node RPC endpoint
# - L2_RPC_URL: L2 execution node RPC endpoint
# - L2_SEQUENCER_RPC_URL: L2 sequencer endpoint
# - AGGKIT_BRIDGE_URL: AggKit REST API endpoint for bridge operations
# - AGGKIT_RPC_URL: AggKit RPC interface
# - ZKEVM_BRIDGE_URL: zkEVM bridge service endpoint
#
# Fallback nodes are tried in order. If a required URL cannot be resolved, the function will fail.
_resolve_required_urls() {
    # L1_RPC_URL
    l1_rpc_url=$(_resolve_url_or_use_env L1_RPC_URL \
        "el-1-geth-lighthouse" "rpc" \
        "Failed to resolve L1 RPC URL" true)
    export l1_rpc_url

    # L2_RPC_URL
    L2_RPC_URL=$(_resolve_url_or_use_env L2_RPC_URL \
        "op-el-1-op-geth-op-node-001" "rpc" "cdk-erigon-rpc-001" "rpc" \
        "Failed to resolve L2 RPC URL" true)
    export L2_RPC_URL

    # L2_SEQUENCER_RPC_URL
    L2_SEQUENCER_RPC_URL=$(_resolve_url_or_use_env L2_SEQUENCER_RPC_URL \
        "op-batcher-001" "http" "cdk-erigon-sequencer-001" "rpc" \
        "Failed to resolve L2 SEQUENCER RPC URL from all fallback nodes" true)
    export L2_SEQUENCER_RPC_URL

    # AGGKIT_BRIDGE_URL
    aggkit_bridge_url=$(_resolve_url_or_use_env AGGKIT_BRIDGE_URL \
        "aggkit-001" "rest" "cdk-node-001" "rest" \
        "Failed to resolve aggkit bridge url from all fallback nodes" true)
    export aggkit_bridge_url

    # AGGKIT_RPC_URL
    aggkit_rpc_url=$(_resolve_url_or_use_env AGGKIT_RPC_URL \
        "aggkit-001" "rpc" "cdk-node-001" "rpc" \
        "Failed to resolve aggkit rpc url from all fallback nodes" true)
    export aggkit_rpc_url

    # ZKEVM_BRIDGE_URL
    zkevm_bridge_url=$(_resolve_url_or_use_env ZKEVM_BRIDGE_URL \
        "zkevm-bridge-service-001" "rpc" \
        "Zk EVM Bridge service is not running" false)
    export zkevm_bridge_url
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
#   - Exits with code 1 if required flag is "true" and no URL is found
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
    local env_var="$1"
    shift

    local -a args=("$@")
    local num_args=$#
    local error_msg="${args[num_args-2]}"
    local required="${args[num_args-1]}"
    local -a nodes=("${args[@]:0:$num_args-2}")

    local env_val="${!env_var:-}"

    if [[ -n "$env_val" ]]; then
        echo "$env_val"
        echo "$env_var: $env_val (from environment)" >&3
    else
        local resolved
        resolved=$(_resolve_url_from_nodes "${nodes[@]}" "$error_msg" "$required" | tail -1)
        echo "$resolved"
        echo "$env_var: $resolved" >&3
    fi
}

# Generates a fresh test wallet using `cast wallet new`, exports the PRIVATE_KEY and PUBLIC_ADDRESS,
# and optionally funds it from the configured admin wallet unless funding is disabled.
# Fails if wallet generation or funding fails after retries.
_generate_and_fund_wallet() {
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

    echo "🛠 Raw L2_SENDER_PRIVATE_KEY: '$L2_PRIVATE_KEY'"
    echo "🛠 Length: ${#L2_PRIVATE_KEY} characters"

    # ✅ Check Admin Wallet Balance Before Sending Funds
    export ADMIN_PRIVATE_KEY="${L2_PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
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

# _resolve_contract_addresses <enclave_name>
# Exports the following lowercase readonly vars:
#   l1_bridge_addr, l2_bridge_addr, pol_address, l1_ger_addr, l2_ger_addr, gas_token_addr
# If any are set via env, all must be set. Otherwise fetches from combined.json.
_resolve_contract_addresses() {
    export contracts_container="${KURTOSIS_CONTRACTS:-contracts-001}"

    local l1="${L1_BRIDGE_ADDRESS:-}"
    local l2="${L2_BRIDGE_ADDRESS:-}"
    local pol="${POL_TOKEN_ADDRESS:-}"
    local l1_ger="${L1_GER_ADDRESS:-}"
    local ger="${L2_GER_ADDRESS:-}"
    local gas="${GAS_TOKEN_ADDRESS:-}"

    if [[ -n "$l1" || -n "$l2" || -n "$pol" || -n "$l1_ger" || -n "$ger" || -n "$gas" ]]; then
        [[ -z "$l1" ]] && { echo "Error: L1_BRIDGE_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$l2" ]] && { echo "Error: L2_BRIDGE_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$pol" ]] && { echo "Error: POL_TOKEN_ADDRESS is required but not set." >&2; exit 1; }
        [[ -z "$l1_ger" ]] && { echo "Error: L1_GER_ADDRESS is required but not set." >&2; exit 1; }
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
        l1_ger=$(echo "$json_output" | jq -r .polygonZkEVMGlobalExitRootAddress)
        ger=$(echo "$json_output" | jq -r .LegacyAgglayerGERL2)
        gas=$(echo "$json_output" | jq -r .gasTokenAddress)
    fi

    # Export and mark as readonly
    export l1_bridge_addr="$l1"; readonly l1_bridge_addr
    export l2_bridge_addr="$l2"; readonly l2_bridge_addr
    export pol_address="$pol"; readonly pol_address
    export l1_ger_addr="$l1_ger"; readonly l1_ger_addr
    export l2_ger_addr="$ger"; readonly l2_ger_addr
    export gas_token_addr="$gas"; readonly gas_token_addr

    # Debug output
    {
        echo "Resolved contract addresses:"
        echo "  l1_bridge_addr = $l1_bridge_addr"
        echo "  l2_bridge_addr = $l2_bridge_addr"
        echo "  pol_address     = $pol_address"
        echo "  l1_ger_addr     = $l1_ger_addr"
        echo "  l2_ger_addr     = $l2_ger_addr"
        echo "  gas_token_addr  = $gas_token_addr"
    } >&3
}

# _set_and_export_bridge_vars initializes and exports environment variables
# needed for bridge operations (e.g., sending messages/tokens across L1/L2).
# It ensures that all required context such as private keys, network IDs,
# destination addresses, and token-related values are available as env vars.
_set_and_export_bridge_vars() {
    local tmp

    tmp=${IS_FORCED:-"true"}
    export is_forced="$tmp"

    tmp=${META_BYTES:-"0x1234"}
    export meta_bytes="$tmp"

    tmp=${SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export sender_private_key="$tmp"

    tmp="$(cast wallet address --private-key "$sender_private_key")"
    export sender_addr="$tmp"

    tmp=${DRY_RUN:-"false"}
    export dry_run="$tmp"

    tmp=${ETHER_VALUE:-"0.0200000054"}
    export ether_value="$tmp"

    tmp=$(cast to-wei "$ether_value" ether)
    export amount="$tmp"

    tmp=${DESTINATION_NET:-"1"}
    export destination_net="$tmp"

    tmp=${DESTINATION_ADDRESS:-"0x0bb7AA0b4FdC2D2862c088424260e99ed6299148"}
    export destination_addr="$tmp"

    tmp=${NATIVE_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}
    export native_token_addr="$tmp"

    tmp=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID() (uint32)')
    export l1_rpc_network_id="$tmp"

    tmp=$(cast call --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" 'networkID() (uint32)')
    export l2_rpc_network_id="$tmp"

    tmp=$(cast gas-price --rpc-url "$L2_RPC_URL")
    export gas_price="$tmp"

    export erc20_artifact_path="$PROJECT_ROOT/core/contracts/erc20mock/ERC20Mock.json"

    tmp=$(cast call --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" 'WETHToken() (address)')
    export weth_token_addr="$tmp"

    tmp=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
    export receiver="$tmp"

    tmp=${MINTER_KEY:-"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"}
    export minter_key="$tmp"
}

_get_gas_token_address() {
    local chain_number="$1"
    local env_var_name="GAS_TOKEN_ADDRESS_ROLLUP_${chain_number#0}"  # 001 → 1
    local env_val="${!env_var_name:-}"

    if [[ -n "$env_val" ]]; then
        echo "$env_val"
        echo "$env_var_name: $env_val (from environment)" >&3
        return
    fi

    local combined_json_file="/opt/zkevm/combined-${chain_number}.json"
    kurtosis_download_file_exec_method "$ENCLAVE_NAME" "$contracts_container" "$combined_json_file" | jq '.' >"combined-${chain_number}.json"

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

    # Resolve L2 RPC URLs
    l2_rpc_url_1=$(_resolve_url_or_use_env L2_RPC_URL_1 \
        "op-el-1-op-geth-op-node-001" "rpc" "cdk-erigon-rpc-001" "rpc" \
        "Failed to resolve L2 RPC URL (Rollup 1) " true)
    readonly l2_rpc_url_1

    l2_rpc_url_2=$(_resolve_url_or_use_env L2_RPC_URL_2 \
        "op-el-1-op-geth-op-node-002" "rpc" "cdk-erigon-rpc-002" "rpc" \
        "Failed to resolve L2 RPC URL (Rollup 2) " true)
    readonly l2_rpc_url_2

    if [[ $number_of_chains -eq 3 ]]; then
        l2_rpc_url_3=$(_resolve_url_or_use_env L2_RPC_URL_3 \
            "op-el-1-op-geth-op-node-003" "rpc" "cdk-erigon-rpc-003" "rpc" \
            "Failed to resolve L2 RPC URL (Rollup 3) " true)
        readonly l2_rpc_url_3
    fi

    # Resolve Aggkit Bridge URLs
    aggkit_bridge_1_url=$(_resolve_url_or_use_env AGGKIT_BRIDGE_1_URL \
        "aggkit-001-bridge" "rest" "cdk-node-001" "rest" \
        "Failed to resolve Rollup 1 aggkit bridge url from all fallback nodes" true)
    readonly aggkit_bridge_1_url

    aggkit_bridge_2_url=$(_resolve_url_or_use_env AGGKIT_BRIDGE_2_URL \
        "aggkit-002-bridge" "rest" "cdk-node-002" "rest" \
        "Failed to resolve Rollup 2 aggkit bridge url from all fallback nodes" true)
    readonly aggkit_bridge_2_url

    if [[ $number_of_chains -eq 3 ]]; then
        aggkit_bridge_3_url=$(_resolve_url_or_use_env AGGKIT_BRIDGE_3_URL \
            "aggkit-003-bridge" "rest" "cdk-node-003" "rest" \
            "Failed to resolve Rollup 3 aggkit bridge url from all fallback nodes" true)
        readonly aggkit_bridge_3_url
    fi

    # AGGKIT_RPC_URL
    aggkit_rpc_1_url=$(_resolve_url_or_use_env AGGKIT_RPC_1_URL \
        "aggkit-001" "rpc" "cdk-node-001" "rpc" \
        "Failed to resolve aggkit rpc url from all fallback nodes" true)
    export aggkit_rpc_1_url

    aggkit_rpc_2_url=$(_resolve_url_or_use_env AGGKIT_RPC_2_URL \
        "aggkit-002" "rpc" "cdk-node-002" "rpc" \
        "Failed to resolve aggkit rpc url from all fallback nodes" true)
    export aggkit_rpc_2_url

    if [[ $number_of_chains -eq 3 ]]; then
        aggkit_rpc_3_url=$(_resolve_url_or_use_env AGGKIT_RPC_3_URL \
            "aggkit-003" "rpc" "cdk-node-003" "rpc" \
            "Failed to resolve aggkit rpc url from all fallback nodes" true)
        export aggkit_rpc_3_url
    fi

    # Rollup network ids
    rollup_1_network_id=$(cast call --rpc-url $l2_rpc_url_1 $l2_bridge_addr 'networkID() (uint32)')
    readonly rollup_1_network_id

    rollup_2_network_id=$(cast call --rpc-url $l2_rpc_url_2 $l2_bridge_addr 'networkID() (uint32)')
    readonly rollup_2_network_id

    if [[ $number_of_chains -eq 3 ]]; then
        rollup_3_network_id=$(cast call --rpc-url $l2_rpc_url_3 $l2_bridge_addr 'networkID() (uint32)')
        readonly rollup_3_network_id
    fi

    # WETH token addresses
    weth_token_rollup_1=$(cast call --rpc-url $l2_rpc_url_1 $l2_bridge_addr 'WETHToken() (address)')
    readonly weth_token_rollup_1

    weth_token_rollup_2=$(cast call --rpc-url $l2_rpc_url_2 $l2_bridge_addr 'WETHToken() (address)')
    readonly weth_token_rollup_2

    if [[ $number_of_chains -eq 3 ]]; then
        weth_token_rollup_3=$(cast call --rpc-url $l2_rpc_url_3 $l2_bridge_addr 'WETHToken() (address)')
        readonly weth_token_rollup_3
    fi

    echo "weth_token_rollup_1: $weth_token_rollup_1" >&3
    echo "weth_token_rollup_2: $weth_token_rollup_2" >&3
    if [[ $number_of_chains -eq 3 ]]; then
        echo "weth_token_rollup_3: $weth_token_rollup_3" >&3
    fi

    # Gas token addresses
    gas_token_rollup_1=$(_get_gas_token_address "001")
    echo "Gas token address (Rollup 1)=$gas_token_rollup_1" >&3

    gas_token_rollup_2=$(_get_gas_token_address "002")
    echo "Gas token address (Rollup 2)=$gas_token_rollup_2" >&3

    if [[ $number_of_chains -eq 3 ]]; then
        gas_token_rollup_3=$(_get_gas_token_address "003")
        echo "Gas token address (Rollup 3)=$gas_token_rollup_3" >&3
    fi

    echo "=== L1 network id=$l1_rpc_network_id ===" >&3
    echo "=== L1 RPC URL=$l1_rpc_url ===" >&3
    echo "=== L2 Rollup 1 ID=$rollup_1_network_id ===" >&3
    echo "=== L2 Rollup 1 URL=$l2_rpc_url_1 ===" >&3
    echo "=== Rollup 1 Bridge Service URL=$aggkit_bridge_1_url ===" >&3
    echo "=== L2 Rollup 2 ID=$rollup_2_network_id ===" >&3
    echo "=== L2 Rollup 2 URL=$l2_rpc_url_2 ===" >&3
    echo "=== Rollup 2 Bridge Service URL=$aggkit_bridge_2_url ===" >&3
    if [[ $number_of_chains -eq 3 ]]; then
        echo "=== L2 Rollup 3 ID=$rollup_3_network_id ===" >&3
        echo "=== L2 Rollup 3 URL=$l2_rpc_url_3 ===" >&3
        echo "=== Rollup 3 Bridge Service URL=$aggkit_bridge_3_url ===" >&3
    fi

    receiver1_private_key="0x9eece9566497455837334ad4d2cc1f81e24ea4fc532c5d9ac2c471df8560f5dd"
    readonly receiver1_private_key
    receiver1_addr="$(cast wallet address --private-key $receiver1_private_key)"
    export receiver1_addr
}

_resolve_aggsender_mode(){
    local mode
    mode=${aggsender_mode:-}
    if [ ! -z "$mode"  ]; then
        echo "Using aggsender_mode from environment: $aggsender_mode" >&3
    else
        echo "Resolving aggsender_mode from aggkit_rpc_url: $aggkit_rpc_url" >&3
        mode=$(curl -X POST $aggkit_rpc_url --header "Content-Type: application/json"  -d '{"method":"aggsender_status", "params":[], "id":1}' | jq .result.mode)
        if [ "$mode" == "null" ] || [ -z "$mode" ]; then
            echo "Failed to resolve aggsender_mode from aggkit_rpc_url: $aggkit_rpc_url" >&2
            exit 1
        fi
    aggsender_mode=$(echo $mode | tr -d '"')
    export aggsender_mode
    fi
    if [ $aggsender_mode == "AggchainProof" ]; then
        export aggsender_mode_is_fep=1
    else
        export aggsender_mode_is_fep=0
    fi
    echo "=== Resolved aggsender_mode: $aggsender_mode (aggsender_mode_is_fep=$aggsender_mode_is_fep)" >&3
}
log_setup_test(){
    log_prefix_test "🛠️🛠️🛠️🛠️ setup:"
}
log_start_test(){
    start_test_time=$(date +%s)
    log_prefix_test "🕵️‍♂️🕵️‍♂️🕵️‍♂️🕵️‍♂️ start:"
}
log_end_test(){
    end_test_time=$(date +%s)
    duration=$((end_test_time - start_test_time))
    log_prefix_test "✅✅✅✅ end: (duration: $duration seconds) "
}

log_prefix_test(){
    echo "=====================================================================" >&3
    echo "=== $1  $test_log_prefix" >&3
    echo "=====================================================================" >&3
}
