# Chaos Testing Documentation

This directory contains network chaos testing tools for Docker containers using [Pumba](https://github.com/alexei-led/pumba) to simulate various network conditions and failures.
We are using a bash script instead of BATS scripts, because these tests were written with the intention to run simultaneously, so there was no additional benefit for the overhead of using the BATS library.

## Overview

The chaos testing framework allows you to inject network faults into running Docker containers to test system resilience and fault tolerance. It supports multiple types of network chaos including:

- **Packet Loss**: Simulates network unreliability
- **Delay/Latency**: Adds network latency and jitter
- **Rate Limiting**: Restricts network bandwidth
- **Packet Duplication**: Simulates network packet duplication
- **Packet Corruption**: Corrupts network packets
- **Connection Drops**: Uses iptables to drop specific connections

## Files Structure

```
scenarios/chaos/
├── network-chaos.bash          # Main chaos testing script
├── assets/
│   ├── chaos_test_model.pict   # PICT model file for test combinations
│   ├── generate-matrix.bash    # Script to generate test matrix from PICT
│   └── test_matrix.json        # Generated test matrix (example)
└── chaos_logs_*/               # Generated log directories (timestamped)
    ├── test_parameters.log     # Overall test run parameters
    └── test_*/                 # Individual test case logs
        ├── test_parameters.log
        ├── container_*_logs.log
        ├── delay_test.log
        ├── loss_test.log
        ├── ratelimit_test.log
        ├── duplicate_test.log
        ├── corrupt_test.log
        └── iptables_test.log
```

## Prerequisites

1. **Docker**: Running Docker containers to test against
2. **Pumba**: Network chaos engineering tool
3. **jq**: JSON processor for parsing test matrix
4. **PICT**: For generating test combinations

## How to Run

### Basic Usage

```bash
# Run chaos tests with 30 second duration using existing test matrix
./network-chaos.bash 30s assets/test_matrix.json
```

### Duration Formats

The duration parameter supports various time formats:
- `500ms` - 500 milliseconds
- `30s` - 30 seconds  
- `5m` - 5 minutes
- `1h` - 1 hour

### Complete Workflow

1. **Start your Docker environment** (e.g., using Kurtosis CDK):
   ```bash
   kurtosis run --enclave cdk --args-file .github/tests/combinations/fork12-cdk-erigon-sovereign.yml .
   ```

2. **Generate test matrix** (optional - if you want new combinations):
   ```bash
   cd assets/
   ./generate-matrix.bash
   ```

3. **Run chaos tests**:
   ```bash
   ./network-chaos.bash 60s assets/test_matrix.json
   ```

4. **Review results** in the generated `chaos_logs_*` directory

## Test Matrix Generation

### PICT Model File

The test combinations are generated using Microsoft's PICT (Pairwise Independent Combinatorial Testing) tool. The model is defined in `assets/chaos_test_model.pict`:

```pict
# Example PICT model
container: el-1-geth-lighthouse, cdk-erigon-sequencer-001, cdk-erigon-rpc-001
percent: 1, 5, 10
probability: 0.1, 0.3, 0.5
rate: 100kbit, 1mbit, 10mbit
jitter: 10, 50, 100
```

### Modifying Test Combinations

To customize the chaos testing parameters:

1. **Edit the PICT model** (`assets/chaos_test_model.pict`):
   ```pict
   # Add or modify parameters
   container: your-container-1, your-container-2, your-container-3
   percent: 2, 8, 15           # Packet loss/corruption percentages
   probability: 0.2, 0.4, 0.8  # Connection drop probabilities  
   rate: 50kbit, 500kbit, 5mbit # Rate limiting values
   jitter: 5, 25, 75           # Network jitter in milliseconds
   ```

2. **Regenerate the test matrix**:
   ```bash
   cd assets/
   ./generate-matrix.bash
   ```

3. **Run with new matrix**:
   ```bash
   ./network-chaos.bash 45s assets/test_matrix.json
   ```

### PICT Parameters Explained

- **container**: Names of Docker containers to target (must match running container names)
- **percent**: Percentage values for packet loss, duplication, and corruption (0-100)
- **probability**: Probability values for iptables connection drops (0.0-1.0)
- **rate**: Network rate limiting values (use tc/netem format: kbit, mbit, etc.)
- **jitter**: Network jitter/delay variation in milliseconds

### PICT Constraints

You can add constraints to the PICT model to exclude invalid combinations:

```pict
# Example constraints
IF [rate] = "100kbit" THEN [percent] <= 5;
IF [container] = "lightweight-service" THEN [jitter] <= 50;
```

## What the Tests Do

For each test case, the script simultaneously applies multiple network chaos conditions:

1. **Delay Injection**: Adds 500ms base delay plus configurable jitter to egress traffic
2. **Packet Loss**: Drops packets at the specified percentage rate
3. **Rate Limiting**: Restricts network bandwidth to the specified rate
4. **Packet Duplication**: Duplicates packets at the specified percentage
5. **Packet Corruption**: Corrupts packet data at the specified percentage  
6. **Connection Drops**: Uses iptables to probabilistically drop TCP connections on port 80

All chaos conditions run in parallel for the specified duration, while container logs are captured to observe the system's response to network faults.

## Log Analysis

### Log Structure

- **Main log directory**: `chaos_logs_YYYYMMDD_HHMMSS/`
- **Test parameters**: Overall test run information
- **Individual test logs**: Separate directory for each test case
- **Container logs**: Real-time container output during chaos injection
- **Chaos tool logs**: Output from each Pumba command

### Key Metrics to Monitor

1. **Container behavior**: Look for errors, timeouts, or recovery patterns
2. **Network resilience**: How services handle packet loss and delays
3. **Fault tolerance**: Whether systems gracefully degrade or fail catastrophically
4. **Recovery time**: How quickly services recover after chaos ends


Example integration:
```bash
# Start chaos testing in background
./tests/chaos/network-chaos.bash 1m ./tests/chaos/assets/test_matrix.json &
CHAOS_PID=$!

# Run your normal E2E tests
bats ./tests/agglayer/bridges.bats

# Stop chaos testing
kill $CHAOS_PID
```
