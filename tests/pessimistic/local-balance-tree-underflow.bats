#!/usr/bin/env bats
# bats file_tags=pessimistic

setup() {
    # Define Variables
    kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"cdk"}
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    admin_address=${ADMIN_ADDRESS:-"0xE34aaF64b29273B7D567FCFc40544c014EEe9970"}
    private_key=${PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    bridge_address=${BRIDGE_ADDRESS:-"0x9D86b4ec07d7e292F296Dad324b14C06F058a4f1"}
    bridge_manager_private_key=${BRIDGE_MANAGER_PRIVATE_KEY:-"0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
    claimtxmanager_addr=${CLAIMTXMANAGER_ADDR:-"0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"}
    deposit_count=$(( $(cast nonce "$claimtxmanager_addr" --rpc-url "$l2_rpc_url") + 2 ))
}

# bats file_tags=bridge,local-balance-tree
@test "trigger local balance tree underflow bridge revert" {
    # Deploy TokenWrapped ERC20 on L1 and capture output
    l1_deploy_output=$(forge create --broadcast --rpc-url "$l1_rpc_url" \
    --private-key "$private_key" \
    core/contracts/erc20sovereignbridge/TokenWrapped.sol:TokenWrapped \
    --constructor-args "L1 ERC20" "yeETH" 18)

    # Extract l1_token_address from output
    l1_token_address=$(echo "$l1_deploy_output" | grep "Deployed to:" | awk '{print $3}')

    # Deploy TokenWrapped ERC20 on L2 and capture output
    l2_deploy_output=$(forge create --broadcast --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)" \
    --private-key "$private_key" \
    core/contracts/erc20sovereignbridge/TokenWrapped.sol:TokenWrapped \
    --constructor-args "L2 Wrapped ERC20" "zETH" 18)

    # Extract l2_token_address from output
    l2_token_address=$(echo "$l2_deploy_output" | grep "Deployed to:" | awk '{print $3}')

    # Remap yeETH on L2 to the TokenWrapped ERC20
    echo "Remapping yeETH on L2 to TokenWrapped ERC20"
    cast send "$bridge_address" \
    "setMultipleSovereignTokenAddress(uint32[],address[],address[],bool[])" \
    "[0]" \
    "[$l1_token_address]" \
    "[$l2_token_address]" \
    "[false]" \
    --private-key "$bridge_manager_private_key" \
    --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"

    # Check tokenInfoToWrappedToken information
    echo "Query getTokenWrappedAddress(uint32,address)(address)"
    cast call "$bridge_address" "getTokenWrappedAddress(uint32,address)(address)" \
    "0" "$l1_token_address" \
    --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"

    # Check L1 and L2 Token addresses
    echo "L1 Token Address: $l1_token_address"
    echo "L2 Token Address: $l2_token_address"

    # Mint L1 ERC20 (yeETH)
    echo "Mint yeETH to address"
    cast send "$l1_token_address" "mint(address,uint256)" \
    "$admin_address" 10000000000 \
    --private-key "$private_key" \
    --rpc-url "$l1_rpc_url" \
    --quiet

    # Check balance of minted ERC20 on L1 (yeETH)
    echo "Check balance of yeETH on L1"
    cast call "$l1_token_address" "balanceOf(address)(uint256)" \
    "$admin_address" \
    --rpc-url "$l1_rpc_url"

    # Approve L1 bridge to send + increase Allowance
    echo "Calling approve() on the yeETH ERC20 contract to increase Allowance of the bridge address"
    cast send "$l1_token_address" "approve(address,uint256)" \
    "$bridge_address" "999999999999999999999999999999" \
    --rpc-url "$l1_rpc_url" \
    --private-key "$private_key" \
    --quiet

    # Approve L2 bridge to send + increase Allowance
    echo "Calling approve() on the zETH ERC20 contract to increase Allowance of the bridge address"
    cast send "$l2_token_address" "approve(address,uint256)" \
    "$bridge_address" "999999999999999999999999999999" \
    --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"\
    --private-key "$private_key" \
    --quiet

    # Bridge Native ETH from L1 -> L2
    echo "Bridging Native ETH from L1 -> L2"
    polycli ulxly bridge asset \
        --bridge-address "$bridge_address" \
        --destination-network 1 \
        --destination-address "$admin_address" \
        --private-key "$private_key" \
        --rpc-url "$l1_rpc_url" \
        --value 20000000000

    # Bridge yeETH from L1 -> L2
    echo "Bridging yeETH from L1 -> remapped L2 TokenWrapped"
    polycli ulxly bridge asset \
        --bridge-address "$bridge_address" \
        --destination-network 1 \
        --private-key "$private_key" \
        --rpc-url "$l1_rpc_url" \
        --value 10000000000 \
        --token-address "$l1_token_address"

    # Claim bridged yeETH which has been remapped to zETH (TokenWrapped)
    echo "Claiming bridged yeETH on L2 as zETH"
    polycli ulxly claim asset \
        --bridge-address "$bridge_address" \
        --bridge-service-url"$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)"\
        --deposit-count "$deposit_count" \
        --destination-address "$admin_address" \
        --deposit-network 0 \
        --private-key "$private_key" \
        --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"\
        --wait 25s

    # Check zETH balance before
    echo "Check zETH balance before converting"
    cast call "$l2_token_address" "balanceOf(address)(uint256)" "$admin_address" \
    --rpc-url"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"

    # Convert L2 Native ETH to zETH
    echo "Convert L2 Native ETH to zETH"
    echo "Mint zETH"
    cast send "$l2_token_address" "mint(address,uint256)" \
    "$admin_address" "10000000000" \
    --private-key "$private_key" \
    --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"\
    --quiet
    echo "Burn native ETH"
    cast send "$(cast az)" \
    --value "10000000000" \
    --private-key "$private_key" \
    --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"\
    --quiet

    # Check zETH balance after
    echo "Check zETH balance after converting"
    cast call "$l2_token_address" "balanceOf(address)(uint256)" "$admin_address" \
    --rpc-url"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"

    echo "Check nativeETH balance after converting"
    cast balance "$admin_address" \
    --rpc-url"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"

    # Try to exit with 2x zETH (1 from yeETH, another from L2 conversion)
    echo "Try to exit 2x zETH - this should revert on the bridge"
    run polycli ulxly bridge asset \
        --bridge-address "$bridge_address" \
        --destination-network 0 \
        --private-key "$private_key" \
        --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)" \
        --value 20000000000 \
        --token-address "$l2_token_address"

    # Check non-zero exit status
    if [[ "$status" -eq 0 ]]; then
        echo "Error: Command succeeded unexpectedly: $status" >&3
        return 1
    fi

    # Check for the revert code in the output
    if ! echo "$output" | grep -q "0x14603c01"; then
        echo "Error: $output" >&3
        return 1
    fi

    echo "Test passed: Command failed with expected revert code 0x14603c01" >&3
}