#!/usr/bin/env bats
# bats file_tags=standard

# =============================================================================
# Setup and Configuration
# =============================================================================

setup() {
    # Initialize test_index for this test run
    test_index=0

    # Environment variables with defaults
    _setup_environment_variables
    
    # Contract addresses
    _setup_contract_addresses
    
    # Load helper functions from helper bash file
    load "./assets/bridge-tests-helper.bash"

    # Load test scenarios from file
    scenarios=$(cat "./tests/lxly/assets/bridge-tests-suite.json")

    # Clean up any previous result files
    rm -f /tmp/test_result_*.txt /tmp/huge_data_*.hex /tmp/max_data_*.hex

    log_root_dir="${LOG_ROOT_DIR:-"/tmp"}"
}

teardown() {
    # Clean up temporary files for this test
    rm -f "/tmp/huge_data_${test_index}.hex" "/tmp/max_data_${test_index}.hex"

    # Clean up result files
    rm -f /tmp/test_result_*.txt /tmp/huge_data_*.hex /tmp/max_data_*.hex
}


_setup_environment_variables() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"
    l1_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l1_eth_address=$(cast wallet address --private-key "$l1_private_key")
    l1_rpc_url="${L1_RPC_URL:-http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)}"
    l1_bridge_addr="${L1_BRIDGE_ADDR:-0x4c1335D41c271beD3eF6a1228a4D0C701Fc87b74}"

    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url="${L2_RPC_URL:-$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)}"
    l2_bridge_addr="${L2_BRIDGE_ADDR:-0x4c1335D41c271beD3eF6a1228a4D0C701Fc87b74}"

    export bridge_service_url="${BRIDGE_SERVICE_URL:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)}"
    l1_network_id=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    l2_network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    export claim_wait_duration="${CLAIM_WAIT_DURATION:-10m}"
}


_setup_contract_addresses() {
    tester_contract_address="0xc54E34B55EF562FE82Ca858F70D1B73244e86388"
    export test_erc20_buggy_addr="0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956"
    test_lxly_proxy_addr="0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191"
    export test_erc20_addr="0x6E3AD1d922fe009dc3Eb267827004ccAA4f23f3d"
    export pp_weth_address
    pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')
    export pol_address="0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E"
    export gas_token_address="0x0000000000000000000000000000000000000000"
}


# =============================================================================
# Test Cases
# =============================================================================

@test "Initial setup" {
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

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


@test "Process bridge scenarios and claim deposits in parallel" {
    echo "Starting parallel bridge scenarios and claims test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    # Create output directory with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$log_root_dir/bridge_test_results_${timestamp}"
    mkdir -p "$output_dir"
    
    echo "Test results will be saved to: $output_dir" >&3

    
    # Get total number of scenarios
    local total_scenarios
    total_scenarios=$(echo "$scenarios" | jq '. | length')
    echo "Total scenarios to process: $total_scenarios" >&3
    
    # Save detailed setup log
    local setup_log="$output_dir/setup_phase.log"
    
    echo "" | tee "$setup_log"
    echo "========================================" | tee -a "$setup_log"
    echo "      PHASE 1: SEQUENTIAL SETUP        " | tee -a "$setup_log"
    echo "========================================" | tee -a "$setup_log"
    
    # Phase 1: Sequential setup of all test accounts
    local index=0
    local setup_failures=0
    
    while read -r scenario; do
        echo "Setting up test account $index" | tee -a "$setup_log"
        
        if ! _setup_single_test_account "$index" "$scenario" 2>>"$output_dir/setup_debug_${index}.log"; then
            echo "Failed to set up account for test $index" | tee -a "$setup_log"
            setup_failures=$((setup_failures + 1))
        else
            echo "Successfully set up account for test $index" | tee -a "$setup_log"
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
    
    if [[ $setup_failures -gt 0 ]]; then
        echo "Failed to set up $setup_failures out of $total_scenarios test accounts" | tee -a "$setup_log"
        echo "Setup logs saved to: $output_dir/setup_*.log" >&3
        return 1
    fi
    
    echo "All $total_scenarios test accounts set up successfully" | tee -a "$setup_log"
    
    # Save detailed bridge test log
    local bridge_log="$output_dir/bridge_phase.log"
    
    echo "" | tee "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    echo "      PHASE 2: PARALLEL BRIDGE TESTS   " | tee -a "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    
    # Phase 2: Run bridge tests in parallel
    local max_concurrent=18
    if [[ $total_scenarios -lt 5 ]]; then
        max_concurrent=$total_scenarios
    fi
    
    echo "Running bridge tests with max concurrency: $max_concurrent" | tee -a "$bridge_log"
    
    local pids=()
    index=0
    
    while read -r scenario; do
        # Wait if we've reached max concurrency
        while (( ${#pids[@]} >= max_concurrent )); do
            # Wait for any process to complete
            local completed_pid=""
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    completed_pid="${pids[$i]}"
                    unset 'pids[$i]'
                    break
                fi
            done
            
            # If no process completed, wait a bit
            if [[ -z "$completed_pid" ]]; then
                sleep 0.5
            fi
            
            # Rebuild pids array to remove gaps
            pids=("${pids[@]}")
        done
        
        echo "Starting bridge test $index" | tee -a "$bridge_log"
        _run_single_bridge_test "$index" "$scenario" 2>"$output_dir/bridge_test_${index}.log" &
        local test_pid=$!
        pids+=("$test_pid")
        index=$((index + 1))
        
        # Small delay to stagger test starts
        sleep 0.1
        
    done < <(echo "$scenarios" | jq -c '.[]')
    
    echo "Started $index parallel bridge test processes" | tee -a "$bridge_log"
    
    # Wait for all remaining background processes to complete
    local wait_timeout=300  # 5 minutes total timeout
    local wait_start
    wait_start=$(date +%s)
    
    while (( ${#pids[@]} > 0 )); do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - wait_start))
        
        if (( elapsed > wait_timeout )); then
            echo "Timeout reached, killing remaining processes..." | tee -a "$bridge_log"
            for pid in "${pids[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            break
        fi
        
        # Check for completed processes
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                echo "Bridge test process ${pids[$i]} completed" | tee -a "$bridge_log"
                unset 'pids[$i]'
            fi
        done
        
        # Rebuild pids array to remove gaps
        pids=("${pids[@]}")
        
        # Wait a bit before checking again
        sleep 1
    done
    
    # Collect and report results
    _collect_and_report_results "$output_dir" "$bridge_log" "$total_scenarios"
    local failed_tests=$?
    
    # Fail the test if any individual test failed
    [[ $failed_tests -eq 0 ]] || {
        echo "Some tests failed. Check the detailed logs in $output_dir" >&3
        return 1
    }
}

@test "Run address tester actions" {
    # This test will be skipped by default. Remove the below "skip" command to run it.
    skip
    local address_tester_actions="001 011 021 031 101 201 301 401 501 601 701 801 901"
    
    for create_mode in 0 1 2; do
        for action in $address_tester_actions; do
            for rpc_url in $l1_rpc_url $l2_rpc_url; do
                for network_id in $l1_network_id $l2_network_id; do
                    # Select appropriate private key based on RPC URL
                    local private_key_for_tx
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