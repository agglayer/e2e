#!/usr/bin/env bash

_common_multi_setup() {
    # generated with cast wallet new
    readonly target_address=0xbecE3a31343c6019CDE0D5a4dF2AF8Df17ebcB0f
    readonly target_private_key=0x51caa196504216b1730280feb63ddd8c5ae194d13e57e58d559f1f1dc3eda7c9
    readonly private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
    readonly eth_address=$(cast wallet address --private-key $private_key)
    readonly l2_pp1_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-001 rpc)
    readonly l2_pp2_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-002 rpc)
    local combined_json_file="/opt/zkevm/combined-001.json"
    combined_json_output=$($CONTRACTS_SERVICE_WRAPPER "cat $combined_json_file")
    bridge_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVMBridgeAddress)
    pol_address=$(echo "$combined_json_output" | jq -r .polTokenAddress)
    readonly aggkit_pp1_node_url=$(kurtosis port print $ENCLAVE cdk-node-001 rpc)
    readonly aggkit_pp2_node_url=$(kurtosis port print $ENCLAVE cdk-node-002 rpc)
    readonly l2_pp1_network_id=$(cast call --rpc-url $l2_pp1_url $bridge_addr 'networkID() (uint32)')
    readonly l2_pp2_network_id=$(cast call --rpc-url $l2_pp2_url $bridge_addr 'networkID() (uint32)')

    echo "=== Bridge address=$bridge_addr ===" >&3
    echo "=== POL address=$pol_address ===" >&3
    if [ -n "$gas_token_addr" ] && [ "$gas_token_addr" != "0x0" ]; then
        echo "=== Gas token address=$gas_token_addr ===" >&3
    fi
    echo "=== L1 network id=$l1_rpc_network_id ===" >&3
    echo "=== L2 PP1 network id=$l2_pp1_network_id ===" >&3
    echo "=== L2 PP2 network id=$l2_pp2_network_id ===" >&3
    echo "=== L1 RPC URL=$l1_rpc_url ===" >&3
    echo "=== L2 PP1 URL=$l2_pp1_url ===" >&3
    echo "=== L2 PP2 URL=$l2_pp2_url ===" >&3
    echo "=== Aggkit PP1 URL=$aggkit_pp1_node_url ===" >&3
    echo "=== Aggkit PP2 URL=$aggkit_pp2_node_url ===" >&3
}
