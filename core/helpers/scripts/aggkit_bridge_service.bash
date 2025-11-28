#!/bin/bash

# shellcheck disable=SC2154
set -euo pipefail

function bridge_asset() {
    local token_addr="$1"
    local rpc_url="$2"
    local bridge_addr="$3"

    if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
        local eth_balance
        eth_balance=$(cast balance -e --rpc-url "$rpc_url" "$sender_addr")
        log "💰 $sender_addr ETH Balance: $eth_balance ethers"
    else
        local balance_wei
        balance_wei=$(cast call --rpc-url "$rpc_url" "$token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr" | awk '{print $1}')
        local token_balance
        token_balance=$(cast --from-wei "$balance_wei")
        log "💎 $sender_addr Token Balance: $token_balance units [$token_addr]"
    fi

    log "🚀 Bridge asset $amount wei → $destination_addr [network: $destination_net]"

    if [[ $dry_run == "true" ]]; then
        log "📝 Dry run bridge asset (showing calldata only)"
        cast calldata "$BRIDGE_ASSET_FN_SIG" "$destination_net" "$destination_addr" "$amount" "$token_addr" "$is_forced" "$meta_bytes"
    else
        local response
        if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
            response=$(cast send --private-key "$sender_private_key" \
                --value "$amount" \
                --rpc-url "$rpc_url" "$bridge_addr" \
                "$BRIDGE_ASSET_FN_SIG" "$destination_net" "$destination_addr" "$amount" "$token_addr" "$is_forced" "$meta_bytes")
        else
            response=$(cast send --private-key "$sender_private_key" \
                --rpc-url "$rpc_url" "$bridge_addr" \
                "$BRIDGE_ASSET_FN_SIG" "$destination_net" "$destination_addr" "$amount" "$token_addr" "$is_forced" "$meta_bytes")
        fi

        local bridge_tx_hash
        bridge_tx_hash=$(echo "$response" | grep "^transactionHash" | cut -f 2- -d ' ' | sed 's/ //g')
        local bridge_tx_block_number
        bridge_tx_block_number=$(echo "$response" | grep "^blockNumber" | cut -f 2- -d ' ' | sed 's/ //g')

        if [[ -n "$bridge_tx_hash" ]]; then
            log "🎉 Success: Tx Hash → $bridge_tx_hash (bn: $bridge_tx_block_number)"
            echo "$bridge_tx_hash"
        else
            log "❌ Error: Transaction failed (no hash returned)"
            return 1
        fi
    fi
}

function bridge_message() {
    local token_addr="$1"
    local rpc_url="$2"
    local bridge_addr="$3"

    if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
        local eth_balance
        eth_balance=$(cast balance -e --rpc-url "$rpc_url" "$sender_addr")
        log "💰 $sender_addr ETH Balance: $eth_balance ethers"
    else
        local balance_wei
        balance_wei=$(cast call --rpc-url "$rpc_url" "$token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr" | awk '{print $1}')
        local token_balance
        token_balance=$(cast --from-wei "$balance_wei")
        log "💎 $sender_addr Token Balance: $token_balance units [$token_addr]"
    fi

    log "🚀 Bridge message $amount wei → $destination_addr [network: $destination_net, token: $token_addr, rpc: $rpc_url]"

    if [[ $dry_run == "true" ]]; then
        log "📝 Dry run bridge message (showing calldata only)"
        cast calldata "$BRIDGE_MSG_FN_SIG" "$destination_net" "$destination_addr" "$is_forced" "$meta_bytes"
    else
        local response
        if [[ $token_addr == "0x0000000000000000000000000000000000000000" ]]; then
            response=$(cast send --private-key "$sender_private_key" --value "$amount" \
                --rpc-url "$rpc_url" "$bridge_addr" "$BRIDGE_MSG_FN_SIG" "$destination_net" "$destination_addr" "$is_forced" "$meta_bytes")
        else
            response=$(cast send --private-key "$sender_private_key" \
                --rpc-url "$rpc_url" "$bridge_addr" "$BRIDGE_MSG_FN_SIG" "$destination_net" "$destination_addr" "$is_forced" "$meta_bytes")
        fi

        local bridge_tx_hash
        bridge_tx_hash=$(echo "$response" | grep "^transactionHash" | cut -f 2- -d ' ' | sed 's/ //g')
        if [[ -n "$bridge_tx_hash" ]]; then
            log "🎉 Success: Tx Hash → $bridge_tx_hash"
            echo "$bridge_tx_hash"
        else
            log "❌ Error: Transaction failed (no hash returned)"
            return 1
        fi
    fi
}

function check_claim_revert_code() {
    local response_content="$1"

    log "💡 Check claim revert code"

    # 0x646cf558 -> AlreadyClaimed()
    if grep -q "0x646cf558" <<<"$response_content"; then
        log "🎉 Deposit is already claimed (revert code 0x646cf558)"
        return 0
    fi

    # 0x002f6fad -> GlobalExitRootInvalid(), meaning that the global exit root is not yet injected to the destination network
    if grep -q "0x002f6fad" <<<"$response_content"; then
        log "⏳ GlobalExitRootInvalid() (revert code 0x002f6fad)"
        return 2
    fi

    # 0x071389e9 -> InvalidGlobalIndex(), meaning that the global index is invalid
    if grep -q "0x071389e9" <<<"$response_content"; then
        log "⏳ InvalidGlobalIndex() (revert code 0x071389e9)"
        return 3
    fi

    log "❌ Claim failed. response: $response_content"
    return 1
}

# claim_bridge
# -----------------------------------------------------------------------------
# Attempts to execute a claim transaction on a bridge contract until it succeeds
# or the maximum number of attempts is reached.
#
# Parameters:
#   $1 - bridge_info          : JSON string containing bridge transfer data
#                               (fields like global_index, origin_network, etc.)
#   $2 - proof                : JSON string with Merkle proofs and exit roots
#   $3 - destination_rpc_url  : RPC endpoint of the destination network
#   $4 - max_attempts         : Maximum number of retry attempts before failing
#   $5 - poll_frequency       : Number of seconds to wait between retries
#   $6 - source_network_id    : Network ID of the source chain (for context/logs)
#   $7 - bridge_addr          : Address of the bridge smart contract
#
# Behavior:
#   - Calls `claim_call` to submit a claim transaction to the bridge contract.
#   - Retries until the claim succeeds or `max_attempts` is reached.
#   - Suppresses all `cast send` output unless there’s an error.
#
# Returns:
#   - On success: prints the `global_index` of the claimed bridge event to stdout
#   - On failure: prints an error message to stderr and returns exit code 1
#
# Example:
#   global_index=$(claim_bridge "$bridge_info" "$proof" "$rpc_url" 5 10 1 "$bridge_addr")
# -----------------------------------------------------------------------------
function claim_bridge() {
    local bridge_info="$1"
    local proof="$2"
    local destination_rpc_url="$3"
    local max_attempts="$4"
    local poll_frequency="$5"
    local source_network_id="$6"
    local bridge_addr="$7"

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        log "🔍 Attempt ${attempt}/${max_attempts}: claim bridge"

        local global_index
        global_index=$(claim_call "$bridge_info" "$proof" "$destination_rpc_url" "$bridge_addr")
        local status=$?

        if [[ $status -eq 0 ]]; then
            log "🎉 Claim successful for global_index: $global_index"
            echo "$global_index"
            return 0
        fi

        log "⚠️  Claim failed (attempt $attempt/$max_attempts)"
        if (( attempt == max_attempts )); then
            echo "❌ Error: Reached max attempts ($max_attempts) without claiming." >&2
            return 1
        fi

        log "⏳ Retrying in ${poll_frequency}s..."
        sleep "$poll_frequency"
    done
}

# ------------------------------------------------------------------------------
# Function: claim_call
#
# Description:
#   Executes a claim transaction on the destination bridge smart contract.
#   It dynamically determines whether to call `claimAsset` or `claimMessage`
#   based on the provided `leaf_type` in the bridge info. The function prepares
#   all required parameters (proofs, roots, addresses, amounts, etc.) and either:
#     - Displays the calldata for a dry run, or
#     - Sends an actual transaction using `cast send`.
#
# Parameters:
#   $1 - bridge_info: JSON object containing bridge claim data (global_index,
#                     leaf_type, origin/destination networks and addresses, amount, metadata)
#   $2 - proof: JSON object containing Merkle proofs and exit roots
#   $3 - destination_rpc_url: RPC endpoint of the destination network
#   $4 - bridge_addr: Address of the bridge contract on the destination network
#
# Globals used:
#   $dry_run            - if "true", prints calldata without sending transaction
#   $sender_private_key - private key used for transaction signing
#
# Returns:
#   Echoes the global_index of the processed claim (for use by the caller)
# ------------------------------------------------------------------------------
function claim_call() {
    local bridge_info="$1"
    local proof="$2"
    local destination_rpc_url="$3"
    local bridge_addr="$4"

    local claim_sig="$CLAIM_ASSET_FN_SIG"

    local leaf_type
    leaf_type=$(echo "$bridge_info" | jq -r '.leaf_type')
    if [[ $leaf_type != "0" ]]; then
        claim_sig="$CLAIM_MSG_FN_SIG"
    fi

    local \
        in_local_exit_proof \
        in_rollup_exit_proof \
        in_global_index \
        in_main_exit_root \
        in_rollup_exit_root \
        in_orig_net \
        in_orig_addr \
        in_dest_net \
        in_dest_addr \
        in_amount \
        in_metadata

    in_global_index=$(echo "$bridge_info" | jq -r '.global_index')
    in_local_exit_proof=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    in_rollup_exit_proof=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    in_main_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    in_rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    in_orig_net=$(echo "$bridge_info" | jq -r '.origin_network')
    in_orig_addr=$(echo "$bridge_info" | jq -r '.origin_address')
    in_dest_net=$(echo "$bridge_info" | jq -r '.destination_network')
    in_dest_addr=$(echo "$bridge_info" | jq -r '.destination_address')
    in_amount=$(echo "$bridge_info" | jq -r '.amount')
    in_metadata=$(echo "$bridge_info" | jq -r '.metadata')

    if [[ $dry_run == "true" ]]; then
        log "📝 Dry run claim (showing calldata only)"
        cast calldata $claim_sig "$in_local_exit_proof" "$in_rollup_exit_proof" "$in_global_index" \
            "$in_main_exit_root" "$in_rollup_exit_root" "$in_orig_net" "$in_orig_addr" \
            "$in_dest_net" "$in_dest_addr" "$in_amount" "$in_metadata" 2>/dev/null
    else
        log "⏳ Claiming deposit: global_index=$in_global_index orig_net=$in_orig_net dest_net=$in_dest_net amount=$in_amount"
        log "🔍 Exit roots: MainnetExitRoot=$in_main_exit_root RollupExitRoot=$in_rollup_exit_root"

        local response
        if ! response=$(cast send --rpc-url "$destination_rpc_url" \
            --private-key "$sender_private_key" \
            "$bridge_addr" "$claim_sig" "$in_local_exit_proof" "$in_rollup_exit_proof" \
            "$in_global_index" "$in_main_exit_root" "$in_rollup_exit_root" \
            "$in_orig_net" "$in_orig_addr" "$in_dest_net" "$in_dest_addr" \
            "$in_amount" "$in_metadata" 2>&1 >/dev/null); then

            check_claim_revert_code "$response"
        fi
    fi

    echo "$in_global_index"
}

function generate_global_index() {
    local bridge_info="$1"
    local source_network_id="$2"
    # Extract values from JSON
    deposit_count=$(echo "$bridge_info" | jq -r '.deposit_count')

    # Ensure source_network_id and deposit_count are within valid bit ranges
    source_network_id=$((source_network_id & 0xFFFFFFFF)) # Mask to 32 bits
    deposit_count=$((deposit_count & 0xFFFFFFFF))         # Mask to 32 bits

    # Construct the final value using bitwise operations
    final_value=0

    # 192nd bit: (if mainnet is 0, then 1, otherwise 0)
    if [ "$source_network_id" -eq 0 ]; then
        final_value=$(echo "$final_value + 2^64" | bc)
    fi

    # 193-224 bits: (if mainnet is 0, 0; otherwise source_network_id - 1)
    if [ "$source_network_id" -ne 0 ]; then
        dest_shifted=$(echo "($source_network_id - 1) * 2^32" | bc)
        final_value=$(echo "$final_value + $dest_shifted" | bc)
    fi

    # 225-256 bits: deposit_count (32 bits)
    final_value=$(echo "$final_value + $deposit_count" | bc)

    echo "$final_value"
}

function wait_for_expected_token() {
    local expected_origin_token="$1"
    local network_id="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"

    local attempt=0
    local token_mappings_result
    local found_match=false

    while true; do
        ((attempt++))

        # Construct and run the curl command
        local cmd="curl -s -H \"Content-Type: application/json\" \"$aggkit_url/bridge/v1/token-mappings?network_id=$network_id\""
        token_mappings_result=$(eval "$cmd")

        # Extract all origin_token_address entries
        local all_tokens
        mapfile -t all_tokens < <(echo "$token_mappings_result" | jq -r '.token_mappings[].origin_token_address // empty')

        echo "🔍 Attempt $attempt/$max_attempts: checking ${#all_tokens[@]} token(s) for expected origin token '$expected_origin_token' \
(network id = $network_id, bridge indexer url = $aggkit_url)" >&3

        # Check if expected token exists among the results (case-insensitive)
        for token in "${all_tokens[@]}"; do
            if [[ "${token,,}" == "${expected_origin_token,,}" ]]; then
                found_match=true
                break
            fi
        done

        if [[ "$found_match" == true ]]; then
            echo "✅ Success: Expected origin_token_address '$expected_origin_token' found among token_mappings." >&3
            echo "$token_mappings_result"
            return 0
        fi

        # Fail if max attempts reached
        if (( attempt >= max_attempts )); then
            echo "❌ Error: Reached max attempts ($max_attempts) without finding expected origin_token_address '$expected_origin_token'." >&3
            echo "❌ Error: Reached max attempts ($max_attempts) without finding expected origin_token_address '$expected_origin_token'." >&2
            echo "Command: $cmd"
            echo "--- token_mappings_result ---"
            echo "$token_mappings_result"
            echo "--- token_mappings_result ---"
            return 1
        fi

        # Wait before the next poll
        sleep "$poll_frequency"
    done
}

# get_claim
# -----------------------------------------------------------------------------
# Continuously queries the bridge indexer API for a specific claim until it is
# found or the maximum number of attempts is reached.
#
# Parameters:
#   $1 - network_id           : ID of the network to search claims on
#   $2 - expected_global_index: The target global index of the claim to locate
#   $3 - max_attempts         : Maximum number of retry attempts before failing
#   $4 - poll_frequency       : Seconds to wait between consecutive retries
#   $5 - aggkit_url           : Base URL of the bridge indexer (Aggkit) service
#
# Behavior:
#   - Repeatedly calls the Aggkit REST endpoint:
#       GET /bridge/v1/claims?network_id=<id>&global_index=<index>
#   - Parses the JSON response and looks for the first claim entry.
#   - Verifies that all required fields are present and non-empty.
#   - Retries until the claim is found or the maximum number of attempts is reached.
#
# Returns:
#   - On success: Prints the full JSON object for the found claim to stdout.
#   - On failure: Prints an error message to stderr and exits with code 1.
#
# Example:
#   claim=$(get_claim 1 42 10 5 "https://indexer.agglayer.io")
# -----------------------------------------------------------------------------
function get_claim() {
    local network_id="$1"
    local expected_global_index="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"
    local attempt=0

    log "🔍 Searching for claim with global_index: ${expected_global_index} (bridge indexer url: ${aggkit_url})..."

    while true; do
        ((attempt++))
        log "🔍 Attempt $attempt/$max_attempts: get claim global index: $expected_global_index"

        # Build the query URL
        local query_url="$aggkit_url/bridge/v1/claims?network_id=$network_id&include_all_fields=true&global_index=$expected_global_index"

        claims_result=$(curl -s -H "Content-Type: application/json" "$query_url" 2>&1)
        log "------ claims_result ------ $query_url"
        log "$claims_result"
        log "------ claims_result ------"

        # Extract the single claim (or null if not found)
        local row
        row=$(echo "$claims_result" | jq -c '.claims[0]')

        # In case row is not empty, we found the expected claim
        if [[ "$row" != "null" ]]; then
            log "🎉 Success: Expected global_index '$expected_global_index' found. Exiting loop."

            # Required fields validation
            local required_fields=(
                "block_num"
                "block_timestamp"
                "tx_hash"
                "global_index"
                "origin_address"
                "origin_network"
                "destination_address"
                "destination_network"
                "amount"
                "global_exit_root"
                "rollup_exit_root"
                "mainnet_exit_root"
                "metadata"
                "proof_local_exit_root"
                "proof_rollup_exit_root"
            )

            for field in "${required_fields[@]}"; do
                value=$(jq -r --arg fld "$field" '.[$fld]' <<<"$row")
                if [ "$value" = "null" ] || [ -z "$value" ]; then
                    log "🔍 Claims result:"
                    log "$claims_result"
                    echo "❌ Error: Assertion failed missing or null '$field' in the claim object." >&2
                    return 1
                fi
            done

            echo "$row"
            return 0
        fi

        # Fail test if max attempts are reached
        if (( attempt >= max_attempts )); then
            log "🔍 Claims result:"
            log "$claims_result"
            echo "❌ Error: Reached max attempts ($max_attempts) without finding expected claim with global index ($expected_global_index)." >&2
            return 1
        fi

        log "⏳ Claim not found yet. Retrying in $poll_frequency seconds..."
        sleep "$poll_frequency"
    done
}

function get_bridge() {
    local debug_msg="[$1]"
    local network_id="$2"
    local expected_tx_hash="$3"
    local max_attempts="$4"
    local poll_frequency="$5"
    local aggkit_url="$6"
    local from_address="${7:-}"

    local attempt=0
    local bridges_result=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 $debug_msg Attempt $attempt/$max_attempts: fetching bridge \
(network id = $network_id, tx hash = $expected_tx_hash, bridge indexer url = $aggkit_url from_address=$from_address)"

        # Build the query URL with optional from_address parameter
        local query_url="$aggkit_url/bridge/v1/bridges?network_id=$network_id"
        if [[ -n "$from_address" ]]; then
            query_url="$query_url&from_address=$from_address"
        fi

        # Capture both stdout (bridge result) and stderr (error message)
        bridges_result=$(curl -s -H "Content-Type: application/json" "$query_url" 2>&1)
        log "$debug_msg ------ bridges_result ------"
        log "$bridges_result"
        log "$debug_msg ------ bridges_result ------"

        # Check if the response contains an error
        if [[ "$bridges_result" == *"error"* || "$bridges_result" == *"Error"* ]]; then
            log "⚠️ $debug_msg Error: $bridges_result , retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        if [[ "$bridges_result" == "" ]]; then
            log "$debug_msg Empty bridges response retrieved, retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        # Extract the elements of the 'bridges' array one by one
        for row in $(echo "$bridges_result" | jq -c '.bridges[]'); do
            # Parse out the tx_hash from each element
            tx_hash=$(echo "$row" | jq -r '.tx_hash')

            if [[ "$tx_hash" == "$expected_tx_hash" ]]; then
                log "🎉 $debug_msg Found expected bridge with tx hash: $tx_hash"
                echo "$row"
                return 0
            fi
        done

        sleep "$poll_frequency"
    done

    log "❌ $debug_msg Failed to find bridge after $max_attempts attempts."
    return 1
}

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&3
}

function generate_claim_proof() {
    local network_id="$1"
    local deposit_count="$2"
    local l1_info_tree_index="$3"
    local max_attempts="$4"
    local poll_frequency="$5"
    local aggkit_url="$6"

    local attempt=0
    local proof=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching proof \
(network id = $network_id, deposit count = $deposit_count, l1 info tree index = $l1_info_tree_index, bridge indexer url = $aggkit_url)"

        # Capture both stdout (proof) and stderr (error message)
        proof=$(curl -s -H "Content-Type: application/json" \
            "$aggkit_url/bridge/v1/claim-proof?network_id=$network_id&deposit_count=$deposit_count&leaf_index=$l1_info_tree_index" 2>&1)
        log "------ proof ------"
        log "$proof"
        log "------ proof ------"

        # Check if the response contains an error
        if [[ "$proof" == *"error"* || "$proof" == *"Error"* ]]; then
            log "⚠️ Error: $proof"
            sleep "$poll_frequency"
            continue
        fi

        if [[ "$proof" == "" ]]; then
            log "Empty proof retrieved, retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        echo "$proof"
        return 0
    done

    log "❌ Failed to generate a claim proof for $deposit_count after $max_attempts attempts."
    return 1
}
function update_l1_info_tree() {
    # This is a required action in FEP op-succinct
    # To be able to claim on L1 it's required an external update of L1infotree in L1
    # because needs to be included in a certificate and the certificate require a proof of
    # block Range that is anchored to the block of last l1infotree update
    local sleep_time="${1:-300}" # default 300 seconds
    local msg="${2:-}"
    if [ $aggsender_mode_is_fep == 0 ]; then
        log "🪤 $msg skipped bridge L1->L2 to update l1InfoTree, because in PP mode is not required" >&3
        return
    fi
    log "🪤 $msg Sleeping $sleep_time seconds before doing a bridge L1->L2 to update l1InfoTree" >&3
    sleep $sleep_time
    log "🪤 $msg Doing a bridge L1->L2 to update l1InfoTree" >&3
    local push_destination_net
    push_destination_net=$destination_net
    local push_amount
    push_amount=$amount
    amount=$(cast --to-unit 0.00001ether wei)
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    destination_net=$push_destination_net
    amount=$push_amount
}

function find_l1_info_tree_index_for_bridge() {
    local network_id="$1"
    local expected_deposit_count="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"
    local debug_msg="[${6:-}]"
    local attempt=0
    local index=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 $debug_msg Attempt $attempt/$max_attempts: fetching L1 info tree index for bridge \
(network id = $network_id, deposit count = $expected_deposit_count, bridge indexer url = $aggkit_url)"

        # Capture both stdout (index) and stderr (error message)
        index=$(curl -s -H "Content-Type: application/json" \
            "$aggkit_url/bridge/v1/l1-info-tree-index?network_id=$network_id&deposit_count=$expected_deposit_count" 2>&1)
        log "$debug_msg ------ index ------"
        log "$index"
        log "$debug_msg ------ index ------"

        # Check if the response contains an error
        if [[ "$index" == *"error"* || "$index" == *"Error"* ]]; then
            log "⚠️ $debug_msg  Error: $index"
            sleep "$poll_frequency"
            continue
        fi

        if [[ "$index" == "" ]]; then
            log "$debug_msg  Empty index retrieved, retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        echo "$index"
        return 0
    done
    log "$debug_msg  curl -s -H "Content-Type: application/json" $aggkit_url/bridge/v1/l1-info-tree-index?network_id=$network_id&deposit_count=$expected_deposit_count"
    log "❌ $debug_msg  Failed to find L1 info tree index after $max_attempts attempts"
    return 1
}

# find_injected_l1_info_leaf
#
# Polls the AggKit bridge indexer until an injected L1 info leaf becomes
# available. This is needed because the indexer may be behind and needs time
# to fill the L1 info tree.
#
# Arguments:
#   $1 - network_id          (the destination network ID where the injected leaf must be found)
#   $2 - index               (leaf index to query)
#   $3 - max_attempts        (how many times to retry)
#   $4 - poll_frequency      (seconds to sleep between attempts)
#   $5 - aggkit_url          (AggKit bridge indexer base URL)
#
# Returns:
#   exit code 0: success
#   exit code 1: failure (after all retries)
function find_injected_l1_info_leaf() {
    local network_id="$1"
    local index="$2"
    local max_attempts="$3"
    local poll_frequency="$4"
    local aggkit_url="$5"

    local attempt=0
    local injected_info=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching injected info after index \
(network id = $network_id, index = $index, bridge indexer url = $aggkit_url)"

        # Capture both stdout (injected_info) and stderr (error message)
        response="$(curl -s -w '\n%{http_code}' \
            "$aggkit_url/bridge/v1/injected-l1-info-leaf?network_id=$network_id&leaf_index=$index")"

        # Extract body and status code
        http_status="$(echo "$response" | tail -n1)"
        # all except the last line
        response="$(echo "$response" | sed '$d')"

        log "------ response (status: $http_status) ------"
        log "$response"
        log "------ response ------"

        # Check for non-200 HTTP status and retry
        if [[ "$http_status" != "200" ]]; then
            log "⚠️ HTTP error ($http_status): $response"
            sleep "$poll_frequency"
            continue
        fi

        # Check empty response
        if [[ -z "$response" ]]; then
            log "⚠️ Empty response; retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        # Check if the response contains an error
        if [[ "$response" == *"error"* || "$response" == *"Error"* ]]; then
            log "⚠️ Error: $response"
            sleep "$poll_frequency"
            continue
        fi

        echo "$response"
        return 0
    done

    log "❌ Failed to find injected info for index $index after $max_attempts attempts."
    return 1
}

# process_bridge_claim processes a bridge claim by fetching the bridge details,
# finding the L1 info tree index, generating a claim proof, and submitting the claim.
#
# Arguments:
#   $1 - message to show on logs
#   $2 - origin_network_id: The origin network ID where the bridge transaction occurred.
#   $3 - bridge_tx_hash: The transaction hash of the bridge interaction.
#   $4 - destination_network_id: The destination network ID for bridge transaction.
#   $5 - bridge_addr: The bridge contract address where the claim will be submitted.
#   $6 - origin_aggkit_bridge_url: The base URL of the bridge service of origin network.
#   $7 - destination_aggkit_bridge_url: The base URL of the bridge service of destination network.
#   $8 - destination_rpc_url: The RPC URL of execution client used to interact with the network for submitting the claim.
#   $9 - from_address (optional): The address used to filter bridge transactions (if empty, no filtering is applied).
function process_bridge_claim() {
    local debug_msg_clean="$1"
    local debug_msg="[$1]"
    local origin_network_id="$2"
    local bridge_tx_hash="$3"
    local destination_network_id="$4"
    local bridge_addr="$5"
    local origin_aggkit_bridge_url="$6"
    local destination_aggkit_bridge_url="$7"
    local destination_rpc_url="$8"
    local from_address="${9:-}"

    # 1. Fetch bridge details
    local bridge
    # n_attempts=34 / sleep=30s -> 17 mins max wait time
    bridge="$(get_bridge "$debug_msg_clean" "$origin_network_id" "$bridge_tx_hash" 34 30 "$origin_aggkit_bridge_url" "$from_address")" || {
        log "❌ $debug_msg process_bridge_claim failed at 🔎 get_bridge (tx: $bridge_tx_hash)"
        echo "process_bridge_claim failed at get_bridge" >&2
        return 1
    }

    # 2. Find the L1 info tree index
    local deposit_count
    deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    local l1_info_tree_index
    l1_info_tree_index="$(find_l1_info_tree_index_for_bridge "$origin_network_id" "$deposit_count" 30 30 "$origin_aggkit_bridge_url" "$debug_msg_clean")" || {
        log "❌ $debug_msg process_bridge_claim failed at 🌳 find_l1_info_tree_index_for_bridge (deposit_count: $deposit_count)"
        echo "process_bridge_claim failed at find_l1_info_tree_index_for_bridge" >&2
        return 1
    }

    # 3. Retrieve the injected L1 info leaf
    local injected_info
    injected_info="$(find_injected_l1_info_leaf "$destination_network_id" "$l1_info_tree_index" 12 10 "$destination_aggkit_bridge_url")" || {
        log "❌ $debug_msg process_bridge_claim failed at 🍃 find_injected_l1_info_leaf (index: $l1_info_tree_index)"
        echo "process_bridge_claim failed at find_injected_l1_info_leaf" >&2
        return 1
    }

    # 4. Generate the claim proof
    l1_info_tree_index="$(echo "$injected_info" | jq -r '.l1_info_tree_index')"
    local proof
    proof="$(generate_claim_proof "$origin_network_id" "$deposit_count" "$l1_info_tree_index" 10 3 "$origin_aggkit_bridge_url")" || {
        log "❌ $debug_msg process_bridge_claim failed at 🛡️ generate_claim_proof (index: $l1_info_tree_index)"
        echo "process_bridge_claim failed at generate_claim_proof" >&2
        return 1
    }

    # 5. Submit the claim
    local global_index
    global_index="$(claim_bridge "$bridge" "$proof" "$destination_rpc_url" 10 3 "$origin_network_id" "$bridge_addr")" || {
        log "❌ $debug_msg process_bridge_claim failed at 📤 claim_bridge (bridge_addr: $bridge_addr)"
        echo "process_bridge_claim failed at claim_bridge" >&2
        return 1
    }

    log "✅ $debug_msg process_bridge_claim succeeded! (global_index: $global_index)"
    echo "$global_index"
}


function get_legacy_token_migrations() {
    local network_id="$1"
    local page_number="$2"
    local page_size="$3"
    local aggkit_url="$4"
    local max_attempts="$5"
    local poll_frequency="$6"
    local tx_hash="${7:-}"

    local attempt=0
    local legacy_token_migrations=""

    while ((attempt < max_attempts)); do
        ((attempt++))
        log "🔎 Attempt $attempt/$max_attempts: fetching legacy token migrations \
(network id = $network_id, page number = $page_number, page size = $page_size, bridge indexer url = $aggkit_url)"

        # Capture both stdout (legacy_token_migrations) and stderr (error message)
        legacy_token_migrations=$(curl -s -H "Content-Type: application/json" \
            "$aggkit_url/bridge/v1/legacy-token-migrations?network_id=$network_id&page_number=$page_number&page_size=$page_size" 2>&1)
        log "------ legacy_token_migrations ------"
        log "$legacy_token_migrations"
        log "------ legacy_token_migrations ------"

        # Check if the response contains an error
        if [[ "$legacy_token_migrations" == *"error"* || "$legacy_token_migrations" == *"Error"* ]]; then
            log "⚠️ Error: $legacy_token_migrations"
            sleep "$poll_frequency"
            continue
        fi

        if [[ "$legacy_token_migrations" == "" ]]; then
            log "Empty legacy token migration response retrieved, retrying in ${poll_frequency}s..."
            sleep "$poll_frequency"
            continue
        fi

        if [[ -n "$tx_hash" ]]; then
            if echo "$legacy_token_migrations" | grep -q "\"tx_hash\":\"$tx_hash\""; then
                log "✅ Found tx_hash $tx_hash in response."
                echo "$legacy_token_migrations"
                return 0
            else
                log "⚠️ tx_hash $tx_hash not found; retrying in ${poll_frequency}s..."
                sleep "$poll_frequency"
                continue
            fi
        fi

        echo "$legacy_token_migrations"
        return 0
    done

    log "❌ Failed to find legacy token migrations after $max_attempts attempts."
    return 1
}

function is_claimed() {
    local deposit_count="$1"
    local origin_network="$2"
    local bridge_addr="$3"
    local rpc_url="$4"

    log "🔍 Checking isClaimed for deposit_count: $deposit_count, origin_network: $origin_network"

    local is_claimed_output
    is_claimed_output=$(cast call \
        "$bridge_addr" \
        "isClaimed(uint32,uint32)" \
        "$deposit_count" \
        "$origin_network" \
        --rpc-url "$rpc_url" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "❌ Error: Failed to check isClaimed"
        log "$is_claimed_output"
        return 1
    fi

    local is_claimed
    is_claimed=$(echo "$is_claimed_output" | tr -d '\n')
    log "📋 isClaimed hex result: $is_claimed"

    # Convert hex to boolean
    if [[ "$is_claimed" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Helper function to extract claim parameters for a bridge transaction
# This function extracts all the claim parameters and returns them as a JSON object
# Usage: claim_params=$(extract_claim_parameters_json <bridge_tx_hash> <asset_number>)
function extract_claim_parameters_json() {
    local bridge_tx_hash="$1"
    local asset_number="$2"
    local origin_network_id="$3"
    local from_address="${4:-}"

    log "📋 Getting ${asset_number} bridge details"
    run get_bridge "-" "$origin_network_id" "$bridge_tx_hash" 50 10 "$aggkit_bridge_url" "$from_address"
    assert_success
    local bridge_response="$output"
    log "📝 ${asset_number} bridge response: $bridge_response"
    local deposit_count
    deposit_count=$(echo "$bridge_response" | jq -r '.deposit_count')
    local global_index
    global_index=$(echo "$bridge_response" | jq -r '.global_index')
    log "📝 ${asset_number} global index: $global_index"

    log "🌳 Getting L1 info tree index for ${asset_number} bridge"
    run find_l1_info_tree_index_for_bridge "$origin_network_id" "$deposit_count" 50 10 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"
    log "📝 ${asset_number} L1 info tree index: $l1_info_tree_index"

    log "🔐 Getting ${asset_number} claim proof"
    run generate_claim_proof "$origin_network_id" "$deposit_count" "$l1_info_tree_index" 50 10 "$aggkit_bridge_url"
    assert_success
    local proof="$output"
    log "📝 ${asset_number} proof: $proof"

    # Extract all claim parameters for the asset
    log "🎯 Extracting claim parameters for ${asset_number} asset"
    local proof_local_exit_root
    proof_local_exit_root=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local proof_rollup_exit_root
    proof_rollup_exit_root=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local mainnet_exit_root
    mainnet_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local rollup_exit_root
    rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local origin_network
    origin_network=$(echo "$bridge_response" | jq -r '.origin_network')
    local origin_address
    origin_address=$(echo "$bridge_response" | jq -r '.origin_address')
    local destination_network
    destination_network=$(echo "$bridge_response" | jq -r '.destination_network')
    local destination_address
    destination_address=$(echo "$bridge_response" | jq -r '.destination_address')
    local amount
    amount=$(echo "$bridge_response" | jq -r '.amount')
    local metadata
    metadata=$(echo "$bridge_response" | jq -r '.metadata')

    # Return all parameters as a JSON object
    # Build a readable JSON object using jq for safe encoding/wrapping
    local json_output
    json_output=$(
        jq -n \
            --arg deposit_count "$deposit_count" \
            --arg proof_local_exit_root "$proof_local_exit_root" \
            --arg proof_rollup_exit_root "$proof_rollup_exit_root" \
            --arg global_index "$global_index" \
            --arg mainnet_exit_root "$mainnet_exit_root" \
            --arg rollup_exit_root "$rollup_exit_root" \
            --arg origin_network "$origin_network" \
            --arg origin_address "$origin_address" \
            --arg destination_network "$destination_network" \
            --arg destination_address "$destination_address" \
            --arg amount "$amount" \
            --arg metadata "$metadata" \
            --arg l1_info_tree_index "$l1_info_tree_index" \
            '{
                deposit_count: $deposit_count,
                proof_local_exit_root: $proof_local_exit_root,
                proof_rollup_exit_root: $proof_rollup_exit_root,
                global_index: $global_index,
                mainnet_exit_root: $mainnet_exit_root,
                rollup_exit_root: $rollup_exit_root,
                origin_network: $origin_network,
                origin_address: $origin_address,
                destination_network: $destination_network,
                destination_address: $destination_address,
                amount: $amount,
                metadata: $metadata,
                l1_info_tree_index: $l1_info_tree_index
            }'
    )

    echo "$json_output"
}

# normalize_cast_array: convert ["0x..","0x.."] or ["0x..", "0x.."]
#   → [0x.., 0x..]
function normalize_cast_array() {
  local arr="$1"

  echo "$arr" \
    | sed 's/"//g' \
    | sed 's/,/, /g'
}
