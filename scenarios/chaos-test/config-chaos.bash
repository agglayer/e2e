#!/bin/bash

###############################################################################
# config-chaos.bash
#
# This script performs configuration fuzz testing on the agglayer container.
# It randomly modifies selected fields in the agglayer TOML config file,
# copies the fuzzed config into the running container, and restarts it.
#
# Steps:
# 1. Checks if the agglayer container is running.
# 2. Copies the current config file from the container to a log directory.
# 3. Randomly fuzzes timeouts, intervals, buffer sizes, ports, booleans, etc.
#    - Some fields are always fuzzed, others are fuzzed with a probability.
# 4. Copies the fuzzed config back into the container.
# 5. Restarts the container to apply the new configuration.
#
# Usage:
#   bash config-chaos.bash
#
# Output:
#   - All configs and logs are saved in a timestamped directory under $PWD.
#   - The agglayer container will be restarted with the fuzzed configuration.
###############################################################################

is_container_running() {
    local container_id="$1"
    docker ps --format '{{.ID}}' | grep -qw "$container_id"
}

if ! is_container_running "$agglayer_container_uuid"; then
    echo "Error: Container $agglayer_container_uuid is not running."
    exit 1
fi

# Set ROOT_DIR to current working directory if not already set
LOG_ROOT_DIR="${LOG_ROOT_DIR:-$PWD}"

# Create main log directory
LOG_DIR="${LOG_ROOT_DIR}/config_chaos_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# Configuration: Single probability for fuzzing any parameter (0.0 to 1.0)
FUZZ_PROB=0.05  # 5% chance to fuzz each parameter

# Get agglayer configs
agglayer_container_uuid=$(docker ps --format '{{.Names}} {{.ID}}' --no-trunc | grep "agglayer--" | awk '{print $2}')
docker cp $agglayer_container_uuid:/etc/zkevm/agglayer-config.toml $LOG_DIR/initial-agglayer-config.toml

# Helper functions to generate random values
_rand_int() {
    local min=$1
    local max=$2
    echo $((RANDOM % (max - min + 1) + min))
}

_rand_float() {
    local min=$1
    local max=$2
    local scale=$3
    local range=$(echo "($max - $min) * $scale" | bc)
    local random_val=$(echo "$min * $scale + ($RANDOM % $range)" | bc)
    echo "scale=$scale; $random_val / $scale" | bc
}

_rand_bool() {
    if [[ $((RANDOM % 2)) -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to decide whether to fuzz a parameter based on FUZZ_PROB
_should_fuzz() {
    local prob_int=$(echo "$FUZZ_PROB * 100" | bc | cut -d. -f1)
    [[ -z "$prob_int" ]] && prob_int=0
    local rand=$((RANDOM % 100))
    if [[ $rand -lt $prob_int ]]; then
        return 0  # Fuzz the parameter
    else
        return 1  # Don't fuzz the parameter
    fi
}

# Function to fuzz a TOML configuration file by modifying sensible fields
# Generates a large number of unique configurations using randomization
_generate_fuzzed_agglayer_configs() {
    # Input and output files
    INPUT_FILE="$LOG_DIR/initial-agglayer-config.toml"
    OUTPUT_FILE="$LOG_DIR/fuzzed-agglayer-config.toml"

    # Check if input file exists
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "Error: Input file $INPUT_FILE not found"
        exit 1
    fi

    # Read the input TOML file
    cp "$INPUT_FILE" "$OUTPUT_FILE"

    # =============================================================================
    # Parameters to always fuzz
    # =============================================================================
    # Timeouts and intervals
    sed -i "s/request-timeout = 180/request-timeout = $(_rand_int 60 300)/" "$OUTPUT_FILE"
    sed -i "s/settlement-timeout = 1200/settlement-timeout = $(_rand_int 600 1800)/" "$OUTPUT_FILE"
    sed -i "s/retry-interval = 7/retry-interval = $(_rand_int 5 15)/" "$OUTPUT_FILE"
    sed -i "s/rpc-timeout = 45/rpc-timeout = $(_rand_int 30 90)/" "$OUTPUT_FILE"
    sed -i "s/runtime-timeout = 5/runtime-timeout = $(_rand_int 3 10)/" "$OUTPUT_FILE"

    # Size limits
    sed -i "s/max-request-body-size = 104857600/max-request-body-size = $(_rand_int 52428800 209715200)/" "$OUTPUT_FILE"
    sed -i "s/max-decoding-message-size = 104857600/max-decoding-message-size = $(_rand_int 52428800 209715200)/" "$OUTPUT_FILE"

    # Retry and gas settings
    sed -i "s/max-retries = 3/max-retries = $(_rand_int 1 5)/" "$OUTPUT_FILE"
    sed -i "s/gas-multiplier-factor = 175/gas-multiplier-factor = $(_rand_int 25 325)/" "$OUTPUT_FILE"

    # Epoch duration
    sed -i "s/epoch-duration = 15/epoch-duration = $(_rand_int 10 30)/" "$OUTPUT_FILE"

    # Rate limiting (randomly enable/disable or set values)
    if [[ $((RANDOM % 2)) -eq 0 ]]; then
        sed -i "s/send-tx = \"unlimited\"/# send-tx = \"limited\"/" "$OUTPUT_FILE"
        sed -i "s/# \[rate-limiting.send-tx\]/[rate-limiting.send-tx]/" "$OUTPUT_FILE"
        sed -i "s/# max-per-interval = 1/max-per-interval = $(_rand_int 1 5)/" "$OUTPUT_FILE"
        sed -i "s/# time-interval = \"15m\"/time-interval = \"$(_rand_int 0 30)m\"/" "$OUTPUT_FILE"
    else
        sed -i "s/send-tx = \"unlimited\"/send-tx = \"unlimited\"/" "$OUTPUT_FILE"
        sed -i "s/\[rate-limiting.send-tx\]/# [rate-limiting.send-tx]/" "$OUTPUT_FILE"
    fi

    # Buffer size
    sed -i "s/input-backpressure-buffer-size = 1000/input-backpressure-buffer-size = $(_rand_int 25 2000)/" "$OUTPUT_FILE"

    # Backup counts
    sed -i "s/state-max-backup-count = 100/state-max-backup-count = $(_rand_int 5 225)/" "$OUTPUT_FILE"
    sed -i "s/pending-max-backup-count = 100/pending-max-backup-count = $(_rand_int 5 225)/" "$OUTPUT_FILE"

    # =============================================================================
    # Parameters to fuzz probabilistically
    # =============================================================================
    # Ports (grpc-port, readrpc-port, admin-port, prometheus-addr port)
    if _should_fuzz; then
        sed -i "s/grpc-port = 4443/grpc-port = $(_rand_int 4443 4446)/" "$OUTPUT_FILE"
    fi
    if _should_fuzz; then
        sed -i "s/readrpc-port = 4444/readrpc-port = $(_rand_int 4443 4446)/" "$OUTPUT_FILE"
    fi
    if _should_fuzz; then
        sed -i "s/admin-port = 4446/admin-port = $(_rand_int 4443 4446)/" "$OUTPUT_FILE"
    fi

    # Boolean flags
    if _should_fuzz; then
        sed -i "s/mock-verifier = true/mock-verifier = $(_rand_bool)/" "$OUTPUT_FILE"
    fi

    echo "Generated fuzzed configuration: $OUTPUT_FILE"
}

# Call the function
_generate_fuzzed_agglayer_configs

# Replace the initial configs with fuzzed configs in the agglayer container
docker cp $LOG_DIR/fuzzed-agglayer-config.toml $agglayer_container_uuid:/etc/zkevm/agglayer-config.toml

# Restart the container
docker stop $agglayer_container_uuid
docker start $agglayer_container_uuid
