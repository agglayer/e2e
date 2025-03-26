#!/usr/bin/env bash

_common_multi_setup() {
    # generated with cast wallet new
    readonly target_address=0xbecE3a31343c6019CDE0D5a4dF2AF8Df17ebcB0f
    readonly target_private_key=0x51caa196504216b1730280feb63ddd8c5ae194d13e57e58d559f1f1dc3eda7c9

    kurtosis service exec $ENCLAVE contracts-001 "cat /opt/zkevm/combined-001.json" | tail -n +2 | jq '.' >combined-001.json
    kurtosis service exec $ENCLAVE contracts-002 "cat /opt/zkevm/combined-002.json" | tail -n +2 | jq '.' >combined-002.json

    readonly private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
    readonly eth_address=$(cast wallet address --private-key $private_key)
    readonly l1_rpc_url=${L1_ETH_RPC_URL:-"$(kurtosis port print $ENCLAVE el-1-geth-lighthouse rpc)"}
    readonly l2_pp1_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-001 rpc)
    readonly l2_pp2_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-002 rpc)
    readonly bridge_addr=$(cat combined-001.json | jq -r .polygonZkEVMBridgeAddress)
    readonly pol_address=$(cat combined-001.json | jq -r .polTokenAddress)
    readonly rollup_params_file=/opt/zkevm/create_rollup_parameters.json
    run bash -c "$CONTRACTS_SERVICE_WRAPPER 'cat $rollup_params_file' | tail -n +2 | jq -r '.gasTokenAddress'"
    assert_success
    readonly gas_token_addr=$output
    readonly aggkit_pp1_node_url=$(kurtosis port print $ENCLAVE cdk-node-001 rpc)
    readonly aggkit_pp2_node_url=$(kurtosis port print $ENCLAVE cdk-node-002 rpc)

    readonly l1_rpc_network_id=$(cast call --rpc-url $l1_rpc_url $bridge_addr 'networkID() (uint32)')
    readonly l2_pp1_network_id=$(cast call --rpc-url $l2_pp1_url $bridge_addr 'networkID() (uint32)')
    readonly l2_pp2_network_id=$(cast call --rpc-url $l2_pp2_url $bridge_addr 'networkID() (uint32)')

    readonly aggsender_find_imported_bridge="../target/aggsender_find_imported_bridge"
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

    rm combined-001.json
    rm combined-002.json
}
