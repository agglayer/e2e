#!/usr/bin/env bats

setup() {
    load '../../core/helpers/scripts/fund.bash'
    load '../../core/helpers/scripts/erc20.bash' 
}


setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"cgt"}

    export l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    export l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    export l1_bridge_addr=${L1_BRIDGE_ADDR:-"$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 'cat /opt/zkevm/combined-001.json | jq -r .polygonZkEVMBridgeAddress')"}

    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    export l2_bridge_addr=${L2_BRIDGE_ADDR:-"$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 'cat /opt/zkevm/combined-001.json | jq -r .polygonZkEVML2BridgeAddress')"}

    export bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"}
    export network_id=$(cast call  --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    export claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    export autoclaim_timeout_seconds=${AUTCLAIM_TIMEOUT_SECONDS:-"300"}
    export l1_claim_timeout_seconds=${L1_CLAIM_TIMEOUT_SECONDS:-"900"}

    export gas_token_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'gasTokenAddress()(address)')
    export weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')

    export zero_address=$(cast address-zero)

    # Fail fast. Failing here will abort any test on this file that would make no sense if we don't have a custom gas token set on L2.
    if [[ $gas_token_address == $zero_address ]]; then
        echo "No custom gas token set on L2 bridge reported by: gasTokenAddress()(address) !"
        exit 1
    else
        if [[ $gas_token_address == $weth_address ]]; then
            echo "The custom gas token and WETH address are the same: WETHToken()(address) ==  gasTokenAddress()(address) !"
            exit 1
        fi
    fi

    # Random wallet
    random_wallet=$(cast wallet new --json)
    export random_address=$(echo "$random_wallet" | jq -r '.[0].address')
    export random_private_key=$(echo "$random_wallet" | jq -r '.[0].privateKey')
}


@test "check address for custom gas token on L2" {
    # That check has been moved to setup_file, we just report success here.
    echo "✅ Custom gas token address: $gas_token_address, WETH address: $weth_address"
}

@test "test custom gas token bridge from L1 to L2" {
    # This test deposits gas token on L1 bridge, so it has to become L2 native balance.
    # It checks few things:
    #   - Token balance on L1 address after L1 deposit has decreased by the amount deposited
    #   - Token balance on L1 bridge address after L1 deposit has increased by the amount deposited
    #   - L2 address balance after L2 claim has increased by the amount claimed
    #   - L2 bridge address balance after L2 claim has decreased by the amount claimed

    wei_amount=1
    claim_amount=$(echo "0.1" | cast to-wei)
    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    # Fund claimtxmanager with 1 ETH for deposits on L1 to be claimed on L2
    echo "Funding ClaimTxManager at $claimtxmanager_addr with 1 ETH..."
    fund_up_to "$l2_private_key" "$claimtxmanager_addr" "$(echo 1 | cast to-wei)" "$l2_rpc_url"

    # Initialize ERC20 vars to call functions afterwards
    erc20_init "$gas_token_address" "$l1_rpc_url"

    # Get token balance for L1 and bridge address
    l1_sender_token_balance=$(erc20_balance "$l1_eth_address")
    l1_bridge_token_balance=$(erc20_balance "$l1_bridge_addr")

    # Get balance on L2 address, to assert later
    l2_receiver_balance=$(cast balance --rpc-url "$l2_rpc_url" "$random_address")
    l2_bridge_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_bridge_addr")

    #
    # L1 deposit and checks
    #
    # If not l1 balance or less than wei_amount, abort test
    if [[ -z "$l1_sender_token_balance" ]]; then
        echo "❌ No token balance found for L1 address $l1_eth_address"
        exit 1
    fi
    is_insufficient=$(echo "$l1_sender_token_balance < $wei_amount" | bc)
    if [[ "$is_insufficient" -eq 1 ]]; then
        echo "❌ Not enough balance for L1 address $l1_eth_address in gas token $gas_token_address: $l1_sender_token_balance"
        exit 1
    else
        echo "✅ L1 address $l1_eth_address has a balance of $l1_sender_token_balance in gas token $gas_token_address"
        echo "✅ L1 bridge address $l1_bridge_addr has a balance of $l1_bridge_token_balance in gas token $gas_token_address"
    fi

    # Approve the L1 bridge to spend 1 wei of token in our behalf
    erc20_approve "$l1_private_key" "$l1_bridge_addr" "$wei_amount"

    # Deposit gas token from L1 to L2
    cast send --rpc-url $l1_rpc_url $l1_bridge_addr \
        "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
        $network_id $random_address $wei_amount $gas_token_address true "0x" \
        --private-key $l1_private_key

    # Assert balance has decreased by 1 wei
    l1_sender_token_balance_after=$(erc20_balance "$l1_eth_address")
    expected_l1_sender_balance=$(echo "$l1_sender_token_balance - $wei_amount" | bc)
    if [[ "$l1_sender_token_balance_after" != "$expected_l1_sender_balance" ]]; then
        echo "❌ L1 address $l1_eth_address balance after deposit is not as expected: $l1_sender_token_balance_after != $expected_l1_sender_balance"
        exit 1
    else
        echo "✅ L1 address $l1_eth_address balance after deposit is as expected: $l1_sender_token_balance_after"
    fi

    # Assert balance of L1 bridge has increased by 1 wei
    l1_bridge_token_balance_after=$(erc20_balance "$l1_bridge_addr")
    expected_l1_bridge_balance=$(echo "$l1_bridge_token_balance + $wei_amount" | bc)
    if [[ "$l1_bridge_token_balance_after" != "$expected_l1_bridge_balance" ]]; then
        echo "❌ L1 bridge address $l1_bridge_addr balance after deposit is not as expected: $l1_bridge_token_balance_after != $expected_l1_bridge_balance"
        exit 1
    else
        echo "✅ L1 bridge address $l1_bridge_addr balance after deposit is as expected: $l1_bridge_token_balance_after"
    fi

    #
    # L2 claim and checks
    #
    # check we have at least 0.1 native balance on L2 address for claim fees
    l2_claimer_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    if [[ -z "$l2_claimer_balance" ]]; then
        echo "❌ No balance found for L2 address $l2_eth_address"
        exit 1
    fi
    is_insufficient=$(echo "$l2_claimer_balance < $claim_amount" | bc)
    if [[ "$is_insufficient" -eq 1 ]]; then
        echo "❌ Not enough balance for L2 address $l2_eth_address to pay for claiming fees: $l2_claimer_balance"
        exit 1
    else
        echo "✅ L2 address $l2_eth_address has a native balance of $l2_claimer_balance"
    fi

    # Wait for deposit to be autoclaimed, timeout after $autoclaim_timeout_seconds
    echo "Waiting for L2 address $random_address balance to be updated after deposit..."
    l2_receiver_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_address")
    end_time=$((SECONDS + autoclaim_timeout_seconds))

    while [[ "$l2_receiver_balance_after" == "$l2_receiver_balance" ]]; do
        if [[ $SECONDS -ge $end_time ]]; then
            echo "❌ Timeout reached while waiting for L2 address $random_address balance to be updated after deposit."
            exit 1
        fi
        sleep 3
        l2_receiver_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$random_address")
    done

    # Assert balance increase for the receiver
    expected_receiver_balance=$(echo "$l2_receiver_balance + $wei_amount" | bc)
    if [[ "$l2_receiver_balance_after" != "$expected_receiver_balance" ]]; then
        echo "❌ L2 address $random_address balance after claim is not as expected:"
        echo "   got:      $l2_receiver_balance_after"
        echo "   expected: $expected_receiver_balance"
        exit 1
    else
        echo "✅ L2 address $random_address balance after claim is as expected: $l2_receiver_balance_after"
    fi

    # Assert balance decrease for the bridge
    l2_bridge_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$l2_bridge_addr")
    expected_bridge_balance=$(echo "$l2_bridge_balance - $wei_amount" | bc)
    if [[ "$l2_bridge_balance_after" != "$expected_bridge_balance" ]]; then
        echo "❌ L2 bridge address $l2_bridge_addr balance after claim is not as expected:"
        echo "   got:      $l2_bridge_balance_after"
        echo "   expected: $expected_bridge_balance"
        exit 1
    else
        echo "✅ L2 bridge address $l2_bridge_addr balance after claim is as expected: $l2_bridge_balance_after"
    fi
}

@test "test custom gas token bridge from L2 to L1" {
    # This test deposits gas token on L1 bridge, so it has to become L2 native balance.
    # It checks few things:
    #   - Token balance on L1 address after L1 deposit has decreased by the amount deposited
    #   - Token balance on L1 bridge address after L1 deposit has increased by the amount deposited
    #   - L2 address balance after L2 claim has increased by the amount claimed
    #   - L2 bridge address balance after L2 claim has decreased by the amount claimed

    wei_amount=1
    claim_amount=$(echo "0.1" | cast to-wei)
    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    # Initialize ERC20 vars to call functions afterwards
    erc20_init "$gas_token_address" "$l1_rpc_url"

    # Get balance on L2 address
    l2_sender_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    l2_bridge_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_bridge_addr")

    # Get token balance for L1 and bridge address
    l1_receiver_token_balance=$(erc20_balance "$random_address")
    l1_bridge_token_balance=$(erc20_balance "$l1_bridge_addr")


    #
    # Prerequisites to check
    #

    # If not l2 balance or less than wei_amount, abort test
    if [[ -z "$l2_sender_balance" ]]; then
        echo "❌ No balance found for L2 address $l2_eth_address"
        exit 1
    fi
    is_insufficient=$(echo "$l2_sender_balance < $wei_amount" | bc)
    if [[ "$is_insufficient" -eq 1 ]]; then
        echo "❌ Not enough balance for L2 address $l2_eth_address: $l2_sender_balance"
        exit 1
    else
        echo "✅ L2 address $l2_eth_address has a balance of $l2_sender_balance"
        echo "✅ L2 bridge address $l2_bridge_addr has a balance of $l2_bridge_balance"
    fi

    # check we have at least 0.1 native balance on L1 address for claim fees, use bc
    l1_claimer_balance=$(cast balance --rpc-url $l1_rpc_url $l1_eth_address)
    if [[ -z "$l1_claimer_balance" ]]; then
        echo "❌ No balance found for L1 address $l1_eth_address"
        exit 1
    fi
    is_too_low=$(echo "$l1_claimer_balance < $claim_amount" | bc)
    if [[ "$is_too_low" -eq 1 ]]; then
        echo "❌ Not enough balance for L1 address $l1_eth_address to pay for claiming fees: $l1_claimer_balance"
        exit 1
    else
        echo "✅ L1 address $l1_eth_address has a native balance of $l1_claimer_balance"
    fi

    # check that L1 bridge has at least 1 wei of gas token
    if [[ -z "$l1_bridge_token_balance" ]]; then
        echo "❌ No token balance found for L1 bridge address $l1_bridge_addr"
        exit 1
    fi
    is_insufficient=$(echo "$l1_bridge_token_balance < $wei_amount" | bc)
    if [[ "$is_insufficient" -eq 1 ]]; then
        echo "❌ Not enough balance for L1 bridge address $l1_bridge_addr in gas token $gas_token_address: $l1_bridge_token_balance"
        exit 1
    else
        echo "✅ L1 bridge address $l1_bridge_addr has a balance of $l1_bridge_token_balance in gas token $gas_token_address"
    fi


    #
    # L2 deposit
    #
    cast send --rpc-url $l2_rpc_url $l2_bridge_addr \
        "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
        0 $random_address $wei_amount $zero_address true "0x" \
        --private-key $l2_private_key --value 1

    # Assert balance of sender account has decreased by at least 1 wei (also fees are deducted), compare using bc to avoid overflow issues
    l2_sender_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    expected_sender_balance=$(echo "$l2_sender_balance - $wei_amount" | bc)
    comparison=$(echo "$l2_sender_balance_after >= $expected_sender_balance" | bc)

    if [[ "$comparison" -eq 1 ]]; then
        echo "❌ L2 address $l2_eth_address balance after deposit is not as expected: $l2_sender_balance_after >= $expected_sender_balance"
        exit 1
    else
        echo "✅ L2 address $l2_eth_address balance after deposit is as expected: $l2_sender_balance_after"
    fi

    # Assert balance of L2 bridge has increased by 1 wei, compare using bc to avoid overflow issues
    l2_bridge_balance_after=$(cast balance --rpc-url "$l2_rpc_url" "$l2_bridge_addr")
    expected_bridge_balance=$(echo "$l2_bridge_balance + $wei_amount" | bc)

    if [[ "$l2_bridge_balance_after" != "$expected_bridge_balance" ]]; then
        echo "❌ L2 bridge address $l2_bridge_addr balance after deposit is not as expected: $l2_bridge_balance_after != $expected_bridge_balance"
        exit 1
    else
        echo "✅ L2 bridge address $l2_bridge_addr balance after deposit is as expected: $l2_bridge_balance_after"
    fi


    #
    # L1 claim and checks
    #

    # loop claiming until random_address balance is updated, timeout after $l1_claim_timeout_seconds
    echo "Waiting for L1 address $random_address balance to be updated after deposit..."
    l1_receiver_token_balance_after=$(erc20_balance "$random_address")
    end_time=$((SECONDS + l1_claim_timeout_seconds))
    while [[ "$l1_receiver_token_balance_after" == "$l1_receiver_token_balance" ]]; do
        if [[ $SECONDS -ge $end_time ]]; then
            echo "❌ Timeout reached while waiting for L1 address $random_address balance to be updated after deposit."
            exit 1
        fi
        polycli ulxly claim-everything \
            --bridge-address $l1_bridge_addr \
            --destination-address $random_address \
            --rpc-url $l1_rpc_url \
            --private-key $l1_private_key \
            --bridge-service-map '0='$bridge_service_url','$network_id'='$bridge_service_url
        sleep 30
        l1_receiver_token_balance_after=$(erc20_balance "$random_address")
    done
}
