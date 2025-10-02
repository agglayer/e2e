#!/usr/bin/env bats
# bats file_tags=lxly,bridge

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    export bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)"}
    export claim_wait_duration=${CLAIM_WAIT_DURATION:-"10m"}

    export erc20_token_name="e2e test"
    export erc20_token_symbol="E2E"

    load "$BATS_TEST_DIRNAME/../../core/helpers/scripts/bridging.bash"

    if [[ -n "$kurtosis_enclave_name" ]]; then
        # For real networks we don't want to fund the claim tx manager, its meant to be there already working :-)
        export claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
        fund_claim_tx_manager
    fi
}

setup() {
    load "$BATS_TEST_DIRNAME/../../core/helpers/scripts/bridging.bash"
}


# bats test_tags=regular
@test "bridge native eth from l1 to l2" {
    bridge_amount=$(date +%s)
    run polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$l2_network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount"

    if [[ $status -ne 0 ]]; then
        echo "Failed to bridge asset from L1 to L2" >&3
        echo "$output" >&3
        exit 1
    fi

    run polycli_bridge_asset_get_info "$output" "$l1_rpc_url" "$l1_bridge_addr"
    if [[ $status -ne 0 ]]; then
        echo "Failed to get deposit info" >&3
        echo "$output" >&3
        exit 1
    fi
    deposit_count=$(echo "$output" | jq -r '.depositCount')
    echo "Deposit on L1 successful, deposit count: $deposit_count" >&3

    # It's possible this command will fail due to the auto claimer
    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e

    echo "Claim on L2 successful" >&3

    # Bridge back to L1
    run polycli ulxly bridge asset \
            --bridge-address "$l2_bridge_addr" \
            --destination-address "$l1_eth_address" \
            --destination-network "$l1_network_id" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --value 1

    if [[ $status -ne 0 ]]; then
        echo "Failed to bridge asset from L2 to L1" >&3
        echo "$output" >&3
        exit 1
    fi

    run polycli_bridge_asset_get_info "$output" "$l2_rpc_url" "$l2_bridge_addr"
    if [[ $status -ne 0 ]]; then
        echo "Failed to get deposit info" >&3
        echo "$output" >&3
        exit 1
    fi
    deposit_count=$(echo "$output" | jq -r '.depositCount')
    echo "Deposit on L2 successful, deposit count: $deposit_count" >&3

    run polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$deposit_count" \
            --deposit-network "$l2_network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"

    if [[ $status -ne 0 ]]; then
        echo "Failed to claim asset on L1" >&3
        echo "$output" >&3
        exit 1
    fi

    echo "Claim on L1 successful" >&3
}

# bats test_tags=erc20
@test "bridge l2 originated token from L2 to L1 and back to L2" {
    salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    deterministic_deployer_addr=0x4e59b44847b379578588920ca78fbf26c0b4956c
    deterministic_deployer_code=$(cast code --rpc-url "$l2_rpc_url" "$deterministic_deployer_addr")

    if [[ $deterministic_deployer_code == "0x" ]]; then
        echo "ℹ️  Deploying missing proxy contract..."
        cast send --legacy --value 0.1ether --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" 0x3fab184622dc19b6109349b94811493bf2a45362
        cast publish --rpc-url "$l2_rpc_url" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
    fi

    erc_20_bytecode=$(cat $PROJECT_ROOT/core/contracts/bin/erc20permitmock.bin)
    constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' "$erc20_token_name" "$erc20_token_symbol" "$l2_eth_address" 100000000000000000000 | sed 's/0x//')
    test_erc20_addr=$(cast create2 --salt $salt --init-code "$erc_20_bytecode$constructor_args")

    if [[ $(cast code --rpc-url "$l2_rpc_url" "$test_erc20_addr") == "0x" ]]; then
        cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" "$deterministic_deployer_addr" "$salt$erc_20_bytecode$constructor_args"
        cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" "$test_erc20_addr" 'approve(address,uint256)' "$l2_bridge_addr" "$(cast max-uint)"
    fi

    bridge_amount=$(date +%s)
    # Bridge some funds from L2 to L1
    run polycli ulxly bridge asset \
            --destination-network 0 \
            --destination-address "$l1_eth_address" \
            --token-address  "$test_erc20_addr" \
            --value "$bridge_amount" \
            --bridge-address "$l2_bridge_addr" \
            --rpc-url "$l2_rpc_url" \
            --private-key "$l2_private_key"

    if [[ $status -ne 0 ]]; then
        echo "Failed to bridge asset from L2 to L1" >&3
        echo "$output" >&3
        exit 1
    fi

    run polycli_bridge_asset_get_info "$output" "$l2_rpc_url" "$l2_bridge_addr"
    if [[ $status -ne 0 ]]; then
        echo "Failed to get deposit info" >&3
        echo "$output" >&3
        exit 1
    fi
    deposit_count=$(echo "$output" | jq -r '.depositCount')
    echo "Deposit count: $deposit_count" >&3

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$deposit_count" \
            --deposit-network "$l2_network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"

    token_hash=$(cast keccak "$(cast abi-encode --packed 'f(uint32, address)' "$l2_network_id" "$test_erc20_addr")")
    wrapped_token_addr=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")

    run polycli ulxly bridge asset \
        --destination-network "$l2_network_id" \
        --destination-address "$l2_eth_address" \
        --token-address "$wrapped_token_addr" \
        --value "$bridge_amount" \
        --bridge-address "$l1_bridge_addr" \
        --rpc-url "$l1_rpc_url" \
        --private-key "$l1_private_key"

    if [[ $status -ne 0 ]]; then
        echo "Failed to bridge asset from L1 to L2" >&3
        echo "$output" >&3
        exit 1
    fi

    run polycli_bridge_asset_get_info "$output" "$l1_rpc_url" "$l1_bridge_addr"
    if [[ $status -ne 0 ]]; then
        echo "Failed to get deposit info" >&3
        echo "$output" >&3
        exit 1
    fi
    deposit_count=$(echo "$output" | jq -r '.depositCount')
    echo "Deposit count: $deposit_count" >&3

    # It's possible this command will fail due to the auto claimer
    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e

    # repeat the first step again to trigger another exit of l2 but with the added claim
    bridge_amount=$(date +%s)
    run polycli ulxly bridge asset \
            --destination-network 0 \
            --destination-address "$l1_eth_address" \
            --token-address  "$test_erc20_addr" \
            --value "$bridge_amount" \
            --bridge-address "$l2_bridge_addr" \
            --rpc-url "$l2_rpc_url" \
            --private-key "$l2_private_key"

    if [[ $status -ne 0 ]]; then
        echo "Failed to bridge asset from L2 to L1" >&3
        echo "$output" >&3
        exit 1
    fi

    run polycli_bridge_asset_get_info "$output" "$l2_rpc_url" "$l2_bridge_addr"
    if [[ $status -ne 0 ]]; then
        echo "Failed to get deposit info" >&3
        echo "$output" >&3
        exit 1
    fi
    deposit_count=$(echo "$output" | jq -r '.depositCount')
    echo "Deposit count: $deposit_count" >&3

    # Wait for that exit to settle on L1
    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$deposit_count" \
            --deposit-network "$l2_network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
}
