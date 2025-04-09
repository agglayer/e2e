#!/bin/bash
set -euo pipefail

function add_network2_to_agglayer() {
    echo "=== Checking if network 2 is added to agglayer ===" >&3
    local _prev=$(kurtosis service exec $ENCLAVE agglayer "grep \"2 = \" /etc/zkevm/agglayer-config.toml || true" | tail -n +2)
    if [ ! -z "$_prev" ]; then
        echo "Network 2 is already added to agglayer" >&3
        return
    fi
    echo "=== Adding network 2 to agglayer ===" >&3
    kurtosis service exec $ENCLAVE agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
    kurtosis service stop $ENCLAVE agglayer
    kurtosis service start $ENCLAVE agglayer
}
