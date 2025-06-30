#!/usr/bin/env bats

setup() {
    # Define environment variables with defaults
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url="${L1_RPC_URL:-http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)}"
    l1_bridge_addr="${L1_BRIDGE_ADDR:-0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7}"

    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url="${L2_RPC_URL:-$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)}"
    l2_bridge_addr="${L2_BRIDGE_ADDR:-0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7}"

    bridge_service_url="${BRIDGE_SERVICE_URL:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)}"
    l1_network_id=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    l2_network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    claimtxmanager_addr="${CLAIMTXMANAGER_ADDR:-0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8}"
    claim_wait_duration="${CLAIM_WAIT_DURATION:-10m}"

    # Define constants
    tester_contract_address="0xc54E34B55EF562FE82Ca858F70D1B73244e86388"
    test_erc20_buggy_addr="0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956"
    test_lxly_proxy_addr="0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191"
    test_erc20_addr="0x6E3AD1d922fe009dc3Eb267827004ccAA4f23f3d"
    pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')

    pol_address="0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E"
    gas_token_address="0x0000000000000000000000000000000000000000"

    token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $gas_token_address))
    l2_gas_token_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'tokenInfoToWrappedToken(bytes32)(address)' "$token_hash")

    # Load test scenarios from file
    scenarios=$(cat "./tests/lxly/assets/bridge-tests-suite.json")
    
    # Initialize array to store test commands and expected results
    declare -A test_results
}

@test "Initial setup" {
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || skip "Bridge Tests Suite file not found"

    load "./assets/bridge-tests-helper.bash"
    # Deploy to L1
    deploy_buggy_erc20 "$l1_rpc_url" "$l1_private_key" "$l1_eth_address" "$l1_bridge_addr"
    deploy_test_erc20 "$l1_rpc_url" "$l1_private_key" "$l1_eth_address" "$l1_bridge_addr"
    deploy_lxly_proxy "$l1_rpc_url" "$l1_private_key" "$l1_bridge_addr"
    deploy_tester_contract "$l1_rpc_url" "$l1_private_key"

    # Deploy to L2
    deploy_buggy_erc20 "$l2_rpc_url" "$l2_private_key" "$l2_eth_address" "$l2_bridge_addr"
    deploy_test_erc20 "$l2_rpc_url" "$l2_private_key" "$l2_eth_address" "$l2_bridge_addr"
    deploy_lxly_proxy "$l2_rpc_url" "$l2_private_key" "$l2_bridge_addr"
    deploy_tester_contract "$l2_rpc_url" "$l2_private_key"
}

@test "Process bridge scenarios" {
    while read -r scenario; do
        testBridgeType=$(echo "$scenario" | jq -r '.BridgeType')
        testDestinationAddress=$(echo "$scenario" | jq -r '.DestinationAddress')
        testToken=$(echo "$scenario" | jq -r '.Token')
        testMetaData=$(echo "$scenario" | jq -r '.MetaData')
        testForceUpdate=$(echo "$scenario" | jq -r '.ForceUpdate')
        testAmount=$(echo "$scenario" | jq -r '.Amount')
        expectedResultProcess=$(echo "$scenario" | jq -r '.ExpectedResultProcess')
        # expectedResultClaim=$(echo "$scenario" | jq -r '.ExpectedResultClaim')


        # l1_rpc_url refers to one network - not necessarily an L1. This can be changed to allow LxLy bridging.
        testCommand="polycli ulxly bridge"

        # Bridge Type
        case "$testBridgeType" in
        "Asset") testCommand="$testCommand asset" ;;
        "Message") testCommand="$testCommand message" ;;
        "Weth") testCommand="$testCommand weth" ;;
        *) echo "Unrecognized Bridge Type: $testBridgeType"; return 1 ;;
        esac
        
        fixedTestCommandFlags="--rpc-url $l1_rpc_url --destination-network $l2_network_id"
        testCommand="$testCommand $fixedTestCommandFlags"

        # Destination Address
        case "$testDestinationAddress" in
        "Contract") testCommand="$testCommand --destination-address $l1_bridge_addr" ;;
        "Precompile") testCommand="$testCommand --destination-address 0x0000000000000000000000000000000000000004" ;;
        "EOA") testCommand="$testCommand --destination-address $l1_eth_address" ;;
        *) echo "Unrecognized Destination Address: $testDestinationAddress"; return 1 ;;
        esac

        # Token
        case "$testToken" in
        "POL") testCommand="$testCommand --token-address $pol_address" ;;
        "LocalERC20") testCommand="$testCommand --token-address $test_erc20_addr" ;;
        "WETH") testCommand="$testCommand --token-address $pp_weth_address" ;;
        "Buggy") testCommand="$testCommand --token-address $test_erc20_buggy_addr" ;;
        "GasToken") testCommand="$testCommand --token-address $gas_token_address" ;;
        "NativeEther") testCommand="$testCommand --token-address 0x0000000000000000000000000000000000000000" ;;
        *) echo "Unrecognized Test Token: $testToken"; return 1 ;;
        esac

        # Metadata
        case "$testMetaData" in
        "Random") testCommand="$testCommand --call-data $(date +%s | xxd -p)" ;;
        "0x") testCommand="$testCommand --call-data 0x" ;;
        "Huge")
            temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 97000 > "$temp_file"
            testCommand="$testCommand --call-data-file $temp_file" ;;
        "Max")
            temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 261569 > "$temp_file"
            testCommand="$testCommand --call-data-file $temp_file" ;;
        *) echo "Unrecognized Metadata: $testMetaData"; return 1 ;;
        esac

        # Force Update
        case "$testForceUpdate" in
        "True") testCommand="$testCommand --force-update-root=true" ;;
        "False") testCommand="$testCommand --force-update-root=false" ;;
        *) echo "Unrecognized Force Update: $testForceUpdate"; return 1 ;;
        esac

        # Amount
        case "$testAmount" in
        "0") testCommand="$testCommand --value 0" ;;
        "1") testCommand="$testCommand --value 1" ;;
        "Max")
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'mint(address,uint256)' "$l1_eth_address" "$(cast max-uint)"
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
            testCommand="$testCommand --value $(cast max-uint)" ;;
        "Random") testCommand="$testCommand --value $(date +%s)" ;;
        *) echo "Unrecognized Amount: $testAmount"; return 1 ;;
        esac

        testCommand="$testCommand --bridge-address $l1_bridge_addr --private-key $l1_private_key"
        echo "Running command: $testCommand" >&3
        run $testCommand
        if [[ "$expectedResultProcess" == "Success" ]]; then
            [[ "$status" -eq 0 ]] || { echo "Test $index expected Success but failed: $testCommand"; return 1; }
        else
            [[ "$status" -ne 0 ]] || { echo "Test $index expected failure with '$expectedResultProcess' but succeeded: $testCommand"; return 1; }
            # Optionally, check if error matches expectedResultProcess
            # error_message=$(echo "$output" | parse_error_message) # Implement based on polycli output
            # [[ "$error_message" =~ "$expectedResultProcess" ]] || { echo "Test $index expected error '$expectedResultProcess' but got '$error_message'"; return 1; }
        fi

        # Store test command and expected results for claim test
        test_results[$index]="$testCommand|$expectedResultProcess|$(echo "$scenario" | jq -r '.ExpectedResultClaim')"
        
        if [[ "$testAmount" = "Max" ]]; then
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
        fi
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
}

@test "Run address tester actions" {
  address_tester_actions="001 011 021 031 101 201 301 401 501 601 701 801 901"
  for create_mode in 0 1 2; do
    for action in $address_tester_actions; do
      for rpc_url in $l1_rpc_url $l2_rpc_url; do
        for network_id in $l1_network_id $l2_network_id; do
          private_key_for_tx=$([[ "$rpc_url" = "$l1_rpc_url" ]] && echo "$l1_private_key" || echo "$l2_private_key")
          run cast send --gas-limit 2500000 --legacy --value "$network_id" --rpc-url "$rpc_url" --private-key "$private_key_for_tx" "$tester_contract_address" \
            "$(cast abi-encode 'f(uint32, address, uint256)' "0x${create_mode}${action}" "$test_lxly_proxy_addr" "$network_id")"
          [[ "$status" -eq 0 ]] || echo "Failed action: 0x${create_mode}${action} on $rpc_url with network $network_id"
        done
      done
    done
  done
}

@test "Claim individual deposits on bridged network" {
    index=0
    for key in "${!test_results[@]}"; do
        IFS='|' read -r cmd expected_result_process expected_result_claim <<< "${test_results[$key]}"
        scenario=$(echo "$scenarios" | jq -c ".[$index]")
        testBridgeType=$(echo "$scenario" | jq -r '.BridgeType')
        testToken=$(echo "$scenario" | jq -r '.Token')

        # Determine the destination network and corresponding RPC URL, private key, and bridge address
        dest_rpc_url="$l2_rpc_url"
        dest_private_key="$l2_private_key"
        dest_bridge_addr="$l2_bridge_addr"
        dest_network_id="$l1_network_id" # Claiming on L2 for deposits from L1

        # Fetch the deposit count for the address
        initial_deposit_count=$(curl -s "$bridge_service_url/bridges/$l1_eth_address" | jq '.deposits | map(select(.claim_tx_hash == "")) | min_by(.deposit_cnt) | .deposit_cnt')
        echo "Attempting to make bridge claim for deposit $initial_deposit_count on index $index..." >&3

        # Construct the claim command based on BridgeType
        case "$testBridgeType" in
            "Asset"|"Weth")
                claim_command="polycli ulxly claim asset"
                ;;
            "Message")
                claim_command="polycli ulxly claim message"
                ;;
            *)
                echo "Unrecognized Bridge Type for claim: $testBridgeType"; return 1
                ;;
        esac

        # Add common flags to the claim command
        claim_command="$claim_command --bridge-address $dest_bridge_addr --private-key $dest_private_key --rpc-url $dest_rpc_url --deposit-count $initial_deposit_count --deposit-network $dest_network_id --bridge-service-url $bridge_service_url --wait $claim_wait_duration"

        # Execute the claim command
        output_file=$(mktemp)
        run $claim_command > "$output_file" 2>&1

        # Check the claim result against expected_result_claim
        if [[ "$expected_result_claim" == "Success" ]]; then
            [[ "$status" -eq 0 ]] || { echo "Test $index expected Claim Success but failed: $claim_command"; cat "$output_file"; rm "$output_file"; return 1; }
        else
            [[ "$status" -ne 0 ]] || { echo "Test $index expected Claim failure with '$expected_result_claim' but succeeded: $claim_command"; cat "$output_file"; rm "$output_file"; return 1; }
            # Check if the error message matches the expected error
            if [[ "$expected_result_claim" != "N/A" ]]; then
                echo "$output" | grep -q "$expected_result_claim" || { echo "Test $index expected Claim error '$expected_result_claim' not found in output: $output"; cat "$output_file"; rm "$output_file"; return 1; }
            fi
        fi

        rm "$output_file"
        index=$((index + 1))
    done
}