#!/usr/bin/env bats
# bats file_tags=op

setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l2_node_url=${L2_NODE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-cl-1-op-node-op-geth-001 http)"}
    rollup_address=${ROLLUP_ADDRESS:-"0x414e9E227e4b589aF92200508aF5399576530E4e"}
    optimistic_mode_manager_pvk=${OPTIMISTIC_MODE_MANAGER_PVK:-"0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}

    load "../../core/helpers/agglayer-certificates-checks.bash"
    agglayer_certificates_checks_setup
}

# Helper function to manage bridge spammer service
manage_bridge_spammer() {
    local action="$1"  # start or stop
    local service="bridge-spammer-001"

    if [[ "$action" == "stop" ]]; then
        if docker ps | grep -q "$service"; then
            echo "Stopping $service..." >&3
            kurtosis service stop "$kurtosis_enclave_name" "$service" || {
                echo "Error: Failed to stop $service" >&3
                return 1
            }
            echo "$service stopped." >&3
        else
            echo "$service does not exist in enclave $kurtosis_enclave_name. Skipping stop operation." >&3
        fi
    elif [[ "$action" == "start" ]]; then
        echo "Starting $service..." >&3
        kurtosis service start "$kurtosis_enclave_name" "$service" || {
            echo "Error: Failed to start $service" >&3
            return 1
        }
        echo "$service started." >&3
    fi
}

# Helper function to toggle optimistic mode
toggle_optimistic_mode() {
    local enabled=$1  # true or false

    local method="enableOptimisticMode"
    [[ "$enabled" == "false" ]] && method="disableOptimisticMode"

    echo "Executing $method..." >&3
    cast send "$rollup_address" "$method()" --rpc-url "$l1_rpc_url" --private-key "$optimistic_mode_manager_pvk" >&3

    local result
    result=$(cast call "$rollup_address" "optimisticMode()(bool)" --rpc-url "$l1_rpc_url")
    if [[ "$result" == "$enabled" ]]; then
        echo "Success: optimisticMode() returned $enabled" >&3
    else
        echo "Error: optimisticMode() did not return $enabled, got $result" >&3
        return 1
    fi
}

# Helper function for initial certificate checks
ensure_non_null_cert() {
    if check_for_null_cert >&3; then
        if ! check_for_latest_settled_cert >&3; then
            wait_for_non_null_cert >&3
        fi
    else
        wait_for_non_null_cert >&3
    fi
}

# Helper function to check network is using optimisticMode compatible FEP consensus
check_fep_consensus_version() {
    contract_version=$(cast call --rpc-url "$l1_rpc_url" "$rollup_address" "version()(string)")
    if [[ -z $contract_version ]]; then
        echo "It seems like the rollup network is not using FEP consensus contract..." >&3
        return 1
    else
        echo "FEP contract on version: $contract_version" >&3
    fi
}

@test "Enable OptimisticMode" {
    check_fep_consensus_version

    ensure_non_null_cert
    manage_bridge_spammer "stop"
    print_settlement_info >&3
    wait_for_null_cert >&3

    echo "Checking last settled certificate" >&3
    latest_settled_l2_block=$(cast rpc --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata' | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
    echo "Latest settled L2 block: $latest_settled_l2_block" >&3

    cast rpc --rpc-url "$l2_node_url" admin_stopSequencer >stop.out
    kurtosis service stop "$kurtosis_enclave_name" aggkit-001 >&3

    toggle_optimistic_mode "true"

    # Restart sequencer with the same configuration used to stop it
    cast rpc --rpc-url "$l2_node_url" admin_startSequencer "$(cat stop.out)" >&3
    kurtosis service start "$kurtosis_enclave_name" aggkit-001 >&3
    manage_bridge_spammer "start"
}

@test "Disable OptimisticMode" {
    ensure_non_null_cert
    manage_bridge_spammer "stop"
    print_settlement_info >&3
    wait_for_null_cert >&3

    kurtosis service stop "$kurtosis_enclave_name" aggkit-001 >&3

    toggle_optimistic_mode "false"

    manage_bridge_spammer "start"
    kurtosis service start "$kurtosis_enclave_name" aggkit-001 >&3

    check_block_increase >&3
    print_settlement_info >&3

    wait_for_null_cert >&3
    print_settlement_info >&3
}