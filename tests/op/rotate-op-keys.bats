#!/usr/bin/env bats
# bats file_tags=op

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars
}

setup() {
    load "$BATS_TEST_DIRNAME/../../core/helpers/scripts/fund.bash"
}


# bats test_tags=op-rotate-batcher-key
@test "Rotate OP batcher key" {
    # Create new wallet for the batcher
    new_batcher_wallet=$(cast wallet new --json)
    new_batcher_address=$(echo "$new_batcher_wallet" | jq -r '.[0].address')
    new_batcher_private_key=$(echo "$new_batcher_wallet" | jq -r '.[0].private_key')

    new_batcher_address=$(echo "$new_batcher_address" | tr '[:upper:]' '[:lower:]')
    new_batcher_private_key=$(echo "$new_batcher_private_key" | tr '[:upper:]' '[:lower:]')

    # Stop and remove current batcher service
    old_batcher_service=$(kurtosis service inspect $kurtosis_enclave_name op-batcher-001 -o json)
    kurtosis service stop $kurtosis_enclave_name op-batcher-001
    kurtosis service rm $kurtosis_enclave_name op-batcher-001
    echo "✅ Successfully stopped and removed current batcher service" >&3

    # Get current L1 block
    latest_l1_block=$(cast bn --rpc-url "$l1_rpc_url")
    echo "✅ Latest L1 block: $latest_l1_block" >&3

    # wait until that L1 block is finalized
    finalized_l1_block=$(cast bn --rpc-url "$l1_rpc_url" finalized)
    while [[ $finalized_l1_block -lt $latest_l1_block ]]; do
        echo "⏳ Waiting for current L1 block to be finalized (finalized: $finalized_l1_block, target: $latest_l1_block)" >&3
        sleep 10
        finalized_l1_block=$(cast bn --rpc-url "$l1_rpc_url" finalized)
    done    
    echo "✅ Finalized L1 block is: $finalized_l1_block, target: $latest_l1_block" >&3

    # Send funds from old batcher to new batcher address
    old_batcher_private_key=$(echo "$old_batcher_service" | jq -r '.cmd[] | select(startswith("--private-key=")) | split("=")[1]')
    drain_to $old_batcher_private_key $new_batcher_address $l1_rpc_url
    echo "✅ Successfully funded new batcher address: $new_batcher_address" >&3

    # Set the new batcher address in the rollup config file
    old_batcher_address=$(cast wallet address --private-key $old_batcher_private_key)
    old_batcher_address=$(echo "$old_batcher_address" | tr '[:upper:]' '[:lower:]')
    node_service=$(kurtosis service inspect $kurtosis_enclave_name op-cl-1-op-node-op-geth-001 -o json)
    rollup_config_file=$(echo "$node_service" | jq -r '.cmd[] | select(startswith("--rollup.config=")) | split("=")[1]')
    kurtosis service exec $kurtosis_enclave_name op-cl-1-op-node-op-geth-001 "sed -i 's|$old_batcher_address|$new_batcher_address|' $rollup_config_file"
    echo "✅ Successfully set new batcher address $new_batcher_address in the rollup config file" >&3

    # Set the new batcher address in the L1 System Config contract
    new_batcher_address_32="0x$(printf "%064s" "${new_batcher_address#0x}" | tr ' ' '0')"
    run cast send --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$l1_system_config_addr" "setBatcherHash(bytes32)" "$new_batcher_address_32"
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to set new batcher address $new_batcher_address in the L1 System Config contract: $output" >&3
        exit 1
    else
        echo "✅ Successfully set new batcher address $new_batcher_address in the L1 System Config contract" >&3
    fi

    # Restart the node service
    kurtosis service stop $kurtosis_enclave_name op-cl-1-op-node-op-geth-001
    kurtosis service start $kurtosis_enclave_name op-cl-1-op-node-op-geth-001
    echo "✅ Successfully restarted node service" >&3

    # Create new batcher service with the new private key
    new_batcher_service=$(echo "$old_batcher_service" | sed "s|--private-key=[^\"]*\"|--private-key=$new_batcher_private_key\"|")
    echo "$new_batcher_service" | kurtosis service add --json-service-config - $kurtosis_enclave_name op-batcher-001
    echo "✅ Successfully created new batcher service with the new private key" >&3

    # wait until current L2 block is finalized
    latest_l2_block=$(cast bn --rpc-url "$l2_rpc_url")
    echo "✅ Latest L2 block: $latest_l2_block" >&3
    finalized_l2_block=$(cast bn --rpc-url "$l2_rpc_url" finalized)
    while [[ $finalized_l2_block -lt $latest_l2_block ]]; do
        echo "⏳ Waiting for current L2 block to be finalized (finalized: $finalized_l2_block, target: $latest_l2_block)" >&3
        sleep 15
        finalized_l2_block=$(cast bn --rpc-url "$l2_rpc_url" finalized)
    done    
    echo "✅ Finalized L2 block is: $finalized_l2_block, target: $latest_l2_block" >&3
}
