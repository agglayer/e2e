# 🚀 Polygon E2E Test Runner

A lightweight, **tag-based test runner** for executing end-to-end tests against **remote blockchain networks**.

## ✨ Features

- ✅ Run tests **against any remote network** by specifying environment variables before execution.
- ✅ **Tag-based execution** (e.g., `light`, `heavy`, `regression`, `danger`) for flexibility.
- ✅ **Configurable Wallet Funding** (`DISABLE_FUNDING`, `FUNDING_AMOUNT_ETH`).
- ✅ **Better Logging Control** (`SHOW_OUTPUT` to enable/disable verbosity).
- ✅ **Allow Partial Failures** (`ALLOW_PARTIAL_FAILURES` prevents full test suite failures).
- ✅ **Shellcheck Support** for Bash linting in CI/CD.
- ✅ **Granular test filtering** with `--filter-tags`.
- ✅ **CI-compatible** – works seamlessly with GitHub Actions.

---

## 📚 Installation

### Installing the Test Runner

Install the test runner **locally**:

```sh
make install
```

This will:

- Install `polygon-test-runner` in `~/.local/bin`
- Ensure all dependencies (BATS (v1.11.1 or higher), Foundry, Go, `jq`, `polycli`) are installed.

💡 **Ensure `~/.local/bin` is in your `PATH`** (handled automatically during install). If not:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

To **uninstall**:

```sh
make uninstall
```

---

## 🚀 Running Tests

Run **tagged tests** against any remote blockchain:

```sh
L2_RPC_URL=http://127.0.0.1:60784 polygon-test-runner --filter-tags "light"
```

### 🔹 Examples

Run all **light** tests:

```sh
polygon-test-runner --filter-tags "light"
```

Run a **specific test**:

```sh
polygon-test-runner --filter-tags "batch-verification"
```

Run **heavy + danger** tests together:

```sh
polygon-test-runner --filter-tags "heavy,danger"
```
**Note:** This commands must be run from the root of the project.

Run **with logging enabled**:

```sh
SHOW_OUTPUT=true polygon-test-runner --filter-tags "light"
```

Run **without failing on errors**:

```sh
ALLOW_PARTIAL_FAILURES=true polygon-test-runner --filter-tags "zk-counters"
```

---

## 🔧 Configurable Wallet Funding

Funding test wallets can now be **enabled/disabled** and dynamically configured:

| **Variable**            | **Description**                            | **Default** |
|-------------------------|--------------------------------|------------|
| `DISABLE_FUNDING`       | Disable wallet funding (set to `true`)  | `false`    |
| `FUNDING_AMOUNT_ETH`    | Amount of ETH to fund test wallets     | `50`       |

### 🔹 Example Usage

Disable wallet funding:
```sh
DISABLE_FUNDING=true polygon-test-runner --filter-tags "light"
```

Fund wallets with **10 ETH instead of 50**:
```sh
FUNDING_AMOUNT_ETH=10 polygon-test-runner --filter-tags "light"
```

---

## 📝 Adding New Tests

### 1️⃣ Create a new test file

```sh
touch tests/<category>/my-new-test.bats
```

**Example `.bats` test file:**

```bash
# bats test_tags=light,zk
@test "RPC handles multiple transactions sequentially" {
    run cast send --rpc-url "$L2_RPC_URL" --private-key "$L2_SENDER_PRIVATE_KEY" --create 0x600160015B810190630000000456
    assert_success
}
```

### 2️⃣ Run the new test

```sh
polygon-test-runner --filter-tags "zk"
```

### 3️⃣ Add to CI (Optional)

Modify `.github/workflows/test-e2e.yml`:

```yaml
- network: "fork12-rollup"
  bats_tests: "tag:zk"
```

---

## 🛡️ Debugging Test Failures

1. **Check logs** in GitHub Actions.
2. **Run locally** using the same environment variables.
3. Ensure `polygon-test-runner --help` outputs correct usage.

---

## 📃 CLI Help

```sh
polygon-test-runner --help
```

```
🛠️ polygon-test-runner CLI

Usage: polygon-test-runner --filter-tags <tags>

Options:
  --filter-tags  Run test categories using BATS-native tags (e.g., light, heavy, danger).
  --allow-failures  Allow partial test failures without stopping the suite.
  --verbose      Show output of passing tests (default is off for readability).
  --help         Show this help message.

Examples:
  polygon-test-runner --filter-tags "light"
  polygon-test-runner --filter-tags "zk"
  polygon-test-runner --filter-tags "heavy,danger"
```

---

## 💪 ShellCheck for CI/CD

To **ensure clean Bash scripts**, we've integrated `shellcheck`.

Run locally before committing:

```sh
make lint
```

To **fix errors automatically**:

```sh
make fix-lint
```

---

## 🛠️ Compile Contracts Before Running Tests

To ensure your contracts are compiled before testing, run:

```sh
make compile-contracts
```

This will:

1. **Run `forge build`** to compile the contracts.
2. **Execute `./core/helpers/scripts/postprocess_contracts.sh`** to apply necessary processing.

💡 **You should run this before executing any tests that interact with deployed contracts.**

---

## 🌟 Conclusion

👉 **Simple setup**  
👉 **Tag-based test execution**  
👉 **Configurable wallet funding**  
👉 **Easily extendable**  
👉 **Designed for CI/CD**  

🚀 **Start testing with `polygon-test-runner` today!**
