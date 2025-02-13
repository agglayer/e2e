#!/usr/bin/env bats

setup() {
    l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l1_eth_address=$(cast wallet address --private-key $l1_private_key)
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"}
    l1_bridge_addr=${L1_BRIDGE_ADDR:-"0x83F138B325164b162b320F797b57f6f7E235ABAC"}

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_eth_address=$(cast wallet address --private-key $l2_private_key)
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    l2_bridge_addr=${L2_BRIDGE_ADDR:-"0x83F138B325164b162b320F797b57f6f7E235ABAC"}

    bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    network_id=$(cast call  --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')

    erc20_token_name="e2e test"
    erc20_token_symbol="E2E"
}

# bats file_tags=lxly,bridge
@test "bridge native eth from l1 to l2" {
    echo $l2_rpc_url
    cast balance --rpc-url $l2_rpc_url $l2_eth_address
    cast balance --rpc-url $l1_rpc_url $l1_eth_address

    bridge_amount=$(date +%s)
    polycli ulxly bridge asset \
            --bridge-address "$l1_bridge_addr" \
            --destination-address "$l2_eth_address" \
            --destination-network "$network_id" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --value "$bridge_amount"

    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ $attempts -gt 20 ]]; then
            echo "The bridge deposit wasn't claimed automatically after 20 checks"
            exit 1
        fi
        curl -s $bridge_service_url/bridges/$l2_eth_address | jq '.deposits[0]' > $deposit_file

        deposit_amt=$(jq -r '.amount' $deposit_file)
        deposit_ready=$(jq -r '.ready_for_claim' $deposit_file)
        deposit_claim_tx_hash=$(jq -r '.claim_tx_hash' $deposit_file)
        if [[ $deposit_amt -eq $bridge_amount && $deposit_ready == "true" && $deposit_claim_tx_hash != "" ]]; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 5
    done
}

# bats test_tags=heavy
@test "bridge l2 originated token from L2 to L1 and back to L2" {
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
    test_erc20_addr=$(cast create2 --salt $salt --init-code $erc_20_bytecode$constructor_args)

    if [[ $(cast code --rpc-url $l2_rpc_url $test_erc20_addr) == "0x" ]]; then
        cast send --legacy --rpc-url $l2_rpc_url --private-key $l2_private_key $deterministic_deployer_addr $salt$erc_20_bytecode$constructor_args
        cast send --legacy --rpc-url $l2_rpc_url --private-key $l2_private_key $test_erc20_addr 'approve(address,uint256)' $l2_bridge_addr $(cast max-uint)
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

    if [[ $initial_deposit_count -eq $depositCount ]]; then
        echo "the deposit count didn't increase"
        exit 1
    fi

    # Wait for that exit to settle on L1
    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ $attempts -gt 20 ]]; then
            echo "the deposit seems to be stuck after 20 attempts"
            exit 1
        fi
        curl -s "$bridge_service_url/bridge?net_id=$network_id&deposit_cnt=$initial_deposit_count" | jq '.' | tee $deposit_file

        deposit_amt=$(jq -r '.deposit.amount' $deposit_file)
        deposit_ready=$(jq -r '.deposit.ready_for_claim' $deposit_file)
        if [[ $deposit_amt -eq $bridge_amount && $deposit_ready == "true" ]]; then
            break
        fi
        attempts=$((attempts+1))
        sleep 10
    done

    polycli ulxly claim asset \
            --bridge-address "$l1_bridge_addr" \
            --private-key "$l1_private_key" \
            --rpc-url "$l1_rpc_url" \
            --deposit-count "$initial_deposit_count" \
            --deposit-network "$network_id" \
            --bridge-service-url "$bridge_service_url"

    token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32, address)' "$network_id" "$test_erc20_addr"))
    wrapped_token_addr=$(cast call --rpc-url $l1_rpc_url "$l1_bridge_addr" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")

    initial_deposit_count=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'depositCount()(uint256)')

    polycli ulxly bridge asset \
        --destination-network "$network_id" \
        --token-address "$wrapped_token_addr" \
        --value "$bridge_amount" \
        --bridge-address "$l1_bridge_addr" \
        --rpc-url "$l1_rpc_url" \
        --private-key "$l1_private_key"

    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ $attempts -gt 20 ]]; then
            echo "the deposit seems to be stuck after 20 attempts"
            exit 1
        fi
        curl -s "$bridge_service_url/bridge?net_id=0&deposit_cnt=$initial_deposit_count" | jq '.' | tee $deposit_file

        deposit_amt=$(jq -r '.deposit.amount' $deposit_file)
        deposit_ready=$(jq -r '.deposit.ready_for_claim' $deposit_file)
        deposit_claim_tx_hash=$(jq -r '.deposit.claim_tx_hash' $deposit_file)
        if [[ $deposit_amt -eq $bridge_amount && $deposit_ready == "true" && $deposit_claim_tx_hash != "" ]]; then
            break
        fi
        attempts=$((attempts+1))
        sleep 10
    done

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
    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ $attempts -gt 20 ]]; then
            echo "the deposit seems to be stuck after 20 attempts"
            exit 1
        fi
        curl -s "$bridge_service_url/bridge?net_id=$network_id&deposit_cnt=$initial_deposit_count" | jq '.' | tee $deposit_file

        deposit_amt=$(jq -r '.deposit.amount' $deposit_file)
        deposit_ready=$(jq -r '.deposit.ready_for_claim' $deposit_file)
        if [[ $deposit_amt -eq $bridge_amount && $deposit_ready == "true" ]]; then
            break
        fi
        attempts=$((attempts+1))
        sleep 10
    done

}

