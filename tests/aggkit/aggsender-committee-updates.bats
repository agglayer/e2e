#!/usr/bin/env bats
# bats file_tags=aggkit

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    log_setup_test
    _agglayer_cdk_common_setup
    _set_vars
    
    export kurtosis_enclave_name=${ENCLAVE_NAME:-"aggkit"}
    timeout=${TIMEOUT:-3000}
    retry_interval=${RETRY_INTERVAL:-15}
    load "${BATS_TEST_DIRNAME}/../../core/helpers/agglayer-certificates-checks.bash"
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

    echo "📄 Fetching Rollup contract address..." >&3
    rollup_address=$(kurtosis service exec $ENCLAVE_NAME $contracts_container "jq -r .rollupAddress /opt/zkevm/combined.json")
    echo "Rollup Address: $rollup_address" >&3
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

@test "Add single validator to committee" {
    # Lets wait for the old committee to settle at least one certificate first
    ensure_non_null_cert

    log "📝 Updating signers and threshold on Rollup..."
    
    aggsender_validator_004_config_path="${BATS_TEST_DIRNAME}/../../scenarios/attach-new-committee-members/configs-aggsender-validator-004"
    aggsender_validator_004_keystore_path=${aggsender_validator_004_config_path}/aggsendervalidator-4.keystore
    aggsender_validator_004_address=$(cast wallet address --keystore "$aggsender_validator_004_keystore_path" --password "$keystore_password")

    # Query the current threshold and increment by 1
    current_threshold=$(cast call "$rollup_address" 'getThreshold() (uint256)' --rpc-url $l1_rpc_url)
    new_threshold=$((current_threshold + 1))

    # Send transaction to update signers and threshold
    run cast send "$rollup_address" \
    "updateSignersAndThreshold((address,uint256)[],(address,string)[],uint256)" \
    "[]" \
    "[($aggsender_validator_004_address,\"http://aggkit-001-aggsender-validator-004:5578\")]" \
    "$new_threshold" \
    --rpc-url $l1_rpc_url \
    --private-key $admin_private_key
    assert_success

    # Verify that the new signer is added
    log "✅ Verifying signers were updated..."
    signers=$(cast call "$rollup_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url")
    if [[ "$signers" != *"$aggsender_validator_004_address"* ]]; then
        echo "Error: New signer $aggsender_validator_004_address not found in signers list." >&3
        return 1
    fi
    log "Signers updated successfully: $signers"

    # Verify that the threshold is updated
    updated_threshold=$(cast call "$rollup_address" 'getThreshold() (uint256)' --rpc-url $l1_rpc_url)
    if [[ "$updated_threshold" -ne "$new_threshold" ]]; then
        echo "Error: Threshold not updated correctly. Expected $new_threshold, got $updated_threshold." >&3
        return 1
    fi
    log "Threshold updated successfully to $updated_threshold."

    log "🐳 Starting additional AggSender Validator container..."
    docker run -d --name aggkit-001-aggsender-validator-004 \
    --network "$kurtosis_network" \
    -v "${aggsender_validator_004_config_path}:/etc/aggkit" \
    -p 5576 \
    -p 5578 \
    -p 6060 \
    aggkit:local \
    run --cfg=/etc/aggkit/config.toml --components=aggsender-validator

    log "⏱️ Waiting for certificates to settle with new committee member..."
    wait_for_null_cert >&3
    check_height_increase >&3
    wait_for_null_cert >&3
    log "✅ New validator successfully added to committee and certificates are settling."
}
