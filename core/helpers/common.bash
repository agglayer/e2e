#!/bin/bash

function _setup_vars() {

    # These vars are set when calling this function:
    #   l2_rpc_url: Set from L2_RPC_URL or from kurtosis enclave if ENCLAVE_NAME is set
    #   l1_rpc_url: Set from L1_RPC_URL or from kurtosis enclave if ENCLAVE_NAME is set
    #   l2_private_key: Set from L2_PRIVATE_KEY or default value
    #   l1_private_key: Set from L1_PRIVATE_KEY or default value
    #   l1_eth_address: Set from l1_private_key
    #   l2_eth_address: Set from l2_private_key
    #   l2_chain_id: Set from chain id from l2_rpc_url if set
    #   l1_chain_id: Set from chain id from l1_rpc_url if set
    #   l2_type: Set to "op-geth" if the kurtosis enclave has an op-geth L2 node, empty otherwise
    #   l2_node_url: Set to the L2 node URL if using op-geth and ENCLAVE_NAME is set
    #   l1_system_config_addr: Set to the L1SystemConfig address if using op-geth and ENCLAVE_NAME is set
    #   l1_optimism_portal_addr: Set to the L1OptimismPortal address if using op-geth and ENCLAVE_NAME is set and l1_system_config_addr is set and l1_rpc_url is set
    #   kurtosis_enclave_name: Set from ENCLAVE_NAME or default to "cdk"
    #   l1_bridge_addr: Set from L1_BRIDGE_ADDR or from kurtosis enclave if ENCLAVE_NAME is set
    #   l2_bridge_addr: Set from L2_BRIDGE_ADDR or from kurtosis enclave if ENCLAVE_NAME is set
    #   l1_network_id: Set from network id from l1_rpc_url if set
    #   l2_network_id: Set from network id from l2_rpc_url if set


    # Paths for libs, etc
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export BATS_LIB_PATH=$BATS_LIB_PATH:$HERE/lib
    export PROJECT_ROOT=${PROJECT_ROOT:-$HERE/../..}
    echo "ℹ️ PROJECT_ROOT=$PROJECT_ROOT BATS_LIB_PATH=$BATS_LIB_PATH" >&3

    #
    # l2_rpc_url
    #
    if [[ -n "$L2_RPC_URL" ]]; then
        l2_rpc_url="$L2_RPC_URL"
    elif [[ -z "$ENCLAVE_NAME" ]]; then
        # If no L2_RPC_URL and no ENCLAVE_NAME, try to get values from default enclave name "cdk"
        ENCLAVE_NAME="cdk"
    fi

    if [[ -n "$ENCLAVE_NAME" ]]; then
        export kurtosis_enclave_name=$ENCLAVE_NAME
        if kurtosis_l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc 2>/dev/null); then
            l2_type="op-geth"
        elif kurtosis_l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc 2>/dev/null); then
            l2_type="cdk-erigon"
        else
            unset kurtosis_l2_rpc_url
        fi
    fi

    # if we have both l2_rpc_url and kurtosis_l2_rpc_url, check they match, otherwise throw an error
    if [[ -n "$l2_rpc_url" && -n "$kurtosis_l2_rpc_url" ]]; then
        if [[ "$l2_rpc_url" != "$kurtosis_l2_rpc_url" ]]; then
            echo "❌ L2_RPC_URL ($l2_rpc_url) does not match the L2 RPC URL from Kurtosis ($kurtosis_l2_rpc_url). Please omit one of L2_RPC_URL, ENCLAVE_NAME from your environment variables." >&3
            exit 1
        fi
    fi

    if [[ -z "$l2_rpc_url" && -n "$kurtosis_l2_rpc_url" ]]; then
        l2_rpc_url=$kurtosis_l2_rpc_url
    fi

    # if the var is set, export value
    if [[ -n "$l2_rpc_url" ]]; then
        l2_chain_id=$(cast chain-id --rpc-url "$l2_rpc_url" 2>/dev/null || echo "")
        if [[ -n "$L2_CHAIN_ID" && -n "$l2_chain_id" && "$L2_CHAIN_ID" != "$l2_chain_id" ]]; then
            echo "❌ L2_CHAIN_ID ($L2_CHAIN_ID) does not match the chain id from the L2 RPC URL $l2_rpc_url). Please check." >&3
            exit 1
        fi
        echo "ℹ️ l2_rpc_url=$l2_rpc_url l2_chain_id=$l2_chain_id" >&3
        export l2_rpc_url l2_chain_id
    fi


    #
    # l1_rpc_url
    #
    if [[ -n "$L1_RPC_URL" ]]; then
        l1_rpc_url="$L1_RPC_URL"
    fi

    if [[ -n "$kurtosis_enclave_name" ]]; then
        if kurtosis_l1_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc 2>/dev/null); then
            true
        else
            unset kurtosis_l1_rpc_url
        fi
    fi

    # if we have both l1_rpc_url and kurtosis_l1_rpc_url, check they match, otherwise throw an error
    if [[ -n "$l1_rpc_url" && -n "$kurtosis_l1_rpc_url" ]]; then
        if [[ "$l1_rpc_url" != "http://${kurtosis_l1_rpc_url}" ]]; then
            echo "❌ L1_RPC_URL ($l1_rpc_url) does not match the L1 RPC URL from Kurtosis (http://${kurtosis_l1_rpc_url}). Please omit one of L1_RPC_URL, ENCLAVE_NAME from your environment variables." >&3
            exit 1
        fi
    fi

    if [[ -z "$l1_rpc_url" && -n "$kurtosis_l1_rpc_url" ]]; then
        l1_rpc_url="http://${kurtosis_l1_rpc_url}"
    fi

    # if the var is set, export value
    if [[ -n "$l1_rpc_url" ]]; then
        l1_chain_id=$(cast chain-id --rpc-url "$l1_rpc_url" 2>/dev/null || echo "")
        if [[ -n "$L1_CHAIN_ID" && -n "$l1_chain_id" && "$L1_CHAIN_ID" != "$l1_chain_id" ]]; then
            echo "❌ L1_CHAIN_ID ($L1_CHAIN_ID) does not match the chain id from the L1 RPC URL $l1_rpc_url). Please check." >&3
            exit 1
        fi
        echo "ℹ️ l1_rpc_url=$l1_rpc_url l1_chain_id=$l1_chain_id" >&3
        export l1_rpc_url l1_chain_id
    fi


    #
    # default private keys and addresses
    #
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    export l1_private_key l2_private_key l1_eth_address l2_eth_address

    echo "ℹ️ l1_eth_address=$l1_eth_address l1_private_key=$l1_private_key" >&3
    echo "ℹ️ l2_eth_address=$l2_eth_address l2_private_key=$l2_private_key" >&3


    #
    # OP stack specific vars
    #
    if [[ "$l2_type" == "op-geth" && -n "$kurtosis_enclave_name" ]]; then
        l2_node_url=${L2_NODE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-cl-1-op-node-op-geth-001 http)"}
        if [[ -n "$l2_node_url" ]]; then
            run cast rpc --rpc-url "$l2_node_url" optimism_rollupConfig
            if [[ "$status" -eq 0 ]]; then
                l1_system_config_addr=$(echo $output | jq -r '.l1_system_config_address')
                if [[ -n "$l1_system_config_addr" && -n "$l1_rpc_url" ]]; then
                    run cast call "$l1_system_config_addr" "optimismPortal()(address)" --rpc-url "$l1_rpc_url"
                    if [[ "$status" -eq 0 ]]; then
                        l1_optimism_portal_addr=$output
                        if [[ -n "$l1_optimism_portal_addr" ]]; then
                            echo "ℹ️ l2_node_url=$l2_node_url l1_system_config_addr=$l1_system_config_addr l1_optimism_portal_addr=$l1_optimism_portal_addr" >&3
                        fi
                    else
                        echo "ℹ️ l2_node_url=$l2_node_url l1_system_config_addr=$l1_system_config_addr" >&3
                    fi
                else
                    echo "ℹ️ l2_node_url=$l2_node_url" >&3
                fi
            else
                echo "ℹ️ l2_node_url=$l2_node_url" >&3
            fi
        else
            echo "ℹ️ Could not determine L2 node URL" >&3
        fi
    else
        # Not op geth or not kurtosis, so don't set any OP stack specific vars
        true
    fi


    #
    # Kurtosis combined.json
    #
    if [[ -n "$kurtosis_enclave_name" ]]; then
        combined_json_data=$(curl -s $(kurtosis port print $kurtosis_enclave_name contracts-001 http)/opt/zkevm/combined-001.json)
        if [[ -z "$combined_json_data" ]] || ! echo "$combined_json_data" | jq empty >/dev/null 2>&1; then
            unset combined_json_data
        fi
    fi


    #
    # Bridge Addresses
    #
    if [[ -n "$L1_BRIDGE_ADDR" ]]; then
        l1_bridge_addr="$L1_BRIDGE_ADDR"
    fi

    if [[ -n "$L2_BRIDGE_ADDR" ]]; then
        l2_bridge_addr="$L2_BRIDGE_ADDR"
    fi

    if [[ -n "$combined_json_data" ]]; then
        kurtosis_l1_bridge_addr=$(echo "$combined_json_data" | jq -r .polygonZkEVMBridgeAddress)
        kurtosis_l2_bridge_addr=$(echo "$combined_json_data" | jq -r .polygonZkEVML2BridgeAddress)
        if [[ -z "$l1_bridge_addr" ]]; then
                l1_bridge_addr=$kurtosis_l1_bridge_addr
        else
            if [[ "$l1_bridge_addr" != "$kurtosis_l1_bridge_addr" ]]; then
                echo "❌ L1_BRIDGE_ADDR ($l1_bridge_addr) does not match the L1 bridge address from Kurtosis ($kurtosis_l1_bridge_addr). Please check." >&3
                exit 1
            fi
        fi
        if [[ -z "$l2_bridge_addr" ]]; then
            l2_bridge_addr=$kurtosis_l2_bridge_addr
        else
            if [[ "$l2_bridge_addr" != "$kurtosis_l2_bridge_addr" ]]; then
                echo "❌ L2_BRIDGE_ADDR ($l2_bridge_addr) does not match the L2 bridge address from Kurtosis ($kurtosis_l2_bridge_addr). Please check." >&3
                exit 1
            fi
        fi
    fi

    if [[ -n "$l1_bridge_addr" && -n "$l2_bridge_addr" ]]; then
        export l1_bridge_addr l2_bridge_addr
        echo "ℹ️ l1_bridge_addr=$l1_bridge_addr l2_bridge_addr=$l2_bridge_addr" >&3
    elif [[ -n "$l1_bridge_addr" ]]; then
        export l1_bridge_addr
        echo "ℹ️ l1_bridge_addr=$l1_bridge_addr" >&3
    elif [[ -n "$l2_bridge_addr" ]]; then
        export l2_bridge_addr
        echo "ℹ️ l2_bridge_addr=$l2_bridge_addr" >&3
    fi


    #
    # Network IDs
    #
    if [[ -n "$l1_rpc_url" && -n "$l1_bridge_addr" ]]; then
        l1_network_id=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    fi

    if [[ -n "$l2_rpc_url" && -n "$l2_bridge_addr" ]]; then
        l2_network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    fi

    if [[ -n "$l1_network_id" && -n "$l2_network_id" ]]; then
        export l1_network_id l2_network_id
        echo "ℹ️ l1_network_id=$l1_network_id l2_network_id=$l2_network_id" >&3
    elif [[ -n "$l1_network_id" ]]; then
        export l1_network_id
        echo "ℹ️ l1_network_id=$l1_network_id" >&3
    elif [[ -n "$l2_network_id" ]]; then
        export l2_network_id
        echo "ℹ️ l2_network_id=$l2_network_id" >&3
    fi

}
