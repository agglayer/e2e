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
}

# bats file_tags=lxly,simple
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
