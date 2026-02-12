#!/usr/bin/env bats
# bats file_tags=bridge-hub-api

setup() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../core/helpers/common.bash"
    _setup_vars

    network_name="devnet"
    bridge_hub_api=$(kurtosis port print "$kurtosis_enclave_name" bridge-hub-api http)
    bridge_amount=$(cast to-wei 0.1)
}

bridge_from_l1_to_l2() {
    polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$l2_network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount" \
            --gas-limit 500000
}

# bats test_tags=bridge-hub-api
@test "consumer indexes bridge data" {
    echo "Bridge funds from L1 to L2"
    deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')
    output=$(bridge_from_l1_to_l2 2>&1)
    echo "$output"

    # Strip ANSI color codes and extract tx hash.
    tx_hash=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -oP 'txHash=\K0x[a-fA-F0-9]+')
    echo "Transaction hash: $tx_hash"

    echo "Poll the bridge hub API"
    data={}
    max_attempts=10
    attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        echo "Check $attempt/$max_attempts..."
        response=$(curl -s "$bridge_hub_api/$network_name/transactions/0/$deposit_count")
        data=$(echo "$response" | jq -r '.data')

        if [[ "$data" != "null" ]] && [[ -n "$data" ]]; then
            # Display the response and keep data in variable
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
    if [[ "$api_tx_hash" -ne "$tx_hash" ]]; then
        echo "ERROR: Transaction hashes don't match"
        return 1
    fi
    echo "Transaction hashes match"
}
