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
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || { echo "Bridge Tests Suite file not found" >&3; skip "Bridge Tests Suite file not found"; }

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
    echo "Starting Process bridge scenarios test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || { echo "Bridge Tests Suite file not found" >&3; skip "Bridge Tests Suite file not found"; }

    index=0
    while read -r scenario; do
        echo "Processing scenario $index: $scenario" >&3
        test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        test_destination_adress=$(echo "$scenario" | jq -r '.DestinationAddress')
        test_token=$(echo "$scenario" | jq -r '.Token')
        test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
        test_force_update=$(echo "$scenario" | jq -r '.ForceUpdate')
        test_amount=$(echo "$scenario" | jq -r '.Amount')
        expected_result_process=$(echo "$scenario" | jq -r '.ExpectedResultProcess')

        test_command="polycli ulxly bridge"

        # Bridge Type
        case "$test_bridge_type" in
        "Asset") test_command="$test_command asset" ;;
        "Message") test_command="$test_command message" ;;
        "Weth") test_command="$test_command weth" ;;
        *) echo "Unrecognized Bridge Type: $test_bridge_type" >&3; return 1 ;;
        esac
        
        fixedTestCommandFlags="--rpc-url $l1_rpc_url --destination-network $l2_network_id"
        test_command="$test_command $fixedTestCommandFlags"

        # Destination Address
        case "$test_destination_adress" in
        "Contract") test_command="$test_command --destination-address $l1_bridge_addr" ;;
        "Precompile") test_command="$test_command --destination-address 0x0000000000000000000000000000000000000004" ;;
        "EOA") test_command="$test_command --destination-address $l1_eth_address" ;;
        *) echo "Unrecognized Destination Address: $test_destination_adress" >&3; return 1 ;;
        esac

        # Token
        case "$test_token" in
        "POL") test_command="$test_command --token-address $pol_address" ;;
        "LocalERC20") test_command="$test_command --token-address $test_erc20_addr" ;;
        "WETH") test_command="$test_command --token-address $pp_weth_address" ;;
        "Buggy") test_command="$test_command --token-address $test_erc20_buggy_addr" ;;
        "GasToken") test_command="$test_command --token-address $gas_token_address" ;;
        "NativeEther") test_command="$test_command --token-address 0x0000000000000000000000000000000000000000" ;;
        *) echo "Unrecognized Test Token: $test_token" >&3; return 1 ;;
        esac

        # Metadata
        case "$test_meta_data" in
        "Random") test_command="$test_command --call-data $(date +%s | xxd -p)" ;;
        "0x") test_command="$test_command --call-data 0x" ;;
        "Huge")
            temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 97000 > "$temp_file"
            test_command="$test_command --call-data-file $temp_file" ;;
        "Max")
            temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 261569 > "$temp_file"
            test_command="$test_command --call-data-file $temp_file" ;;
        *) echo "Unrecognized Metadata: $test_meta_data" >&3; return 1 ;;
        esac

        # Force Update
        case "$test_force_update" in
        "True") test_command="$test_command --force-update-root=true" ;;
        "False") test_command="$test_command --force-update-root=false" ;;
        *) echo "Unrecognized Force Update: $test_force_update" >&3; return 1 ;;
        esac

        # Amount
        case "$test_amount" in
        "0") test_command="$test_command --value 0" ;;
        "1") test_command="$test_command --value 1" ;;
        "Max")
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'mint(address,uint256)' "$l1_eth_address" "$(cast max-uint)"
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
            test_command="$test_command --value $(cast max-uint)" ;;
        "Random") test_command="$test_command --value $(date +%s)" ;;
        *) echo "Unrecognized Amount: $test_amount" >&3; return 1 ;;
        esac

        test_command="$test_command --bridge-address $l1_bridge_addr --private-key $l1_private_key"
        echo "Running command: $test_command" >&3
        run $test_command
        if [[ "$expected_result_process" == "Success" ]]; then
            [[ "$status" -eq 0 ]] || { echo "Test $index expected Success but failed: $test_command" >&3; return 1; }
        else
            [[ "$status" -ne 0 ]] || { echo "Test $index expected failure with '$expected_result_process' but succeeded: $test_command" >&3; return 1; }
        fi

        # Store test command and expected results for claim test
        test_results[$index]="$test_command|$expected_result_process|$(echo "$scenario" | jq -r '.ExpectedResultClaim')"
        echo "test_results[$index]=${test_results[$index]}" >&3
        
        if [[ "$test_amount" = "Max" ]]; then
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
        fi
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
    
    echo "Final test_results contents:" >&3
    for key in "${!test_results[@]}"; do
        echo "test_results[$key]=${test_results[$key]}" >&3
    done
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
    echo "Starting Claim individual deposits test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || { echo "Bridge Tests Suite file not found" >&3; skip "Bridge Tests Suite file not found"; }

    index=0
    while read -r scenario; do
        echo "Processing claim for scenario $index: $scenario" >&3
        test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        test_token=$(echo "$scenario" | jq -r '.Token')
        expected_result_claim=$(echo "$scenario" | jq -r '.ExpectedResultClaim')

        dest_rpc_url="$l2_rpc_url"
        dest_private_key="$l2_private_key"
        dest_bridge_addr="$l2_bridge_addr"
        dest_network_id="$l1_network_id"

        # Retry fetching all unclaimed deposit counts to handle auto-claimer race conditions
        unclaimed_deposits=""
        for attempt in {1..5}; do
            echo "Attempt $attempt to fetch unclaimed deposit counts..." >&3
            deposits_response=$(curl -s "$bridge_service_url/bridges/$l1_eth_address")
            echo "Bridge service response: $deposits_response" >&3
            unclaimed_deposits=$(echo "$deposits_response" | jq -r '.deposits | map(select(.claim_tx_hash == "")) | map(.deposit_cnt) | join(" ")')
            echo "Fetched unclaimed deposit counts: $unclaimed_deposits" >&3
            [[ -n "$unclaimed_deposits" ]] && break
            echo "No unclaimed deposits found, retrying in 10 seconds..." >&3
            sleep 10
        done

        if [[ -z "$unclaimed_deposits" ]]; then
            echo "No unclaimed deposits found for address $l1_eth_address at index $index after retries" >&3
            [[ "$expected_result_claim" == "N/A" ]] || { echo "Test $index expected a claim but no unclaimed deposits found" >&3; return 1; }
            index=$((index + 1))
            continue
        fi

        # Iterate through unclaimed deposits
        claim_attempted=false
        for deposit_count in $unclaimed_deposits; do
            echo "Validating deposit $deposit_count is unclaimed..." >&3
            claim_tx_hash=$(curl -s toman"$bridge_service_url/bridges/$l1_eth_address" | jq -r ".deposits | map(select(.deposit_cnt == $deposit_count)) | .[0].claim_tx_hash")
            echo "Claim transaction hash for deposit $deposit_count: $claim_tx_hash" >&3
            if [[ -n "$claim_tx_hash" ]]; then
                echo "Deposit $deposit_count is already claimed with tx hash: $claim_tx_hash" >&3
                continue
            fi

            echo "Attempting to make bridge claim for deposit $deposit_count on index $index..." >&3

            # Determine claim command based on BridgeType
            case "$test_bridge_type" in
                "Asset"|"Weth") claim_command="polycli ulxly claim asset" ;;
                "Message") claim_command="polycli ulxly claim message" ;;
                *) echo "Unrecognized Bridge Type for claim: $test_bridge_type" >&3; return 1 ;;
            esac

            # Construct the claim command
            claim_command="$claim_command --bridge-address $dest_bridge_addr --private-key $dest_private_key --rpc-url $dest_rpc_url --deposit-count $deposit_count --deposit-network $dest_network_id --bridge-service-url $bridge_service_url --wait $claim_wait_duration"
            output_file=$(mktemp)
            echo "Running command: $claim_command" >&3
            run $claim_command > "$output_file" 2>&3
            echo "Command output:" >&3
            cat "$output_file" >&3

            # Validate the claim result
            if [[ "$expected_result_claim" == "Success" ]]; then
                [[ "$status" -eq 0 ]] || { echo "Test $index expected Claim Success but failed for deposit $deposit_count: $claim_command" >&3; cat "$output_file" >&3; rm "$output_file"; return 1; }
            else
                [[ "$status" -ne 0 ]] || { echo "Test $index expected Claim failure with '$expected_result_claim' but succeeded for deposit $deposit_count: $claim_command" >&3; cat "$output_file" >&3; rm "$output_file"; return 1; }
                if [[ "$expected_result_claim" != "N/A" ]]; then
                    echo "$output" | grep -q "$expected_result_claim" || { echo "Test $index expected Claim error '$expected_result_claim' not found in output for deposit $deposit_count: $output" >&3; cat "$output_file" >&3; rm "$output_file"; return 1; }
                fi
            fi

            rm "$output_file"
            claim_attempted=true
            break # Exit loop after attempting a claim
        done

        if [[ "$claim_attempted" == false && "$expected_result_claim" != "N/A" ]]; then
            echo "Test $index expected a claim but no unclaimed deposits were available after validation" >&3
            return 1
        fi

        rm "$output_file"
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
}