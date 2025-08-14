#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

get_certificate_height() {
    local aggkit_rpc_url=$1
    height=$(curl -X POST "$aggkit_rpc_url" -H "Content-Type: application/json" -d '{"method":"aggsender_getCertificateHeaderPerHeight", "params":[], "id":1}' | tail -n 1 | jq -r '.result.Header.Height')
    echo "$height"
    return 0
}

check_certificate_height() {
    local expected_height=$1
    local max_retries=${2:-10}
    local retry_delay=${3:-5}

    echo "=== Getting certificate height (expected: $expected_height, retry: $max_retries) ===" >&3
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

    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 100 5 "$aggkit_bridge_url" "$sender_addr"
    assert_success
    local bridge="$output"

    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 100 5 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"

    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index" 100 5 "$aggkit_bridge_url"
    assert_success
    local injected_info="$output"

    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 3 "$aggkit_bridge_url"
    assert_success
    local proof="$output"

    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 3 "$l1_rpc_network_id" "$l2_bridge_addr" "true"
    assert_success
    local global_index_1="$output"
    echo "Global index: $global_index_1" >&3

    echo "=== Waiting for settled certificate with imported bridge for global_index: $global_index_1 (L2 network: $aggkit_rpc_url)"
    wait_to_settled_certificate_containing_global_index $aggkit_rpc_url $global_index_1

    echo "----------- Test mainnet flag 1, rollup id != 0 -----------" >&3

    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    run get_bridge "$l1_rpc_network_id" "$bridge_tx_hash" 100 5 "$aggkit_bridge_url" "$sender_addr"
    assert_success
    local bridge="$output"

    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l1_rpc_network_id" "$deposit_count" 100 5 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"

    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index" 100 5 "$aggkit_bridge_url"
    assert_success
    local injected_info="$output"

    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l1_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 3 "$aggkit_bridge_url"
    assert_success
    local proof="$output"

    run claim_bridge "$bridge" "$proof" "$L2_RPC_URL" 10 3 "$l1_rpc_network_id" "$l2_bridge_addr" "false" "true"
    assert_success
    local global_index_2="$output"
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

    run get_bridge "$l2_rpc_network_id" "$bridge_tx_hash" 100 5 "$aggkit_bridge_url" "$sender_addr"
    assert_success
    local bridge="$output"

    local deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    run find_l1_info_tree_index_for_bridge "$l2_rpc_network_id" "$deposit_count" 100 5 "$aggkit_bridge_url"
    assert_success
    local l1_info_tree_index="$output"

    run find_injected_l1_info_leaf "$l2_rpc_network_id" "$l1_info_tree_index" 100 5 "$aggkit_bridge_url"
    assert_success
    local injected_info="$output"

    local l1_info_tree_index=$(echo "$injected_info" | jq -r '.l1_info_tree_index')
    run generate_claim_proof "$l2_rpc_network_id" "$deposit_count" "$l1_info_tree_index" 10 3 "$aggkit_bridge_url"
    assert_success
    local proof="$output"

    run claim_bridge "$bridge" "$proof" "$l1_rpc_url" 10 3 "$l2_rpc_network_id" "$l1_bridge_addr" "true"
    assert_success
    local global_index_3="$output"
    echo "Global index: $global_index_3" >&3

    check_certificate_height "$((height + 1))" 10 5
    assert_success
}
