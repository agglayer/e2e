#!/usr/bin/env bats
# bats file_tags=lxly,multi-chain-bridge

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"
    l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    # l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l1_bridge_addr=${L1_BRIDGE_ADDR:-"0x78908F7A87d589fdB46bdd5EfE7892C5aD6001b6"}

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    
    # Multi-chain network configurations
    declare -A l2_rpc_urls=(
        ["network1"]="$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"
        ["network2"]="$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-002 rpc)"
        ["network3"]="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-003 rpc)"
        ["network4"]="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-004 rpc)"
        ["network5"]="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-005 rpc)"
    )
    
    declare -A bridge_service_urls=(
        ["network1"]="$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"
        ["network2"]="$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-002 rpc)"
        ["network3"]="$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-003 rpc)"
        ["network4"]="$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-004 rpc)"
        ["network5"]="$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-005 rpc)"
    )
    
    # Default to network1 for backward compatibility
    default_network=${NETWORK_TARGET:-"network1"}
    l2_rpc_url=${L2_RPC_URL:-"${l2_rpc_urls[$default_network]}"}
    l2_bridge_addr=${L2_BRIDGE_ADDR:-"0x78908F7A87d589fdB46bdd5EfE7892C5aD6001b6"}
    bridge_service_url=${BRIDGE_SERVICE_URL:-"${bridge_service_urls[$default_network]}"}
    
    network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    claim_wait_duration=${CLAIM_WAIT_DURATION:-"10m"}

    erc20_token_name="e2e test"
    erc20_token_symbol="E2E"

    fund_claim_tx_manager
}

function fund_claim_tx_manager() {
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

# Helper function to get network configuration
function get_network_config() {
    local network_name="$1"
    local config_type="$2"
    
    case $config_type in
        "rpc_url")
            case $network_name in
                "network1") echo "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)" ;;
                "network2") echo "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-002 rpc)" ;;
                "network3") echo "$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-003 rpc)" ;;
                "network4") echo "$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-004 rpc)" ;;
                "network5") echo "$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-005 rpc)" ;;
                *) echo "" ;;
            esac
            ;;
        "bridge_service_url")
            case $network_name in
                "network1") echo "$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)" ;;
                "network2") echo "$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-002 rpc)" ;;
                "network3") echo "$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-003 rpc)" ;;
                "network4") echo "$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-004 rpc)" ;;
                "network5") echo "$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-005 rpc)" ;;
                *) echo "" ;;
            esac
            ;;
    esac
}

# bats test_tags=bridge
@test "bridge native eth from l1 to l2 ("$NETWORK_TARGET")" {
    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    bridge_amount=$(date +%s)
    polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount"

    # It's possible this command will fail due to the auto claimer
    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e
}

# bats test_tags=bridge,transaction-erc20
@test "bridge l2 ("$NETWORK_TARGET") originated token from L2 to L1 and back to L2" {
    salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    deterministic_deployer_addr=0x4e59b44847b379578588920ca78fbf26c0b4956c
    deterministic_deployer_code=$(cast code --rpc-url "$l2_rpc_url" "$deterministic_deployer_addr")

    if [[ $deterministic_deployer_code == "0x" ]]; then
        echo "ℹ️  Deploying missing proxy contract..."
        cast send --legacy --value 0.1ether --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" 0x3fab184622dc19b6109349b94811493bf2a45362
        cast publish --rpc-url "$l2_rpc_url" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
    fi

    erc_20_bytecode=$(cat core/contracts/bin/erc20permitmock.bin)
    constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' "$erc20_token_name" "$erc20_token_symbol" "$l2_eth_address" 100000000000000000000 | sed 's/0x//')
    test_erc20_addr=$(cast create2 --salt $salt --init-code "$erc_20_bytecode$constructor_args")

    if [[ $(cast code --rpc-url "$l2_rpc_url" "$test_erc20_addr") == "0x" ]]; then
        cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" "$deterministic_deployer_addr" "$salt$erc_20_bytecode$constructor_args"
        cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$l2_private_key" "$test_erc20_addr" 'approve(address,uint256)' "$l2_bridge_addr" "$(cast max-uint)"
    fi

    initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
    bridge_amount=$(date +%s)
    # Bridge some funds from L2 to L1
    polycli ulxly bridge asset \
            --destination-network 0 \
            --token-address  "$test_erc20_addr" \
            --value "$bridge_amount" \
            --bridge-address "$l2_bridge_addr" \
            --rpc-url "$l2_rpc_url" \
            --private-key "$l2_private_key"

    deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')

    if [[ $initial_deposit_count -eq $deposit_count ]]; then
        echo "the deposit count didn't increase"
        exit 1
    fi

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"

    token_hash=$(cast keccak "$(cast abi-encode --packed 'f(uint32, address)' "$network_id" "$test_erc20_addr")")
    wrapped_token_addr=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")

    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    polycli ulxly bridge asset \
        --destination-network "$network_id" \
        --token-address "$wrapped_token_addr" \
        --value "$bridge_amount" \
        --bridge-address "$l1_bridge_addr" \
        --rpc-url "$l1_rpc_url" \
        --private-key "$l1_private_key"

    # It's possible this command will fail due to the auto claimer
    set +e
    polycli ulxly claim asset \
            --bridge-address "$l2_bridge_addr" \
            --private-key "$l2_private_key" \
            --rpc-url "$l2_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "0" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
    set -e

    # repeat the first step again to trigger another exit of l2 but with the added claim
    initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
    bridge_amount=$(date +%s)
    polycli ulxly bridge asset \
            --destination-network 0 \
            --token-address  "$test_erc20_addr" \
            --value "$bridge_amount" \
            --bridge-address "$l2_bridge_addr" \
            --rpc-url "$l2_rpc_url" \
            --private-key "$l2_private_key"

    # Wait for that exit to settle on L1
    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$network_id" \
            --bridge-service-url "$bridge_service_url" \
            --wait "$claim_wait_duration"
}

# # bats test_tags=bridge,multi-chain
# @test "cross-chain bridge between different L2 networks (source: network1, target:"$NETWORK_TARGET")" {
#     # Test bridging between network1 and network3
#     local source_network="network1"
#     local target_network="network3"
    
#     local source_rpc_url=$(get_network_config "$source_network" "rpc_url")
#     local target_rpc_url=$(get_network_config "$target_network" "rpc_url")
#     local source_bridge_service_url=$(get_network_config "$source_network" "bridge_service_url")
#     local target_bridge_service_url=$(get_network_config "$target_network" "bridge_service_url")
    
#     # Get network IDs
#     local source_network_id=$(cast call --rpc-url "$source_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
#     local target_network_id=$(cast call --rpc-url "$target_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    
#     echo "Bridging from network $source_network_id to network $target_network_id"
    
#     # Bridge from source to target network
#     local initial_deposit_count=$(cast call --rpc-url "$source_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
#     local bridge_amount=$(date +%s)
    
#     polycli ulxly bridge asset \
#             --destination-network "$target_network_id" \
#             --destination-address "$l2_eth_address" \
#             --bridge-address "$l2_bridge_addr" \
#             --rpc-url "$source_rpc_url" \
#             --private-key "$l2_private_key" \
#             --value "$bridge_amount"
    
#     # Claim on target network
#     set +e
#     polycli ulxly claim asset \
#             --bridge-address "$l2_bridge_addr" \
#             --private-key "$l2_private_key" \
#             --rpc-url "$target_rpc_url" \
#             --deposit-count "$initial_deposit_count" \
#             --deposit-network "$source_network_id" \
#             --bridge-service-url "$target_bridge_service_url" \
#             --wait "$claim_wait_duration"
#     set -e
# }