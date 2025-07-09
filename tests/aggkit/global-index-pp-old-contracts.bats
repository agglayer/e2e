setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

# Function to get certificate height
get_certificate_height() {
    local aggkit_rpc_url=$1
    height=$(curl -X POST "$aggkit_rpc_url" -H "Content-Type: application/json" -d '{"method":"aggsender_getCertificateHeaderPerHeight", "params":[], "id":1}' | tail -n 1 | jq -r '.result.Header.Height')
    echo "$height"
    return 0
}

# Function to check certificate height with retry logic
check_certificate_height() {
    local expected_height=$1
    local enable_retry=${2:-false}
    local max_retries=${3:-10}
    local retry_delay=${4:-5}

    echo "=== Getting certificate height (expected: $expected_height, retry: $enable_retry) ===" >&3
    # With retry logic
    local retry_count=0
    local height=0

    while [ $retry_count -lt $max_retries ]; do
        height=$(curl -X POST "$aggkit_rpc_url" -H "Content-Type: application/json" -d '{"method":"aggsender_getCertificateHeaderPerHeight", "params":[], "id":1}' | tail -n 1 | jq -r '.result.Header.Height')
        echo "Certificate height: $height" >&3

        if [ "$height" -eq "$expected_height" ]; then
            echo "Certificate height: $height" >&3
            return 0
        fi

        sleep $retry_delay
        retry_count=$((retry_count + 1))
    done
}

@test "Global Index PP old contracts: " {
    echo "----------- Test mainnet flag 1, unused bits != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "true"
    assert_success
    local global_index_1=$output
    echo "Global index: $global_index_1" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_1 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_1

    echo "----------- Test mainnet flag 1, rollup id != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l1_rpc_network_id" "$bridge_tx_hash" "$l2_rpc_network_id" "$l2_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "false" "true"
    assert_success
    local global_index_2=$output
    echo "Global index: $global_index_2" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_2 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_2

    run get_certificate_height $aggkit_rpc_url
    local height=$(echo "$output" | tail -n 1)
    echo "Certificate height: $height" >&3

    echo "----------- Test mainnet flag 0, unused bits != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l1_rpc_network_id
    run bridge_asset "$native_token_addr" "$L2_RPC_URL" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run process_bridge_claim "$l2_rpc_network_id" "$bridge_tx_hash" "$l1_rpc_network_id" "$l1_bridge_addr" "$aggkit_bridge_url" "$aggkit_bridge_url" "$l1_rpc_url" "false" "true"
    assert_success

    check_certificate_height "$((height + 1))" "true"
    assert_success
}
