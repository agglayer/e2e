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
