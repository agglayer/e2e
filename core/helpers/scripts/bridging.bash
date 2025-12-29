#!/bin/bash

# Variables set by test environment setup functions - disable shellcheck warnings
# shellcheck disable=SC2154
declare l2_rpc_url l2_private_key claimtxmanager_addr

function fund_claim_tx_manager() {
    local balance

    balance=$(cast balance --rpc-url "$l2_rpc_url" "$claimtxmanager_addr")
    if [[ $balance != "0" ]]; then
        return
    fi
    cast send --legacy --value 1ether \
         --rpc-url "$l2_rpc_url" \
         --private-key "$l2_private_key" \
         "$claimtxmanager_addr"
}

function polycli_bridge_asset_get_info() {
    local bridge_asset_output="$1"
    local rpc_url="$2"
    local bridge_addr="$3"

    # remove ANSI escape codes
    clean_output=$(echo "$bridge_asset_output" | sed -r 's/\x1B\[[0-9;]*[JKmsu]//g')

    # get the deposit count from the output
    depositCount=$(sed -n 's/.*depositCount=\([0-9][0-9]*\).*/\1/p' <<< "$clean_output")

    if [[ -z "$depositCount" ]]; then
        # if that's ano old version of polycli, get the txhash for the bridge asset
        bridge_tx_hash=$(sed -n 's/.*txHash=\(0x[a-fA-F0-9][a-fA-F0-9]*\).*/\1/p' <<< "$clean_output")
        if [[ -z "$bridge_tx_hash" ]]; then
            echo "Bridge tx hash is empty"
            exit 1
        fi

        # get the event data for the bridge asset
        bridge_deposit_log_data=$(cast receipt --rpc-url $rpc_url $bridge_tx_hash --json | jq -r \
            --arg bridge_addr "$bridge_addr" '
            .logs[] 
            | select((.address|ascii_downcase) == ($bridge_addr | ascii_downcase)
            and .topics == ["0x501781209a1f8899323b96b4ef08b168df93e0a90c673d1e4cce39366cb62f9b"]) 
        | .data')
        if [[ -z "$bridge_deposit_log_data" ]]; then
            echo "Bridge deposit log data is empty"
            exit 1
        fi

        # get the deposit count by decoding the event
        # BridgeEvent (uint8 leafType, uint32 originNetwork, address originAddress, uint32 destinationNetwork, address destinationAddress, uint256 amount, bytes metadata, uint32 depositCount)
        event_sig='BridgeEvent(uint8,uint32,address,uint32,address,uint256,bytes,uint32)'
        deposit_count=$(cast decode-event "$bridge_deposit_log_data" --sig "$event_sig" --json | jq -r '.[7]')
        if [[ -z "$deposit_count" ]]; then
            echo "Deposit count is empty"
            exit 1
        fi
    fi

    # JSON format just in case we want to add more info later on
    echo "{\"depositCount\":\"$depositCount\"}"
}
