#!/usr/bin/env bats

# Run this bats test from the root e2e directory.

# Array to track all PIDs for cleanup
declare -a ALL_PIDS=()

setup_file() {
    export ENCLAVE_NAME
    export L2_RPC_URL
    export TEST_DURATION
    export TEST_TIMEOUT
    export LOG_ROOT_DIR
    export TMP_DIR

    ENCLAVE_NAME="${ENCLAVE_NAME:-cdk}"
    L2_RPC_URL="${L2_RPC_URL:-"$(kurtosis port print "$ENCLAVE_NAME" cdk-erigon-rpc-001 rpc)"}"
    TEST_DURATION="${TEST_DURATION:-1200s}"
    TEST_TIMEOUT="${TEST_TIMEOUT:-1260s}" # Default timeout for individual tests
    # Directory where the logs will be stored
    LOG_ROOT_DIR="${LOG_ROOT_DIR:-"./scenarios/monitored-tests/post-state"}"
    TMP_DIR=$(mktemp -d)

    _check_docker_network_exists
    _parse_pre_state_input
    echo "tmp directory created at: $TMP_DIR" >&3

    # Trap SIGINT to handle Ctrl+C
    trap '_handle_interrupt' SIGINT
}

teardown_file() {
    # Cleanup any remaining processes
    if [[ ${#ALL_PIDS[@]} -gt 0 ]]; then
        for pid in "${ALL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "Terminating process $pid" >&3
                kill "$pid" 2>/dev/null
            fi
        done
    fi
}

_handle_interrupt() {
    echo "Received Ctrl+C, cleaning up..." >&3
    teardown_file
    exit 1
}

_check_docker_network_exists() {
    if docker network ls --filter name=^kt-"${ENCLAVE_NAME}"$ --format '{{.Name}}' | grep -q "^kt-${ENCLAVE_NAME}$"; then
        echo "Network 'kt-${ENCLAVE_NAME}' exists." >&3
    else
        echo "Network 'kt-${ENCLAVE_NAME}' does not exist." >&3
        exit 1
    fi
}

_parse_pre_state_input() {
    # parse chaos-test input matrix
    cat "./scenarios/monitored-tests/pre-state/test_input_template.json" | jq '."chaos_test"' > "$TMP_DIR"/chaos_test_input.json
    echo "chaos_test_input created at: $TMP_DIR/chaos_test_input.json" >&3

    # parse stress-test input matrix
    cat "./scenarios/monitored-tests/pre-state/test_input_template.json" | jq '."stress_test"' > "$TMP_DIR"/stress_test_input.json
    echo "stress_test_input created at: $TMP_DIR/stress_test_input.json" >&3

    # parse e2e-tests to run
    cat "./scenarios/monitored-tests/pre-state/test_input_template.json" | jq '."e2e_tests"' > "$TMP_DIR"/e2e_tests.json
    echo "e2e_tests to run created at: $TMP_DIR/e2e_tests.json" >&3 

    echo "====================================================" >&3
}

@test "Run tests combinations" {
    # Run network-chaos test
    bash ./scenarios/chaos-test/network-chaos.bash "$TEST_DURATION" "$TMP_DIR"/chaos_test_input.json &
    CHAOS_TEST_PID=$!
    ALL_PIDS+=("$CHAOS_TEST_PID")
    echo "Chaos test PID: $CHAOS_TEST_PID" >&3

    # Run container-stress test
    export STRESS_TEST_INPUT
    STRESS_TEST_INPUT=$TMP_DIR/stress_test_input.json
    bats ./scenarios/stress-test/container-stress.bats &
    STRESS_TEST_PID=$!
    ALL_PIDS+=("$STRESS_TEST_PID")
    echo "Stress test PID: $STRESS_TEST_PID" >&3

    # Run E2E tests from e2e_tests.json
    if [[ ! -f "$TMP_DIR/e2e_tests.json" ]]; then
        echo "E2E tests file not found: $TMP_DIR/e2e_tests.json" >&3
        exit 1
    fi

    # Read E2E test file paths into an array
    mapfile -t E2E_TEST_FILES < <(jq -r '.[]' "$TMP_DIR/e2e_tests.json")

    if [[ ${#E2E_TEST_FILES[@]} -eq 0 ]]; then
        echo "No E2E test files found in $TMP_DIR/e2e_tests.json" >&3
    else
        echo "Found ${#E2E_TEST_FILES[@]} E2E test files to run" >&3

        # Run each E2E test in parallel with timeout
        for test_file in "${E2E_TEST_FILES[@]}"; do
            if [[ ! -f "$test_file" ]]; then
                echo "E2E test file not found: $test_file" >&3
                exit 1
            fi
            timeout "$TEST_TIMEOUT" bats "$test_file" &
            # Give time for each test to run and to avoid nonce conflicts during funding
            sleep 5
            local e2e_pid=$!
            ALL_PIDS+=("$e2e_pid")
            echo "E2E test file $test_file started with PID: $e2e_pid" >&3
        done
    fi

    # Wait for all tests to complete
    failed=false
    for pid in "${ALL_PIDS[@]}"; do
        wait "$pid" || {
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                echo "Test (PID $pid) timed out after $TEST_TIMEOUT" >&3
            else
                echo "Test (PID $pid) failed with exit code $exit_code" >&3
            fi
            failed=true
}
    done

    # Check if any test failed
    if $failed; then
        exit 1
    fi

    echo "All tests completed successfully" >&3
}