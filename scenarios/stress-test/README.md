# Container Stress Testing

This directory contains stress testing tools for Docker containers using Linux cgroups and stress-ng to simulate high resource usage and test system resilience under load.
BATS tests format was used to isolate different stress tests, as running them in parallel would likely halt the host machine.

## Overview

The stress testing framework targets specific Docker containers and applies various types of stress conditions:

- **CPU Stress**: Matrix operations using all available CPU cores
- **Memory Stress**: Virtual memory allocation and operations
- **I/O Stress**: Hard disk read/write operations

All stress tests run within the container's cgroup boundaries, respecting Docker resource limits and constraints.

## Files Structure

```
scenarios/stress-test/
├── container-stress.bats           # Main BATS test file
├── env.example                     # Example environment configuration
├── assets/
│   ├── generate-container-mappings.sh  # Script to generate container mappings
│   └── container_mappings.json     # Generated container ID mappings
├── stress_logs_yyyymmdd_hhmmss/    # Generated logs for test
└── README.md                       # This documentation
```

## Prerequisites

1. **stress-ng**: Stress testing tool
2. **cgroup-tools**: Control group utilities
3. **jq**: JSON processor for parsing container mappings

## How to Run

### Generate Container Mappings

First, generate the container mappings to identify which containers to stress test:

```bash
# Generate container mappings (excludes system containers)
cd assets/
./generate-container-mappings.sh
```

This creates `container_mappings.json` with container names mapped to their full IDs.

### Using Environment File

```bash
# Source and run
source .env
bats container-stress.bats
```

### Run Specific Tests

```bash
# Run only CPU stress tests
bats container-stress.bats --filter "CPU stress"

# Run only memory tests
bats container-stress.bats --filter "Memory stress"

# Run only I/O tests
bats container-stress.bats --filter "I/O stress"
```

### Example Environment File

```bash
# env.example or .env
STRESS_DURATION=30s
CONTAINER_MAPPINGS_FILE="./assets/container_mappings.json"
```

## What the Tests Do

### CPU Stress Test (`@test "CPU stress test with matrix operations"`)

- **Purpose**: Tests CPU performance under heavy computational load
- **Method**: Runs matrix operations using all available CPU cores (`--matrix 0`)
- **Target**: Each container in the mappings file
- **Command**: `stress-ng --matrix 0 -t $DURATION`

### Memory Stress Test (`@test "Memory stress test"`)

- **Purpose**: Tests memory allocation and usage patterns
- **Method**: Creates 2 virtual memory workers, each allocating 128MB
- **Target**: Each container in the mappings file  
- **Command**: `stress-ng --vm 2 --vm-bytes 128M -t $DURATION`

### I/O Stress Test (`@test "I/O stress test"`)

- **Purpose**: Tests disk I/O performance and storage subsystem
- **Method**: Creates 2 hard disk workers, each writing 64MB of data
- **Target**: Each container in the mappings file
- **Command**: `stress-ng --hdd 2 --hdd-bytes 64M -t $DURATION`

## Container Selection and Exclusions

The [`generate-container-mappings.sh`](assets/generate-container-mappings.sh) script automatically excludes system containers:

```bash
EXCLUDE_CONTAINERS=("kurtosis-" "validator-key-generation-cl-validator-keystore" "test-runner" "contracts-001")
```

To modify which containers are excluded, edit this array in the script.

## How Cgroup Targeting Works

Each stress test runs within the specific container's cgroup:

```bash
sudo cgexec -g "*:system.slice/docker-${container_id}.scope" stress-ng [options]
```

- **`cgexec`**: Runs commands within specified cgroups
- **`*:system.slice/docker-${container_id}.scope`**: Container's cgroup path
- **Resource limits**: Respects Docker CPU, memory, and I/O constraints
- **Isolation**: Stress only affects the targeted container

## Container Mappings File

The `container_mappings.json` file contains container information:

```json
[
  {
    "name": "cdk-erigon-sequencer-001",
    "id": "4f479fdb201d8feca21104a2e161b8a1a940e8da52b2ef9a3df2886e1cb6119c"
  },
  {
    "name": "el-1-geth-lighthouse", 
    "id": "abc123def456..."
  }
]
```

This mapping allows the tests to:
1. Target containers by their full 64-character Docker ID
2. Provide readable container names in test output
3. Maintain consistency across test runs

## Log Analysis and Monitoring

### System Monitoring

While tests run, monitor system resources:

```bash
# Monitor overall system load
htop

# Monitor Docker container resources
docker stats

# Monitor cgroup usage
cat /sys/fs/cgroup/system.slice/docker-${container_id}.scope/memory.usage_in_bytes
```

### Container Logs

Monitor container behavior during stress tests:

```bash
# Follow container logs during stress testing
docker logs -f container_name

# Check for errors or performance degradation
docker logs container_name | grep -i error
```

### Running with E2E Tests

Stress tests can run alongside functional tests to validate resilience:

```bash
# Start stress tests in background
STRESS_DURATION="300s" bats container-stress.bats &
STRESS_PID=$!

# Run your functional tests
bats ../agglayer/bridges.bats

# Stop stress tests
kill $STRESS_PID
```

### Debugging

1. **Check container cgroup paths**:
   ```bash
   ls /sys/fs/cgroup/system.slice/ | grep docker
   ```

2. **Verify container is running**:
   ```bash
   docker ps --format '{{.Names}} {{.ID}}'
   ```

3. **Test cgroup access**:
   ```bash
   sudo cgexec -g "*:system.slice/docker-${container_id}.scope" echo "test"
   ```

4. **Manual stress test**:
   ```bash
   sudo cgexec -g "*:system.slice/docker-${container_id}.scope" stress-ng --matrix 1 -t 10s
   ```
