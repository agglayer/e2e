#!/usr/bin/env bash

function claim_tx_hash() {
    local timeout="$1" 
    tx_hash="$2"
    local destination_addr="$3"
    local destination_rpc_url="$4"
    local bridge_merkle_proof_url="$5"
    
    readonly bridge_deposit_file=$(mktemp)
    local ready_for_claim="false"
    local start_time=$(date +%s)
    local current_time=$(date +%s)
    local end_time=$((current_time + timeout))
    while true; do
        current_time=$(date +%s)
        elpased_time=$((current_time - start_time))
        if ((current_time > end_time)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached waiting for tx_hash [$tx_hash] timeout: $timeout! (elapsed: $elpased_time)"
            echo "     $current_time > $end_time" >&3
            exit 1
        fi
        curl -s "$bridge_merkle_proof_url/bridges/$destination_addr?limit=100&offset=0" | jq  "[.deposits[] | select(.tx_hash == \"$tx_hash\" )]" > $bridge_deposit_file
        deposit_count=$(jq '. | length' $bridge_deposit_file)
        if [[ $deposit_count == 0 ]]; then
            echo "...[$(date '+%Y-%m-%d %H:%M:%S')] ❌  the tx_hash [$tx_hash] not found (elapsed: $elpased_time / timeout:$timeout)" >&3   
            sleep "$claim_frequency"
            continue
        fi
        local ready_for_claim=$(jq '.[0].ready_for_claim' $bridge_deposit_file)
        if [ $ready_for_claim != "true" ]; then
            echo ".... [$(date '+%Y-%m-%d %H:%M:%S')] ⏳ the tx_hash $tx_hash is not ready for claim yet (elapsed: $elpased_time / timeout:$timeout)" >&3
            sleep "$claim_frequency"
            continue
        else
            break
        fi
    done
    # Deposit is ready for claim
    echo "....[$(date '+%Y-%m-%d %H:%M:%S')] 🎉 the tx_hash $tx_hash is ready for claim! (elapsed: $elpased_time)" >&3
    local curr_claim_tx_hash=$(jq '.[0].claim_tx_hash' $bridge_deposit_file)
    if [ $curr_claim_tx_hash != "\"\"" ]; then
        echo "....[$(date '+%Y-%m-%d %H:%M:%S')] 🎉  the tx_hash $tx_hash is already claimed" >&3
        exit 0
    fi
    local curr_deposit_cnt=$(jq '.[0].deposit_cnt' $bridge_deposit_file)
    local curr_network_id=$(jq  '.[0].network_id' $bridge_deposit_file)
    readonly current_deposit=$(mktemp)
    jq '.[(0|tonumber)]' $bridge_deposit_file | tee $current_deposit
    readonly current_proof=$(mktemp)
    echo ".... requesting merkel proof for $tx_hash deposit_cnt=$curr_deposit_cnt network_id: $curr_network_id" >&3
    request_merkle_proof "$curr_deposit_cnt" "$curr_network_id" "$bridge_merkle_proof_url" "$current_proof"
    echo "FILE current_deposit=$current_deposit" 
    echo "FILE bridge_deposit_file=$bridge_deposit_file" 
    echo "FILE current_proof=$current_proof" 

    while true; do 
        echo ".... requesting claim for $tx_hash" >&3
        run request_claim $current_deposit $current_proof $destination_rpc_url
        request_result=$status
        echo "....[$(date '+%Y-%m-%d %H:%M:%S')] 🎉  request_claim returns $request_result" >&3
        if [ $request_result -eq 0 ]; then
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] 🎉   claim successful" >&3
            break
        fi
        if [ $request_result -eq 2 ]; then
            # GlobalExitRootInvalid() let's retry
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ❌  claim failed, let's retry" >&3
            current_time=$(date +%s)
            elpased_time=$((current_time - start_time))
            if ((current_time > end_time)); then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached waiting for tx_hash [$tx_hash] timeout: $timeout! (elapsed: $elpased_time)"
                echo "     $current_time > $end_time" >&3
                exit 1
            fi
            sleep $claim_frequency
            continue
        fi
        if [ $request_result -ne 0 ]; then
            echo "....[$(date '+%Y-%m-%d %H:%M:%S')] ✅  claim successful tx_hash [$tx_hash]" >&3
            exit 1
        fi
    done
    echo "....[$(date '+%Y-%m-%d %H:%M:%S')]   claimed" >&3
    export global_index=$(jq '.global_index' $current_deposit | sed -e 's/\x1b\[[0-9;]*m//g' | tr -d '"')
    # clean up temp files
    rm $current_deposit
    rm $current_proof
    rm $bridge_deposit_file
    
}
