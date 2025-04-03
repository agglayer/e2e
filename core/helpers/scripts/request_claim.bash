#!/usr/bin/env bash

function request_claim(){
    local deposit_file="$1"
    local proof_file="$2"
    local destination_rpc_url="$3"
    
    local leaf_type=$(jq -r '.leaf_type' $deposit_file)
    local claim_sig="claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    
    if [[ $leaf_type != "0" ]]; then
       claim_sig="claimMessage(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"
    fi

    local in_merkle_proof="$(jq -r -c '.proof.merkle_proof' $proof_file | tr -d '"')"
    local in_rollup_merkle_proof="$(jq -r -c '.proof.rollup_merkle_proof' $proof_file | tr -d '"')"
    local in_global_index=$(jq -r '.global_index' $deposit_file)
    local in_main_exit_root=$(jq -r '.proof.main_exit_root' $proof_file)
    local in_rollup_exit_root=$(jq -r '.proof.rollup_exit_root' $proof_file)
    local in_orig_net=$(jq -r '.orig_net' $deposit_file)
    local in_orig_addr=$(jq -r '.orig_addr' $deposit_file)
    local in_dest_net=$(jq -r '.dest_net' $deposit_file)
    local in_dest_addr=$(jq -r '.dest_addr' $deposit_file)
    local in_amount=$(jq -r '.amount' $deposit_file)
    local in_metadata=$(jq -r '.metadata' $deposit_file)
    if [[ $dry_run == "true" ]]; then
            echo "... Not real cleaim (dry_run mode)" >&3
            cast calldata $claim_sig "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata
        else
            local comp_gas_price=$(bc -l <<< "$gas_price * 1.5" | sed 's/\..*//')
            if [[ $? -ne 0 ]]; then
                echo "Failed to calculate gas price" >&3
                exit 1
            fi
            echo "... Claiming deposit: global_index: $in_global_index orig_net: $in_orig_net dest_net: $in_dest_net  amount:$in_amount" >&3
            echo "claim: mainnetExitRoot=$in_main_exit_root  rollupExitRoot=$in_rollup_exit_root"
            echo "cast send --legacy --gas-price $comp_gas_price --rpc-url $destination_rpc_url --private-key $sender_private_key $bridge_addr \"$claim_sig\" \"$in_merkle_proof\" \"$in_rollup_merkle_proof\" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata" 
            local tmp_response=$(mktemp)
            cast send --legacy --gas-price $comp_gas_price \
                        --rpc-url $destination_rpc_url \
                        --private-key $sender_private_key \
                        $bridge_addr "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" $in_global_index $in_main_exit_root $in_rollup_exit_root $in_orig_net $in_orig_addr $in_dest_net $in_dest_addr $in_amount $in_metadata 2> $tmp_response ||  check_claim_revert_code $tmp_response 
        fi
}
