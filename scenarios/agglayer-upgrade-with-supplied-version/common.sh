#!/usr/bin/env bash
# common.sh — standalone version of common.bash (no Bats).
# Usage:
#   source ./common.sh && _setup_vars     # to use from another script
#   ./common.sh                            # to run once and print vars

set -euo pipefail

# Quiet shellcheck about variables we set later
# shellcheck disable=SC2034
declare status output || true

log() { echo "[$(date -Is)] $*" >&2; }

function _setup_vars() {
    # These vars are set when calling this function:
    #   l2_rpc_url, l1_rpc_url, l2_private_key, l1_private_key,
    #   l1_eth_address, l2_eth_address, l2_chain_id, l1_chain_id,
    #   l2_type, l2_node_url, l1_system_config_addr, l1_optimism_portal_addr,
    #   kurtosis_enclave_name, l1_bridge_addr, l2_bridge_addr,
    #   l1_network_id, l2_network_id

    #
    # Paths for libs, etc
    #
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


    # Keep this for compatibility; harmless if Bats isn't used.
    export BATS_LIB_PATH="${BATS_LIB_PATH:-}:$HERE/lib"
    export PROJECT_ROOT="${PROJECT_ROOT:-$HERE/../..}"
    log "PROJECT_ROOT=$PROJECT_ROOT BATS_LIB_PATH=$BATS_LIB_PATH"

    #
    # L2 RPC URL
    #
    l2_rpc_url="${L2_RPC_URL:-}"
    if [[ -z "${ENCLAVE_NAME:-}" && -z "$l2_rpc_url" ]]; then
        # If no L2_RPC_URL and no ENCLAVE_NAME, try default enclave "cdk"
        ENCLAVE_NAME="cdk"
    fi

    if [[ -n "${ENCLAVE_NAME:-}" ]]; then
        export kurtosis_enclave_name="$ENCLAVE_NAME"
        if kurtosis_l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc 2>/dev/null)"; then
            l2_type="op-geth"
        elif kurtosis_l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc 2>/dev/null)"; then
            l2_type="cdk-erigon"
        else
            unset kurtosis_l2_rpc_url
        fi
    fi

    # If both are set, enforce they match
    if [[ -n "${l2_rpc_url:-}" && -n "${kurtosis_l2_rpc_url:-}" && "$l2_rpc_url" != "$kurtosis_l2_rpc_url" ]]; then
        log "L2_RPC_URL ($l2_rpc_url) != Kurtosis L2 RPC ($kurtosis_l2_rpc_url). Omit one of L2_RPC_URL or ENCLAVE_NAME."
        exit 1
    fi
    if [[ -z "${l2_rpc_url:-}" && -n "${kurtosis_l2_rpc_url:-}" ]]; then
        l2_rpc_url="$kurtosis_l2_rpc_url"
    fi

    if [[ -n "${l2_rpc_url:-}" ]]; then
        l2_chain_id="$(cast chain-id --rpc-url "$l2_rpc_url" 2>/dev/null || echo "")"
        if [[ -n "${L2_CHAIN_ID:-}" && -n "$l2_chain_id" && "$L2_CHAIN_ID" != "$l2_chain_id" ]]; then
            log "L2_CHAIN_ID ($L2_CHAIN_ID) != chain id from $l2_rpc_url ($l2_chain_id)."
            exit 1
        fi
        log "l2_rpc_url=$l2_rpc_url l2_chain_id=$l2_chain_id"
        export l2_rpc_url l2_chain_id
    fi

    #
    # L1 RPC URL
    #
    l1_rpc_url="${L1_RPC_URL:-}"

    if [[ -n "${kurtosis_enclave_name:-}" ]]; then
        if kurtosis_l1_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc 2>/dev/null)"; then
            true
        else
            unset kurtosis_l1_rpc_url
        fi
    fi

    # Enforce match if both are set (note: Kurtosis returns host:port)
    if [[ -n "${l1_rpc_url:-}" && -n "${kurtosis_l1_rpc_url:-}" && "$l1_rpc_url" != "http://${kurtosis_l1_rpc_url}" ]]; then
        log "L1_RPC_URL ($l1_rpc_url) != Kurtosis L1 RPC (http://${kurtosis_l1_rpc_url}). Omit one of L1_RPC_URL or ENCLAVE_NAME."
        exit 1
    fi
    if [[ -z "${l1_rpc_url:-}" && -n "${kurtosis_l1_rpc_url:-}" ]]; then
        l1_rpc_url="http://${kurtosis_l1_rpc_url}"
    fi

    if [[ -n "${l1_rpc_url:-}" ]]; then
        l1_chain_id="$(cast chain-id --rpc-url "$l1_rpc_url" 2>/dev/null || echo "")"
        if [[ -n "${L1_CHAIN_ID:-}" && -n "$l1_chain_id" && "$L1_CHAIN_ID" != "$l1_chain_id" ]]; then
            log "L1_CHAIN_ID ($L1_CHAIN_ID) != chain id from $l1_rpc_url ($l1_chain_id)."
            exit 1
        fi
        log "l1_rpc_url=$l1_rpc_url l1_chain_id=$l1_chain_id"
        export l1_rpc_url l1_chain_id
    fi

    #
    # Default private keys & addresses (TEST ONLY)
    #
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_eth_address="$(cast wallet address --private-key "$l1_private_key")"
    l2_eth_address="$(cast wallet address --private-key "$l2_private_key")"
    export l1_private_key l2_private_key l1_eth_address l2_eth_address
    log "l1_eth_address=$l1_eth_address l1_private_key=$l1_private_key"
    log "l2_eth_address=$l2_eth_address l2_private_key=$l2_private_key"

    #
    # OP Stack–specific vars (only if op-geth + Kurtosis)
    #
    if [[ "${l2_type:-}" == "op-geth" && -n "${kurtosis_enclave_name:-}" ]]; then
        l2_node_url="${L2_NODE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-cl-1-op-node-op-geth-001 http 2>/dev/null || true)"}"
        if [[ -n "${l2_node_url:-}" ]]; then
            if output="$(cast rpc --rpc-url "$l2_node_url" optimism_rollupConfig 2>/dev/null)"; then
                l1_system_config_addr="$(echo "$output" | jq -r '.l1_system_config_address')"
                if [[ -n "$l1_system_config_addr" && -n "${l1_rpc_url:-}" ]]; then
                    if l1_optimism_portal_addr="$(cast call "$l1_system_config_addr" "optimismPortal()(address)" --rpc-url "$l1_rpc_url" 2>/dev/null)"; then
                        export l1_optimism_portal_addr
                        log "l2_node_url=$l2_node_url l1_system_config_addr=$l1_system_config_addr l1_optimism_portal_addr=$l1_optimism_portal_addr"
                    else
                        log "l2_node_url=$l2_node_url l1_system_config_addr=$l1_system_config_addr"
                    fi
                else
                    log "l2_node_url=$l2_node_url"
                fi
            else
                log "l2_node_url=$l2_node_url"
            fi
        else
            log "Could not determine L2 node URL"
        fi
    fi

    #
    # Kurtosis combined.json (for bridge addresses)
    #
    if [[ -n "${kurtosis_enclave_name:-}" ]]; then
        combined_url="$(kurtosis port print "$kurtosis_enclave_name" contracts-001 http 2>/dev/null || true)"
        combined_json_data=""
        if [[ -n "$combined_url" ]]; then
            combined_json_data="$(curl -s "$combined_url/opt/zkevm/combined-001.json" || true)"
        fi
        if [[ -z "${combined_json_data:-}" ]] || ! echo "$combined_json_data" | jq empty >/dev/null 2>&1; then
            unset combined_json_data
        fi
    fi

    #
    # Bridge addresses (env overrides, else from combined.json)
    #
    l1_bridge_addr="${L1_BRIDGE_ADDR:-}"
    l2_bridge_addr="${L2_BRIDGE_ADDR:-}"

    if [[ -n "${combined_json_data:-}" ]]; then
        kurtosis_l1_bridge_addr="$(echo "$combined_json_data" | jq -r .polygonZkEVMBridgeAddress)"
        kurtosis_l2_bridge_addr="$(echo "$combined_json_data" | jq -r .polygonZkEVML2BridgeAddress)"

        if [[ -z "$l1_bridge_addr" ]]; then
            l1_bridge_addr="$kurtosis_l1_bridge_addr"
        elif [[ "$l1_bridge_addr" != "$kurtosis_l1_bridge_addr" ]]; then
            log "L1_BRIDGE_ADDR ($l1_bridge_addr) != Kurtosis ($kurtosis_l1_bridge_addr)."
            exit 1
        fi

        if [[ -z "$l2_bridge_addr" ]]; then
            l2_bridge_addr="$kurtosis_l2_bridge_addr"
        elif [[ "$l2_bridge_addr" != "$kurtosis_l2_bridge_addr" ]]; then
            log "L2_BRIDGE_ADDR ($l2_bridge_addr) != Kurtosis ($kurtosis_l2_bridge_addr)."
            exit 1
        fi
    fi

    if [[ -n "${l1_bridge_addr:-}" && -n "${l2_bridge_addr:-}" ]]; then
        export l1_bridge_addr l2_bridge_addr
        log "l1_bridge_addr=$l1_bridge_addr l2_bridge_addr=$l2_bridge_addr"
    elif [[ -n "${l1_bridge_addr:-}" ]]; then
        export l1_bridge_addr
        log "l1_bridge_addr=$l1_bridge_addr"
    elif [[ -n "${l2_bridge_addr:-}" ]]; then
        export l2_bridge_addr
        log "l2_bridge_addr=$l2_bridge_addr"
    fi

    #
    # Network IDs (via bridge contracts)
    #
    if [[ -n "${l1_rpc_url:-}" && -n "${l1_bridge_addr:-}" ]]; then
        l1_network_id="$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')"
    fi
    if [[ -n "${l2_rpc_url:-}" && -n "${l2_bridge_addr:-}" ]]; then
        l2_network_id="$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')"
    fi

    if [[ -n "${l1_network_id:-}" && -n "${l2_network_id:-}" ]]; then
        export l1_network_id l2_network_id
        log "l1_network_id=$l1_network_id l2_network_id=$l2_network_id"
    elif [[ -n "${l1_network_id:-}" ]]; then
        export l1_network_id
        log "l1_network_id=$l1_network_id"
    elif [[ -n "${l2_network_id:-}" ]]; then
        export l2_network_id
        log "l2_network_id=$l2_network_id"
    fi
}

# If executed directly, run setup and print a concise summary
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _setup_vars
    echo
    echo "=== common.sh initialized ==="
    echo "PROJECT_ROOT=$PROJECT_ROOT"
    echo "l1_rpc_url=${l1_rpc_url:-}"
    echo "l2_rpc_url=${l2_rpc_url:-}"
    echo "l1_chain_id=${l1_chain_id:-}"
    echo "l2_chain_id=${l2_chain_id:-}"
    echo "l1_eth_address=${l1_eth_address:-}"
    echo "l2_eth_address=${l2_eth_address:-}"
    echo "l1_bridge_addr=${l1_bridge_addr:-}"
    echo "l2_bridge_addr=${l2_bridge_addr:-}"
    echo "l1_network_id=${l1_network_id:-}"
    echo "l2_network_id=${l2_network_id:-}"
    echo "l2_type=${l2_type:-}"
    echo "l2_node_url=${l2_node_url:-}"
    echo "l1_system_config_addr=${l1_system_config_addr:-}"
    echo "l1_optimism_portal_addr=${l1_optimism_portal_addr:-}"
    echo "l1_private_key=${l1_private_key:-}"
    echo "l2_private_key=${l2_private_key:-}"
fi






