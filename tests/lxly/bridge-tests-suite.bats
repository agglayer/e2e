#!/usr/bin/env bats

setup() {
    # Define environment variables with defaults
    kurtosis_enclave_name="${ENCLAVE_NAME:-cdk}"
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url="${L1_RPC_URL:-http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)}"
    l1_bridge_addr="${L1_BRIDGE_ADDR:-0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7}"

    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url="${L2_RPC_URL:-$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc)}"
    l2_bridge_addr="${L2_BRIDGE_ADDR:-0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7}"

    bridge_service_url="${BRIDGE_SERVICE_URL:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)}"
    l1_network_id=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    l2_network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    claim_wait_duration="${CLAIM_WAIT_DURATION:-10m}"

    # Define contract addresses
    tester_contract_address="0xc54E34B55EF562FE82Ca858F70D1B73244e86388"
    test_erc20_buggy_addr="0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956"
    test_lxly_proxy_addr="0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191"
    test_erc20_addr="0x6E3AD1d922fe009dc3Eb267827004ccAA4f23f3d"
    pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')
    pol_address="0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E"
    gas_token_address="0x0000000000000000000000000000000000000000"

    # Load test scenarios from file
    scenarios=$(cat "./tests/lxly/assets/bridge-tests-suite.json")
    
    # Initialize arrays to store test commands, expected results, and deposit cache
    declare -A test_results
    declare -A deposits_cache
}

# Function to fetch unclaimed deposits with caching
fetch_unclaimed_deposits() {
    local dest_addr="$1"
    local cache_key="deposits_$dest_addr"
    
    # Check if we already have cached deposits for this address
    if [[ -n "${deposits_cache[$cache_key]:-}" ]]; then
        echo "Using cached deposits for address $dest_addr" >&3
        echo "${deposits_cache[$cache_key]}"
        return 0
    fi
    
    # Fetch deposits with retry logic
    local unclaimed_deposits=""
    for attempt in {1..5}; do
        echo "Attempt $attempt to fetch unclaimed deposits for address $dest_addr..." >&3
        local deposits_response=$(curl -s "$bridge_service_url/bridges/$dest_addr")
        unclaimed_deposits=$(echo "$deposits_response" | jq -c '.deposits | map(select(.claim_tx_hash == ""))')
        
        if [[ -n "$unclaimed_deposits" ]]; then
            # Cache the result
            deposits_cache[$cache_key]="$unclaimed_deposits"
            echo "$unclaimed_deposits"
            return 0
        fi
        
        echo "No unclaimed deposits found for address $dest_addr, retrying in 10 seconds..." >&3
        sleep 10
    done
    
    # Return empty if no deposits found after all attempts
    echo ""
    return 1
}

# Function to invalidate cache for a specific address (called after successful claims)
invalidate_deposits_cache() {
    local dest_addr="$1"
    local cache_key="deposits_$dest_addr"
    echo "Invalidating cache for address $dest_addr" >&3
    unset deposits_cache[$cache_key]
}

@test "Initial setup" {
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    load "./assets/bridge-tests-helper.bash"
    
    # Deploy contracts to L1
    deploy_buggy_erc20 "$l1_rpc_url" "$l1_private_key" "$l1_eth_address" "$l1_bridge_addr"
    deploy_test_erc20 "$l1_rpc_url" "$l1_private_key" "$l1_eth_address" "$l1_bridge_addr"
    deploy_lxly_proxy "$l1_rpc_url" "$l1_private_key" "$l1_bridge_addr"
    deploy_tester_contract "$l1_rpc_url" "$l1_private_key"

    # Deploy contracts to L2
    deploy_buggy_erc20 "$l2_rpc_url" "$l2_private_key" "$l2_eth_address" "$l2_bridge_addr"
    deploy_test_erc20 "$l2_rpc_url" "$l2_private_key" "$l2_eth_address" "$l2_bridge_addr"
    deploy_lxly_proxy "$l2_rpc_url" "$l2_private_key" "$l2_bridge_addr"
    deploy_tester_contract "$l2_rpc_url" "$l2_private_key"
}

@test "Process bridge scenarios" {
    echo "Starting Process bridge scenarios test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    index=0
    while read -r scenario; do
        echo "Processing scenario $index: $scenario" >&3
        
        # Extract scenario parameters
        test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        test_destination_address=$(echo "$scenario" | jq -r '.DestinationAddress')
        test_token=$(echo "$scenario" | jq -r '.Token')
        test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
        test_force_update=$(echo "$scenario" | jq -r '.ForceUpdate')
        test_amount=$(echo "$scenario" | jq -r '.Amount')
        expected_result_process=$(echo "$scenario" | jq -r '.ExpectedResultProcess')

        # Build base command
        test_command="polycli ulxly bridge"
        fixed_test_command_flags="--rpc-url $l1_rpc_url --destination-network $l2_network_id"

        # Set bridge type
        case "$test_bridge_type" in
            "Asset") test_command="$test_command asset" ;;
            "Message") test_command="$test_command message" ;;
            "Weth") test_command="$test_command weth" ;;
            *) echo "Unrecognized Bridge Type: $test_bridge_type" >&3; return 1 ;;
        esac
        
        test_command="$test_command $fixed_test_command_flags"

        # Set destination address
        case "$test_destination_address" in
            "Contract") test_command="$test_command --destination-address $l1_bridge_addr" ;;
            "Precompile") test_command="$test_command --destination-address 0x0000000000000000000000000000000000000004" ;;
            "EOA") test_command="$test_command --destination-address $l1_eth_address" ;;
            *) echo "Unrecognized Destination Address: $test_destination_address" >&3; return 1 ;;
        esac

        # Set token address
        case "$test_token" in
            "POL") test_command="$test_command --token-address $pol_address" ;;
            "LocalERC20") test_command="$test_command --token-address $test_erc20_addr" ;;
            "WETH") test_command="$test_command --token-address $pp_weth_address" ;;
            "Buggy") test_command="$test_command --token-address $test_erc20_buggy_addr" ;;
            "GasToken") test_command="$test_command --token-address $gas_token_address" ;;
            "NativeEther") test_command="$test_command --token-address 0x0000000000000000000000000000000000000000" ;;
            *) echo "Unrecognized Test Token: $test_token" >&3; return 1 ;;
        esac

        # Set metadata
        case "$test_meta_data" in
            "Random") test_command="$test_command --call-data $(date +%s | xxd -p)" ;;
            "0x") test_command="$test_command --call-data 0x" ;;
            "Huge")
                temp_file=$(mktemp)
                xxd -p /dev/zero | tr -d "\n" | head -c 97000 > "$temp_file"
                test_command="$test_command --call-data-file $temp_file"
                ;;
            "Max")
                temp_file=$(mktemp)
                xxd -p /dev/zero | tr -d "\n" | head -c 261569 > "$temp_file"
                test_command="$test_command --call-data-file $temp_file"
                ;;
            *) echo "Unrecognized Metadata: $test_meta_data" >&3; return 1 ;;
        esac

        # Set force update flag
        case "$test_force_update" in
            "True") test_command="$test_command --force-update-root=true" ;;
            "False") test_command="$test_command --force-update-root=false" ;;
            *) echo "Unrecognized Force Update: $test_force_update" >&3; return 1 ;;
        esac

        # Set amount/value
        case "$test_amount" in
            "0") test_command="$test_command --value 0" ;;
            "1") test_command="$test_command --value 1" ;;
            "Max")
                cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                    "$test_erc20_buggy_addr" 'mint(address,uint256)' "$l1_eth_address" "$(cast max-uint)"
                cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                    "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
                test_command="$test_command --value $(cast max-uint)"
                ;;
            "Random") test_command="$test_command --value $(date +%s)" ;;
            *) echo "Unrecognized Amount: $test_amount" >&3; return 1 ;;
        esac

        # Add final command parameters
        test_command="$test_command --bridge-address $l1_bridge_addr --private-key $l1_private_key"
        
        # Execute the test command
        echo "Running command: $test_command" >&3
        run $test_command
        
        # Validate result
        if [[ "$expected_result_process" == "Success" ]]; then
            [[ "$status" -eq 0 ]] || {
                echo "Test $index expected Success but failed: $test_command" >&3
                return 1
            }
        else
            [[ "$status" -ne 0 ]] || {
                echo "Test $index expected failure with '$expected_result_process' but succeeded: $test_command" >&3
                return 1
            }
        fi

        # Store test results for claim test
        test_results[$index]="$test_command|$expected_result_process|$(echo "$scenario" | jq -r '.ExpectedResultClaim')"
        echo "test_results[$index]=${test_results[$index]}" >&3
        
        # Clean up Max amount setup
        if [[ "$test_amount" = "Max" ]]; then
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
    
    echo "Final test_results contents:" >&3
    for key in "${!test_results[@]}"; do
        echo "test_results[$key]=${test_results[$key]}" >&3
    done
}

@test "Claim individual deposits on bridged network" {
    echo "Starting Claim individual deposits test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    # Load scenarios from JSON
    scenarios=$(cat "./tests/lxly/assets/bridge-tests-suite.json")

    # Process each scenario and try to match with an unclaimed deposit
    index=0
    while read -r scenario; do
        echo "Processing claim for scenario $index: $scenario" >&3
        
        # Extract scenario parameters
        test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        test_token=$(echo "$scenario" | jq -r '.Token')
        test_destination_address=$(echo "$scenario" | jq -r '.DestinationAddress')
        test_amount=$(echo "$scenario" | jq -r '.Amount')
        test_metadata=$(echo "$scenario" | jq -r '.MetaData')
        expected_result_claim=$(echo "$scenario" | jq -c '.ExpectedResultClaim')

        # Skip if no claim is expected
        if [[ "$expected_result_claim" == '"N/A"' ]]; then
            echo "Scenario $index expects no claim (N/A), skipping" >&3
            index=$((index + 1))
            continue
        fi

        # Map destination address
        case "$test_destination_address" in
            "Contract") expected_dest_addr="$l1_bridge_addr" ;;
            "Precompile") expected_dest_addr="0x0000000000000000000000000000000000000004" ;;
            "EOA") expected_dest_addr="$l1_eth_address" ;;
            *) echo "Unrecognized Destination Address: $test_destination_address" >&3; return 1 ;;
        esac

        # Map token address
        case "$test_token" in
            "POL") default_token_addr="$pol_address" ;;
            "LocalERC20") default_token_addr="$test_erc20_addr" ;;
            "WETH") default_token_addr="$pp_weth_address" ;;
            "Buggy") default_token_addr="$test_erc20_buggy_addr" ;;
            "GasToken") default_token_addr="$gas_token_address" ;;
            "NativeEther") default_token_addr="0x0000000000000000000000000000000000000000" ;;
            *) echo "Unrecognized Test Token: $test_token" >&3; return 1 ;;
        esac

        # Map amount
        case "$test_amount" in
            "0") expected_amount="0" ;;
            "1") expected_amount="1" ;;
            "Max") expected_amount=$(cast max-uint) ;;
            "Random") expected_amount=$(echo "${test_results[$index]}" | cut -d'|' -f4) ;;
            *) echo "Unrecognized Amount: $test_amount" >&3; return 1 ;;
        esac
        echo "test_results[$index]=${test_results[$index]}" >&3
        echo "Expected amount for scenario $index: $expected_amount" >&3

        # Set expected leaf_type based on BridgeType
        case "$test_bridge_type" in
            "Asset"|"Weth") expected_leaf_type="0" ;;
            "Message") expected_leaf_type="1" ;;
            *) echo "Unrecognized Bridge Type: $test_bridge_type" >&3; return 1 ;;
        esac
        echo "Expected leaf_type for scenario $index: $expected_leaf_type" >&3

        # Fetch deposits for the specific destination address using cache
        unclaimed_deposits=$(fetch_unclaimed_deposits "$expected_dest_addr")
        
        if [[ -z "$unclaimed_deposits" ]]; then
            echo "No unclaimed deposits found for address $expected_dest_addr in scenario $index" >&3
            echo "Expected: dest_addr=$expected_dest_addr, orig_addr=$default_token_addr, amount=$expected_amount, metadata=$test_metadata, leaf_type=$expected_leaf_type" >&3
            return 1
        fi

        # Find matching deposit
        matched_deposit=""
        while read -r deposit; do
            deposit_cnt=$(echo "$deposit" | jq -r '.deposit_cnt')
            deposit_dest_addr=$(echo "$deposit" | jq -r '.dest_addr')
            deposit_token_addr=$(echo "$deposit" | jq -r '.orig_addr')
            deposit_amount=$(echo "$deposit" | jq -r '.amount')
            deposit_metadata=$(echo "$deposit" | jq -r '.metadata')
            deposit_leaf_type=$(echo "$deposit" | jq -r '.leaf_type')

            # Check leaf_type consistency
            if [[ "$deposit_leaf_type" != "$expected_leaf_type" ]]; then
                echo "Leaf type mismatch for deposit $deposit_cnt: expected $expected_leaf_type for BridgeType $test_bridge_type, got $deposit_leaf_type" >&3
                continue
            fi

            # Set expected_token_addr based on leaf_type
            if [[ "$deposit_leaf_type" == "1" ]]; then
                expected_token_addr="$l1_eth_address"
                echo "Message bridge (leaf_type=1), using sender address $expected_token_addr for expected_token_addr" >&3
            else
                expected_token_addr="$default_token_addr"
                echo "Asset bridge (leaf_type=0), using token address $expected_token_addr for expected_token_addr" >&3
            fi

            # Match deposit to scenario
            if [[ "$deposit_dest_addr" == "$expected_dest_addr" && "$deposit_token_addr" == "$expected_token_addr" ]]; then
                # Skip amount check for Random
                if [[ "$test_amount" != "Random" && "$deposit_amount" != "$expected_amount" ]]; then
                    echo "Amount mismatch: expected $expected_amount, got $deposit_amount" >&3
                    continue
                fi
                
                # Handle metadata matching
                if [[ "$deposit_dest_addr" == "0x0000000000000000000000000000000000000004" ]]; then
                    # Skip metadata check for precompile address
                    matched_deposit="$deposit_cnt"
                    echo "Skipping metadata check for precompile address deposit $deposit_cnt" >&3
                    break
                elif [[ "$test_token" == "Buggy" && "$test_metadata" == "0x" ]]; then
                    # Skip metadata check for Buggy token with MetaData=0x
                    matched_deposit="$deposit_cnt"
                    echo "Skipping metadata check for Buggy token with MetaData=0x for deposit $deposit_cnt" >&3
                    break
                elif [[ "$test_metadata" == "0x" && "$deposit_token_addr" != "0x0000000000000000000000000000000000000000" ]]; then
                    # Skip metadata check for MetaData=0x when orig_addr is not zero
                    matched_deposit="$deposit_cnt"
                    echo "Skipping metadata check for MetaData=0x with non-zero orig_addr $deposit_token_addr for deposit $deposit_cnt" >&3
                    break
                elif [[ "$test_metadata" == "Huge" ]]; then
                    # Handle Huge metadata
                    expected_metadata_length=$((97000 + 2)) # 97,000 bytes + 0x
                    actual_metadata_length=${#deposit_metadata}
                    if [[ "$actual_metadata_length" -eq "$expected_metadata_length" && "$deposit_metadata" =~ ^0x0+$ ]]; then
                        matched_deposit="$deposit_cnt"
                        echo "Matched Huge metadata for deposit $deposit_cnt: length=$actual_metadata_length, all zeros" >&3
                        break
                    else
                        echo "Huge metadata mismatch: expected length=$expected_metadata_length, all zeros; got length=$actual_metadata_length, metadata=$deposit_metadata" >&3
                        continue
                    fi
                elif [[ "$test_metadata" == "Max" ]]; then
                    # Handle Max metadata
                    expected_metadata_length=$((261570))
                    actual_metadata_length=${#deposit_metadata}
                    if [[ "$actual_metadata_length" -eq "$expected_metadata_length" && "$deposit_metadata" =~ ^0x0+$ ]]; then
                        matched_deposit="$deposit_cnt"
                        echo "Matched Max metadata for deposit $deposit_cnt: length=$actual_metadata_length, all zeros" >&3
                        break
                    else
                        echo "Max metadata mismatch: expected length=$expected_metadata_length, all zeros; got length=$actual_metadata_length, metadata=$deposit_metadata" >&3
                        continue
                    fi
                elif [[ "$test_metadata" != "Random" && "$deposit_metadata" != "$test_metadata" ]]; then
                    # Standard metadata comparison for other cases
                    echo "Metadata mismatch: expected $test_metadata, got $deposit_metadata" >&3
                    continue
                else
                    matched_deposit="$deposit_cnt"
                    break
                fi
            fi
        done < <(echo "$unclaimed_deposits" | jq -c '.[]')

        if [[ -z "$matched_deposit" ]]; then
            echo "No matching unclaimed deposit found for scenario $index" >&3
            echo "Expected: dest_addr=$expected_dest_addr, orig_addr=$expected_token_addr, amount=$expected_amount, metadata=$test_metadata, leaf_type=$expected_leaf_type" >&3
            return 1
        fi

        echo "Matched deposit $matched_deposit for scenario $index" >&3

        # Construct the claim command
        case "$test_bridge_type" in
            "Asset"|"Weth") claim_command="polycli ulxly claim asset" ;;
            "Message") claim_command="polycli ulxly claim message" ;;
            *) echo "Unrecognized Bridge Type for claim: $test_bridge_type" >&3; return 1 ;;
        esac

        claim_command="$claim_command --destination-address $deposit_dest_addr --bridge-address $l2_bridge_addr --private-key $l2_private_key --rpc-url $l2_rpc_url --deposit-count $matched_deposit --deposit-network $l1_network_id --bridge-service-url $bridge_service_url --wait $claim_wait_duration"
        
        # Execute claim command
        output_file=$(mktemp)
        echo "Running command: $claim_command" >&3
        run $claim_command > "$output_file" 2>&3
        echo "Command output:" >&3
        cat "$output_file" >&3

        # Validate the claim result
        if [[ "$expected_result_claim" == '"Success"' ]]; then
            if [[ "$status" -ne 0 ]]; then
                if echo "$output" | grep -q "already been claimed"; then
                    echo "Deposit $matched_deposit already claimed, continuing" >&3
                    [[ -f "$output_file" ]] && rm "$output_file"
                    index=$((index + 1))
                    continue
                else
                    echo "Test $index expected Claim Success but failed for deposit $matched_deposit: $claim_command" >&3
                    [[ -f "$output_file" ]] && cat "$output_file" >&3
                    [[ -f "$output_file" ]] && rm "$output_file"
                    return 1
                fi
            else
                # Successful claim - invalidate cache for this address since deposit state changed
                invalidate_deposits_cache "$expected_dest_addr"
            fi
        else
            if [[ "$status" -eq 0 ]]; then
                echo "Test $index expected Claim failure but succeeded for deposit $matched_deposit: $claim_command" >&3
                [[ -f "$output_file" ]] && cat "$output_file" >&3
                [[ -f "$output_file" ]] && rm "$output_file"
                return 1
            fi
            
            # Check if expected_result_claim is an array or a single string
            if [[ "$expected_result_claim" =~ ^\[.*\]$ ]]; then
                # Handle array of expected results
                match_found=false
                while read -r expected_error; do
                    expected_error=$(echo "$expected_error" | jq -r '.') # Remove quotes
                    if [[ "$expected_error" =~ ^oversized\ data ]]; then
                        if echo "$output" | grep -q "oversized data: transaction size [0-9]\+, limit 131072"; then
                            match_found=true
                            break
                        fi
                    else
                        if echo "$output" | grep -q "$expected_error"; then
                            match_found=true
                            break
                        fi
                    fi
                done < <(echo "$expected_result_claim" | jq -c '.[]')
                
                if ! $match_found; then
                    echo "Test $index expected one of Claim errors $expected_result_claim not found in output for deposit $matched_deposit: $output" >&3
                    cat "$output_file" >&3
                    [[ -f "$output_file" ]] && rm "$output_file"
                    return 1
                fi
            else
                # Handle single expected error
                expected_error=$(echo "$expected_result_claim" | jq -r '.') # Remove quotes
                if [[ "$expected_error" =~ ^oversized\ data ]]; then
                    echo "$output" | grep -q "oversized data: transaction size [0-9]\+, limit 131072" || {
                        echo "Test $index expected Claim error pattern 'oversized data: transaction size [0-9]+, limit 131072' not found in output for deposit $matched_deposit: $output" >&3
                        cat "$output_file" >&3
                        [[ -f "$output_file" ]] && rm "$output_file"
                        return 1
                    }
                else
                    echo "$output" | grep -q "$expected_error" || {
                        echo "Test $index expected Claim error '$expected_error' not found in output for deposit $matched_deposit: $output" >&3
                        cat "$output_file" >&3
                        [[ -f "$output_file" ]] && rm "$output_file"
                        return 1
                    }
                fi
            fi
        fi

        [[ -f "$output_file" ]] && rm "$output_file"
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
}

@test "Run address tester actions" {
    address_tester_actions="001 011 021 031 101 201 301 401 501 601 701 801 901"
    
    for create_mode in 0 1 2; do
        for action in $address_tester_actions; do
            for rpc_url in $l1_rpc_url $l2_rpc_url; do
                for network_id in $l1_network_id $l2_network_id; do
                    # Select appropriate private key based on RPC URL
                    private_key_for_tx=$([[ "$rpc_url" = "$l1_rpc_url" ]] && echo "$l1_private_key" || echo "$l2_private_key")
                    
                    # Execute the tester action
                    run cast send \
                        --gas-limit 2500000 \
                        --legacy \
                        --value "$network_id" \
                        --rpc-url "$rpc_url" \
                        --private-key "$private_key_for_tx" \
                        "$tester_contract_address" \
                        "$(cast abi-encode 'f(uint32, address, uint256)' "0x${create_mode}${action}" "$test_lxly_proxy_addr" "$network_id")"
                    
                    [[ "$status" -eq 0 ]] || echo "Failed action: 0x${create_mode}${action} on $rpc_url with network $network_id"
                done
            done
        done
    done
}