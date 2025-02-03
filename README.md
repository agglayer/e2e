# End-to-End Testing Guide

## Overview
This repository includes a **matrix-based CI testing framework** that allows you to:
- Run **E2E tests** across multiple **networks and forks**.
- Specify **custom environment variables** per test.
- Select **specific BATS test files** to run for each network.
- Easily **extend** the test suite with new test cases.

## How the Testing Framework Works
- **Tests are written in [BATS](https://github.com/bats-core/bats-core)**.
- **Each test case lives in `test/`** and follows the `.bats` extension.
- **GitHub Actions CI** automatically picks up new tests and runs them on a schedule or on push.
- **`run-e2e.sh`** is the main script that:
  - Reads environment variables.
  - Launches the appropriate network setup via **Kurtosis**.
  - Executes **BATS tests** based on user input.

## How to Add a New Test
1. **Create a New `.bats` Test File**
   - Place your test inside the `test/` folder.
   - Name it something relevant, e.g., `my-feature-test.bats`.

   Example:
   ```bash
   # test/my-feature-test.bats
   
   @test "My new feature works" {
       run some-command --option
       assert_success
       assert_output --regexp "Expected Output"
   }
   ```

2. **Ensure Your Test Uses Common Setup**
   - Load environment variables in the **setup block**:
   
   ```bash
   setup() {
       load 'helpers/common-setup'
       _common_setup  # Load shared env vars
   }
   ```

3. **Register the Test in CI**
   - Modify `.github/workflows/test-e2e.yml`.
   - Add a new **network+test combination** inside the `matrix.include` array:
   
   ```yaml
   - network: "fork12-rollup"
     bats_tests: "my-feature-test.bats"
   ```

   **OR** to include multiple tests:
   ```yaml
   - network: "fork12-rollup"
     bats_tests: "batch-verification.bats,my-feature-test.bats"
   ```

4. **Trigger a Run**
   - Push your changes, or manually trigger a **workflow_dispatch** in GitHub Actions.
   - Monitor the test results under the **Actions** tab.

## Running Tests Locally
You can run tests **locally** before pushing to CI:

```bash
make test-e2e NETWORK=fork12-rollup DEPLOY_INFRA=false BATS_TESTS=my-feature-test.bats
```

or:

```bash
make test-e2e NETWORK=fork12-rollup DEPLOY_INFRA=false L2_RPC_URL=http://127.0.0.1:50504 BATS_LIB_PATH=/Users/dmoore/e2e/test/lib BATS_TESTS=batch-verification.bats
```

or run all tests:

```bash
make test-e2e NETWORK=fork12-rollup DEPLOY_INFRA=true BATS_TESTS=all
```

## Understanding CI Execution
- **GitHub Actions Workflow (`.github/workflows/test-e2e.yml`)**
  - Runs **all defined test cases in parallel** using a matrix strategy.
  - Executes `make test-e2e` with **network, test list, and env vars**.
  - Uploads logs for debugging in case of failures.

- **Makefile (`test-e2e` target)**
  - Calls `run-e2e.sh` with environment variables passed.
  - Ensures correct execution of BATS tests.

- **`run-e2e.sh` Script**
  - Initializes the **Kurtosis testing environment**.
  - Runs the selected tests with `env bats`.
  - Supports running **specific tests or all tests** dynamically.

## Debugging Test Failures
1. **Check GitHub Actions Logs**
   - Open the failing job in **GitHub Actions**.
   - Look at the error messages and logs.
   
2. **Manually Inspect Logs**
   - Failed tests automatically **upload logs** to CI.
   - Download and inspect the logs for detailed errors.
   
3. **Run Locally**
   - If a test fails in CI, try running it locally with the same env vars.

## Conclusion
This framework allows for **easily scalable** and **configurable E2E testing**. By following this guide, you can:
- Add new tests quickly.
- Extend the CI matrix with new configurations.
- Debug failures effectively.

🚀 **Happy Testing!**

