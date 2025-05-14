#!/usr/bin/env bash

function claim() {
    local destination_rpc_url="$1"
    local bridge_type="$2"
    local bridge_addr="$3"
    local claim_sig="claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    if [[ $bridge_type == "bridgeMessage" ]]; then
        claim_sig="claimMessage(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    fi
    
    readonly bridge_deposit_file=$(mktemp)
    readonly claimable_deposit_file=$(mktemp)
    echo "Getting full list of deposits" >&3
    echo "    curl -s \"$bridge_api_url/bridges/$destination_addr?limit=100&offset=0\"" >&3
    curl -s "$bridge_api_url/bridges/$destination_addr?limit=100&offset=0" | jq '.' | tee $bridge_deposit_file

    echo "Looking for claimable deposits" >&3
    jq '[.deposits[] | select(.ready_for_claim == true and .claim_tx_hash == "" and .dest_net == '$destination_net')]' $bridge_deposit_file | tee $claimable_deposit_file
    readonly claimable_count=$(jq '. | length' $claimable_deposit_file)
    echo "Found $claimable_count claimable deposits" >&3

    if [[ $claimable_count == 0 ]]; then
        echo "We have no claimable deposits at this time" >&3
        exit 1
    fi

    echo "We have $claimable_count claimable deposits on network $destination_net. Let's get this party started." >&3
    readonly current_deposit=$(mktemp)
    readonly current_proof=$(mktemp)
    local gas_price_factor=1
    while read deposit_idx; do
        echo "Starting claim for tx index: "$deposit_idx >&3
        echo "Deposit info:" >&3
        jq --arg idx $deposit_idx '.[($idx | tonumber)]' $claimable_deposit_file | tee $current_deposit >&3

        curr_deposit_cnt=$(jq -r '.deposit_cnt' $current_deposit)
        curr_network_id=$(jq -r '.network_id' $current_deposit)
        curl -s "$bridge_api_url/merkle-proof?deposit_cnt=$curr_deposit_cnt&net_id=$curr_network_id" | jq '.' | tee $current_proof

        in_merkle_proof="$(jq -r -c '.proof.merkle_proof' $current_proof | tr -d '"')"
        in_rollup_merkle_proof="$(jq -r -c '.proof.rollup_merkle_proof' $current_proof | tr -d '"')"
        in_global_index=$(jq -r '.global_index' $current_deposit)
        in_main_exit_root=$(jq -r '.proof.main_exit_root' $current_proof)
        in_rollup_exit_root=$(jq -r '.proof.rollup_exit_root' $current_proof)
        in_orig_net=$(jq -r '.orig_net' $current_deposit)
        in_orig_addr=$(jq -r '.orig_addr' $current_deposit)
        in_dest_net=$(jq -r '.dest_net' $current_deposit)
        in_dest_addr=$(jq -r '.dest_addr' $current_deposit)
        in_amount=$(jq -r '.amount' $current_deposit)
        in_metadata=$(jq -r '.metadata' $current_deposit)

        if [[ $dry_run == "true" ]]; then
            cast calldata $claim_sig "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata
        else
            local comp_gas_price=$(bc -l <<< "$gas_price * 1.5" | sed 's/\..*//')
            if [[ $? -ne 0 ]]; then
                echo "Failed to calculate gas price" >&3
                exit 1
            fi
            
            echo "cast send --legacy --gas-price $comp_gas_price --rpc-url $destination_rpc_url --private-key $sender_private_key $bridge_addr \"$claim_sig\" \"$in_merkle_proof\" \"$in_rollup_merkle_proof\" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata" >&3
            cast send --legacy --gas-price $comp_gas_price --rpc-url $destination_rpc_url --private-key $sender_private_key $bridge_addr "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata
        fi

    done < <(seq 0 $((claimable_count - 1)))
}
