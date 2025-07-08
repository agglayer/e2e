#!/usr/bin/env bats

# =============================================================================
# Setup and Configuration
# =============================================================================

setup() {
    # Environment variables with defaults
    _setup_environment_variables
    
    # Contract addresses
    _setup_contract_addresses
    
    # Load test scenarios from file
    scenarios=$(cat "./tests/lxly/assets/bridge-tests-suite.json")
    
    # Initialize arrays to store test commands, expected results, and deposit cache
    declare -A test_results
    declare -A deposits_cache
}

_setup_environment_variables() {
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
    claim_wait_duration="${CLAIM_WAIT_DURATION:-10m}"
}

_setup_contract_addresses() {
    tester_contract_address="0xc54E34B55EF562FE82Ca858F70D1B73244e86388"
    test_erc20_buggy_addr="0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956"
    test_lxly_proxy_addr="0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191"
    test_erc20_addr="0x6E3AD1d922fe009dc3Eb267827004ccAA4f23f3d"
    pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')
    pol_address="0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E"
    gas_token_address="0x0000000000000000000000000000000000000000"
}

# =============================================================================
# Utility Functions
# =============================================================================

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

_get_bridge_type_command() {
    local bridge_type="$1"
    case "$bridge_type" in
        "Asset") echo "asset" ;;
        "Message") echo "message" ;;
        "Weth") echo "weth" ;;
        *) echo "Unrecognized Bridge Type: $bridge_type" >&3; return 1 ;;
    esac
}

_get_destination_address() {
    local dest_type="$1"
    case "$dest_type" in
        "Contract") echo "$l1_bridge_addr" ;;
        "Precompile") echo "0x0000000000000000000000000000000000000004" ;;
        "EOA") echo "$l1_eth_address" ;;
        *) echo "Unrecognized Destination Address: $dest_type" >&3; return 1 ;;
    esac
}

_get_token_address() {
    local token_type="$1"
    case "$token_type" in
        "POL") echo "$pol_address" ;;
        "LocalERC20") echo "$test_erc20_addr" ;;
        "WETH") echo "$pp_weth_address" ;;
        "Buggy") echo "$test_erc20_buggy_addr" ;;
        "GasToken") echo "$gas_token_address" ;;
        "NativeEther") echo "0x0000000000000000000000000000000000000000" ;;
        *) echo "Unrecognized Test Token: $token_type" >&3; return 1 ;;
    esac
}

_add_metadata_to_command() {
    local command="$1"
    local metadata_type="$2"
    
    case "$metadata_type" in
        "Random")
            echo "$command --call-data $(date +%s | xxd -p)"
            ;;
        "0x")
            echo "$command --call-data 0x"
            ;;
        "Huge")
            local temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 97000 > "$temp_file"
            echo "$command --call-data-file $temp_file"
            ;;
        "Max")
            local temp_file=$(mktemp)
            xxd -p /dev/zero | tr -d "\n" | head -c 261569 > "$temp_file"
            echo "$command --call-data-file $temp_file"
            ;;
        *)
            echo "Unrecognized Metadata: $metadata_type" >&3
            return 1
            ;;
    esac
}

_add_force_update_to_command() {
    local command="$1"
    local force_update="$2"
    
    case "$force_update" in
        "True") echo "$command --force-update-root=true" ;;
        "False") echo "$command --force-update-root=false" ;;
        *) echo "Unrecognized Force Update: $force_update" >&3; return 1 ;;
    esac
}

_setup_amount_and_add_to_command() {
    local command="$1"
    local amount_type="$2"
    
    case "$amount_type" in
        "0")
            echo "$command --value 0"
            ;;
        "1")
            echo "$command --value 1"
            ;;
        "Max")
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                "$test_erc20_buggy_addr" 'mint(address,uint256)' "$l1_eth_address" "$(cast max-uint)" --quiet
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                "$test_erc20_buggy_addr" 'approve(address,uint256)' "$l1_bridge_addr" "$(cast max-uint)" --quiet
            cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
                "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0 --quiet
            echo "$command --value $(cast max-uint) --gas-limit 5000000"
            ;;
        "Random")
            echo "$command --value $(date +%s)"
            ;;
        *)
            echo "Unrecognized Amount: $amount_type" >&3
            exit 1
            ;;
    esac
}

_cleanup_max_amount_setup() {
    local amount_type="$1"
    if [[ "$amount_type" = "Max" ]]; then
        cast send --legacy --rpc-url "$l1_rpc_url" --private-key "$l1_private_key" \
            "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$l1_bridge_addr" 0
    fi
}

_get_expected_leaf_type() {
    local bridge_type="$1"
    case "$bridge_type" in
        "Asset"|"Weth") echo "0" ;;
        "Message") echo "1" ;;
        *) echo "Unrecognized Bridge Type: $bridge_type" >&3; return 1 ;;
    esac
}

_get_expected_amount() {
    local amount_type="$1"
    local test_results_entry="$2"
    
    case "$amount_type" in
        "0") echo "0" ;;
        "1") echo "1" ;;
        "Max") echo "$(cast max-uint)" ;;
        "Random") echo "$(echo "$test_results_entry" | cut -d'|' -f4)" ;;
        *) echo "Unrecognized Amount: $amount_type" >&3; return 1 ;;
    esac
}

_should_skip_metadata_check() {
    local dest_addr="$1"
    local token_type="$2"
    local metadata_type="$3"
    local deposit_token_addr="$4"
    
    # Skip metadata check for precompile address
    if [[ "$dest_addr" == "0x0000000000000000000000000000000000000004" ]]; then
        return 0
    fi
    
    # Skip metadata check for Buggy token with MetaData=0x
    if [[ "$token_type" == "Buggy" && "$metadata_type" == "0x" ]]; then
        return 0
    fi
    
    # Skip metadata check for MetaData=0x when orig_addr is not zero
    if [[ "$metadata_type" == "0x" && "$deposit_token_addr" != "0x0000000000000000000000000000000000000000" ]]; then
        return 0
    fi
    
    return 1
}

_validate_metadata_match() {
    local metadata_type="$1"
    local deposit_metadata="$2"
    
    case "$metadata_type" in
        "Huge")
            local expected_length=$((97000 + 2)) # 97,000 bytes + 0x
            local actual_length=${#deposit_metadata}
            if [[ "$actual_length" -eq "$expected_length" && "$deposit_metadata" =~ ^0x0+$ ]]; then
                return 0
            fi
            echo "Huge metadata mismatch: expected length=$expected_length, all zeros; got length=$actual_length, metadata=$deposit_metadata" >&3
            return 1
            ;;
        "Max")
            local expected_length=$((261570))
            local actual_length=${#deposit_metadata}
            if [[ "$actual_length" -eq "$expected_length" && "$deposit_metadata" =~ ^0x0+$ ]]; then
                return 0
            fi
            echo "Max metadata mismatch: expected length=$expected_length, all zeros; got length=$actual_length, metadata=$deposit_metadata" >&3
            return 1
            ;;
        "Random")
            return 0  # Skip validation for Random
            ;;
        *)
            if [[ "$deposit_metadata" == "$metadata_type" ]]; then
                return 0
            fi
            echo "Metadata mismatch: expected $metadata_type, got $deposit_metadata" >&3
            return 1
            ;;
    esac
}

_validate_claim_error() {
    local expected_result="$1"
    local output="$2"
    
    # Check if expected_result_claim is an array or a single string
    if [[ "$expected_result" =~ ^\[.*\]$ ]]; then
        # Handle array of expected results
        local match_found=false
        while read -r expected_error; do
            expected_error=$(echo "$expected_error" | jq -r '.') # Remove quotes
            if _check_error_pattern "$expected_error" "$output"; then
                match_found=true
                break
            fi
        done < <(echo "$expected_result" | jq -c '.[]')
        
        if ! $match_found; then
            return 1
        fi
    else
        # Handle single expected error
        local expected_error=$(echo "$expected_result" | jq -r '.') # Remove quotes
        if ! _check_error_pattern "$expected_error" "$output"; then
            return 1
        fi
    fi
    
    return 0
}

_check_error_pattern() {
    local expected_error="$1"
    local output="$2"
    
    if [[ "$expected_error" =~ ^oversized\ data ]]; then
        echo "$output" | grep -q "oversized data: transaction size [0-9]\+, limit 131072"
    else
        echo "$output" | grep -q "$expected_error"
    fi
}

# =============================================================================
# Test Cases
# =============================================================================

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

@test "Process bridge scenarios and claim deposits" {
    echo "Starting Process bridge scenarios and claims test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    local index=0
    while read -r scenario; do
        echo "Processing scenario $index: $scenario" >&3
        
        # Extract scenario parameters
        local test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        local test_destination_address=$(echo "$scenario" | jq -r '.DestinationAddress')
        local test_token=$(echo "$scenario" | jq -r '.Token')
        local test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
        local test_force_update=$(echo "$scenario" | jq -r '.ForceUpdate')
        local test_amount=$(echo "$scenario" | jq -r '.Amount')
        local expected_result_process=$(echo "$scenario" | jq -r '.ExpectedResultProcess')
        local expected_result_claim=$(echo "$scenario" | jq -r '.ExpectedResultClaim')

        # Build bridge command
        local bridge_command="polycli ulxly bridge"
        local bridge_type_cmd=$(_get_bridge_type_command "$test_bridge_type")
        bridge_command="$bridge_command $bridge_type_cmd"
        
        local fixed_flags="--rpc-url $l1_rpc_url --destination-network $l2_network_id"
        bridge_command="$bridge_command $fixed_flags"

        # Add destination address
        local dest_addr=$(_get_destination_address "$test_destination_address")
        bridge_command="$bridge_command --destination-address $dest_addr"

        # Add token address
        local token_addr=$(_get_token_address "$test_token")
        bridge_command="$bridge_command --token-address $token_addr"

        # Add metadata
        bridge_command=$(_add_metadata_to_command "$bridge_command" "$test_meta_data")

        # Add force update flag
        bridge_command=$(_add_force_update_to_command "$bridge_command" "$test_force_update")

        # Setup amount and add to command
        bridge_command=$(_setup_amount_and_add_to_command "$bridge_command" "$test_amount")

        # Add final command parameters
        bridge_command="$bridge_command --bridge-address $l1_bridge_addr --private-key $l1_private_key"
        
        # Execute the bridge command
        echo "Running bridge command: $bridge_command" >&3
        run $bridge_command
        echo "Bridge command output: $output" >&3
        deposit_count=$(echo "$output" | awk '/depositCount=/ {gsub(/.*depositCount=/, ""); gsub(/\x1b\[[0-9;]*m/, ""); print}')
        
        if [[ "$expected_result_process" == "Success" ]]; then
            [[ "$status" -eq 0 ]] || {
                echo "Test $index bridge expected Success but failed: $bridge_command" >&3
                return 1
            }
            
            # Extract deposit count from bridge output
            echo "Extracted deposit count: $deposit_count" >&3
            
            # Skip claim if no claim is expected
            if [[ "$expected_result_claim" == "N/A" ]]; then
                echo "Scenario $index expects no claim (N/A), skipping claim" >&3
                index=$((index + 1))
                continue
            fi

            # Build claim command
            local claim_command="polycli ulxly claim"
            case "$test_bridge_type" in
                "Asset"|"Weth") claim_command="$claim_command asset" ;;
                "Message") claim_command="$claim_command message" ;;
                *) echo "Unrecognized Bridge Type for claim: $test_bridge_type" >&3; return 1 ;;
            esac

            claim_command="$claim_command --destination-address $dest_addr --bridge-address $l2_bridge_addr --private-key $l2_private_key --rpc-url $l2_rpc_url --deposit-count $deposit_count --deposit-network $l1_network_id --bridge-service-url $bridge_service_url --wait $claim_wait_duration"
            
            # Execute claim command
            echo "Running claim command: $claim_command" >&3
            run $claim_command >&3
            echo "Claim command output: $output" >&3

            # Validate claim result
            if [[ "$expected_result_claim" == "Success" ]]; then
                if [[ "$status" -ne 0 ]]; then
                    if ! echo "$output" | grep -q "already been claimed"; then
                        echo "Test $index expected Claim Success but failed for deposit $deposit_count" >&3
                        return 1
                    fi
                fi
            else
                if [[ "$status" -eq 0 ]]; then
                    echo "Test $index expected Claim failure but succeeded for deposit $deposit_count" >&3
                    return 1
                fi
                
                if ! _validate_claim_error "$expected_result_claim" "$output"; then
                    echo "Test $index expected Claim errors $expected_result_claim not found in output" >&3
                    return 1
                fi
            fi
        else
            [[ "$status" -ne 0 ]] || {
                echo "Test $index bridge expected failure but succeeded: $bridge_command" >&3
                return 1
            }
        fi
        
        # Clean up
        _cleanup_max_amount_setup "$test_amount"
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
}

# @test "Run address tester actions" {
#     local address_tester_actions="001 011 021 031 101 201 301 401 501 601 701 801 901"
    
#     for create_mode in 0 1 2; do
#         for action in $address_tester_actions; do
#             for rpc_url in $l1_rpc_url $l2_rpc_url; do
#                 for network_id in $l1_network_id $l2_network_id; do
#                     # Select appropriate private key based on RPC URL
#                     local private_key_for_tx=$([[ "$rpc_url" = "$l1_rpc_url" ]] && echo "$l1_private_key" || echo "$l2_private_key")
                    
#                     # Execute the tester action
#                     run cast send \
#                         --gas-limit 2500000 \
#                         --legacy \
#                         --value "$network_id" \
#                         --rpc-url "$rpc_url" \
#                         --private-key "$private_key_for_tx" \
#                         "$tester_contract_address" \
#                         "$(cast abi-encode 'f(uint32, address, uint256)' "0x${create_mode}${action}" "$test_lxly_proxy_addr" "$network_id")"
                    
#                     [[ "$status" -eq 0 ]] || echo "Failed action: 0x${create_mode}${action} on $rpc_url with network $network_id"
#                 done
#             done
#         done
#     done
# }