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

    export l1_rpc_url l2_rpc_url l2_node_url l1_private_key l2_private_key
}

# bats test_tags=forced-txs
@test "Send a rergular EOA forced tx" {
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

    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey_sender=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr_receiver=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')

    # Fund sender on L1 to pay fees
    l1_gas_price=$(cast gas-price --rpc-url "$l1_rpc_url")
    fund_up_to "$l1_private_key" "$random_addr_sender" $((l1_gas_price * 175000)) "$l1_rpc_url"

    # Fund sender on L2 to send 3 wei through forced tx
    fund_up_to "$l2_private_key" "$random_addr_sender" 3 "$l2_rpc_url"

    # Lets save and check the balances before the forced tx
    l2_sender_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    l2_receiver_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")
    if [[ "$l2_sender_balance_before" != "3" ]]; then
        echo "❌ L2 address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != 3"
        exit 1
    else
        echo "✅ L2 address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before"
    fi

    # Lets check the receiver balance before the forced tx
    if [[ "$l2_receiver_balance_before" != "0" ]]; then
        echo "❌ L2 address $random_addr_receiver balance before deposit is not as expected: $l2_receiver_balance_before != 0"
        exit 1
    else
        echo "✅ L2 address $random_addr_receiver balance before deposit is as expected: $l2_receiver_balance_before"
    fi

    # function depositTransaction(
    #     address _to,
    #     uint256 _value,
    #     uint64 _gasLimit,
    #     bool _isCreation,
    #     bytes memory _data
    # )
    run cast send --rpc-url $l1_rpc_url "$l1_optimism_portal_addr" \
        --private-key $random_pkey_sender \
        --value 0 \
        --json \
        "depositTransaction(address,uint256,uint64,bool,bytes)" \
        "$random_addr_receiver" \
        3 \
        21000 \
        false \
        "0x"

    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to send depositTransaction to L1 Optimism Portal: $output"
        exit 1
    else
        tx_hash=$(echo "$output" | jq -r '.transactionHash')
    fi
    echo "✅ Successfully sent depositTransaction to L1 Optimism Portal with txhash: $tx_hash"

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
        echo "❌ L2 address $random_addr_sender balance after deposit is not as expected: $l2_sender_balance_after != 0"
        exit 1
    else
        echo "✅ L2 address $random_addr_sender balance after deposit is as expected: $l2_sender_balance_after"
    fi

    if [[ "$l2_receiver_balance_after" != "3" ]]; then
        echo "❌ L2 address $random_addr_receiver balance after deposit is not as expected: $l2_receiver_balance_after != 3"
        exit 1
    else
        echo "✅ L2 address $random_addr_receiver balance after deposit is as expected: $l2_receiver_balance_after"
    fi

}
