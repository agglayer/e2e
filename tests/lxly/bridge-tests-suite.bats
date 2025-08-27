#!/usr/bin/env bats
# bats file_tags=standard,lxly

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
    global_timeout="$(echo "${ETH_RPC_TIMEOUT:-2400}" | sed 's/[smh]$//')"
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
    l1_bridge_addr="${L1_BRIDGE_ADDR:-0xD779d520D2F8DdD71Eb131f509f2f8Fa355362ae}"
    if [[ $(cast code $l1_bridge_addr --rpc-url $l1_rpc_url) == "0x" ]]; then
        echo "Replacing empty bridge contract address..." >&3
        l1_bridge_addr=$(_get_bridge_address)
    fi

    l2_private_key="${L2_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    l2_rpc_url="${L2_RPC_URL:-$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)}"
    l2_bridge_addr="${L2_BRIDGE_ADDR:-0xD779d520D2F8DdD71Eb131f509f2f8Fa355362ae}"
    if [[ $(cast code $l2_bridge_addr --rpc-url $l2_rpc_url) == "0x" ]]; then
        echo "Replacing empty bridge contract address..." >&3
        l2_bridge_addr=$(_get_bridge_address)
    fi

    export bridge_service_url="${BRIDGE_SERVICE_URL:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)}"
    l1_network_id=$(cast call --rpc-url "$l1_rpc_url" "$l1_bridge_addr" 'networkID()(uint32)')
    l2_network_id=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'networkID()(uint32)')
    export claim_wait_duration="${CLAIM_WAIT_DURATION:-120m}"
}


_get_bridge_address() {
    # L1 and L2 bridge address should be identical
    local bridge_addr
    bridge_addr=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "jq -r '.polygonZkEVMBridgeAddress' /opt/zkevm/combined.json")
    echo "$bridge_addr"
}


_setup_contract_addresses() {
    tester_contract_address="${TESTER_CONTRACT_ADDRESS:-0xc54E34B55EF562FE82Ca858F70D1B73244e86388}"
    export test_erc20_buggy_addr="${TEST_ERC20_BUGGY_ADDRESS:-0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956}"
    test_lxly_proxy_addr="${TEST_LXLY_PROXY_ADDRESS:-0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191}"
    export test_erc20_addr="${TEST_ERC20_ADDRESS:-0x6E3AD1d922fe009dc3Eb267827004ccAA4f23f3d}"
    export pp_weth_address="${TEST_PP_WETH_ADDRESS:-$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')}"
    # pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')
    export pol_address="${POL_ADDRESS:-0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E}"
    export gas_token_address="${GAS_TOKEN_ADDRESS:-0x0000000000000000000000000000000000000000}"
}


# =============================================================================
# Test Cases
# =============================================================================
# bats test_tags=bridge
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

# bats test_tags=bridge
@test "Process L1 to L2 bridge scenarios and claim deposits in parallel" {
    echo "Starting L1 to L2 parallel bridge scenarios and claims test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    # Create output directory with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$log_root_dir/bridge_test_results_l1_to_l2_${timestamp}"
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
    local successful_setups=()  # Array to track successfully set up test indices
    
    echo "Setting up $total_scenarios test accounts..." >&3
    
    while read -r scenario; do
        local progress_percent=$((index * 100 / total_scenarios))
        echo "[$progress_percent%] Setting up test account $index/$total_scenarios" | tee -a "$setup_log" >&3
        
        if ! _setup_single_test_account "$index" "$scenario" "L1_TO_L2" 2>>"$output_dir/setup_debug_${index}.log"; then
            echo "❌ Failed to set up account for test $index" | tee -a "$setup_log" >&3
            setup_failures=$((setup_failures + 1))
        else
            echo "✅ Successfully set up account for test $index" | tee -a "$setup_log"
            successful_setups+=("$index")  # Track successful setup
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
    
    local successful_count=${#successful_setups[@]}
    
    echo "" >&3
    echo "Setup Phase Complete:" >&3
    echo "  ✅ Successful setups: $successful_count" >&3
    echo "  ❌ Failed setups: $setup_failures" >&3
    
    if [[ $setup_failures -gt 0 ]]; then
        echo "Failed to set up $setup_failures out of $total_scenarios test accounts" | tee -a "$setup_log"
        echo "Successfully set up $successful_count accounts" | tee -a "$setup_log"
        echo "Setup logs saved to: $output_dir/setup_*.log" | tee -a "$setup_log"
        
        # Continue with successful setups if we have any
        if [[ $successful_count -eq 0 ]]; then
            echo "No accounts were successfully set up, aborting test" | tee -a "$setup_log"
            return 1
        fi
    else
        echo "All $total_scenarios test accounts set up successfully" | tee -a "$setup_log"
    fi
    
    # Save detailed bridge test log
    local bridge_log="$output_dir/bridge_phase.log"
    
    echo "" | tee "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    echo "      PHASE 2: PARALLEL BRIDGE TESTS   " | tee -a "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    
    # Phase 2: Run bridge tests in parallel - only for successfully set up accounts
    local max_concurrent=5
    if [[ $successful_count -lt 5 ]]; then
        max_concurrent=$successful_count
    fi
    
    echo "Running bridge tests for $successful_count successfully set up accounts" | tee -a "$bridge_log"
    echo "Using max concurrency: $max_concurrent" | tee -a "$bridge_log"
    
    echo "" >&3
    echo "Starting parallel bridge tests with max concurrency: $max_concurrent" >&3
    
    local pids=()
    local scenario_array
    readarray -t scenario_array < <(echo "$scenarios" | jq -c '.[]')
    
    # Track progress
    local started_tests=0
    local completed_tests=0
    
    for test_index in "${successful_setups[@]}"; do
        # Wait if we've reached max concurrency
        while (( ${#pids[@]} >= max_concurrent )); do
            # Check for completed processes
            local new_completions=0
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                    new_completions=$((new_completions + 1))
                fi
            done
            
            # Update progress if we had completions
            if [[ $new_completions -gt 0 ]]; then
                completed_tests=$((completed_tests + new_completions))
                local progress_percent=$((completed_tests * 100 / successful_count))
                echo "[${progress_percent}%] Completed: $completed_tests/$successful_count bridge tests" >&3
            fi
            
            # Rebuild pids array to remove gaps
            pids=("${pids[@]}")
            
            # If no process completed, wait a bit
            if [[ $new_completions -eq 0 ]]; then
                sleep 0.5
            fi
        done
        
        started_tests=$((started_tests + 1))
        local start_progress_percent=$((started_tests * 100 / successful_count))
        echo "[${start_progress_percent}%] Starting bridge test $test_index (${started_tests}/${successful_count})" | tee -a "$bridge_log" >&3
        
        _run_single_bridge_test "$test_index" "${scenario_array[$test_index]}" "L1_TO_L2" 2>"$output_dir/bridge_test_${test_index}.log" &
        local test_pid=$!
        pids+=("$test_pid")
        
        # Small delay to stagger test starts
        sleep 0.1
        
    done
    
    echo "Started all ${#successful_setups[@]} parallel bridge test processes" | tee -a "$bridge_log" >&3
    
    # Wait for all remaining background processes to complete
    local wait_start
    wait_start=$(date +%s)
    
    echo "" >&3
    echo "Waiting for all bridge tests to complete..." >&3
    
    while (( ${#pids[@]} > 0 )); do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - wait_start))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        if (( elapsed > ${global_timeout%s} )); then
            echo "Timeout reached after ${elapsed_minutes}m${elapsed_seconds}s, killing remaining processes..." | tee -a "$bridge_log" >&3
            for pid in "${pids[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            break
        fi
        
        # Check for completed processes
        local new_completions=0
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                echo "Bridge test process ${pids[$i]} completed" | tee -a "$bridge_log"
                unset 'pids[$i]'
                new_completions=$((new_completions + 1))
            fi
        done
        
        # Update progress if we had completions
        if [[ $new_completions -gt 0 ]]; then
            completed_tests=$((completed_tests + new_completions))
            local progress_percent=$((completed_tests * 100 / successful_count))
            local remaining_tests=$((successful_count - completed_tests))
            echo "[${progress_percent}%] Completed: $completed_tests/$successful_count tests (${remaining_tests} remaining) - ${elapsed_minutes}m${elapsed_seconds}s elapsed" >&3
        fi
        
        # Rebuild pids array to remove gaps
        pids=("${pids[@]}")
        
        # Show periodic progress even if no completions
        if (( elapsed % 30 == 0 )); then
            local active_processes=${#pids[@]}
            echo "Status: $active_processes tests still running, $completed_tests/$successful_count completed - ${elapsed_minutes}m${elapsed_seconds}s elapsed" >&3
        fi
        
        # Wait a bit before checking again
        sleep 1
    done
    
    echo "" >&3
    echo "All bridge tests completed! Collecting results..." >&3
    
    # Collect and report results - pass the successful count instead of total
    _collect_and_report_results "$output_dir" "$bridge_log" "$successful_count"
    local failed_tests=$?
    
    # Report setup failures in the final summary but don't fail the test for them
    if [[ $setup_failures -gt 0 ]]; then
        echo "Note: $setup_failures accounts failed setup and were skipped" >&3
    fi
    
    # Fail the test only if bridge tests failed (not setup failures)
    [[ $failed_tests -eq 0 ]] || {
        echo "Some bridge tests failed. Check the detailed logs in $output_dir" >&3
        return 1
    }
}


# bats test_tags=bridge
@test "Process L2 to L1 bridge scenarios and claim deposits in parallel" {
    echo "Starting L2 to L1 parallel bridge scenarios and claims test" >&3
    [[ -f "./tests/lxly/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    # Create output directory with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$log_root_dir/bridge_test_results_l2_to_l1_${timestamp}"
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
    local successful_setups=()  # Array to track successfully set up test indices
    
    echo "Setting up $total_scenarios test accounts..." >&3
    
    while read -r scenario; do
        local progress_percent=$((index * 100 / total_scenarios))
        echo "[$progress_percent%] Setting up test account $index/$total_scenarios" | tee -a "$setup_log" >&3
        
        if ! _setup_single_test_account "$index" "$scenario" "L2_TO_L1" 2>>"$output_dir/setup_debug_${index}.log"; then
            echo "❌ Failed to set up account for test $index" | tee -a "$setup_log" >&3
            setup_failures=$((setup_failures + 1))
        else
            echo "✅ Successfully set up account for test $index" | tee -a "$setup_log"
            successful_setups+=("$index")  # Track successful setup
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')
    
    local successful_count=${#successful_setups[@]}
    
    echo "" >&3
    echo "Setup Phase Complete:" >&3
    echo "  ✅ Successful setups: $successful_count" >&3
    echo "  ❌ Failed setups: $setup_failures" >&3
    
    if [[ $setup_failures -gt 0 ]]; then
        echo "Failed to set up $setup_failures out of $total_scenarios test accounts" | tee -a "$setup_log"
        echo "Successfully set up $successful_count accounts" | tee -a "$setup_log"
        echo "Setup logs saved to: $output_dir/setup_*.log" | tee -a "$setup_log"
        
        # Continue with successful setups if we have any
        if [[ $successful_count -eq 0 ]]; then
            echo "No accounts were successfully set up, aborting test" | tee -a "$setup_log"
            return 1
        fi
    else
        echo "All $total_scenarios test accounts set up successfully" | tee -a "$setup_log"
    fi
    
    # Save detailed bridge test log
    local bridge_log="$output_dir/bridge_phase.log"
    
    echo "" | tee "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    echo "      PHASE 2: PARALLEL BRIDGE TESTS   " | tee -a "$bridge_log"
    echo "========================================" | tee -a "$bridge_log"
    
    # Phase 2: Run bridge tests in parallel - only for successfully set up accounts
    local max_concurrent=5
    if [[ $successful_count -lt 5 ]]; then
        max_concurrent=$successful_count
    fi
    
    echo "Running bridge tests for $successful_count successfully set up accounts" | tee -a "$bridge_log"
    echo "Using max concurrency: $max_concurrent" | tee -a "$bridge_log"
    
    echo "" >&3
    echo "Starting parallel bridge tests with max concurrency: $max_concurrent" >&3
    
    local pids=()
    local scenario_array
    readarray -t scenario_array < <(echo "$scenarios" | jq -c '.[]')
    
    # Track progress
    local started_tests=0
    local completed_tests=0
    
    for test_index in "${successful_setups[@]}"; do
        # Wait if we've reached max concurrency
        while (( ${#pids[@]} >= max_concurrent )); do
            # Check for completed processes
            local new_completions=0
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                    new_completions=$((new_completions + 1))
                fi
            done
            
            # Update progress if we had completions
            if [[ $new_completions -gt 0 ]]; then
                completed_tests=$((completed_tests + new_completions))
                local progress_percent=$((completed_tests * 100 / successful_count))
                echo "[${progress_percent}%] Completed: $completed_tests/$successful_count bridge tests" >&3
            fi
            
            # Rebuild pids array to remove gaps
            pids=("${pids[@]}")
            
            # If no process completed, wait a bit
            if [[ $new_completions -eq 0 ]]; then
                sleep 0.5
            fi
        done
        
        started_tests=$((started_tests + 1))
        local start_progress_percent=$((started_tests * 100 / successful_count))
        echo "[${start_progress_percent}%] Starting bridge test $test_index (${started_tests}/${successful_count})" | tee -a "$bridge_log" >&3
        
        _run_single_bridge_test "$test_index" "${scenario_array[$test_index]}" "L2_TO_L1" 2>"$output_dir/bridge_test_${test_index}.log" &
        local test_pid=$!
        pids+=("$test_pid")
        
        # Small delay to stagger test starts
        sleep 0.1
        
    done
    
    echo "Started all ${#successful_setups[@]} parallel bridge test processes" | tee -a "$bridge_log" >&3
    
    # Wait for all remaining background processes to complete
    local wait_start
    wait_start=$(date +%s)
    
    echo "" >&3
    echo "Waiting for all bridge tests to complete..." >&3
    
    while (( ${#pids[@]} > 0 )); do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - wait_start))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        if (( elapsed > ${global_timeout%s} )); then
            echo "Timeout reached after ${elapsed_minutes}m${elapsed_seconds}s, killing remaining processes..." | tee -a "$bridge_log" >&3
            for pid in "${pids[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            break
        fi
        
        # Check for completed processes
        local new_completions=0
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                echo "Bridge test process ${pids[$i]} completed" | tee -a "$bridge_log"
                unset 'pids[$i]'
                new_completions=$((new_completions + 1))
            fi
        done
        
        # Update progress if we had completions
        if [[ $new_completions -gt 0 ]]; then
            completed_tests=$((completed_tests + new_completions))
            local progress_percent=$((completed_tests * 100 / successful_count))
            local remaining_tests=$((successful_count - completed_tests))
            echo "[${progress_percent}%] Completed: $completed_tests/$successful_count tests (${remaining_tests} remaining) - ${elapsed_minutes}m${elapsed_seconds}s elapsed" >&3
        fi
        
        # Rebuild pids array to remove gaps
        pids=("${pids[@]}")
        
        # Show periodic progress even if no completions
        if (( elapsed % 30 == 0 )); then
            local active_processes=${#pids[@]}
            echo "Status: $active_processes tests still running, $completed_tests/$successful_count completed - ${elapsed_minutes}m${elapsed_seconds}s elapsed" >&3
        fi
        
        # Wait a bit before checking again
        sleep 1
    done
    
    echo "" >&3
    echo "All bridge tests completed! Collecting results..." >&3
    
    # Collect and report results - pass the successful count instead of total
    _collect_and_report_results "$output_dir" "$bridge_log" "$successful_count"
    local failed_tests=$?
    
    # Report setup failures in the final summary but don't fail the test for them
    if [[ $setup_failures -gt 0 ]]; then
        echo "Note: $setup_failures accounts failed setup and were skipped" >&3
    fi
    
    # Fail the test only if bridge tests failed (not setup failures)
    [[ $failed_tests -eq 0 ]] || {
        echo "Some bridge tests failed. Check the detailed logs in $output_dir" >&3
        return 1
    }
}

# bats test_tags=bridge
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