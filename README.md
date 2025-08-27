# AggLayer End to End Tests

To directly view the Tests Inventory, refer to the [Tests Inventory](#tests-inventory) section.

The TLDR for getting started is that these tests are based on a [TAP](https://en.wikipedia.org/wiki/Test_Anything_Protocol) compatible tool called [Bats](https://github.com/bats-core/bats-core). All of the tests are small bash scripts. If the test exits with a non-zero exit code, the test fails. If you're new to bash or Bats, these are some useful links:

- [Bash cheatsheet](https://devhints.io/bash)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Bats documentation](https://bats-core.readthedocs.io/en/stable/)

## How to run your test

The tests in this repository depend on an external RPC which can be specified via environment variables. If you're testing locally, using the [kurtosis-cdk](https://github.com/0xPolygon/kurtosis-cdk/releases/tag/v0.3.4) is probably the easiest way to get started.

```bash
# from within the kurtosis-cdk repo
kurtosis run --enclave cdk --args-file .github/tests/combinations/fork12-cdk-erigon-sovereign.yml .
```

With a network in place, if you'd like to run a single test file, or use Bats directly, it's pretty easy as well:

```bash
# You'll want to set whatever environment variables your test needs. If you want to use defaults you could skip this.
set -a
source tests/.env
set +a

# Some tests will use helpers. If your test does, you'll want to add that to the bats lib path.
export BATS_LIB_PATH="$PWD/core/helpers/lib"

# Now you can run bats
bats tests/agglayer/bridges.bats --filter-tags agglayer,rpc
```

## Philosophy and Goals

*Separation of concerns* between infrastructure and test logic is a major goal of this project. We want to have a wide variety of tests. The tests themselves shouldn't be concerned with the details of the infrastructure on which they execute. A single test should be configurable based on environment variables and should be able to run against a Kurtosis devnet or a mainnet RPC.

Ideally, this repository is *self-documenting*. For our test cases, that means they should be thoughtfully [named](#test-case-naming) and [tagged](#thinking-about-tagging). In the case of a failure, the error messaging and naming should make it very clear what failed and what it might mean.

```bash
# Bad example
@test "send bridge" {
    if ! bridge ; then {
        echo "bridge failed"
        exit 1
    }
}

# Better example
@test "bridge native eth from l1 to l2" {
    if ! bridge ; then {
        echo "Bridge deposit was not claimed despite being finalized on L1. Check that bridge service is running properly"
        exit 1
    }
}
```

The "better" example above has a descriptive name that indicates what type of bridge is being tested. It also has a lot more context if and when there is a failure.

Another major goal of this project is to have a *simple developer experience*. Making that happen isn't easy, but we want to have shared [environment variables](#thinking-about-environment-variables) that are common across test cases. Similarly, we want to have tags and a project layout that's intuitive.

## Thinking about environment variables

As a test developer, you can define whatever environment variables you like, but in order for the test cases to be executed via generic automations, it's critical that you're aware of commonly used environment variables and to use them whenever possible.

| Variable              | Purpose                                                            |
|-----------------------|--------------------------------------------------------------------|
| RPC_URL               | A generic JSON RPC URL for tests that do not require L1/L2 context |
| L1_RPC_URL            | An RPC URL that serves as the L1 for some rollup or validium       |
| L2_RPC_URL            | An RPC URL for a rollup that's anchored on L1                      |
| PRIVATE_KEY           | A private key that's funded for RPC_URL                            |
| L1_PRIVATE_KEY        | A private key that's funded for L1_RPC_URL                         |
| L2_PRIVATE_KEY        | A private key that's funded for L2_RPC_URL                         |
| SEQUENCER_RPC_URL     | An RPC URL that's directly connected to a sequencer                |
| GAS_TOKEN_ADDR        | The L1 address of a custom gas token                               |
| BRIDGE_SERVICE_URL    | The URL of the bridge service used for claiming deposits           |
| L1_BRIDGE_ADDR        | The address of the bridge on L1                                    |
| L2_BRIDGE_ADDR        | The address of the bridge on L2                                    |
| LEGACY_MODE           | If true, don't send a type 2 transaction                           |
| KURTOSIS_ENCLAVE_NAME | Specifies the enclave name used in some defaults                   |

A few points on the design and thinking. In general, we're going to *prefer deriving* rather than specifying everything. Rather than specifying an `L1_ETH_ADDRESS` variable that can be set, we would derive this value from the `L1_PRIVATE_KEY`. Similarly, rather than specifying the [networkID](https://github.com/0xPolygonHermez/zkevm-contracts/blob/98b8b1f0af6074d5e2cf6b6c223db99d1f3e29f3/contracts/v2/PolygonZkEVMBridgeV2.sol#L61) with something like `L2_NETWORK_ID`, we would rather read this value from the bridge.

The test cases aren't meant for a specific environment, but in many cases, the default values for environment variables will target the [kurtosis-cdk](https://github.com/0xPolygon/kurtosis-cdk) package or the [kurtosis-polygon-pos](https://github.com/0xPolygon/kurtosis-polygon-pos) package. For example, if you startup the kurtosis package like this:

```bash
kurtosis run --enclave cdk --args-file .github/tests/combinations/fork12-cdk-erigon-sovereign.yml .
```

Many tests will assume the default target of the test is kurtosis and define the keys and URLs accordingly.

## Test Case Naming

Consistent and clear test naming is critical for maintaining readability, ensuring searchability, and improving test result clarity. We will enforce these naming standards during code review to maintain consistency across our test suite.

### Naming Standard

Each test should follow this pattern:

```bats
@test "<action> <test scope> <conditions or properties> [expected outcome]"
```

Where:

- `<action>` – What the test is *doing* (e.g., bridge, send, claim, create).
- `<test scope>` – The subject of the test (e.g., native ETH, ERC20, contract, RPC call).
- `<conditions or properties>` (optional) – Any constraints or test conditions (e.g., with low gas, after).
- `[expected outcome]` (only if needed) – If success/failure isn’t obvious (e.g., fails if contract is paused).

Examples:
- `@test "bridge native ETH from L2 to L1"`
- `@test "bridge native ETH from L2 to L1 without initial deposit fails"`
- `@test "withdraw ERC20 and finalize after challenge period"`
- `@test "deposit ETH on L2 with custom gas limit"`
- `@test "replay transaction on L1 with same nonce reverts"`
- `@test "bridge fails when contract is paused"`
- `@test "query interop_getLatestSettledCertificateHeader on agglayer RPC returns expected fields"`

### Best Practices:
- Start with a clear action (e.g., bridge, deposit, send).
- Be specific but concise—avoid vague test names.
- Do not include "test" in the name (it’s redundant).
- Use present tense ("bridge native ETH" not "bridging native ETH").
- Failure states should be explicit (e.g., "deposit fails when network ID is the current network").

Test names should be reviewed for clarity and adherence to this standard before merging. Future linting may enforce a predefined set of allowed actions to further standardize test naming.

## Project organization

All of the tests live in the [./tests](./tests) folder. We're still trying to figure out the right organization, but for now, please follow these guidelines:

- Place your tests in sub-folders of the `tests` directory according to their dependencies.
  - `agglayer/` tests depend on access directly to the Agglayer RPC and the bridge.
  - `lxly/` tests would depend on direct access to the bridge service and contracts, but might not need access to the Agglayer itself.
  - `pos/` tests depend on a running PoS environment.
- There are going to be some generic tests that can be reused across varied environments. In that case, we can name based on the test case itself:
  - `ethereum-test-cases/` come from the standard Ethereum test suite, but could be run against any EVM RPC.
  - `polycli-loadtests/` depend on running the PolyCLI load tests, but could also be run against any EVM RPC.
- Bats files should contain test cases that can be run together:
  - Each file represents a logical collection of related tests.
  - Try to keep each file small and focused (e.g., 5–15 tests) so it’s easier to run, maintain, and debug.
  - If a particular test case is likely to break subsequent tests, it should be placed in its own file.
- Use descriptive naming for `.bats` files:
  - Each file name should reflect the test’s primary focus.

In addition to *tests*, we have *scenarios* that live in the [./scenarios](./scenarios) folder. The main guideline is that *tests* should be used in most cases so that we can run checks against generic RPCs and treat the infrastructure as a black-box. In situations where we need to manipulate the underlying infrastructure, we use *scenarios*.

|                    | Tests                         | Scenarios                   |
|--------------------+-------------------------------+-----------------------------|
| Scripting Language | Bats                          | Generic Bash                |
| Infrastructure     | Pre-configured                | Setup and torn down in test |
| Coupling           | Decoupled from client version | Bundled with client version |
| Example            | Bridge transactions           | Bridge version upgrade      |

A scenario consists of a single executable `run.sh` plus optional helpers. `run.sh`:

1. Spin up its environment (Kurtosis, Docker, ...) in a temporary namespace.
2. Run its assertions (you may call Bats, Go tests, or plain shell here).
3. Tear everything down cleanly, even on failure (set an `EXIT` trap).

Because scenarios are isolated, they can run in parallel with each other and with `tests/` without clashing over ports, volume mounts, or chain state.

```
scenarios/
├── <scenario-name>/   # One folder per scenario
│   ├── run.sh         # The orchestrator. *Must* be executable and idempotent.
│   ├── README.md      # Some short description of the test scenario.
│   ├── env.example    # Minimal set of env vars a caller may override.
│   ├── lib/           # Optional helper scripts reused by this scenario
│   └── assets/        # SQL snapshots, JSON fixtures, contract byte-code
└── common/            # Shared helpers for *all* scenarios (similar to tests/core/helpers/)
```

# Tagging tests

## file_tags

These will target holistic features or services within the entire system.
Naming convention should follow that of the directories.

```bash
grep -hoR --include="*.bats" 'file_tags=[^ ]*' . | sed 's/.*file_tags=//' | tr ',' '\n' | sort -u | sed 's/^/- /'
```

- aggkit
- agglayer
- bridge
- cdk
- cdk-erigon
- dapps
- eip-2537
- eip-2935
- eip-7623
- ethereum-test-cases
- evm-gas
- evm-opcode
- evm-precompile
- evm-rpc
- execution
- local-balance-tree
- lxly
- op
- op-fep
- pectra
- pessimistic
- polycli-loadtests
- prover-stress
- standard
- standard-kurtosis
- transaction-erc20
- zkevm
- zkevm-batch

## test_tags

These will aim to have feature-specific targeted tests.
Naming convention should follow general EVM or Polygon standards.

```bash
grep -hoR --include="*.bats" 'test_tags=[^ ]*' . | sed 's/.*test_tags=//' | tr ',' '\n' | sort -u | sed 's/^/- /'
```

- acl-accesslist
- acl-blocklist
- agglayer-admin
- agglayer-cert
- agglayer-rpc
- bridge
- cdk-op-geth
- check-hardfork
- custom-gas-token
- eip-7685
- eip-7691
- erc-4337
- evm-block
- evm-gas
- evm-inscription
- evm-nonce
- evm-pool
- evm-precompile
- evm-stress
- gnosis-safe
- katana
- loadtest
- native-gas-token
- operator-fee
- optimistic-mode
- pos
- pos-delegate
- pos-undelegate
- pos-validator
- railgun
- smooth-crypto-lib
- transaction-eoa
- transaction-erc20
- transaction-erc721
- transaction-pol
- transaction-uniswap
- weth
- zkevm-batch
- zkevm-counters

## Common helper functions

TODO - We need to document the various helper functions. Some helpers might be mandatory (enforced by code review) while others are there for your convenience.

## CI Development

We use [act](https://github.com/nektos/act) to do a local simulation of the GitHub Action in this repo. If you just want to run like CI does, you can use the following command:

```bash
act --container-options "--group-add $(stat -c %g /var/run/docker.sock)" -s GITHUB_TOKEN=$ACT_GITHUB_TOKEN workflow_call
```

## Tests Inventory

Refer to the [TESTSINVENTORY.md](./TESTSINVENTORY.md) file for a list of integrated and WIP tests.

## Standard Battery Test Tags

The Standard Battery Tests workflow runs all Bats tests with the `standard` tag. The below tests are currently included:

- [conflicting-contracts-calls](./tests/execution/conflicting-contract-calls.bats)
- [conflicting-transactions-to-pool](./tests/execution/conflicting-transactions-to-pool.bats)
- [polycli-cases](./tests/execution/polycli-cases.bats)
- [railgun-contracts](./tests/execution/railgun-contracts.bats)
- [smooth-crypto-lib](./tests/execution/smooth-crypto-lib.bats)
- [special-addresses](./tests/execution/special-addresses.bats)
- [bridge-tests-suite](./tests/lxly/bridge-tests-suite.bats)
- [polycli-loadtests](./tests/polycli-loadtests/polycli-loadtests.bats)

To include your test, add `# bats test_tags=standard` above your test in the `.bats` file.

You can use multiple tags for more granular control, e.g.:
```
# bats test_tags=standard,agglayer,rpc
```

Only tests with the `standard` tag will be picked up by the workflow when run from project root directory:
```bash
bats --filter-tags standard $(find tests -name '*.bats')
```