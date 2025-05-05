#!/usr/bin/env bash

_common_multi_setup() {
    readonly private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
    readonly eth_address=$(cast wallet address --private-key $private_key)
    readonly l2_pp1_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-001 rpc)
    readonly l2_pp2_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-002 rpc)
    readonly aggkit_pp1_node_url=$(kurtosis port print $ENCLAVE aggkit-001 rpc)
    readonly aggkit_pp2_node_url=$(kurtosis port print $ENCLAVE aggkit-002 rpc)
    readonly l2_pp1_network_id=$(cast call --rpc-url $l2_pp1_url $l1_bridge_addr 'networkID() (uint32)')
    readonly l2_pp2_network_id=$(cast call --rpc-url $l2_pp2_url $l2_bridge_addr 'networkID() (uint32)')

    echo "=== L1 network id=$l1_rpc_network_id ===" >&3
    echo "=== L2 PP1 network id=$l2_pp1_network_id ===" >&3
    echo "=== L2 PP2 network id=$l2_pp2_network_id ===" >&3
    echo "=== L1 RPC URL=$l1_rpc_url ===" >&3
    echo "=== L2 PP1 URL=$l2_pp1_url ===" >&3
    echo "=== L2 PP2 URL=$l2_pp2_url ===" >&3
    echo "=== Aggkit PP1 URL=$aggkit_pp1_node_url ===" >&3
    echo "=== Aggkit PP2 URL=$aggkit_pp2_node_url ===" >&3
}
