#!/bin/bash
set -euo pipefail

function add_network_to_agglayer() {
    local network_id=$1
    local rpc_url=$2

    echo "=== Checking if network $network_id is added to agglayer ===" >&3
    local _prev=$(kurtosis service exec $ENCLAVE agglayer "grep \"$network_id = \" /etc/zkevm/agglayer-config.toml || true" | kurtosis_filer_exec_method)
    if [ ! -z "$_prev" ]; then
        echo "Network $network_id is already added to agglayer" >&3
        return
    fi
    echo "=== Adding network $network_id to agglayer ===" >&3
    # Extract hostname from the RPC URL
    local rpc_host=$(echo "$rpc_url" | sed -E 's|^https?://([^:]+).*|\1|')
    kurtosis service exec $ENCLAVE agglayer "sed -i 's/\[proof\-signers\]/$network_id = \"http:\/\/$rpc_host:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
    kurtosis service stop $ENCLAVE agglayer
    kurtosis service start $ENCLAVE agglayer
}

function fund_claim_tx_manager() {
    local number_of_chains=$1

    echo "=== Funding bridge auto-claim  ===" >&3
    cast send --legacy --value 100ether --rpc-url $l2_pp1_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
    cast send --legacy --value 100ether --rpc-url $l2_pp2_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
    if [ $number_of_chains -eq 3 ]; then
        cast send --legacy --value 100ether --rpc-url $l2_pp3_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
    fi
}
