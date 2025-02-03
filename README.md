# 🚀 Polygon E2E Test Runner

A lightweight, **tag-based test runner** for executing end-to-end tests against **remote blockchain networks**.

## ✨ Features
- ✅ Run tests **against any remote network** by specifying environment variables.
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
polygon-test-runner --tags "light" --env-vars "L2_RPC_URL=http://127.0.0.1:60784,L2_SENDER_PRIVATE_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
```

### 🔹 Examples
Run all **light** tests:
```sh
polygon-test-runner --tags "light"
```

Run a **specific test**:
```sh
polygon-test-runner --tags "tests/light/batch-verification.bats"
```

Run **heavy + danger** tests together:
```sh
polygon-test-runner --tags "heavy,danger"
```

Run **with environment variables**:
```sh
polygon-test-runner --tags "light" --env-vars "L2_RPC_URL=http://127.0.0.1:60784"
```

---

## 🛠️ Adding New Tests
### 1️⃣ Create a new test
Place it inside the relevant tag directory (`tests/light`, `tests/heavy`, etc.).
```sh
mkdir -p tests/light
touch tests/light/my-new-test.bats
```

Example `.bats` file:
```bash
setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

@test "Ensure contract deployment works" {
    run cast send --rpc-url "$L2_RPC_URL" --private-key "$L2_SENDER_PRIVATE_KEY" --create 0x600160015B810190630000000456
    assert_success
}
```

### 2️⃣ Run the new test
```sh
polygon-test-runner --tags "tests/light/my-new-test.bats"
```

### 3️⃣ Add to CI (Optional)
Modify `.github/workflows/test-e2e.yml`:
```yaml
- network: "fork12-rollup"
  bats_tests: "my-new-test.bats"
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

Usage: polygon-test-runner --tags <tags> --env-vars <key=value,key=value>

Options:
  --tags       Run test categories (light, heavy, danger) OR specific .bats files.
  --env-vars   Pass environment variables needed for the tests.
  --help       Show this help message.

Examples:
  polygon-test-runner --tags "light"
  polygon-test-runner --tags "tests/light/batch-verification.bats"
  polygon-test-runner --tags "heavy,danger"
  polygon-test-runner --tags "light" --env-vars "L2_RPC_URL=http://127.0.0.1:60784"
```

---

## 🎯 Conclusion
✅ **Simple setup**  
✅ **Tag-based test execution**  
✅ **Easily extendable**  
✅ **Designed for CI/CD**

🚀 **Start testing with `polygon-test-runner` today!**
