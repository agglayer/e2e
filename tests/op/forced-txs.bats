#!/usr/bin/env bats
# bats file_tags=op,forced-txs

setup() {
    load '../../core/helpers/scripts/fund.bash'
}

setup_file() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"cdk"}
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    l2_node_url=${L2_NODE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-cl-1-op-node-op-geth-001 http)"}
    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"

    export l1_rpc_url l2_rpc_url l1_private_key l2_private_key

    run cast rpc --rpc-url "$l2_node_url" optimism_rollupConfig
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to retrieve rollup config from l2 node"
        exit 1
    else
        l1_system_config_addr=$(echo $output | jq -r '.l1_system_config_address')
        if [[ -z "$l1_system_config_addr" ]]; then
            echo "❌ Failed to retrieve L1 system config address from Rollup Config: $output"
            exit 1
        else
            echo "✅ L1 system config address: $l1_system_config_addr"
        fi
    fi

    run cast call "$l1_system_config_addr" "optimismPortal()(address)" --rpc-url "$l1_rpc_url"
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to retrieve L1 Optimism Portal address from L1 System Config: $output"
        exit 1
    else
        l1_optimism_portal_addr=$output
        if [[ -z "$l1_optimism_portal_addr" ]]; then
            echo "❌ Failed to retrieve L1 Optimism Portal address from L1 System Config: $output"
            exit 1
        else
            echo "✅ L1 Optimism Portal address: $l1_optimism_portal_addr"
        fi
    fi

    export l1_optimism_portal_addr
}

function send_forced_tx() {
    local sender_key=$1
    local l2_receiver=$2
    local l2_amount=$3
    local l2_gas_limit=$4
    local l2_data=${5:-"0x"}

    # function depositTransaction(
    #     address _to,
    #     uint256 _value,
    #     uint64 _gasLimit,
    #     bool _isCreation,
    #     bytes memory _data
    # )
    run cast estimate --rpc-url $l1_rpc_url "$l1_optimism_portal_addr" \
        --value 0 \
        "depositTransaction(address,uint256,uint64,bool,bytes)" \
        "$l2_receiver" \
        "$l2_amount" \
        $l2_gas_limit \
        false \
        "$l2_data"
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to estimate forced transaction to L1 Optimism Portal: $output"
        exit 1
    else
        gas=$output
        echo "✅ Successfully estimated gas for depositTransaction to L1 Optimism Portal: $gas"
    fi

    run cast send --rpc-url $l1_rpc_url "$l1_optimism_portal_addr" \
        --private-key $sender_key \
        --value 0 \
        --gas-limit $((gas * 2)) \
        --json \
        "depositTransaction(address,uint256,uint64,bool,bytes)" \
        "$l2_receiver" \
        "$l2_amount" \
        $l2_gas_limit \
        false \
       "$l2_data"

    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to send forced transaction to L1 Optimism Portal: $output"
        exit 1
    else
        forced_tx_hash=$(echo "$output" | jq -r '.transactionHash')
        tx_status=$(echo "$output" | jq -r '.status')
        if [[ "$tx_status" -ne 1 ]]; then
            jq_output=$(echo $output | jq .)
            echo "❌ Forced transaction $forced_tx_hash was mined with failed status: $jq_output"
            exit 1
        fi
    fi
    export forced_tx_hash
}

# bats test_tags=forced-txs
@test "Send a regular EOA forced tx" {
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_receiver=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')

    # The sender needs to pay fees on L1, however, sender is not charged for fees on L2
    l1_sender_funds_required=$(echo 0.01 | cast to-wei)
    l2_sender_funds_required=3

    # Fund sender on L1 to pay fees
    fund_up_to "$l1_private_key" "$random_addr_sender" $l1_sender_funds_required "$l1_rpc_url"

    # Fund sender on L2 to send 3 wei through forced tx
    fund_up_to "$l2_private_key" "$random_addr_sender" $l2_sender_funds_required "$l2_rpc_url"

    # Lets save and check the balances before the forced tx
    l2_sender_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    l2_receiver_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")
    if [[ "$l2_sender_balance_before" != "$l2_sender_funds_required" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != $l2_sender_funds_required"
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before"
    fi

    # Lets check the receiver balance before the forced tx
    if [[ "$l2_receiver_balance_before" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance before deposit is not as expected: $l2_receiver_balance_before != 0"
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance before deposit is as expected: $l2_receiver_balance_before"
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$random_addr_receiver" $l2_sender_funds_required 21000
    echo "✅ Successfully sent depositTransaction to L1 Optimism Portal with txhash: $forced_tx_hash"

    # lets loop until receiver has some balance on l2
    while true; do
        l2_receiver_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")
        if [[ "$l2_receiver_balance_after" -gt "0" ]]; then
            break
        fi
        sleep 1
    done

    # Lets check L2 balances after the forced tx
    l2_sender_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")

    if [[ "$l2_sender_balance_after" != "0" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance after deposit is not as expected: $l2_sender_balance_after != 0"
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance after deposit is as expected: $l2_sender_balance_after"
    fi

    if [[ "$l2_receiver_balance_after" != "$l2_sender_funds_required" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance after deposit is not as expected: $l2_receiver_balance_after != $l2_sender_funds_required"
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance after deposit is as expected: $l2_receiver_balance_after"
    fi

}

# bats test_tags=forced-txs
@test "Send a regular EOA forced tx with no l2 funds" {
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_receiver=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')

   l1_sender_funds_required=$(echo 0.01 | cast to-wei)
 
     # Fund sender on L1 to pay fees
    fund_up_to "$l1_private_key" "$random_addr_sender" $l1_sender_funds_required "$l1_rpc_url"

    # Lets save and check the balances before the forced tx
    l2_sender_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    l2_receiver_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")
    if [[ "$l2_sender_balance_before" != "0" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != 0"
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before"
    fi

    # Lets check the receiver balance before the forced tx
    if [[ "$l2_receiver_balance_before" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance before deposit is not as expected: $l2_receiver_balance_before != 0"
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance before deposit is as expected: $l2_receiver_balance_before"
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$random_addr_receiver" 1 21000
    echo "✅ Successfully sent depositTransaction to L1 Optimism Portal with txhash: $forced_tx_hash"

    # Let's wait to allow forced tx to be processed
    sleep 20

    # Lets check L2 balances after the forced tx
    l2_sender_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    l2_receiver_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")

    if [[ "$l2_sender_balance_after" != "0" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance after deposit is not as expected: $l2_sender_balance_after != 0"
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance after deposit is as expected: $l2_sender_balance_after"
    fi

    if [[ "$l2_receiver_balance_after" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance after deposit is not as expected: $l2_receiver_balance_after != 0"
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance after deposit is as expected: $l2_receiver_balance_after"
    fi
}

# bats test_tags=forced-txs
@test "Contract call through forced tx" {
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')

    # The sender needs to pay fees on L1, however, sender is not charged for fees on L2
    l1_sender_funds_required=$(echo 0.01 | cast to-wei)
    l2_sender_funds_required=$(echo 0 | cast to-wei)
    contract_call_value=3

    # Deploy the contract
    contract_bytecode=$(cat contracts/SimpleStorage.json | jq -r .bytecode.object)
    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --create $contract_bytecode --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to deploy contract: $output"
        exit 1
    else
        contract_address=$(echo "$output" | jq -r '.contractAddress')
        if [ -z "$contract_address" ]; then
            echo "❌ Contract address not found in output"
            exit 1
        else
            echo "✅ Successfully deployed contract with address: $contract_address"
        fi
    fi

    # Fund sender on L1 to pay fees
    fund_up_to "$l1_private_key" "$random_addr_sender" $l1_sender_funds_required "$l1_rpc_url"

    # Fund sender on L2
    fund_up_to "$l2_private_key" "$random_addr_sender" $l2_sender_funds_required "$l2_rpc_url"

    # Lets save and check the balances before the forced tx
    l2_sender_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    if [[ "$l2_sender_balance_before" != "$l2_sender_funds_required" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != $l2_sender_funds_required"
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before"
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$contract_address" 0 15000000 "$(cast abi-encode "set(uint256)" $contract_call_value)"
    echo "✅ Successfully sent forced transaction to L1 Optimism Portal with txhash $forced_tx_hash"

    while true; do
        sleep 5
        run cast call --rpc-url $l2_rpc_url $contract_address 'getValue()'
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to call l2 contract: $output"
            exit 1
        else
            value=$(echo $output | cast to-dec)
            if [[ "$value" == "43981" ]]; then
                echo "⏳ L2 contract value is still the default $value, waiting for forced tx to be processed..."
            elif [[ "$value" == "1337" ]]; then
                echo "❌ L2 contract value is $value, which means that the call was not processed correctly"
                exit 1
            elif [[ "$value" == "$contract_call_value" ]]; then
                echo "✅ L2 contract value is as expected: $value"
                break
            else
                echo "❌ L2 contract value is unexpected: $value"
                exit 1
            fi
        fi
    done
    # L2 balances are not modified at all, no need to check
}
