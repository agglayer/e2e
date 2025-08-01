# Monitored Tests

## Overview

This directory contains a scenario template for running multiple E2E tests against a single Kurtosis CDK network, with well-defined pre-state and post-state (TODO) conditions. It is designed to orchestrate chaos and stress tests in parallel with E2E tests, enabling robust validation of network behavior under various conditions.

## Structure

- **monitored-tests.bats**: Main Bats test orchestrator that sets up the environment, parses input, and runs chaos, stress, and E2E tests in parallel.
- **pre-state/**: Contains input templates and configuration files that define the initial state and test matrices.
- **post-state/**: Directory where logs and outputs from the tests are stored. Automation and useful parsing of this needs to be done in the future.

## How It Works

1. **Setup**: The test orchestrator sets up environment variables, checks for the required Docker network, and parses the test input template to generate specific input files for chaos, stress, and E2E tests.
2. **Parallel Execution**: 
   - Runs chaos and stress tests in the background.
   - Reads the list of E2E test files from the input and runs each in parallel, with configurable timeouts.
3. **Monitoring & Cleanup**: Tracks all test process IDs for proper cleanup and handles interrupts gracefully.
4. **Logging**: Redirects logs and results to the `post-state` directory for later analysis.

## Usage

From the root `e2e` directory, run:

```sh
bats ./scenarios/monitored-tests/monitored-tests.bats
```

### Environment Variables

- `ENCLAVE_NAME`: Name of the Kurtosis enclave (default: `cdk`)
- `L2_RPC_URL`: RPC URL for L2 node (auto-detected if not set)
- `TEST_DURATION`: Duration for chaos/stress tests (default: `5s`)
- `TEST_TIMEOUT`: Timeout for each E2E test (default: `300s`)
- `LOG_ROOT_DIR`: Directory for logs (default: `./scenarios/monitored-tests/post-state`)

## Input Configuration

Edit `pre-state/test_input_template.json` to define:
- Chaos test parameters
- Stress test parameters
- List of E2E test files to run

To automatically generate new valid stress and chaos test inputs, run `./pre-state/generate_test_input.bash` file.
You will still have to manually fill out the E2E tests array to run.

```
  "e2e_tests": [
    "./tests/execution/polycli-cases.bats",
    "./tests/execution/conflicting-contract-calls.bats",
    "./tests/execution/special-addresses.bats",
    "./tests/execution/conflicting-transactions-to-pool.bats"
  ],
```

## Notes

- Ensure all referenced E2E test files exist and are executable, and compatible with the monitored-tests orchestrator.