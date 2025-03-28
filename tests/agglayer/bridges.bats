#!/usr/bin/env bats

setup() {
    l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"}
    l1_bridge_addr=${L1_BRIDGE_ADDR:-"0x12494fE98D3f67EB0c9e2512a4cd18e703aDe49d"}

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    l2_bridge_addr=${L2_BRIDGE_ADDR:-"0x12494fE98D3f67EB0c9e2512a4cd18e703aDe49d"}

    bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    network_id=$(cast call  --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    claim_wait_duration=${CLAIM_WAIT_DURATION:-"10m"}

    agglayer_rpc_url=${AGGLAYER_RPC_URL:-"$(kurtosis port print cdk agglayer aglr-readrpc)"}

    fund_claim_tx_manager
}

function fund_claim_tx_manager() {
    local balance
    balance=$(cast balance --rpc-url "$l2_rpc_url" "$claimtxmanager_addr")
    if [[ $balance != "0" ]]; then
        return
    fi
    cast send --legacy --value 1ether \
         --rpc-url "$l2_rpc_url" \
         --private-key "$l2_private_key" \
         "$claimtxmanager_addr"
}

# bats file_tags=agglayer

# bats test_tags=smoke,bridge
@test "bridge native ETH from L1 to L2" {
    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    initial_l2_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    bridge_amount=$(cast to-wei 0.1)
    polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount"

    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e
    final_l2_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    if [[ $initial_l2_balance == $final_l2_balance ]]; then
        echo "It looks like the bridge deposit to l2 was not synced correctly. The balance on L2 did not increase."
        exit 1
    fi
}


# bats test_tags=smoke,bridge
@test "bridge native ETH from L2 to L1" {
    initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
    initial_l1_balance=$(cast balance --rpc-url "$l1_rpc_url" "$l1_eth_address")

    bridge_amount=$(cast to-wei 0.05)
    polycli ulxly bridge asset \
            --bridge-address "$l2_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --destination-network 0 \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --value "$bridge_amount"

    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestPendingCertificateHeader "$network_id" > "$tmp_file"

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"

    final_l1_balance=$(cast balance --rpc-url "$l1_rpc_url" "$l1_eth_address")
    if [[ $initial_l1_balance == $final_l1_balance ]]; then
        echo "It looks like the bridge deposit to l1 was not processed. The balance on L1 did not increase."
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getEpochConfiguration on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getEpochConfiguration > "$tmp_file"

    if ! jq -e 'has("epoch_duration")' "$tmp_file" ; then
        echo "the agglayer's epoch configuration response is missing the epoch_duration field"
        exit 1
    fi

    if ! jq -e 'has("genesis_block")' "$tmp_file" ; then
        echo "the agglayer's epoch configuration response is missing the genesis_block field"
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getLatestKnownCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$network_id" > "$tmp_file"

    # Skip the test if for whatever reason there hasn't been a certificate at any point
    if jq -e '. == null' "$tmp_file" ; then
        skip
    fi

    required_fields='["status","certificate_id","certificate_index","epoch_number","height","metadata","network_id","new_local_exit_root","prev_local_exit_root","settlement_tx_hash"]'
    missing_fields=$(jq --argjson fields "$required_fields" '$fields - (. | keys) | .[]' "$tmp_file")

    if [[ -n "$missing_fields" ]]; then
        echo "Missing fields: $missing_fields"
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$network_id" > "$tmp_file"

    # Skip the test if there is no known certificate
    if jq -e '. == null' "$tmp_file" ; then
        skip
    fi

    certificate_id=$(jq -r '.certificate_id' "$tmp_file")
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getCertificateHeader "$certificate_id" > "$tmp_file"

    required_fields='["status","certificate_id","certificate_index","epoch_number","height","metadata","network_id","new_local_exit_root","prev_local_exit_root","settlement_tx_hash"]'
    missing_fields=$(jq --argjson fields "$required_fields" '$fields - (. | keys) | .[]' "$tmp_file")

    if [[ -n "$missing_fields" ]]; then
        echo "Missing fields: $missing_fields"
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getTxStatus on agglayer RPC for latest settled certificate returns done" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$network_id" > "$tmp_file"

    # Skip the test if there is no known certificate
    if jq -e '. == null' "$tmp_file" ; then
        skip
    fi

    certificate_id=$(jq -r '.settlement_tx_hash' "$tmp_file")
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getTxStatus "$certificate_id" > "$tmp_file"

    if [[ $(cat "$tmp_file") != '"done"' ]]; then
        echo "transaction status seems to be incorrect"
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getLatestPendingCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestPendingCertificateHeader "$network_id" > "$tmp_file"

    # Skip the test if there is no pending certificate
    if jq -e '. == null' "$tmp_file" ; then
        skip
    fi

    required_fields='["status","certificate_id","certificate_index","epoch_number","height","metadata","network_id","new_local_exit_root","prev_local_exit_root","settlement_tx_hash"]'
    missing_fields=$(jq --argjson fields "$required_fields" '$fields - (. | keys) | .[]' "$tmp_file")

    if [[ -n "$missing_fields" ]]; then
        echo "Missing fields: $missing_fields"
        exit 1
    fi
}

# bats test_tags=smoke,rpc
@test "query interop_getLatestSettledCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$network_id" > "$tmp_file"

    if jq -e '. == null' "$tmp_file" ; then
        skip
    fi

    required_fields='["status","certificate_id","certificate_index","epoch_number","height","metadata","network_id","new_local_exit_root","prev_local_exit_root","settlement_tx_hash"]'
    missing_fields=$(jq --argjson fields "$required_fields" '$fields - (. | keys) | .[]' "$tmp_file")

    if [[ -n "$missing_fields" ]]; then
        echo "Missing fields: $missing_fields"
        exit 1
    fi
}
