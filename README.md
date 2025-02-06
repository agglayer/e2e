# 🚀 Polygon E2E Test Runner

A lightweight, **tag-based test runner** for executing end-to-end tests against **remote blockchain networks**.

## ✨ Features

- ✅ Run tests **against any remote network** by specifying environment variables before execution.
- ✅ **Tag-based execution** (e.g., `light`, `heavy`, `regression`, `danger`) for flexibility.
- ✅ **Simple CLI usage** via `polygon-test-runner` or direct script execution.
- ✅ **Easily extendable** with new `.bats` test cases.
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
- Ensure all dependencies (BATS, Foundry, Go, `jq`, `polycli`) are installed.

💡 \*\*Ensure ****`~/.local/bin`**** is in your \*\***`PATH`** (handled automatically during install). If not:

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
L2_RPC_URL=http://127.0.0.1:60784 \
L2_SENDER_PRIVATE_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 \
polygon-test-runner --filter-tags "light"
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

### Alternative Way to Run Tests

If you prefer **not to install the CLI wrapper**, you can directly execute `test-runner.sh`:

```sh
L2_RPC_URL=http://127.0.0.1:60784 \
L2_SENDER_PRIVATE_KEY=xyz \
./test-runner.sh --filter-tags "zk-counters"
```

Both methods work the same way!

---

## 🛠️ Adding New Tests

###

note: categories currently include: light / heavy / regression / danger (tests that can break networks). 
users can add their own, new categories as desired
```sh
touch tests/<category>/my-new-test.bats
```

**Example ********`.bats`******** file with tagging and standardized naming:**

```bash
# bats test_tags=light,zk
@test "RPC handles multiple transactions sequentially" {
    run cast send --rpc-url "$L2_RPC_URL" --private-key "$L2_SENDER_PRIVATE_KEY" --create 0x600160015B810190630000000456
    assert_success
}
```

### Naming Standards for Tests

To improve clarity, test names should follow this standard:

| **Category**     | **Example Test Name**                                          |
| ---------------- | -------------------------------------------------------------- |
| **RPC Behavior** | `@test "RPC handles multiple transactions sequentially"`       |
| **Sequencer**    | `@test "Sequencer processes two large transactions correctly"` |
| **Gas Limits**   | `@test "Gas limit is respected for high-volume TXs"`           |
| **Contracts**    | `@test "Deployed contract executes expected behavior"`         |

**Format:**

- **Component/Behavior** (e.g., RPC, Sequencer, Gas Limits)
- **What it does** (e.g., handles multiple TXs, respects limits, executes as expected)
- **(Optional) Edge Cases** (e.g., "under high network load", "with malformed input")

### 2⃣ Run the new test

```sh
polygon-test-runner --filter-tags "zk"
```

### 3⃣ Add to CI (Optional)

Modify `.github/workflows/test-e2e.yml`:

```yaml
- network: "fork12-rollup"
  bats_tests: "tag:zk"
```

---

## 🔍 Debugging Test Failures

1. **Check logs** in GitHub Actions.
2. **Run locally** using the same environment variables.
3. Ensure `polygon-test-runner --help` outputs correct usage.

---

## 📝 CLI Help

```sh
polygon-test-runner --help
```

```
🛠️ polygon-test-runner CLI

Usage: polygon-test-runner --filter-tags <tags>

Options:
  --filter-tags  Run test categories using BATS-native tags (e.g., light, heavy, danger).
  --help         Show this help message.

Examples:
  polygon-test-runner --filter-tags "light"
  polygon-test-runner --filter-tags "zk"
  polygon-test-runner --filter-tags "heavy,danger"
```

---

## 💪 Compiling Contracts Before Running Tests

To ensure your contracts are compiled before testing, run:

```sh
make compile-contracts
```

This will:

1. \*\*Run \*\***`forge build`** to compile the contracts.
2. \*\*Execute \*\***`./scripts/postprocess-contracts.sh`** to apply necessary processing.

💡 **You should run this before executing any tests that interact with deployed contracts.**

---

## 🎯 Conclusion

✅ **Simple setup**\
✅ **Tag-based test execution**\
✅ **Easily extendable**\
✅ **Designed for CI/CD**

🚀 **Start testing with ********`polygon-test-runner`******** today!**

