#!/usr/bin/env bats
# bats file_tags=agglayer

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"}
    export bridge_service_url

    export network_id=$l2_network_id
    export claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    export claim_wait_duration=${CLAIM_WAIT_DURATION:-"10m"}

    agglayer_rpc_url=${AGGLAYER_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)"}
    export agglayer_rpc_url

    _fund_claim_tx_manager
}


_fund_claim_tx_manager() {
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

# bats test_tags=native-gas-token,bridge
@test "bridge native ETH from L1 to L2" {
    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')

    initial_l2_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    if [[ $gas_token_address != "0x0000000000000000000000000000000000000000" ]]; then
        initial_l2_balance=$(cast call --rpc-url "$l2_rpc_url" "$weth_address" "balanceOf(address)(uint256)" "$l2_eth_address")
    fi

    bridge_amount=$(cast to-wei 0.1)
    polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$l2_network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount" \
            --gas-limit 500000

    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e

    final_l2_balance=$(cast balance --rpc-url "$l2_rpc_url" "$l2_eth_address")
    if [[ $gas_token_address != "0x0000000000000000000000000000000000000000" ]]; then
        final_l2_balance=$(cast call --rpc-url "$l2_rpc_url" "$weth_address" "balanceOf(address)(uint256)" "$l2_eth_address")
    fi

    if [[ $initial_l2_balance == "$final_l2_balance" ]]; then
        echo "It looks like the bridge deposit to l2 was not synced correctly. The balance on L2 did not increase."
        exit 1
    fi
}

# bats test_tags=native-gas-token,bridge
@test "bridge native ETH from L2 to L1" {
    initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')
    initial_l1_balance=$(cast balance --rpc-url "$l1_rpc_url" "$l1_eth_address")

    bridge_amount=$(cast to-wei 0.05)
    polycli ulxly bridge asset \
            --bridge-address "$l2_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --destination-network 0 \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --value "$bridge_amount" \
            --token-address "$weth_address" \
            --gas-limit 500000

    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestPendingCertificateHeader "$l2_network_id" > "$tmp_file"

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$l2_network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"

    final_l1_balance=$(cast balance --rpc-url "$l1_rpc_url" "$l1_eth_address")
    if [[ $initial_l1_balance == "$final_l1_balance" ]]; then
        echo "It looks like the bridge deposit to l1 was not processed. The balance on L1 did not increase."
        exit 1
    fi
}

# bats test_tags=transaction-erc20,bridge
@test "bridge L2 originated ERC20 from L2 to L1" {
    dd_code=$(cast code --rpc-url "$l2_rpc_url" 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    if [[ $dd_code == "0x" ]]; then
       echo "The deterministict deployer address is empty"
       exit 1
    fi
    init_code=$(cat core/contracts/bin/erc20permitmock.bin)
    constructor_data=$(cast abi-encode 'f(string name, string symbol, address initAccount, uint256 initBalance)' "agglayer e2e" "e2e" "$l2_eth_address" 100000000000000000000)
    erc20_addr=$(cast create2 --salt "$(cast hz)" --init-code "$(cast concat-hex "$init_code" "$constructor_data" )")
    erc20_code=$(cast code --rpc-url "$l2_rpc_url" "$erc20_addr")
    if [[ $erc20_code == "0x" ]]; then
        cast send \
             --private-key "$l2_private_key" \
             --rpc-url "$l2_rpc_url" 0x4e59b44847b379578588920ca78fbf26c0b4956c \
             "$(cast concat-hex "$(cast hz)" "$init_code" "$constructor_data")"
    fi
    cast send \
         --private-key "$l2_private_key" \
         --rpc-url "$l2_rpc_url" "$erc20_addr" \
         "mint(address account, uint256 amount)" \
         "$l2_eth_address" 100000000000000000000

    cast send \
         --private-key "$l2_private_key" \
         --rpc-url "$l2_rpc_url" "$erc20_addr" \
         "approve(address spender, uint256 value)" \
         "$l2_bridge_addr" 100000000000000000000

    initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)' | awk '{print $1}')
    polycli ulxly bridge asset \
            --bridge-address "$l2_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --destination-network 0 \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --value "100" \
            --token-address "$erc20_addr"

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$l2_network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
}

# bats test_tags=agglayer-rpc
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

# bats test_tags=agglayer-rpc
@test "query interop_getLatestKnownCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$l2_network_id" > "$tmp_file"

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

# bats test_tags=agglayer-rpc
@test "query interop_getCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$l2_network_id" > "$tmp_file"

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

# bats test_tags=agglayer-rpc
@test "query interop_getTxStatus on agglayer RPC for latest settled certificate returns done" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$l2_network_id" > "$tmp_file"

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

# bats test_tags=agglayer-rpc
@test "query interop_getLatestPendingCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestPendingCertificateHeader "$l2_network_id" > "$tmp_file"

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

# bats test_tags=agglayer-rpc
@test "query interop_getLatestSettledCertificateHeader on agglayer RPC returns expected fields" {
    tmp_file=$(mktemp)
    cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$l2_network_id" > "$tmp_file"

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
