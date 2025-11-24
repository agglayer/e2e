#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    log_setup_test
    _agglayer_cdk_common_setup
    _set_vars
    timeout=${TIMEOUT:-3000}
    retry_interval=${RETRY_INTERVAL:-15}
    load "${BATS_TEST_DIRNAME}/../../core/helpers/agglayer-certificates-checks.bash"
}

teardown_file() {
    echo "🧹 Cleaning up Docker containers..." >&3
    # Stop and remove the additional validator container if it exists
    if docker ps -a --format "table {{.Names}}" | grep -q "aggkit-001-aggsender-validator-004"; then
        docker stop aggkit-001-aggsender-validator-004 2>/dev/null || true
        docker rm aggkit-001-aggsender-validator-004 2>/dev/null || true
        echo "✅ Removed aggkit-001-aggsender-validator-004 container" >&3
    fi
}

function _set_vars() {
    export kurtosis_enclave_name=${ENCLAVE_NAME:-"aggkit"}

    echo "🔗 Getting admin_private_key value..." >&3
    contracts_url="$(kurtosis port print $ENCLAVE_NAME $contracts_container http)"

    admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_sovereignadmin_private_key')"
    export admin_private_key

    log "🔍 Finding Docker network for Kurtosis enclave..." >&3
    kurtosis_network=$(
        docker ps \
            --filter "name=${ENCLAVE_NAME}" \
            --format "table {{.Names}}\t{{.Networks}}" |
        grep -v NETWORKS |
        head -1 |
        awk '{print $2}'
    )
    export kurtosis_network
    echo "Kurtosis network: $kurtosis_network" >&3

    echo "📄 Fetching Rollup contract address..." >&3
    rollup_address=$(kurtosis service exec $ENCLAVE_NAME $contracts_container "jq -r .rollupAddress /opt/zkevm/combined.json")
    echo "Rollup Address: $rollup_address" >&3

    echo "📄 Fetching AggSender Validator 004 address..." >&3
    aggsender_validator_004_config_path="${BATS_TEST_DIRNAME}/../../scenarios/attach-new-committee-members/configs-aggsender-validator-004"
    aggsender_validator_004_keystore_path=${aggsender_validator_004_config_path}/aggsendervalidator-4.keystore
    aggsender_validator_004_address=$(cast wallet address --private-key "$admin_private_key")
    export aggsender_validator_004_address
    echo "AggSender Validator 004 Address: $aggsender_validator_004_address" >&3
}

function update_signers_and_threshold() {
    local signers_to_remove="$1"
    local signers_to_add="$2"
    local new_threshold="$3"
    
    log "📝 Updating signers and threshold on Rollup..."
    
    # Send transaction to update signers and threshold
    run cast send "$rollup_address" \
    "updateSignersAndThreshold((address,uint256)[],(address,string)[],uint256)" \
    "$signers_to_remove" \
    "$signers_to_add" \
    "$new_threshold" \
    --rpc-url $l1_rpc_url \
    --private-key $admin_private_key
    assert_success
    
    log "✅ Transaction sent to update signers and threshold."
}

function get_current_threshold() {
    local threshold
    threshold=$(cast call "$rollup_address" 'getThreshold() (uint256)' --rpc-url $l1_rpc_url)
    echo "$threshold"
}

function verify_threshold_updated() {
    local expected_threshold="$1"
    local updated_threshold
    
    log "🔍 Verifying threshold was updated..."
    updated_threshold=$(get_current_threshold)
    if [[ "$updated_threshold" -ne "$expected_threshold" ]]; then
        echo "Error: Threshold not updated correctly. Expected $expected_threshold, got $updated_threshold." >&3
        return 1
    fi
    log "✅ Threshold updated successfully to $updated_threshold."
}

function verify_is_in_signers_list() {
    local signers="$1"
    local address="$2"
    
    if [[ "$signers" != *"$address"* ]]; then
        echo "Error: Signer $address not found in signers list." >&3
        return 1
    fi
    log "✅ Signer $address found in signers list."
}

@test "Add single validator to committee" {
    # Lets wait for the old committee to settle at least one certificate first
    ensure_non_null_cert >&3

    # Query the current threshold and increment by 1
    current_threshold=$(get_current_threshold)
    new_threshold=$((current_threshold + 1))

    # Update signers and threshold using the new function
    update_signers_and_threshold "[]" "[($aggsender_validator_004_address,\"http://aggkit-001-aggsender-validator-004:5578\")]" "$new_threshold"

    # Verify that the new signer is added
    log "🔍 Verifying signers were updated..."
    signers=$(cast call "$rollup_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url")
    run verify_is_in_signers_list "$signers" "$aggsender_validator_004_address"
    assert_success
    log "✅ Signers updated successfully: $signers"

    # Verify that the threshold is updated
    run verify_threshold_updated "$new_threshold"
    assert_success

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
    wait_for_null_cert >&3 # wait so that we do not have a pending certificate
    check_height_increase >&3 # check that new certificate is sent with new committee
    wait_for_null_cert >&3 # wait for the new certificate to be settled
    log "✅ New validator successfully added to committee and certificates are settling."
}

@test "Remove single validator from committee" {
    # Query the current threshold and decrement by 1
    current_threshold=$(get_current_threshold)
    new_threshold=$((current_threshold - 1))

    # Get current signers and find aggsender_validator_004_address
    signers=$(cast call "$rollup_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url")
    run verify_is_in_signers_list "$signers" "$aggsender_validator_004_address"
    assert_success
    
    # Calculate the correct array index by counting parentheses before our address
    # The format is [(addr1, url1), (addr2, url2), ...] so we count opening parentheses before our address
    signers_before_target=$(echo "$signers" | sed "s/$aggsender_validator_004_address.*//" | grep -o '(' | wc -l)
    aggsender_validator_004_index=$((signers_before_target - 1))

    # Update signers and threshold using the new function by removing the validator
    update_signers_and_threshold "[($aggsender_validator_004_address, $aggsender_validator_004_index)]" "[]" "$new_threshold"

    # Verify that the signer is removed
    log "🔍 Verifying signers were updated..."
    signers=$(cast call "$rollup_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url")
    if [[ "$signers" == *"$aggsender_validator_004_address"* ]]; then
        echo "Error: Signer $aggsender_validator_004_address still found in signers list." >&3
        return 1
    fi
    log "✅ Signers updated successfully: $signers"

    # Verify that the threshold is updated
    run verify_threshold_updated "$new_threshold"
    assert_success

    log "⏱️ Waiting for certificates to settle after removing committee member..."
    wait_for_null_cert >&3 # wait so that we do not have a pending certificate
    check_height_increase >&3 # check that new certificate is sent with new committee
    wait_for_null_cert >&3 # wait for the new certificate to be settled
    log "✅ Validator successfully removed from committee and certificates are settling."
}
