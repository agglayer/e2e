#!/bin/bash

# Default common image for all commands
NETTOOLS_IMAGE="ghcr.io/alexei-led/pumba-alpine-nettools:latest"

# Check if duration and JSON matrix file are provided as arguments
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 <duration in ms/s/m/h value> <path_to_test_matrix.json>"
    exit 1
fi
DURATION="$1"
MATRIX_FILE="$2"

# Verify jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required to parse JSON. Please install jq."
    exit 1
fi

# Verify JSON file exists
if [[ ! -f "$MATRIX_FILE" ]]; then
    echo "Error: JSON matrix file $MATRIX_FILE does not exist."
    exit 1
fi

# Create main log directory
LOG_DIR="chaos_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"


# Get list of running container names
RUNNING_CONTAINERS=("$(docker ps --format '{{.Names}}')")
if [[ ${#RUNNING_CONTAINERS[@]} -eq 0 ]]; then
    echo "No running containers found!" | tee -a "$LOG_DIR/test_parameters.log"
    exit 1
fi

# Extract unique container names from JSON matrix
UNIQUE_CONTAINERS=("$(jq -r '.[] | .container' "$MATRIX_FILE" | sort -u)")
if [[ ${#UNIQUE_CONTAINERS[@]} -eq 0 ]]; then
    echo "No containers found in JSON matrix!" | tee -a "$LOG_DIR/test_parameters.log"
    exit 1
fi

# Validate containers
VALID_CONTAINERS=()
for container in "${UNIQUE_CONTAINERS[@]}"; do
    # Check if container is running
    if echo "${RUNNING_CONTAINERS[@]}" | grep -qw "$container"; then
        VALID_CONTAINERS+=("$container")
    else
        echo "Warning: Container $container is not running and will be skipped" | tee -a "$LOG_DIR/test_parameters.log"
    fi
done

if [[ ${#VALID_CONTAINERS[@]} -eq 0 ]]; then
    echo "No valid containers found after validation!" | tee -a "$LOG_DIR/test_parameters.log"
    exit 1
fi

echo "Valid containers: ${VALID_CONTAINERS[*]}" | tee -a "$LOG_DIR/test_parameters.log"

# Read JSON matrix and iterate through each test case
TEST_CASES=$(jq -c '.[]' "$MATRIX_FILE")
TEST_INDEX=1

while IFS= read -r test_case; do
    # Create test-specific log directory
    TEST_LOG_DIR="$LOG_DIR/test_$TEST_INDEX"
    mkdir -p "$TEST_LOG_DIR"

    # Extract parameters from JSON
    CONTAINER=$(echo "$test_case" | jq -r '.container')
    PERCENT=$(echo "$test_case" | jq -r '.percent')
    PROBABILITY=$(echo "$test_case" | jq -r '.probability')
    RATE=$(echo "$test_case" | jq -r '.rate')
    JITTER=$(echo "$test_case" | jq -r '.jitter')

    # Skip if container is not valid
    if ! echo "${VALID_CONTAINERS[@]}" | grep -qw "$CONTAINER"; then
        echo "Skipping test case $TEST_INDEX: Container $CONTAINER is invalid or excluded" | tee -a "$TEST_LOG_DIR/test_parameters.log"
        ((TEST_INDEX++))
        continue
    fi

    echo "Running test case $TEST_INDEX" | tee -a "$TEST_LOG_DIR/test_parameters.log"

    # Log test parameters
    echo "Test Case $TEST_INDEX Parameters:" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Container: $CONTAINER" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Duration: $DURATION" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Percent: $PERCENT%" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Probability: $PROBABILITY" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Rate: $RATE" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    echo "Jitter: $JITTER ms" | tee -a "$TEST_LOG_DIR/test_parameters.log"

    # Start collecting container logs in background
    docker logs "$CONTAINER" --follow > "$TEST_LOG_DIR/container_${CONTAINER}_logs.log" 2>&1 &
    CONTAINER_LOG_PID=$!

    # Add delay to egress traffic
    pumba --log-level debug netem \
      --duration "$DURATION" \
      --interface eth0 \
      --tc-image "$NETTOOLS_IMAGE" \
      delay \
      --time 500 \
      --jitter "$JITTER" \
      "$CONTAINER" > "$TEST_LOG_DIR/delay_test.log" 2>&1 &
    DELAY_PID=$!

    # Adds packet loss
    pumba --log-level debug netem \
      --duration "$DURATION" \
      --interface eth0 \
      --tc-image "$NETTOOLS_IMAGE" \
      loss \
      --percent "$PERCENT" \
      "$CONTAINER" > "$TEST_LOG_DIR/loss_test.log" 2>&1 &
    LOSS_PID=$!

    # Adds rate limiting
    pumba --log-level debug netem \
      --duration "$DURATION" \
      --interface eth0 \
      --tc-image "$NETTOOLS_IMAGE" \
      rate \
      --rate "$RATE" \
      --packetoverhead 0 \
      --cellsize 0 \
      --celloverhead 0 \
      "$CONTAINER" > "$TEST_LOG_DIR/ratelimit_test.log" 2>&1 &
    RATELIMIT_PID=$!

    # Adds packet duplication
    pumba --log-level debug net:em \
      --duration "$DURATION" \
      --interface eth0 \
      --tc-image "$NETTOOLS_IMAGE" \
      duplicate \
      --percent "$PERCENT" \
      "$CONTAINER" > "$TEST_LOG_DIR/duplicate_test.log" 2>&1 &
    DUPLICATE_PID=$!

    # Corrupt packets
    pumba --log-level debug netem \
      --duration "$DURATION" \
      --interface eth0 \
      --tc-image "$NETTOOLS_IMAGE" \
      corrupt \
      --percent "$PERCENT" \
      "$CONTAINER" > "$TEST_LOG_DIR/corrupt_test.log" 2>&1 &
    CORRUPT_PID=$!

    # Drop incoming packets
    pumba --log-level debug iptables \
      --duration "$DURATION" \
      --protocol tcp \
      --dst-port 80 \
      --iptables-image "$NETTOOLS_IMAGE" \
      loss \
      --probability "$PROBABILITY" \
      "$CONTAINER" > "$TEST_LOG_DIR/iptables_test.log" 2>&1 &
    IPTABLES_PID=$!

    # Wait for all chaos tests to complete
    wait $DELAY_PID
    wait $LOSS_PID
    wait $RATELIMIT_PID
    wait $DUPLICATE_PID
    wait $CORRUPT_PID
    wait $IPTABLES_PID

    # Stop container log collection
    kill $CONTAINER_LOG_PID 2>/dev/null
    wait $CONTAINER_LOG_PID 2>/dev/null

    echo "Test case $TEST_INDEX complete!" | tee -a "$TEST_LOG_DIR/test_parameters.log"
    ((TEST_INDEX++))
done <<< "$TEST_CASES"

echo "Network chaos complete! Logs saved in $LOG_DIR"