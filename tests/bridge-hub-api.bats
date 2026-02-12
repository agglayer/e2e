#!/usr/bin/env bats
# bats file_tags=bridge-hub-api

setup() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../core/helpers/common.bash"
    _setup_vars

    network_name="devnet"
    bridge_hub_api=$(kurtosis port print "$kurtosis_enclave_name" bridge-hub-api http)
}

# bats test_tags=bridge-hub-api
@test "bridge transaction is indexed and autoclaimed on L2" {
    echo "Bridge funds from L1 to L2"
    deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')
    bridge_amount=$(cast to-wei 0.1)
    output=$(polycli ulxly bridge asset \
        --bridge-address "$l1_bridge_addr" \
        --destination-address "$l2_eth_address" \
        --destination-network "$l2_network_id" \
        --private-key "$l1_private_key" \
        --rpc-url "$l1_rpc_url" \
        --value "$bridge_amount" \
        --gas-limit 500000 \
        --pretty-logs=false 2>&1)
    echo "$output"

    # Parse JSON output to extract tx hash (from the line that contains txHash field).
    tx_hash=$(echo "$output" | jq -r 'select(.txHash != null) | .txHash')
    echo "Transaction hash: $tx_hash"

    echo "Wait for the bridge to be indexed by the consumer"
    data={}
    max_attempts=10
    attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        echo "Check $attempt/$max_attempts..."
        response=$(curl -s "$bridge_hub_api/$network_name/transactions/0/$deposit_count")
        data=$(echo "$response" | jq -r '.data')

        if [[ "$data" != "null" ]] && [[ -n "$data" ]]; then
            echo "Bridge indexed"
            echo "$response" | jq
            break
        fi

        attempt=$((attempt + 1))
        if [[ $attempt -le $max_attempts ]]; then
            sleep 2
        else
            echo "ERROR: Bridge data not indexed after $max_attempts seconds"
            return 1
        fi
    done

    # Validate indexed data
    api_tx_hash=$(echo "$data" | jq -r '.transactionHash')
    if [[ "$api_tx_hash" != "$tx_hash" ]]; then
        echo "ERROR: Transaction hashes don't match"
        echo "Expected: $tx_hash"
        echo "Got: $api_tx_hash"
        return 1
    fi
    echo "Transaction hashes match"

    echo "Wait for the bridge to be claimed by the autoclaimer"
    max_attempts=50
    attempt=1
    status=""
    while [[ $attempt -le $max_attempts ]]; do
        echo "Check $attempt/$max_attempts..."
        response=$(curl -s "$bridge_hub_api/$network_name/transactions/0/$deposit_count")
        status=$(echo "$response" | jq -r '.data.status')

        if [[ "$status" == "CLAIMED" ]]; then
            echo "Bridge claimed"
            echo "$response" | jq
            break
        fi

        echo "Current status: $status"
        attempt=$((attempt + 1))
        if [[ $attempt -le $max_attempts ]]; then
            sleep 2
        else
            echo "ERROR: Bridge was not claimed after $((max_attempts * 2)) seconds"
            echo "Final status: $status"
            return 1
        fi
    done
}

# bats test_tags=bridge-hub-api
@test "bridge transaction is indexed and autoclaimed on L1" {
    echo "Bridge funds from L2 to L1"
    deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')
    bridge_amount=$(cast to-wei 0.05)
    output=$(polycli ulxly bridge asset \
        --bridge-address "$l2_bridge_addr" \
        --destination-address "$l1_eth_address" \
        --destination-network 0 \
        --private-key "$l2_private_key" \
        --rpc-url "$l2_rpc_url" \
        --value "$bridge_amount" \
        --token-address "$weth_address" \
        --gas-limit 500000 \
        --pretty-logs=false 2>&1)
    echo "$output"

    # Parse JSON output to extract tx hash (from the line that contains txHash field).
    tx_hash=$(echo "$output" | jq -r 'select(.txHash != null) | .txHash')
    echo "Transaction hash: $tx_hash"

    echo "Wait for the bridge to be indexed by the consumer"
    data={}
    max_attempts=10
    attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        echo "Check $attempt/$max_attempts..."
        response=$(curl -s "$bridge_hub_api/$network_name/transactions/$l2_network_id/$deposit_count")
        data=$(echo "$response" | jq -r '.data')

        if [[ "$data" != "null" ]] && [[ -n "$data" ]]; then
            echo "Bridge indexed"
            echo "$response" | jq
            break
        fi

        attempt=$((attempt + 1))
        if [[ $attempt -le $max_attempts ]]; then
            sleep 2
        else
            echo "ERROR: Bridge data not indexed after $max_attempts seconds"
            return 1
        fi
    done

    # Validate indexed data
    api_tx_hash=$(echo "$data" | jq -r '.transactionHash')
    if [[ "$api_tx_hash" != "$tx_hash" ]]; then
        echo "ERROR: Transaction hashes don't match"
        echo "Expected: $tx_hash"
        echo "Got: $api_tx_hash"
        return 1
    fi
    echo "Transaction hashes match"

    echo "Wait for the bridge to be claimed by the autoclaimer"
    max_attempts=50
    attempt=1
    status=""
    while [[ $attempt -le $max_attempts ]]; do
        echo "Check $attempt/$max_attempts..."
        response=$(curl -s "$bridge_hub_api/$network_name/transactions/$l2_network_id/$deposit_count")
        status=$(echo "$response" | jq -r '.data.status')

        if [[ "$status" == "CLAIMED" ]]; then
            echo "Bridge claimed"
            echo "$response" | jq
            break
        fi

        echo "Current status: $status"
        attempt=$((attempt + 1))
        if [[ $attempt -le $max_attempts ]]; then
            sleep 2
        else
            echo "ERROR: Bridge was not claimed after $((max_attempts * 2)) seconds"
            echo "Final status: $status"
            return 1
        fi
    done
}
