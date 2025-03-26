setup() {
    load '../../core/helpers/common-setup'

    _common_setup

    local combined_json_file="/opt/zkevm/combined.json"
    combined_json_output=$($CONTRACTS_SERVICE_WRAPPER "cat $combined_json_file" | tail -n +2)
    bridge_addr=$(echo "$combined_json_output" | jq -r .polygonZkEVMBridgeAddress)
    echo "Bridge address=$bridge_addr" >&3
}

@test "Verify certificate settlement" {
    echo "Waiting 10 minutes to get some settle certificate...." >&3

    readonly l2_rpc_network_id=$(cast call --rpc-url $L2_RPC_URL $bridge_addr 'networkID() (uint32)')

    run $PROJECT_ROOT/../scripts/agglayer_certificates_monitor.sh 1 600 $l2_rpc_network_id
    assert_success
}
