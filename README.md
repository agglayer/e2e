# EVM Regression Test Library

This repository provides a **reusable, lightweight test library** for all internal EVM-compatible chains. It enables developers to run existing tests against any devnet, testnet, or mainnet chain simply by specifying environment variables (e.g., `L2_RPC_URL`) in the `.env` file.

## Features
- **Reusable Testing Framework**: Run tests on any EVM network by updating the `.env` file with the appropriate values.
- **Lightweight and Portable**: No infrastructure dependencies—just update `.env` and run the tests out of the box.
- **Integrated Dependencies**: All required tools (e.g., `bats`, `cast`) are automatically bundled into the run process if they aren't already installed.
- **Flexible Test Formats**:
  - Supports `.bats` and `.go` tests.
  - Shared `Makefile` ensures a common syntax for running all test commands.
  - Designed to support additional languages (e.g., Rust) in the future.
- **Seamless CI Integration**: Add your own tests and have them run automatically in nightly CI jobs.

## Getting Started

### Prerequisites
- Ensure you have the following installed:
  - [Make](https://www.gnu.org/software/make/)

### Setup
1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd evm-regression-tests
   ```

2. Configure the `.env` file with your network's details:
   ```plaintext
   l2_rpc_url=http://<your-rpc-url>
   SENDER_PRIVATE_KEY=<your-private-key>
   RECEIVER=<receiver-address>
   BATS_LIB_PATH="<path-to-bats-lib>"
   ```

3. Run the tests:
   ```bash
   bats bats/e2e.bats
   ```

### Adding New Tests
- Add `.bats` tests under the `scripts/bats-scripts/` directory or `.go` tests under the `scripts/go-scripts/` directory.
- Update the `Makefile` to include any new test types or commands.
- Submit your test changes, and they will automatically run in the nightly CI pipeline.


### Load env variables
```bash
if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please create one."
    exit 1
fi
```

### Running All Tests
Use the `Makefile` to run all tests:
```bash
make test
```

## Roadmap
- **Additional Language Support**: Extend support for Rust, Python, and more.
- **Enhanced Orchestration**: Simplify multi-environment testing with advanced orchestration.
- **CI Enhancements**: Add detailed reports and test coverage tracking.

## Contributing
We welcome contributions! To add your tests or suggest improvements:
1. Fork the repository.
2. Create a new branch for your changes.
3. Submit a pull request.

## License
This repository is for internal use only.

## Contact
For support or questions, reach out to the DevTools team on Slack
