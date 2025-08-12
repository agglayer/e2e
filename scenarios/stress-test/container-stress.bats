#!/usr/bin/env bats

# Array to track all PIDs for cleanup
declare -a ALL_PIDS=()

setup() {
    # Set default values if not provided via environment variables
    DURATION="${TEST_DURATION:-30s}"
    MATRIX_FILE="${STRESS_TEST_INPUT:-./assets/container_mappings.json}"
    
    # Set ROOT_DIR to current working directory if not already set
    LOG_ROOT_DIR="${LOG_ROOT_DIR:-$PWD}"

    # Create timestamped log directory
    LOG_DIR="${LOG_ROOT_DIR}/stress_logs_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$LOG_DIR"
    
    echo "Stress test logs will be saved to: $LOG_DIR" >&3
    
    # Trap SIGINT to handle Ctrl+C
    trap 'handle_interrupt' SIGINT

    _load_containers_to_target
}

teardown() {
    # Cleanup any remaining processes
    if [[ ${#ALL_PIDS[@]} -gt 0 ]]; then
        for pid in "${ALL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "Terminating process $pid" >&3
                kill "$pid" 2>/dev/null
            fi
        done
    fi

    # Cleanup any remaining log processes and PID files
    if [[ -d "$LOG_DIR" ]]; then
        # Find and kill any remaining docker logs processes
        for pid_file in "$LOG_DIR"/*/log_pid; do
            if [[ -f "$pid_file" ]]; then
                local pid
                pid=$(cat "$pid_file")
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Terminating log process $pid" >&3
                    kill "$pid" 2>/dev/null
                fi
                rm -f "$pid_file"
            fi
        done
        
        echo "All stress test logs saved to: $LOG_DIR" >&3
        echo "Review logs with: ls -la $LOG_DIR" >&3
    fi
}

handle_interrupt() {
    echo "Received Ctrl+C, cleaning up..." >&3
    # Call teardown to handle cleanup
    teardown
    exit 1
}

_load_containers_to_target() {
    # Check if the container mappings file exists
    if [[ ! -f "$MATRIX_FILE" ]]; then
        echo "Container mappings file not found: $MATRIX_FILE" >&3
        echo "Please run: ./assets/generate-container-mappings.sh" >&3
        exit 1
    fi

    # Read container IDs from the JSON file into an array
    mapfile -t CONTAINER_IDS < <(jq -r '.[].id' "$MATRIX_FILE")

    if [[ ${#CONTAINER_IDS[@]} -eq 0 ]]; then
        echo "No container IDs found in mapping file: $MATRIX_FILE" >&3
        exit 1
    fi

    echo "Found ${#CONTAINER_IDS[@]} containers to stress test for duration: $DURATION" >&3
    echo "Using container mappings from: $MATRIX_FILE" >&3
    
    # Save test parameters
    cat > "$LOG_DIR/test_parameters.log" << EOF
Stress Test Parameters
=====================
Timestamp: $(date)
Duration: $DURATION
Mapping File: $MATRIX_FILE
Total Containers: ${#CONTAINER_IDS[@]}

Container Mappings:
EOF
    jq '.' "$MATRIX_FILE" >> "$LOG_DIR/test_parameters.log"
}

_start_container_logging() {
    local container_id="$1"
    local test_type="$2"
    local container_log_dir="$LOG_DIR/container_${container_id}_${test_type}"
    
    mkdir -p "$container_log_dir"
    
    # Get container name for readability
    local container_name
    container_name=$(jq -r ".[] | select(.id==\"$container_id\") | .name" "$MATRIX_FILE")
    
    # Save container info
    cat > "$container_log_dir/container_info.log" << EOF
Container Information
====================
Name: $container_name
ID: $container_id
Test Type: $test_type
Start Time: $(date)
EOF
    
    # Start logging container output
    echo "Starting log capture for container: $container_name ($container_id)" >&3
    docker logs -f "$container_id" > "$container_log_dir/container_logs.log" 2>&1 &
    local log_pid=$!
    
    # Save the PID for later cleanup
    echo "$log_pid" > "$container_log_dir/log_pid"
    ALL_PIDS+=("$log_pid")
    
    echo "$log_pid"
}

_stop_container_logging() {
    local container_id="$1"
    local test_type="$2"
    local container_log_dir="$LOG_DIR/container_${container_id}_${test_type}"
    
    if [[ -f "$container_log_dir/log_pid" ]]; then
        local log_pid
        log_pid=$(cat "$container_log_dir/log_pid")
        if kill -0 "$log_pid" 2>/dev/null; then
            kill "$log_pid" 2>/dev/null
            echo "Stopped log capture for container: $container_id" >&3
        fi
        rm -f "$container_log_dir/log_pid"
    fi
    
    # Add end timestamp
    echo "End Time: $(date)" >> "$container_log_dir/container_info.log"
}

_run_stress_with_logging() {
    local container_id="$1"
    local test_type="$2"
    local stress_command="$3"
    local container_log_dir="$LOG_DIR/container_${container_id}_${test_type}"
    
    # Start container logging
    local log_pid
    log_pid=$(_start_container_logging "$container_id" "$test_type")
    
    # Get container name for display
    local container_name
    container_name=$(jq -r ".[] | select(.id==\"$container_id\") | .name" "$MATRIX_FILE")
    
    echo "Starting $test_type for container: $container_name ($container_id)" >&3
    
    # Run the stress test and capture its output
    run bash -c "sudo cgexec -g '*:system.slice/docker-${container_id}.scope' $stress_command" &
    local stress_pid=$!
    ALL_PIDS+=("$stress_pid")
    
    # Wait for the stress test to complete
    wait "$stress_pid"
    local status=$?
    
    # Save stress test output
    cat > "$container_log_dir/stress_test_output.log" << EOF
Stress Test Output
=================
Command: $stress_command
Exit Code: $status
Output:
$output

Error Output:
EOF
    
    if [[ -n "$output" ]]; then
        echo "$output" >> "$container_log_dir/stress_test_output.log"
    fi
    
    # Stop container logging
    _stop_container_logging "$container_id" "$test_type"
    
    echo "$test_type completed for container: $container_name" >&3
    echo "Exit code: $status" >&3
    echo "Logs saved to: $container_log_dir" >&3
    
    # Return the status for test assertion
    return $status
}

@test "CPU stress test with matrix operations" {
    local test_type="cpu_stress"
    
    # Loop through each container ID and run stress test
    for container_id in "${CONTAINER_IDS[@]}"; do
        local stress_command="stress-ng --matrix 0 -t $DURATION"
        
        _run_stress_with_logging "$container_id" "$test_type" "$stress_command"
        local stress_status=$?
        
        # Check if stress test was successful
        [[ "$stress_status" -eq 0 ]]
    done
}

@test "Memory stress test" {
    local test_type="memory_stress"
    
    for container_id in "${CONTAINER_IDS[@]}"; do
        local stress_command="stress-ng --vm 4 --vm-bytes 1024M -t $DURATION"
        
        _run_stress_with_logging "$container_id" "$test_type" "$stress_command"
        local stress_status=$?
        
        [[ "$stress_status" -eq 0 ]]
    done
}

@test "I/O stress test" {
    local test_type="io_stress"
    
    for container_id in "${CONTAINER_IDS[@]}"; do
        local stress_command="stress-ng --hdd 2 --hdd-bytes 64M -t $DURATION"
        
        _run_stress_with_logging "$container_id" "$test_type" "$stress_command"
        local stress_status=$?
        
        [[ "$stress_status" -eq 0 ]]
    done
}

@test "Disk Read/Write stress test" {
    local test_type="disk_read_write_stress"

    for container_id in "${CONTAINER_IDS[@]}"; do
        local stress_command="stress-ng --hdd 8 --io 8 --vm 8 -t $DURATION"

        _run_stress_with_logging "$container_id" "$test_type" "$stress_command"

        local stress_status=$?

        [[ "$stress_status" -eq 0 ]]
    done
}