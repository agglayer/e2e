# 🚀 Polygon E2E Test Runner

A lightweight, **tag-based test runner** for executing end-to-end tests against **remote blockchain networks**.

## ✨ Features
- ✅ Run tests **against any remote network** by specifying environment variables before execution.
- ✅ **Tag-based execution** (e.g., `light`, `heavy`, `danger`) for flexibility.
- ✅ **Simple CLI usage** via `polygon-test-runner`.
- ✅ **Easily extendable** with new `.bats` test cases.
- ✅ **CI-compatible** – works seamlessly with GitHub Actions.

---

## 📦 Installation
Install the test runner **locally**:
```sh
make install
```
This will:
- Install `polygon-test-runner` in `~/.local/bin`
- Ensure all dependencies (BATS, Foundry, Go, `jq`, `polycli`) are installed.

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

---

## 🛠️ Adding New Tests
### 1️⃣ Create a new test
Place it inside the **tests/** directory.
```sh
touch tests/my-new-test.bats
```

**Example `.bats` file with tagging:**
```bash
# bats test_tags=light,zk
@test "Ensure contract deployment works" {
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

## 🎯 Conclusion
✅ **Simple setup**  
✅ **Tag-based test execution**  
✅ **Easily extendable**  
✅ **Designed for CI/CD**

🚀 **Start testing with `polygon-test-runner` today!**

