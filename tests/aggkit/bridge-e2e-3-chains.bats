#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    local num_chain=3
    _agglayer_cdk_common_multi_setup $num_chain

    add_network_to_agglayer 2 "$l2_rpc_url_2"
    add_network_to_agglayer 3 "$l2_rpc_url_3"
    mint_pol_token "$l1_bridge_addr"
}

@test "L1 → Rollup 3 (native/WETH) → Rollup 1" {
    run query_contract "$l2_rpc_url_1" "$weth_token_rollup_1" "$BALANCE_OF_FN_SIG" "$destination_addr"
    assert_success
    local initial_weth_token_rollup1_balance
    initial_weth_token_rollup1_balance=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial destination addr balance $initial_weth_token_rollup1_balance of gas token on L1" >&3

    echo "=== Running LxLy bridge eth L1 to L2(Rollup 3) amount:$amount" >&3
    destination_net=$rollup_3_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp3=$output

    echo "=== Running LxLy claim L1 to L2(Rollup 3) for $bridge_tx_hash_pp3" >&3
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp3" "$rollup_3_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_3_url" "$l2_rpc_url_3"
    assert_success

    # reduce eth amount
    amount="0.01ether"
    local wei_amount
    wei_amount=$(cast --to-unit $amount wei)
    echo "=== Running LxLy bridge L2(Rollup 3) to L2(Rollup 1) amount:$amount" >&3
    destination_net=$rollup_1_network_id
    meta_bytes="0xbeef"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_3" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    echo "=== Running LxLy claim L2(Rollup 3) to L2(Rollup 1) for: $bridge_tx_hash" >&3
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$rollup_3_network_id" "$bridge_tx_hash" "$rollup_1_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success

    # Verify final balance on Rollup 1
    run query_contract "$l2_rpc_url_1" "$weth_token_rollup_1" "$BALANCE_OF_FN_SIG" "$destination_addr"
    assert_success
    local final_weth_token_rollup1_balance
    final_weth_token_rollup1_balance=$(echo "$output" |
        tail -n 1 |
        awk '{print $1}')
    local expected_balance
    expected_balance=$(echo "$initial_weth_token_rollup1_balance + $wei_amount" |
        bc |
        awk '{print $1}')

    echo "$destination_addr balance on Rollup 1: $final_weth_token_rollup1_balance" >&3
    assert_equal "$final_weth_token_rollup1_balance" "$expected_balance"
}

@test "L1 → Rollup 1 (custom gas token) → Rollup 2" {
    # Set receiver address and query for its initial native token addr balance on the Rollup 1
    local initial_receiver_balance_rollup1
    initial_receiver_balance_rollup1=$(cast balance "$receiver" --rpc-url "$l2_rpc_url_1")
    echo "Initial receiver ($receiver) balance of native token addr on Rollup 1 $initial_receiver_balance_rollup1" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_rollup_1" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance_l1
    gas_token_init_sender_balance_l1=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance_l1 of gas token on L1" >&3

    # Mint gas token on L1
    local tokens_amount="1ether"
    local wei_amount
    wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$gas_token_rollup_1" "$minter_key" "$sender_addr" "$tokens_amount" "$l1_bridge_addr"
    assert_success

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$rollup_1_network_id
    amount=$tokens_amount
    meta_bytes="0x"
    run bridge_asset "$gas_token_rollup_1" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the Rollup 1)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$rollup_1_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_1_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_1_url"
    assert_success

    local final_receiver_balance_rollup1
    final_receiver_balance_rollup1=$(cast balance "$receiver" --rpc-url "$l2_rpc_url_1")
    echo "Final receiver ($receiver) balance of gas token addr on Rollup 1 $final_receiver_balance_rollup1" >&3

    echo "==== 💰 Verifying balance on Rollup 1" >&3
    run verify_balance "$l2_rpc_url_1" "$native_token_addr" "$destination_addr" "$initial_receiver_balance_rollup1" "$amount"
    assert_success

    # DEPOSIT
    destination_addr=$receiver
    destination_net=$rollup_2_network_id
    amount="0.01ether"
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_1" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the Rollup 2)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$rollup_1_network_id" "$bridge_tx_hash" "$rollup_2_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success

    run wait_for_expected_token "$gas_token_rollup_1" "$rollup_2_network_id" 15 2 "$aggkit_bridge_2_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr
    origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$gas_token_rollup_1" "$origin_token_addr"

    local rollup2_wrapped_token_addr
    rollup2_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 Rollup 2 wrapped token address $rollup2_wrapped_token_addr"

    echo "==== 💰 Verifying balance on Rollup 2" >&3
    run verify_balance "$l2_rpc_url_2" "$rollup2_wrapped_token_addr" "$destination_addr" 0 "$amount"
    assert_success
}

@test "L1 → Rollup 1 (native) → Rollup 3" {
    # Query for initial sender_addr balance on Rollup 1
    run query_contract "$l2_rpc_url_1" "$weth_token_rollup_1" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local weth_token_init_sender_balance_rollup1
    weth_token_init_sender_balance_rollup1=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $weth_token_init_sender_balance_rollup1" of WETH on Rollup 1 >&3

    # Bridge native from L1 to Rollup 1
    destination_net=$rollup_1_network_id
    destination_addr=$sender_addr
    amount="0.1ether"
    meta_bytes="0x"
    echo "=== Running LxLy bridge native L1 to Rollup 1 amount:$amount" >&3
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp1=$output

    # Claim on Rollup 1
    echo "=== Running LxLy claim L1 to Rollup 1 for $bridge_tx_hash_pp1" >&3
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp1" "$rollup_1_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success
    echo "==== 💰 Verifying balance on Rollup 1" >&3
    run verify_balance "$l2_rpc_url_1" "$weth_token_rollup_1" "$destination_addr" "$weth_token_init_sender_balance_rollup1" "$amount"
    assert_success

    # Set receiver address and query for its initial native token addr balance on the Rollup 1
    local initial_receiver_balance_rollup3
    initial_receiver_balance_rollup3=$(cast balance "$receiver" --rpc-url "$l2_rpc_url_3")
    echo "Initial receiver ($receiver) balance of native token addr on Rollup 3 $initial_receiver_balance_rollup3" >&3

    # Bridge WETH from Rollup 1 to Rollup 3
    amount="0.01ether"
    meta_bytes="0x"
    destination_net=$rollup_3_network_id
    destination_addr=$receiver
    echo "=== Running LxLy bridge WETH Rollup 1 to Rollup 3 amount:$amount" >&3
    run bridge_asset "$weth_token_rollup_1" "$l2_rpc_url_1" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Final claim on Rollup 3
    echo "=== Running LxLy claim Rollup 1 to Rollup 3 for: $bridge_tx_hash" >&3
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$rollup_1_network_id" "$bridge_tx_hash" "$rollup_3_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_3_url" "$l2_rpc_url_3"
    assert_success

    echo "==== 💰 Verifying balance on Rollup 3" >&3
    run verify_balance "$l2_rpc_url_3" "$native_token_addr" "$destination_addr" "$initial_receiver_balance_rollup3" "$amount"
    assert_success
}

@test "L1 → Rollup 1 (custom gas token) → Rollup 3 -> Rollup 2" {
    # Set receiver1 address and query for its initial native token addr balance on the Rollup 1
    local initial_receiver1_balance_rollup1
    initial_receiver1_balance_rollup1=$(cast balance "$receiver1_addr" --rpc-url "$l2_rpc_url_1")
    echo "Initial receiver1 ($receiver1_addr) balance of native token addr on Rollup 1 $initial_receiver1_balance_rollup1" >&3

    local minter_addr
    minter_addr=$(cast wallet address "$minter_key")

    local l1_minter_balance
    l1_minter_balance=$(cast balance "$minter_addr" --rpc-url "$l1_rpc_url")
    echo "Initial minter balance on L1 $l1_minter_balance" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_rollup_1" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance_l1
    gas_token_init_sender_balance_l1=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance_l1 of gas token on L1" >&3

    # Mint gas token on L1
    local tokens_amount="1ether"
    local wei_amount
    wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$gas_token_rollup_1" "$minter_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Send approve transaction to the gas token on L1
    run send_tx "$l1_rpc_url" "$sender_private_key" "$gas_token_rollup_1" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT
    destination_addr=$receiver1_addr
    destination_net=$rollup_1_network_id
    amount="0.1ether"
    meta_bytes="0x"
    run bridge_asset "$gas_token_rollup_1" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the Rollup 1)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$rollup_1_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_1_url" "$l2_rpc_url_1"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_1_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_1_url"
    assert_success

    local final_receiver1_balance_rollup1
    final_receiver1_balance_rollup1=$(cast balance "$receiver1_addr" --rpc-url "$l2_rpc_url_1")
    echo "Final receiver1 ($receiver1_addr) balance of gas token addr on Rollup 1 $final_receiver1_balance_rollup1" >&3

    echo "==== 💰 Verifying balance on Rollup 1" >&3
    run verify_balance "$l2_rpc_url_1" "$native_token_addr" "$destination_addr" "$initial_receiver1_balance_rollup1" "$amount"
    assert_success

    # Set receiver1 address and query for its initial native token addr balance on the Rollup 2
    local initial_receiver1_balance_rollup2
    initial_receiver1_balance_rollup2=$(cast balance "$receiver1_addr" --rpc-url "$l2_rpc_url_2")
    echo "Initial receiver1 ($receiver1_addr) balance of native token addr on Rollup 2 $initial_receiver1_balance_rollup2" >&3

    local l1_minter_balance
    l1_minter_balance=$(cast balance "$minter_addr" --rpc-url "$l1_rpc_url")
    echo "Initial minter balance on L1 $l1_minter_balance" >&3

    # Query for initial sender balance
    run query_contract "$l1_rpc_url" "$gas_token_rollup_2" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local gas_token_init_sender_balance_l1
    gas_token_init_sender_balance_l1=$(echo "$output" | tail -n 1 | awk '{print $1}')
    echo "Initial sender balance $gas_token_init_sender_balance_l1" of gas token on L1 >&3

    # Mint gas token on L1
    local tokens_amount="1ether"
    local wei_amount
    wei_amount=$(cast --to-unit $tokens_amount wei)
    run mint_and_approve_erc20_tokens "$l1_rpc_url" "$gas_token_rollup_2" "$minter_key" "$sender_addr" "$tokens_amount"
    assert_success

    # Send approve transaction to the gas token on L1
    run send_tx "$l1_rpc_url" "$sender_private_key" "$gas_token_rollup_2" "$APPROVE_FN_SIG" "$l1_bridge_addr" "$tokens_amount"
    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"

    # DEPOSIT
    destination_addr=$receiver1_addr
    destination_net=$rollup_2_network_id
    amount="0.1ether"
    meta_bytes="0x"
    run bridge_asset "$gas_token_rollup_2" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the Rollup 2)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash" "$rollup_2_network_id" "$l1_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success

    local final_receiver1_balance_rollup2
    final_receiver1_balance_rollup2=$(cast balance "$receiver1_addr" --rpc-url "$l2_rpc_url_2")
    echo "Final receiver1 ($receiver1_addr) balance of gas token addr on Rollup 2 $final_receiver1_balance_rollup2" >&3

    echo "==== 💰 Verifying balance on Rollup 2" >&3
    run verify_balance "$l2_rpc_url_2" "$native_token_addr" "$destination_addr" "$initial_receiver1_balance_rollup2" "$amount"
    assert_success

    echo "=== Running LxLy bridge eth L1 to L2(Rollup 3) amount:$amount for gas" >&3
    destination_addr=$receiver1_addr
    destination_net=$rollup_3_network_id
    run bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
    assert_success
    local bridge_tx_hash_pp3=$output

    echo "=== Running LxLy claim L1 to L2(Rollup 3) for $bridge_tx_hash_pp3" >&3
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$l1_rpc_network_id" "$bridge_tx_hash_pp3" "$rollup_3_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_3_url" "$l2_rpc_url_3"
    assert_success

    # DEPOSIT
    sender_private_key=$receiver1_private_key
    sender_addr=$receiver1_addr
    destination_addr=$receiver1_addr
    destination_net=$rollup_3_network_id
    amount="0.01ether"
    meta_bytes="0x"
    run bridge_asset "$native_token_addr" "$l2_rpc_url_1" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposit (settle it on the Rollup 3)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$rollup_1_network_id" "$bridge_tx_hash" "$rollup_3_network_id" "$l2_bridge_addr" "$aggkit_bridge_1_url" "$aggkit_bridge_3_url" "$l2_rpc_url_3"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_3_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_3_url"
    assert_success

    run wait_for_expected_token "$gas_token_rollup_1" "$rollup_3_network_id" 15 2 "$aggkit_bridge_3_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr
    origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$gas_token_rollup_1" "$origin_token_addr"

    local rollup3_wrapped_token_addr
    rollup3_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 Rollup 3 wrapped token address $rollup3_wrapped_token_addr"

    echo "==== 💰 Verifying balance on Rollup 3" >&3
    run verify_balance "$l2_rpc_url_3" "$rollup3_wrapped_token_addr" "$destination_addr" 0 "$amount"
    assert_success

    # DEPOSIT
    sender_private_key=$receiver1_private_key
    sender_addr=$receiver1_addr
    destination_addr=$receiver1_addr
    destination_net=$rollup_2_network_id
    amount="0.01ether"
    meta_bytes="0x"
    run bridge_asset "$rollup3_wrapped_token_addr" "$l2_rpc_url_3" "$l2_bridge_addr"
    assert_success
    local bridge_tx_hash=$output

    # Claim deposits (settle them on the Rollup 3)
    run process_bridge_claim "3bridge-e2e-3-chains: $LINENO" "$rollup_3_network_id" "$bridge_tx_hash" "$rollup_2_network_id" "$l2_bridge_addr" "$aggkit_bridge_3_url" "$aggkit_bridge_2_url" "$l2_rpc_url_2"
    assert_success
    local claim_global_index="$output"
    # Validate the bridge service get claims API
    echo "==== 💰 get_claim $claim_global_index :$LINENO" >&3
    run get_claim "$rollup_2_network_id" "$claim_global_index" 50 10 "$aggkit_bridge_2_url"
    assert_success

    run wait_for_expected_token "$gas_token_rollup_1" "$rollup_2_network_id" 15 2 "$aggkit_bridge_2_url"
    assert_success
    local token_mappings_result=$output

    local origin_token_addr
    origin_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].origin_token_address')
    assert_equal "$gas_token_rollup_1" "$origin_token_addr"

    local rollup2_wrapped_token_addr
    rollup2_wrapped_token_addr=$(echo "$token_mappings_result" | jq -r '.token_mappings[0].wrapped_token_address')
    log "🪙 Rollup 2 wrapped token address $rollup2_wrapped_token_addr"

    echo "==== 💰 Verifying balance on Rollup 2" >&3
    run verify_balance "$l2_rpc_url_2" "$rollup2_wrapped_token_addr" "$destination_addr" 0 "$amount"
    assert_success
}
