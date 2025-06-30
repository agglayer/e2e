#!/usr/bin/env bats

# Bridge Asset:Buggy from PP1 to PP2 targeting EOA
# The Buggy ERC20 contract will be used to mint all possible supply, then bridge, then remint (buggy) and bridge again (should fail)
setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}

    l1_private_key=${L1_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l1_bridge_addr=${L1_BRIDGE_ADDR:-"0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7"}

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    l2_bridge_addr=${L2_BRIDGE_ADDR:-"0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7"}

    bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"}
    l1_network_id=$(cast call  --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    l2_network_id=$(cast call  --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    claim_wait_duration=${CLAIM_WAIT_DURATION:-"10m"}
}

function deploy_buggy_erc20() {
    local rpc_url=$1
    local private_key=$2
    local eth_address=$3
    local bridge_address=$4
    echo "Deploying Buggy ERC20 - RPC: $rpc_url, Address: $eth_address, Bridge: $bridge_address" >&3

    salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    deterministic_deployer_addr="0x4e59b44847b379578588920ca78fbf26c0b4956c"
    erc20_buggy_bytecode=608060405234801561001057600080fd5b506040516109013803806109018339818101604052606081101561003357600080fd5b810190808051604051939291908464010000000082111561005357600080fd5b90830190602082018581111561006857600080fd5b825164010000000081118282018810171561008257600080fd5b82525081516020918201929091019080838360005b838110156100af578181015183820152602001610097565b50505050905090810190601f1680156100dc5780820380516001836020036101000a031916815260200191505b50604052602001805160405193929190846401000000008211156100ff57600080fd5b90830190602082018581111561011457600080fd5b825164010000000081118282018810171561012e57600080fd5b82525081516020918201929091019080838360005b8381101561015b578181015183820152602001610143565b50505050905090810190601f1680156101885780820380516001836020036101000a031916815260200191505b5060405260209081015185519093506101a792506003918601906101d8565b5081516101bb9060049060208501906101d8565b506005805460ff191660ff92909216919091179055506102799050565b828054600181600116156101000203166002900490600052602060002090601f01602090048101928261020e5760008555610254565b82601f1061022757805160ff1916838001178555610254565b82800160010185558215610254579182015b82811115610254578251825591602001919060010190610239565b50610260929150610264565b5090565b5b808211156102605760008155600101610265565b610679806102886000396000f3fe608060405234801561001057600080fd5b50600436106100b45760003560e01c806370a082311161007157806370a082311461021257806395d89b41146102385780639dc29fac14610240578063a9059cbb1461026c578063b46310f614610298578063dd62ed3e146102c4576100b4565b806306fdde03146100b9578063095ea7b31461013657806318160ddd1461017657806323b872dd14610190578063313ce567146101c657806340c10f19146101e4575b600080fd5b6100c16102f2565b6040805160208082528351818301528351919283929083019185019080838360005b838110156100fb5781810151838201526020016100e3565b50505050905090810190601f1680156101285780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6101626004803603604081101561014c57600080fd5b506001600160a01b038135169060200135610380565b604080519115158252519081900360200190f35b61017e6103e6565b60408051918252519081900360200190f35b610162600480360360608110156101a657600080fd5b506001600160a01b038135811691602081013590911690604001356103ec565b6101ce610466565b6040805160ff9092168252519081900360200190f35b610210600480360360408110156101fa57600080fd5b506001600160a01b03813516906020013561046f565b005b61017e6004803603602081101561022857600080fd5b50356001600160a01b031661047d565b6100c161048f565b6102106004803603604081101561025657600080fd5b506001600160a01b0381351690602001356104ea565b6101626004803603604081101561028257600080fd5b506001600160a01b0381351690602001356104f4565b610210600480360360408110156102ae57600080fd5b506001600160a01b03813516906020013561054f565b61017e600480360360408110156102da57600080fd5b506001600160a01b038135811691602001351661056b565b6003805460408051602060026001851615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103785780601f1061034d57610100808354040283529160200191610378565b820191906000526020600020905b81548152906001019060200180831161035b57829003601f168201915b505050505081565b3360008181526002602090815260408083206001600160a01b038716808552908352818420869055815186815291519394909390927f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925928290030190a350600192915050565b60005481565b6001600160a01b0380841660008181526002602090815260408083203384528252808320805487900390558383526001825280832080548790039055938616808352848320805487019055845186815294519294909392600080516020610624833981519152929181900390910190a35060019392505050565b60055460ff1681565b6104798282610588565b5050565b60016020526000908152604090205481565b6004805460408051602060026001851615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103785780601f1061034d57610100808354040283529160200191610378565b61047982826105d3565b336000818152600160209081526040808320805486900390556001600160a01b03861680845281842080548701905581518681529151939490939092600080516020610624833981519152928290030190a350600192915050565b6001600160a01b03909116600090815260016020526040902055565b600260209081526000928352604080842090915290825290205481565b6001600160a01b038216600081815260016020908152604080832080548601905582548501835580518581529051600080516020610624833981519152929181900390910190a35050565b6001600160a01b0382166000818152600160209081526040808320805486900390558254859003835580518581529051929392600080516020610624833981519152929181900390910190a3505056feddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa2646970667358221220364a383ccce0e270376267b8631412d1b7ddb1883c5379556b58cbefc1ca504564736f6c63430007060033
    
    # This contract is a weird ERC20 that has a infinite money glitch and allows for some bizarre testing
    constructor_args=$(cast abi-encode 'f(string,string,uint8)' 'Buggy ERC20' 'BUG' "18" | sed 's/0x//')
    test_erc20_buggy_addr=$(cast create2 --salt $salt --init-code $erc20_buggy_bytecode$constructor_args)
    echo "Calculated Buggy ERC20 address: $test_erc20_buggy_addr" >&3

    if [[ $(cast code --rpc-url "$rpc_url" "$test_erc20_buggy_addr") != "0x" ]]; then
        echo "The network on $rpc_url already has the Buggy ERC20 deployed. Skipping deployment..." >&3
    else
        echo "Deploying Buggy ERC20 to $rpc_url..." >&3
        cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" "$deterministic_deployer_addr" "$salt$erc20_buggy_bytecode$constructor_args"
        echo "Deployment transaction sent." >&3

        echo "Minting max uint tokens to $eth_address..." >&3
        cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" "$test_erc20_buggy_addr" 'mint(address,uint256)' "$eth_address" "$(cast max-uint)"
        echo "Minting completed." >&3

        echo "Approving max uint tokens for bridge $bridge_address..." >&3
        cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" "$test_erc20_buggy_addr" 'approve(address,uint256)' "$bridge_address" "$(cast max-uint)"
        echo "Approval completed." >&3
    fi
}

@test "bridge Buggy ERC20 from l1 to l2" {
    deploy_buggy_erc20 "$l1_rpc_url" "$l1_private_key" "$l1_eth_address" "$l1_bridge_addr"
    deploy_buggy_erc20 "$l2_rpc_url" "$l2_private_key" "$l2_eth_address" "$l2_bridge_addr"
    
    echo "Starting bridge test from L1 to L2..." >&3

    echo "Checking bridge contract allowance..." >&3
    allowance=$(cast call --rpc-url "$l1_rpc_url" "$test_erc20_buggy_addr" 'allowance(address,address)(uint256)' "$l1_eth_address" "$l1_bridge_addr")
    echo "Bridge allowance: $allowance" >&3

    echo "Minting L1 token..." >&3
    cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_eth_address" "$(cast max-uint)"

    echo "Checking L1 token balance before bridging..." >&3
    balance_before=$(cast call --rpc-url "$l1_rpc_url" "$test_erc20_buggy_addr" 'balanceOf(address)(uint256)' "$l1_eth_address")
    echo "L1 balance before: $balance_before" >&3

    echo "Zeroing out bridge contract balance..." >&3
    cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" "0"
    echo "Bridge contract balance zeroed." >&3

    echo "Initiating bridge operation..." >&3
    polycli ulxly bridge asset \
        --bridge-address "$l1_bridge_addr" \
        --destination-address "$l2_eth_address" \
        --destination-network "$l2_network_id" \
        --token-address "$test_erc20_buggy_addr" \
        --private-key "$l1_private_key" \
        --rpc-url "$l1_rpc_url" \
        --value $(cast max-uint)
    echo "Bridge operation transaction sent." >&3

    echo "Checking L1 token balance after bridging..." >&3
    balance_after=$(cast call --rpc-url "$l1_rpc_url" "$test_erc20_buggy_addr" 'balanceOf(address)(uint256)' "$l1_eth_address")
    echo "L1 balance after: $balance_after" >&3
}

@test "Claiming Buggy ERC20 from l1 to l2" {
    # It's possible this command will fail due to the auto claimer
    initial_deposit_count=$(curl -s $bridge_service_url/bridges/$l1_eth_address | jq '.deposits | map(select(.claim_tx_hash == "")) | min_by(.deposit_cnt) | .deposit_cnt')
    echo "Attempting to make bridge claim on $initial_deposit_count..." >&3
    run polycli ulxly claim asset \
        --bridge-address "$l2_bridge_addr" \
        --private-key "$l2_private_key" \
        --rpc-url "$l2_rpc_url" \
        --deposit-count "$initial_deposit_count" \
        --deposit-network "$l1_network_id" \
        --bridge-service-url "$bridge_service_url" \
        --wait "$claim_wait_duration"

    # Assert the command failed (non-zero exit status)
    [[ "$status" -ne 0 ]]
    
    # Assert the output contains the expected error message and data
    echo "$output" | grep -q '0x23d72133'
    [[ $? -eq 0 ]] || fail "Expected error '0x23d72133' not found in output: $output"
}
