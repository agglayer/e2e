#!/usr/bin/env bash

_common_multi_setup() {
    readonly private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
    readonly eth_address=$(cast wallet address --private-key $private_key)
    readonly l2_pp1_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-001 rpc)
    readonly l2_pp2_url=$(kurtosis port print $ENCLAVE cdk-erigon-rpc-002 rpc)
    readonly aggkit_pp1_rpc_url=$(kurtosis port print $ENCLAVE cdk-node-001 rpc)
    readonly l2_pp1_network_id=$(cast call --rpc-url $l2_pp1_url $l1_bridge_addr 'networkID() (uint32)')
    readonly l2_pp2_network_id=$(cast call --rpc-url $l2_pp2_url $l2_bridge_addr 'networkID() (uint32)')

    local fallback_nodes=("aggkit-001" "cdk-node-001")
    local resolved_url=""
    for node in "${fallback_nodes[@]}"; do
        # Need to invoke the command this way, otherwise it would fail the entire test
        # if the node is not running, but this is just a sanity check
        kurtosis service inspect "$ENCLAVE" "$node" || {
            echo "⚠️ Node $node is not running in the "$ENCLAVE" enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node" rest)
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved aggkit bridge url ("$resolved_url") from "$node"" >&3
            break
        fi
    done
    if [ -z "$resolved_url" ]; then
        echo "❌ Failed to resolve aggkit bridge url from all fallback nodes" >&2
        return 1
    fi
    readonly aggkit_bridge_1_url="$resolved_url"

    local fallback_nodes=("aggkit-002" "cdk-node-002")
    local resolved_url=""
    for node in "${fallback_nodes[@]}"; do
        # Need to invoke the command this way, otherwise it would fail the entire test
        # if the node is not running, but this is just a sanity check
        kurtosis service inspect "$ENCLAVE" "$node" || {
            echo "⚠️ Node $node is not running in the "$ENCLAVE" enclave, trying next one..." >&3
            continue
        }

        resolved_url=$(kurtosis port print "$ENCLAVE" "$node" rest)
        if [ -n "$resolved_url" ]; then
            echo "✅ Successfully resolved aggkit node url ("$resolved_url") from "$node"" >&3
            break
        fi
    done
    if [ -z "$resolved_url" ]; then
        echo "❌ Failed to resolve aggkit node url from all fallback nodes" >&2
        return 1
    fi
    readonly aggkit_bridge_2_url="$resolved_url"

    echo "=== L1 network id=$l1_rpc_network_id ===" >&3
    echo "=== L2 PP1 network id=$l2_pp1_network_id ===" >&3
    echo "=== L2 PP2 network id=$l2_pp2_network_id ===" >&3
    echo "=== L1 RPC URL=$l1_rpc_url ===" >&3
    echo "=== L2 PP1 URL=$l2_pp1_url ===" >&3
    echo "=== L2 PP2 URL=$l2_pp2_url ===" >&3
    echo "=== Aggkit Bridge 1 URL=$aggkit_bridge_1_url ===" >&3
    echo "=== Aggkit Bridge 2 URL=$aggkit_bridge_2_url ===" >&3
    echo "=== Aggkit PP1 RPC URL=$aggkit_pp1_rpc_url ===" >&3
}
