#!/usr/bin/env bats

setup() {
    L1_PRIVATE_KEY=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    L1_ETH_ADDRESS=$(cast wallet address --private-key "$L1_PRIVATE_KEY")
    L1_RPC_URL=${L1_RPC_URL:-"http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"}
    L1_BRIDGE_ADDR=${L1_BRIDGE_ADDR:-"0x83F138B325164b162b320F797b57f6f7E235ABAC"}

    L2_PRIVATE_KEY=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    L2_ETH_ADDRESS=$(cast wallet address --private-key "$L2_PRIVATE_KEY")
    L2_RPC_URL=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    L2_BRIDGE_ADDR=${L2_BRIDGE_ADDR:-"0x83F138B325164b162b320F797b57f6f7E235ABAC"}

    BRIDGE_SERVICE_URL=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    NETWORK_ID=$(cast call --rpc-url "$L2_RPC_URL" "$L2_BRIDGE_ADDR" 'networkID()(uint32)')
    CLAIMTXMANAGER_ADDR=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}

    ERC20_TOKEN_NAME="e2e test"
    ERC20_TOKEN_SYMBOL="E2E"

    fund_claim_tx_manager
}

function fund_claim_tx_manager() {
    local balance
    balance=$(cast balance --rpc-url "$L2_RPC_URL" "$CLAIMTXMANAGER_ADDR")
    
    if [[ "$balance" != "0" ]]; then
        return
    fi

    cast send --legacy --value 1ether \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$L2_PRIVATE_KEY" \
         "$CLAIMTXMANAGER_ADDR"
}

# bats file_tags=lxly,bridge
@test "bridge native eth from l1 to l2" {
    echo "$L2_RPC_URL"
    cast balance --rpc-url "$L2_RPC_URL" "$L2_ETH_ADDRESS"
    cast balance --rpc-url "$L1_RPC_URL" "$L1_ETH_ADDRESS"

    local bridge_amount
    bridge_amount=$(date +%s)

    polycli ulxly bridge asset \
            --bridge-address "$L1_BRIDGE_ADDR" \
            --destination-address "$L2_ETH_ADDRESS" \
            --destination-network "$NETWORK_ID" \
            --private-key "$L1_PRIVATE_KEY" \
            --rpc-url "$L1_RPC_URL" \
            --value "$bridge_amount"

    local deposit_file
    deposit_file=$(mktemp)

    local attempts=0
    while true; do
        if [[ "$attempts" -gt 20 ]]; then
            echo "❌ The bridge deposit wasn't claimed automatically after 20 checks"
            exit 1
        fi

        curl -s "$BRIDGE_SERVICE_URL/bridges/$L2_ETH_ADDRESS" | jq '.deposits[0]' > "$deposit_file"

        local deposit_amt deposit_ready deposit_claim_tx_hash
        deposit_amt=$(jq -r '.amount' "$deposit_file")
        deposit_ready=$(jq -r '.ready_for_claim' "$deposit_file")
        deposit_claim_tx_hash=$(jq -r '.claim_tx_hash' "$deposit_file")

        if [[ "$deposit_amt" -eq "$bridge_amount" && "$deposit_ready" == "true" && -n "$deposit_claim_tx_hash" ]]; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 5
    done
}


@test "bridge l2 originated token from L2 to L1 and back to L2" {
    local salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    local deterministic_deployer_addr="0x4e59b44847b379578588920ca78fbf26c0b4956c"
    local deterministic_deployer_code
    deterministic_deployer_code=$(cast code --rpc-url "$L2_RPC_URL" "$deterministic_deployer_addr")

    if [[ "$deterministic_deployer_code" == "0x" ]]; then
        echo "ℹ️  Deploying missing proxy contract..."
        cast send --legacy --value 0.1ether --rpc-url "$L2_RPC_URL" --private-key "$L2_PRIVATE_KEY" "0x3fab184622dc19b6109349b94811493bf2a45362"
        cast publish --rpc-url "$L2_RPC_URL" "0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
    fi

    local erc_20_bytecode
    erc_20_bytecode=$(cat core/contracts/bin/erc20permitmock.bin)
    local constructor_args
    constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' "$ERC20_TOKEN_NAME" "$ERC20_TOKEN_SYMBOL" "$L2_ETH_ADDRESS" 100000000000000000000 | sed 's/0x//')

    local test_erc20_addr
    test_erc20_addr=$(cast create2 --salt "$salt" --init-code "$erc_20_bytecode$constructor_args")

    if [[ "$(cast code --rpc-url "$L2_RPC_URL" "$test_erc20_addr")" == "0x" ]]; then
        cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_PRIVATE_KEY" "$deterministic_deployer_addr" "$salt$erc_20_bytecode$constructor_args"
        cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_PRIVATE_KEY" "$test_erc20_addr" 'approve(address,uint256)' "$L2_BRIDGE_ADDR" "$(cast max-uint)"
    fi

    local initial_deposit_count
    initial_deposit_count=$(cast call --rpc-url "$L2_RPC_URL" "$L2_BRIDGE_ADDR" 'depositCount()(uint256)')

    local bridge_amount
    bridge_amount=$(date +%s)

    # Bridge some funds from L2 to L1
    polycli ulxly bridge asset \
        --destination-network 0 \
        --token-address "$test_erc20_addr" \
        --value "$bridge_amount" \
        --bridge-address "$L2_BRIDGE_ADDR" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$L2_PRIVATE_KEY"

    local deposit_count
    deposit_count=$(cast call --rpc-url "$L2_RPC_URL" "$L2_BRIDGE_ADDR" 'depositCount()(uint256)')

    if [[ "$initial_deposit_count" -eq "$deposit_count" ]]; then
        echo "❌ The deposit count didn't increase"
        exit 1
    fi

    # Wait for that exit to settle on L1
    local deposit_file
    deposit_file=$(mktemp)
    local attempts=0
    while true; do
        if [[ "$attempts" -gt 20 ]]; then
            echo "❌ The deposit seems to be stuck after 20 attempts"
            exit 1
        fi

        curl -s "$BRIDGE_SERVICE_URL/bridge?net_id=$NETWORK_ID&deposit_cnt=$initial_deposit_count" | jq '.' | tee "$deposit_file"

        local deposit_amt deposit_ready
        deposit_amt=$(jq -r '.deposit.amount' "$deposit_file")
        deposit_ready=$(jq -r '.deposit.ready_for_claim' "$deposit_file")

        if [[ "$deposit_amt" -eq "$bridge_amount" && "$deposit_ready" == "true" ]]; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 30
    done

    polycli ulxly claim asset \
        --bridge-address "$L1_BRIDGE_ADDR" \
        --private-key "$L1_PRIVATE_KEY" \
        --rpc-url "$L1_RPC_URL" \
        --deposit-count "$initial_deposit_count" \
        --deposit-network "$NETWORK_ID" \
        --bridge-service-url "$BRIDGE_SERVICE_URL"

    local token_hash
    token_hash=$(cast keccak "$(cast abi-encode --packed 'f(uint32, address)' "$NETWORK_ID" "$test_erc20_addr")")

    local wrapped_token_addr
    wrapped_token_addr=$(cast call --rpc-url "$L1_RPC_URL" "$L1_BRIDGE_ADDR" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")

    initial_deposit_count=$(cast call --rpc-url "$L1_RPC_URL" "$L1_BRIDGE_ADDR" 'depositCount()(uint256)')

    polycli ulxly bridge asset \
        --destination-network "$NETWORK_ID" \
        --token-address "$wrapped_token_addr" \
        --value "$bridge_amount" \
        --bridge-address "$L1_BRIDGE_ADDR" \
        --rpc-url "$L1_RPC_URL" \
        --private-key "$L1_PRIVATE_KEY"

    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ "$attempts" -gt 20 ]]; then
            echo "❌ The deposit seems to be stuck after 20 attempts"
            exit 1
        fi

        curl -s "$BRIDGE_SERVICE_URL/bridge?net_id=0&deposit_cnt=$initial_deposit_count" | jq '.' | tee "$deposit_file"

        local deposit_claim_tx_hash
        deposit_amt=$(jq -r '.deposit.amount' "$deposit_file")
        deposit_ready=$(jq -r '.deposit.ready_for_claim' "$deposit_file")
        deposit_claim_tx_hash=$(jq -r '.deposit.claim_tx_hash' "$deposit_file")

        if [[ "$deposit_amt" -eq "$bridge_amount" && "$deposit_ready" == "true" && -n "$deposit_claim_tx_hash" ]]; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 30
    done

    # Repeat the first step again to trigger another exit of L2 but with the added claim
    initial_deposit_count=$(cast call --rpc-url "$L2_RPC_URL" "$L2_BRIDGE_ADDR" 'depositCount()(uint256)')
    bridge_amount=$(date +%s)

    polycli ulxly bridge asset \
        --destination-network 0 \
        --token-address "$test_erc20_addr" \
        --value "$bridge_amount" \
        --bridge-address "$L2_BRIDGE_ADDR" \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$L2_PRIVATE_KEY"

    # Wait for that exit to settle on L1
    deposit_file=$(mktemp)
    attempts=0
    while true; do
        if [[ "$attempts" -gt 20 ]]; then
            echo "❌ The deposit seems to be stuck after 20 attempts"
            exit 1
        fi

        curl -s "$BRIDGE_SERVICE_URL/bridge?net_id=$NETWORK_ID&deposit_cnt=$initial_deposit_count" | jq '.' | tee "$deposit_file"

        deposit_amt=$(jq -r '.deposit.amount' "$deposit_file")
        deposit_ready=$(jq -r '.deposit.ready_for_claim' "$deposit_file")

        if [[ "$deposit_amt" -eq "$bridge_amount" && "$deposit_ready" == "true" ]]; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 30
    done
}
