#!/bin/bash
set -euo pipefail

function claim_bridge() {
    local bridge_info="$1"
    local proof="$2"
    local destination_rpc_url="$3"
    local max_attempts="$4"
    local poll_frequency="$5"
    local source_network_id="$6"

    local attempt=0

    while true; do
        ((attempt++))
        log "🔍 Attempt $attempt"

        run claim_call "$bridge_info" "$proof" "$destination_rpc_url" "$source_network_id"
        local request_result="$status"
        log "💡 claim_call returns $request_result"
        if [ "$request_result" -eq 0 ]; then
            log "🎉 Claim successful"
            run generate_global_index "$bridge_info" "$source_network_id"
            echo $output
            return 0
        fi

        # Fail test if max attempts are reached
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            echo "❌ Error: Reached max attempts ($max_attempts) without claiming." >&2
            return 1
        fi

        log "⏳ Claim failed this time. We'll retry in $poll_frequency seconds"
        # Sleep before the next attempt
        sleep "$poll_frequency"
    done
}

function claim_call() {
    local bridge_info="$1"
    local proof="$2"
    local destination_rpc_url="$3"
    local source_network_id="$4"

    local claim_sig="claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    local leaf_type=$(echo "$bridge_info" | jq -r '.leaf_type')
    if [[ $leaf_type != "0" ]]; then
        claim_sig="claimMessage(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    fi

    local in_merkle_proof=$(echo "$proof" | jq -r '.proof_local_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    local in_rollup_merkle_proof=$(echo "$proof" | jq -r '.proof_rollup_exit_root | join(",")' | sed 's/^/[/' | sed 's/$/]/')
    run generate_global_index "$bridge_info" "$source_network_id"
    local in_global_index=$output
    local in_main_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    local in_rollup_exit_root=$(echo "$proof" | jq -r '.l1_info_tree_leaf.rollup_exit_root')
    local in_orig_net=$(echo "$bridge_info" | jq -r '.origin_network')
    local in_orig_addr=$(echo "$bridge_info" | jq -r '.origin_address')
    local in_dest_net=$(echo "$bridge_info" | jq -r '.destination_network')
    local in_dest_addr=$(echo "$bridge_info" | jq -r '.destination_address')
    local in_amount=$(echo "$bridge_info" | jq -r '.amount')
    local in_metadata=$(echo "$bridge_info" | jq -r '.metadata')

    if [[ $dry_run == "true" ]]; then
        log "📝 Dry run claim (showing calldata only)"
        cast calldata $claim_sig "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata
    else
        local comp_gas_price=$(bc -l <<<"$gas_price * 1.5" | sed 's/\..*//')
        if [[ $? -ne 0 ]]; then
            log "❌ Failed to calculate gas price" >&3
            return 1
        fi
        log "⏳ Claiming deposit: global_index: $in_global_index orig_net: $in_orig_net dest_net: $in_dest_net amount:$in_amount"
        log "🔍 Exit roots: MainnetExitRoot=$in_main_exit_root RollupExitRoot=$in_rollup_exit_root"
        echo "cast send --legacy --gas-price $comp_gas_price --rpc-url $destination_rpc_url --private-key $sender_private_key $bridge_addr \"$claim_sig\" \"$in_merkle_proof\" \"$in_rollup_merkle_proof\" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata"
        local tmp_response=$(mktemp)
        cast send --legacy --gas-price $comp_gas_price \
            --rpc-url $destination_rpc_url \
            --private-key $sender_private_key \
            $bridge_addr "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata 2>$tmp_response || check_claim_revert_code $tmp_response
    fi
}

function generate_global_index() {
    local bridge_info="$1"
    local source_network_id="$2"

    # Extract values from JSON
    deposit_count=$(echo "$bridge_info" | jq -r '.deposit_count')

    # Ensure source_network_id and deposit_count are within valid bit ranges
    source_network_id=$((source_network_id & 0xFFFFFFFF))           # Mask to 32 bits
    deposit_count=$((deposit_count & 0xFFFFFFFF)) # Mask to 32 bits

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
