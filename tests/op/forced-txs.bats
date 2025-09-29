#!/usr/bin/env bats
# bats file_tags=op,forced-txs

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars
}

setup() {
    load '../../core/helpers/scripts/fund.bash'
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
        echo "❌ Failed to estimate forced transaction to L1 Optimism Portal: $output" >&3
        exit 1
    else
        gas=$output
        echo "✅ Successfully estimated gas for depositTransaction to L1 Optimism Portal: $gas" >&3
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
        echo "❌ Failed to send forced transaction to L1 Optimism Portal: $output" >&3
        exit 1
    else
        forced_tx_hash=$(echo "$output" | jq -r '.transactionHash')
        tx_status=$(echo "$output" | jq -r '.status')
        if [[ "$tx_status" -ne 1 ]]; then
            jq_output=$(echo $output | jq .)
            echo "❌ Forced transaction $forced_tx_hash was mined with failed status: $jq_output" >&3
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
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != $l2_sender_funds_required" >&3
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before" >&3
    fi

    # Lets check the receiver balance before the forced tx
    if [[ "$l2_receiver_balance_before" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance before deposit is not as expected: $l2_receiver_balance_before != 0" >&3
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance before deposit is as expected: $l2_receiver_balance_before" >&3
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$random_addr_receiver" $l2_sender_funds_required 21000
    echo "✅ Successfully sent depositTransaction to L1 Optimism Portal with txhash: $forced_tx_hash" >&3

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
        echo "❌ L2 sender address $random_addr_sender balance after deposit is not as expected: $l2_sender_balance_after != 0" >&3
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance after deposit is as expected: $l2_sender_balance_after" >&3
    fi

    if [[ "$l2_receiver_balance_after" != "$l2_sender_funds_required" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance after deposit is not as expected: $l2_receiver_balance_after != $l2_sender_funds_required" >&3
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance after deposit is as expected: $l2_receiver_balance_after" >&3
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
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != 0" >&3
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before" >&3
    fi

    # Lets check the receiver balance before the forced tx
    if [[ "$l2_receiver_balance_before" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance before deposit is not as expected: $l2_receiver_balance_before != 0" >&3
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance before deposit is as expected: $l2_receiver_balance_before" >&3
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$random_addr_receiver" 1 21000
    echo "✅ Successfully sent depositTransaction to L1 Optimism Portal with txhash: $forced_tx_hash" >&3

    # Let's wait to allow forced tx to be processed
    sleep 20

    # Lets check L2 balances after the forced tx
    l2_sender_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    l2_receiver_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_receiver")

    if [[ "$l2_sender_balance_after" != "0" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance after deposit is not as expected: $l2_sender_balance_after != 0" >&3
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance after deposit is as expected: $l2_sender_balance_after" >&3
    fi

    if [[ "$l2_receiver_balance_after" != "0" ]]; then
        echo "❌ L2 receiver address $random_addr_receiver balance after deposit is not as expected: $l2_receiver_balance_after != 0" >&3
        exit 1
    else
        echo "✅ L2 receiver address $random_addr_receiver balance after deposit is as expected: $l2_receiver_balance_after" >&3
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
    contract_bytecode=$(cat $BATS_TEST_DIRNAME/contracts/SimpleStorage.json | jq -r .bytecode.object)
    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --create $contract_bytecode --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to deploy contract: $output" >&3
        exit 1
    else
        contract_address=$(echo "$output" | jq -r '.contractAddress')
        if [ -z "$contract_address" ]; then
            echo "❌ Contract address not found in output" >&3
            exit 1
        else
            echo "✅ Successfully deployed contract with address: $contract_address" >&3
        fi
    fi

    # Fund sender on L1 to pay fees
    fund_up_to "$l1_private_key" "$random_addr_sender" $l1_sender_funds_required "$l1_rpc_url"

    # Fund sender on L2
    fund_up_to "$l2_private_key" "$random_addr_sender" $l2_sender_funds_required "$l2_rpc_url"

    # Lets save and check the balances before the forced tx
    l2_sender_balance_before=$(cast balance --rpc-url "$l2_rpc_url" "$random_addr_sender")
    if [[ "$l2_sender_balance_before" != "$l2_sender_funds_required" ]]; then
        echo "❌ L2 sender address $random_addr_sender balance before deposit is not as expected: $l2_sender_balance_before != $l2_sender_funds_required" >&3
        exit 1
    else
        echo "✅ L2 sender address $random_addr_sender balance before deposit is as expected: $l2_sender_balance_before" >&3
    fi

    # send_forced_tx sender_key l1_gas_limit l2_receiver_addr l2_amount l2_gas_limit l2_data(optional)
    send_forced_tx "$random_pkey_sender" "$contract_address" 0 15000000 "$(cast abi-encode "set(uint256)" $contract_call_value)"
    echo "✅ Successfully sent forced transaction to L1 Optimism Portal with txhash $forced_tx_hash" >&3

    while true; do
        sleep 5
        run cast call --rpc-url $l2_rpc_url $contract_address 'getValue()'
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to call l2 contract: $output" >&3
            exit 1
        else
            value=$(echo $output | cast to-dec)
            if [[ "$value" == "43981" ]]; then
                echo "⏳ L2 contract value is still the default $value, waiting for forced tx to be processed..." >&3
            elif [[ "$value" == "1337" ]]; then
                echo "❌ L2 contract value is $value, which means that the call was not processed correctly" >&3
                exit 1
            elif [[ "$value" == "$contract_call_value" ]]; then
                echo "✅ L2 contract value is as expected: $value" >&3
                break
            else
                echo "❌ L2 contract value is unexpected: $value" >&3
                exit 1
            fi
        fi
    done
    # L2 balances are not modified at all, no need to check

}