#!/usr/bin/env bats
# bats file_tags=standard,lxly

# =============================================================================
# Setup and Configuration
# =============================================================================

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    # Source the logger functions
    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../../core/helpers/logger.bash"

    export bridge_service_url="${BRIDGE_SERVICE_URL:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc)}"
    export claim_wait_duration="${CLAIM_WAIT_DURATION:-120m}"

    # Load test scenarios from file
    scenarios=$(cat "$BATS_TEST_DIRNAME/../lxly/assets/bridge-tests-suite.json")
    export scenarios

    # Contract addresses
    _setup_contract_addresses

    export log_root_dir="${LOG_ROOT_DIR:-"/tmp"}"
    global_timeout="$(echo "$ETH_RPC_TIMEOUT" | sed 's/[smh]$//')"
    export global_timeout
    export max_concurrent="${MAX_CONCURRENT:-10}"
}

setup() {
    # Initialize test_index for this test run
    test_index=0
  
    # Clean up any previous result files
    rm -f /tmp/test_result_*.txt /tmp/huge_data_*.hex /tmp/max_data_*.hex

    # Load helper functions from helper bash file
    load "$BATS_TEST_DIRNAME/../lxly/assets/bridge-tests-helper.bash"
}

teardown() {
    # Clean up temporary files for this test
    rm -f "/tmp/huge_data_${test_index}.hex" "/tmp/max_data_${test_index}.hex"

    # Clean up result files
    rm -f /tmp/test_result_*.txt /tmp/huge_data_*.hex /tmp/max_data_*.hex
}


_setup_contract_addresses() {
    tester_contract_address="${TESTER_CONTRACT_ADDRESS:-0xc54E34B55EF562FE82Ca858F70D1B73244e86388}"
    export test_erc20_buggy_addr="${TEST_ERC20_BUGGY_ADDRESS:-0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956}"
    test_lxly_proxy_addr="${TEST_LXLY_PROXY_ADDRESS:-0x8Cf49821aAFC2859ACEa047a1ee845A76D5C4191}"
    export test_erc20_addr="${TEST_ERC20_ADDRESS:-0x0a0Ba80F5D8Ce83D9d620dDfD1437507C793171f}"
    export pp_weth_address="${TEST_PP_WETH_ADDRESS:-$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')}"
    # pp_weth_address=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'WETHToken()(address)')
    export pol_address="${POL_ADDRESS:-0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E}"
}


_calculate_test_erc20_address() {
    local eth_address=$1
    
    local salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    local erc_20_bytecode=60806040526040516200143a3803806200143a833981016040819052620000269162000201565b8383600362000036838262000322565b50600462000045828262000322565b5050506200005a82826200007160201b60201c565b505081516020909201919091206006555062000416565b6001600160a01b038216620000cc5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015260640160405180910390fd5b8060026000828254620000e09190620003ee565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b505050565b634e487b7160e01b600052604160045260246000fd5b600082601f8301126200016457600080fd5b81516001600160401b03808211156200018157620001816200013c565b604051601f8301601f19908116603f01168101908282118183101715620001ac57620001ac6200013c565b81604052838152602092508683858801011115620001c957600080fd5b600091505b83821015620001ed5785820183015181830184015290820190620001ce565b600093810190920192909252949350505050565b600080600080608085870312156200021857600080fd5b84516001600160401b03808211156200023057600080fd5b6200023e8883890162000152565b955060208701519150808211156200025557600080fd5b50620002648782880162000152565b604087015190945090506001600160a01b03811681146200028457600080fd5b6060959095015193969295505050565b600181811c90821680620002a957607f821691505b602082108103620002ca57634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200013757600081815260208120601f850160051c81016020861015620002f95750805b601f850160051c820191505b818110156200031a5782815560010162000305565b505050505050565b81516001600160401b038111156200033e576200033e6200013c565b62000356816200034f845462000294565b84620002d0565b602080601f8311600181146200038e5760008415620003755750858301515b600019600386901b1c1916600185901b1785556200031a565b600085815260208120601f198616915b82811015620003bf578886015182559484019460019091019084016200039e565b5085821015620003de5787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b808201808211156200041057634e487b7160e01b600052601160045260246000fd5b92915050565b61101480620004266000396000f3fe608060405234801561001057600080fd5b506004361061014d5760003560e01c806340c10f19116100c35780639e4e73181161007c5780639e4e73181461033c578063a457c2d714610363578063a9059cbb14610376578063c473af3314610389578063d505accf146103b0578063dd62ed3e146103c357600080fd5b806340c10f19146102b257806342966c68146102c557806356189cb4146102d857806370a08231146102eb5780637ecebe001461031457806395d89b411461033457600080fd5b806323b872dd1161011557806323b872dd146101c357806330adf81f146101d6578063313ce567146101fd5780633408e4701461020c5780633644e51514610212578063395093511461029f57600080fd5b806304622c2e1461015257806306fdde031461016e578063095ea7b31461018357806318160ddd146101a6578063222f5be0146101ae575b600080fd5b61015b60065481565b6040519081526020015b60405180910390f35b6101766103d6565b6040516101659190610db1565b610196610191366004610e1b565b610468565b6040519015158152602001610165565b60025461015b565b6101c16101bc366004610e45565b610482565b005b6101966101d1366004610e45565b610492565b61015b7f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c981565b60405160128152602001610165565b4661015b565b61015b6006546000907f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f907fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc646604080516020810195909552840192909252606083015260808201523060a082015260c00160405160208183030381529060405280519060200120905090565b6101966102ad366004610e1b565b6104b6565b6101c16102c0366004610e1b565b6104d8565b6101c16102d3366004610e81565b6104e6565b6101c16102e6366004610e45565b6104f3565b61015b6102f9366004610e9a565b6001600160a01b031660009081526020819052604090205490565b61015b610322366004610e9a565b60056020526000908152604090205481565b6101766104fe565b61015b7fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc681565b610196610371366004610e1b565b61050d565b610196610384366004610e1b565b61058d565b61015b7f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f81565b6101c16103be366004610ebc565b61059b565b61015b6103d1366004610f2f565b6106ae565b6060600380546103e590610f62565b80601f016020809104026020016040519081016040528092919081815260200182805461041190610f62565b801561045e5780601f106104335761010080835404028352916020019161045e565b820191906000526020600020905b81548152906001019060200180831161044157829003601f168201915b5050505050905090565b6000336104768185856106d9565b60019150505b92915050565b61048d8383836107fd565b505050565b6000336104a08582856109a3565b6104ab8585856107fd565b506001949350505050565b6000336104768185856104c983836106ae565b6104d39190610fb2565b6106d9565b6104e28282610a17565b5050565b6104f03382610ad6565b50565b61048d8383836106d9565b6060600480546103e590610f62565b6000338161051b82866106ae565b9050838110156105805760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f77604482015264207a65726f60d81b60648201526084015b60405180910390fd5b6104ab82868684036106d9565b6000336104768185856107fd565b428410156105eb5760405162461bcd60e51b815260206004820152601960248201527f48455a3a3a7065726d69743a20415554485f45585049524544000000000000006044820152606401610577565b6001600160a01b038716600090815260056020526040812080547f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9918a918a918a91908661063883610fc5565b909155506040805160208101969096526001600160a01b0394851690860152929091166060840152608083015260a082015260c0810186905260e0016040516020818303038152906040528051906020012090506106998882868686610c08565b6106a48888886106d9565b5050505050505050565b6001600160a01b03918216600090815260016020908152604080832093909416825291909152205490565b6001600160a01b03831661073b5760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f206164646044820152637265737360e01b6064820152608401610577565b6001600160a01b03821661079c5760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f206164647265604482015261737360f01b6064820152608401610577565b6001600160a01b0383811660008181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a3505050565b6001600160a01b0383166108615760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f206164604482015264647265737360d81b6064820152608401610577565b6001600160a01b0382166108c35760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201526265737360e81b6064820152608401610577565b6001600160a01b0383166000908152602081905260409020548181101561093b5760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e7420657863656564732062604482015265616c616e636560d01b6064820152608401610577565b6001600160a01b03848116600081815260208181526040808320878703905593871680835291849020805487019055925185815290927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35b50505050565b60006109af84846106ae565b9050600019811461099d5781811015610a0a5760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e63650000006044820152606401610577565b61099d84848484036106d9565b6001600160a01b038216610a6d5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f2061646472657373006044820152606401610577565b8060026000828254610a7f9190610fb2565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b6001600160a01b038216610b365760405162461bcd60e51b815260206004820152602160248201527f45524332303a206275726e2066726f6d20746865207a65726f206164647265736044820152607360f81b6064820152608401610577565b6001600160a01b03821660009081526020819052604090205481811015610baa5760405162461bcd60e51b815260206004820152602260248201527f45524332303a206275726e20616d6f756e7420657863656564732062616c616e604482015261636560f81b6064820152608401610577565b6001600160a01b0383166000818152602081815260408083208686039055600280548790039055518581529192917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a3505050565b600654604080517f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f602080830191909152818301939093527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a0808301919091528251808303909101815260c082019092528151919092012061190160f01b60e083015260e282018190526101028201869052906000906101220160408051601f198184030181528282528051602091820120600080855291840180845281905260ff89169284019290925260608301879052608083018690529092509060019060a0016020604051602081039080840390855afa158015610d1b573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b03811615801590610d515750876001600160a01b0316816001600160a01b0316145b6106a45760405162461bcd60e51b815260206004820152602b60248201527f48455a3a3a5f76616c69646174655369676e6564446174613a20494e56414c4960448201526a445f5349474e415455524560a81b6064820152608401610577565b600060208083528351808285015260005b81811015610dde57858101830151858201604001528201610dc2565b506000604082860101526040601f19601f8301168501019250505092915050565b80356001600160a01b0381168114610e1657600080fd5b919050565b60008060408385031215610e2e57600080fd5b610e3783610dff565b946020939093013593505050565b600080600060608486031215610e5a57600080fd5b610e6384610dff565b9250610e7160208501610dff565b9150604084013590509250925092565b600060208284031215610e9357600080fd5b5035919050565b600060208284031215610eac57600080fd5b610eb582610dff565b9392505050565b600080600080600080600060e0888a031215610ed757600080fd5b610ee088610dff565b9650610eee60208901610dff565b95506040880135945060608801359350608088013560ff81168114610f1257600080fd5b9699959850939692959460a0840135945060c09093013592915050565b60008060408385031215610f4257600080fd5b610f4b83610dff565b9150610f5960208401610dff565b90509250929050565b600181811c90821680610f7657607f821691505b602082108103610f9657634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b8082018082111561047c5761047c610f9c565b600060018201610fd757610fd7610f9c565b506001019056fea26469706673582212207bede9966bc8e8634cc0c3dc076626579b27dff7bbcac0b645c87d4cf1812b9864736f6c63430008140033
    
    local constructor_args
    constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' 'Bridge Test' 'BT' "$eth_address" 100000000000000000000 | sed 's/0x//')
    
    cast create2 --salt $salt --init-code $erc_20_bytecode"$constructor_args"
}

# =============================================================================
# Test Cases
# =============================================================================
# bats test_tags=bridge
@test "Initial setup" {
    [[ -f "$BATS_TEST_DIRNAME/assets/bridge-tests-suite.json" ]] || {
        _log_file_descriptor "3" "Bridge Tests Suite file not found"
        skip "Bridge Tests Suite file not found"
    }

    echo "ETH_RPC_TIMEOUT: $ETH_RPC_TIMEOUT" >&3

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
    skip
    _log_file_descriptor "3" "Starting L1 to L2 parallel bridge scenarios and claims test"
    [[ -f "$BATS_TEST_DIRNAME/assets/bridge-tests-suite.json" ]] || {
        _log_file_descriptor "3" "Bridge Tests Suite file not found"
        skip "Bridge Tests Suite file not found"
    }

    export test_erc20_addr
    test_erc20_addr="$(_calculate_test_erc20_address "$l1_eth_address")"

    # Create output directory with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$log_root_dir/bridge_test_results_l1_to_l2_${timestamp}"
    mkdir -p "$output_dir"
    
    _log_file_descriptor "3" "Test results will be saved to: $output_dir"

    
    # Get total number of scenarios
    local total_scenarios
    total_scenarios=$(echo "$scenarios" | jq '. | length')
    _log_file_descriptor "3" "Total scenarios to process: $total_scenarios"
    
    # Save detailed setup log
    local setup_log="$output_dir/setup_phase.log"

    echo "" | tee "$setup_log" >&3
    echo "========================================" | tee -a "$setup_log" >&3
    echo "      PHASE 1: SEQUENTIAL SETUP         " | tee -a "$setup_log" >&3
    echo "              L1 -> L2                  " | tee -a "$setup_log" >&3
    echo "========================================" | tee -a "$setup_log" >&3
    
    # Phase 1: Sequential setup of all test accounts
    local index=0
    local setup_failures=0
    local successful_setups=()  # Array to track successfully set up test indices

    _log_file_descriptor "3" "Setting up $total_scenarios test accounts..." | tee -a "$setup_log"

    while read -r scenario; do
        local progress_percent=$((index * 100 / total_scenarios))
        _log_file_descriptor "3" "[$progress_percent%] Setting up test account $index/$total_scenarios" | tee -a "$setup_log"
        
        if ! _setup_single_test_account "$index" "$scenario" "L1_TO_L2" 2>>"$output_dir/setup_debug_${index}.log"; then
            _log_file_descriptor "3" "❌ Failed to set up account for test $index" | tee -a "$setup_log"
            setup_failures=$((setup_failures + 1))
        else
            _log_file_descriptor "3" "✅ Successfully set up account for test $index" | tee -a "$setup_log"
            successful_setups+=("$index")  # Track successful setup
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')

    local successful_count=${#successful_setups[@]}

    _log_file_descriptor "3" "" | tee -a "$setup_log"
    _log_file_descriptor "3" "Setup Phase Complete:" | tee -a "$setup_log"
    _log_file_descriptor "3" "  ✅ Successful setups: $successful_count" | tee -a "$setup_log"
    _log_file_descriptor "3" "  ❌ Failed setups: $setup_failures" | tee -a "$setup_log"

    if [[ $setup_failures -gt 0 ]]; then
        echo "Failed to set up $setup_failures out of $total_scenarios test accounts" | tee -a "$setup_log" >&3
        echo "Successfully set up $successful_count accounts" | tee -a "$setup_log" >&3
        echo "Setup logs saved to: $output_dir/setup_*.log" | tee -a "$setup_log" >&3
        
        # Continue with successful setups if we have any
        if [[ $successful_count -eq 0 ]]; then
            echo "No accounts were successfully set up, aborting test" | tee -a "$setup_log" >&3
            return 1
        fi
    else
        echo "All $total_scenarios test accounts set up successfully" | tee -a "$setup_log" >&3
    fi

    # Save detailed bridge test log
    local bridge_log="$output_dir/bridge_phase.log"

    echo "" | tee "$bridge_log" >&3
    echo "========================================" | tee -a "$bridge_log" >&3
    echo "      PHASE 2: PARALLEL BRIDGE TESTS    " | tee -a "$bridge_log" >&3
    echo "              L1 -> L2                  " | tee -a "$bridge_log" >&3
    echo "========================================" | tee -a "$bridge_log" >&3

    # Phase 2: Run bridge tests in parallel - only for successfully set up accounts
    # Set concurrency to match number of tests to avoid deadlock scenarios
    # where all concurrent slots are occupied by stuck/retrying tests
    max_concurrent=$successful_count

    echo "Running bridge tests for $successful_count successfully set up accounts" | tee -a "$bridge_log" >&3
    echo "Using max concurrency: $max_concurrent" | tee -a "$bridge_log" >&3

    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "Starting parallel bridge tests with max concurrency: $max_concurrent" | tee -a "$bridge_log"
    
    local pids=()
    local scenario_array
    scenario_array=()
    while IFS= read -r line; do
        scenario_array+=("$line")
    done < <(echo "$scenarios" | jq -c '.[]')
    
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
                _log_file_descriptor "3" "[${progress_percent}%] Completed: $completed_tests/$successful_count bridge tests"
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
        _log_file_descriptor "3" "[${start_progress_percent}%] Starting bridge test $test_index (${started_tests}/${successful_count})" | tee -a "$bridge_log"
        
        _run_single_bridge_test "$test_index" "${scenario_array[$test_index]}" "L1_TO_L2" 2>"$output_dir/bridge_test_${test_index}.log" &
        local test_pid=$!
        pids+=("$test_pid")
        
        # Small delay to stagger test starts
        sleep 0.1
        
    done
    
    _log_file_descriptor "3" "Started all ${#successful_setups[@]} parallel bridge test processes" | tee -a "$bridge_log"
    
    # Wait for all remaining background processes to complete
    local wait_start
    wait_start=$(date +%s)
    
    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "Waiting for all bridge tests to complete..."
    
    while (( ${#pids[@]} > 0 )); do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - wait_start))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        if (( elapsed > ${global_timeout%s} )); then
            _log_file_descriptor "3" "Timeout reached after ${elapsed_minutes}m${elapsed_seconds}s, killing remaining processes..." | tee -a "$bridge_log"
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
            _log_file_descriptor "3" "[${progress_percent}%] Completed: $completed_tests/$successful_count tests (${remaining_tests} remaining) - ${elapsed_minutes}m${elapsed_seconds}s elapsed"
        fi
        
        # Rebuild pids array to remove gaps
        pids=("${pids[@]}")
        
        # Show periodic progress even if no completions
        if (( elapsed % 30 == 0 )); then
            local active_processes=${#pids[@]}
            _log_file_descriptor "3" "Status: $active_processes tests still running, $completed_tests/$successful_count completed - ${elapsed_minutes}m${elapsed_seconds}s elapsed"
        fi
        
        # Wait a bit before checking again
        sleep 1
    done
    
    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "All bridge tests completed! Collecting results..."
    
    # Collect and report results - pass the successful count instead of total
    _collect_and_report_results "$output_dir" "$bridge_log" "$successful_count"
    local failed_tests=$?
    
    # Report setup failures in the final summary but don't fail the test for them
    if [[ $setup_failures -gt 0 ]]; then
        _log_file_descriptor "3" "Note: $setup_failures accounts failed setup and were skipped"
    fi
    
    # Fail the test only if bridge tests failed (not setup failures)
    [[ $failed_tests -eq 0 ]] || {
        _log_file_descriptor "3" "Some bridge tests failed. Check the detailed logs in $output_dir"
        return 1
    }
}


# bats test_tags=bridge
@test "Process L2 to L1 bridge scenarios and claim deposits in parallel" {
    _log_file_descriptor "3" "Starting L2 to L1 parallel bridge scenarios and claims test"
    [[ -f "$BATS_TEST_DIRNAME/assets/bridge-tests-suite.json" ]] || {
        echo "Bridge Tests Suite file not found" >&3
        skip "Bridge Tests Suite file not found"
    }

    export test_erc20_addr
    test_erc20_addr="$(_calculate_test_erc20_address "$l2_eth_address")"

    # Create output directory with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$log_root_dir/bridge_test_results_l2_to_l1_${timestamp}"
    mkdir -p "$output_dir"
    
    _log_file_descriptor "3" "Test results will be saved to: $output_dir"

    
    # Get total number of scenarios
    local total_scenarios
    total_scenarios=$(echo "$scenarios" | jq '. | length')
    _log_file_descriptor "3" "Total scenarios to process: $total_scenarios"
    
    # Save detailed setup log
    local setup_log="$output_dir/setup_phase.log"
    
    echo "" | tee "$setup_log" >&3
    echo "========================================" | tee -a "$setup_log" >&3
    echo "      PHASE 1: SEQUENTIAL SETUP         " | tee -a "$setup_log" >&3
    echo "              L2 -> L1                  " | tee -a "$setup_log" >&3
    echo "========================================" | tee -a "$setup_log" >&3
    
    # Phase 1: Sequential setup of all test accounts
    local index=0
    local setup_failures=0
    local successful_setups=()  # Array to track successfully set up test indices

    echo "Setting up $total_scenarios test accounts..." | tee -a "$setup_log" >&3

    while read -r scenario; do
        local progress_percent=$((index * 100 / total_scenarios))
        echo "[$progress_percent%] Setting up test account $index/$total_scenarios" | tee -a "$setup_log" >&3
        
        if ! _setup_single_test_account "$index" "$scenario" "L2_TO_L1" 2>>"$output_dir/setup_debug_${index}.log"; then
            echo "❌ Failed to set up account for test $index" | tee -a "$setup_log" >&3
            setup_failures=$((setup_failures + 1))
        else
            echo "✅ Successfully set up account for test $index" | tee -a "$setup_log" >&3
            successful_setups+=("$index")  # Track successful setup
        fi
        
        index=$((index + 1))
    done < <(echo "$scenarios" | jq -c '.[]')

    local successful_count=${#successful_setups[@]}

    echo "" | tee -a "$setup_log" >&3
    echo "Setup Phase Complete:" | tee -a "$setup_log" >&3
    echo "  ✅ Successful setups: $successful_count" | tee -a "$setup_log" >&3
    echo "  ❌ Failed setups: $setup_failures" | tee -a "$setup_log" >&3

    if [[ $setup_failures -gt 0 ]]; then
        echo "Failed to set up $setup_failures out of $total_scenarios test accounts" | tee -a "$setup_log" >&3
        echo "Successfully set up $successful_count accounts" | tee -a "$setup_log" >&3
        echo "Setup logs saved to: $output_dir/setup_*.log" | tee -a "$setup_log" >&3
        
        # Continue with successful setups if we have any
        if [[ $successful_count -eq 0 ]]; then
            echo "No accounts were successfully set up, aborting test" | tee -a "$setup_log" >&3
            return 1
        fi
    else
        echo "All $total_scenarios test accounts set up successfully" | tee -a "$setup_log" >&3
    fi

    # Save detailed bridge test log
    local bridge_log="$output_dir/bridge_phase.log"

    echo "" | tee "$bridge_log" >&3
    echo "========================================" | tee -a "$bridge_log" >&3
    echo "      PHASE 2: PARALLEL BRIDGE TESTS    " | tee -a "$bridge_log" >&3
    echo "              L2 -> L1                  " | tee -a "$bridge_log" >&3
    echo "========================================" | tee -a "$bridge_log" >&3

    # Phase 2: Run bridge tests in parallel - only for successfully set up accounts
    # Set concurrency to match number of tests to avoid deadlock scenarios
    # where all concurrent slots are occupied by stuck/retrying tests
    max_concurrent=$successful_count

    echo "Running bridge tests for $successful_count successfully set up accounts" | tee -a "$bridge_log" >&3
    echo "Using max concurrency: $max_concurrent" | tee -a "$bridge_log" >&3

    echo "" | tee -a "$bridge_log" >&3
    echo "Starting parallel bridge tests with max concurrency: $max_concurrent" | tee -a "$bridge_log" >&3
    
    local pids=()
    local scenario_array
    scenario_array=()
    while IFS= read -r line; do
        scenario_array+=("$line")
    done < <(echo "$scenarios" | jq -c '.[]')
    
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
                _log_file_descriptor "3" "[${progress_percent}%] Completed: $completed_tests/$successful_count bridge tests"
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

    echo "" | tee -a "$bridge_log" >&3
    echo "Waiting for all bridge tests to complete..." | tee -a "$bridge_log" >&3
    
    while (( ${#pids[@]} > 0 )); do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - wait_start))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        if (( elapsed > ${global_timeout%s} )); then
            _log_file_descriptor "3" "Timeout reached after ${elapsed_minutes}m${elapsed_seconds}s, killing remaining processes..." | tee -a "$bridge_log"
            for pid in "${pids[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            break
        fi
        
        # Check for completed processes
        local new_completions=0
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                _log_file_descriptor "3" "Bridge test process ${pids[$i]} completed" | tee -a "$bridge_log"
                unset 'pids[$i]'
                new_completions=$((new_completions + 1))
            fi
        done
        
        # Update progress if we had completions
        if [[ $new_completions -gt 0 ]]; then
            completed_tests=$((completed_tests + new_completions))
            local progress_percent=$((completed_tests * 100 / successful_count))
            local remaining_tests=$((successful_count - completed_tests))
            _log_file_descriptor "3" "[${progress_percent}%] Completed: $completed_tests/$successful_count tests (${remaining_tests} remaining) - ${elapsed_minutes}m${elapsed_seconds}s elapsed"
        fi
        
        # Rebuild pids array to remove gaps
        pids=("${pids[@]}")
        
        # Show periodic progress even if no completions
        if (( elapsed % 30 == 0 )); then
            local active_processes=${#pids[@]}
            _log_file_descriptor "3" "Status: $active_processes tests still running, $completed_tests/$successful_count completed - ${elapsed_minutes}m${elapsed_seconds}s elapsed"
        fi
        
        # Wait a bit before checking again
        sleep 1
    done
    
    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "All bridge tests completed! Collecting results..."
    
    # Collect and report results - pass the successful count instead of total
    _collect_and_report_results "$output_dir" "$bridge_log" "$successful_count"
    local failed_tests=$?
    
    # Report setup failures in the final summary but don't fail the test for them
    if [[ $setup_failures -gt 0 ]]; then
        _log_file_descriptor "3" "Note: $setup_failures accounts failed setup and were skipped"
    fi
    
    # Fail the test only if bridge tests failed (not setup failures)
    [[ $failed_tests -eq 0 ]] || {
        _log_file_descriptor "3" "Some bridge tests failed. Check the detailed logs in $output_dir"
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

# bats test_tags=bridge
@test "Reclaim test funds" {
    # Sanity check for l1_rpc_url
    if [[ -z "$l1_rpc_url" ]]; then
        _log_file_descriptor "3" "l1_rpc_url is empty"
        return 1
    fi

    # Sanity check for l2_rpc_url
    if [[ -z "$l2_rpc_url" ]]; then
        _log_file_descriptor "3" "l2_rpc_url is empty"
        return 1
    fi

    # Check and reclaim funds for L1
    if [[ ! "$l1_rpc_url" =~ 127.0.0.1 ]]; then
        _log_file_descriptor "3" "Non-Kurtosis L1 network detected, attempting to reclaim funds..."
        _reclaim_funds_after_test "$l1_eth_address" "$l1_rpc_url"
    else
        _log_file_descriptor "3" "Kurtosis L1 network detected, skipping reclaiming funds..."
    fi

    # Check and reclaim funds for L2
    if [[ ! "$l2_rpc_url" =~ 127.0.0.1 ]]; then
        _log_file_descriptor "3" "Non-Kurtosis L2 network detected, attempting to reclaim funds..."
        _reclaim_funds_after_test "$l2_eth_address" "$l2_rpc_url"
    else
        _log_file_descriptor "3" "Kurtosis L2 network detected, skipping reclaiming funds..."
    fi
}