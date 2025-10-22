#!/usr/bin/env bats
# bats file_tags=aggkit

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    log_setup_test
    _agglayer_cdk_common_setup
    _set_vars
}

function _set_vars() {
    echo "🔗 Getting admin_private_key and keystore_password values..." >&3
    local contracts_url="$(kurtosis port print $ENCLAVE_NAME $contracts_container http)"

    admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_admin_private_key')"
    export admin_private_key

    keystore_password="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_keystore_password')"
    export keystore_password

    echo "🔍 Finding Docker network for Kurtosis enclave..." >&3
    kurtosis_network=$(docker ps --filter "name=${ENCLAVE_NAME}" --format "table {{.Names}}\t{{.Networks}}" | grep -v NETWORKS | head -1 | awk '{print $2}')
    export kurtosis_network
    echo "Kurtosis network: $kurtosis_network" >&3

    echo "📄 Fetching AggLayer Gateway contract address..." >&3
    agglayer_gateway_address=$(kurtosis service exec $ENCLAVE_NAME $contracts_container "jq -r .aggLayerGatewayAddress /opt/zkevm/combined.json")
    echo "AggLayer Gateway Address: $agglayer_gateway_address" >&3
}

@test "Add single validator to committee" {
    log "📝 Updating signers and threshold on AggLayer Gateway..."
    
    aggsender_validator_004_config_path="${BATS_TEST_DIRNAME}/../../scenarios/attach-new-committee-members/configs-aggsender-validator-004"
    aggsender_validator_004_keystore_path=${aggsender_validator_004_config_path}/aggsendervalidator-4.keystore
    aggsender_validator_004_address=$(cast wallet address --keystore "$aggsender_validator_004_keystore_path" --password "$keystore_password")

    # Query the current threshold and increment by 1
    current_threshold=$(cast call "$agglayer_gateway_address" 'getThreshold() (uint256)' --rpc-url $l1_rpc_url)
    new_threshold=$((current_threshold + 1))

    # Send transaction to update signers and threshold
    run cast send "$agglayer_gateway_address" \
    "updateSignersAndThreshold((address,uint256)[],(address,string)[],uint256)" \
    "[]" \
    "[($aggsender_validator_004_address,\"http://aggkit-001-aggsender-validator-004:5578\")]" \
    "$new_threshold" \
    --rpc-url $l1_rpc_url \
    --private-key $admin_private_key
    assert_success

    # TODO: Verify that the new signer is added
    log "✅ Verifying signers were updated..."
    cast call "$agglayer_gateway_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url"

    log "🐳 Starting additional AggSender Validator container..."
    docker run -d --name aggkit-001-aggsender-validator-004 \
    --network "$kurtosis_network" \
    -v "${aggsender_validator_004_config_path}:/etc/aggkit" \
    -p 5576 \
    -p 5578 \
    -p 6060 \
    aggkit:local \
    run --cfg=/etc/aggkit/config.toml --components=aggsender-validator
}
