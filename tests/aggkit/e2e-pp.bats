setup() {
    load '../../core/helpers/common-setup'
    _common_setup
}

@test "Verify certificate settlement" {
    echo "Waiting 10 minutes to get some settle certificate...." >&3

    run $PROJECT_ROOT/core/helpers/scripts/agglayer_certificates_monitor.sh 1 600 $l2_rpc_network_id
    assert_success
}
