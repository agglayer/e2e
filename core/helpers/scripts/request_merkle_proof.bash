#!/usr/bin/env bash

function request_merkle_proof(){
    local curr_deposit_cnt="$1"
    local curr_network_id="$2"
    local bridge_merkle_proof_url="$3"
    local result_proof_file="$4"
    curl -s "$bridge_merkle_proof_url/merkle-proof?deposit_cnt=$curr_deposit_cnt&net_id=$curr_network_id" | jq '.' > $result_proof_file
    echo "request_merkle_proof: $result_proof_file"
}
