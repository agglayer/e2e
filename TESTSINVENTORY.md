# Tests Inventory

Table of tests currently implemented or being implemented in the E2E repository.


## LxLy Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| L1 to L2 Bridge Native Asset | LxLy | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/lxly/lxly.bats#L36) | |
| L2 to L1 to L2 Bridge Asset | LxLy | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/lxly/lxly.bats#L70) | |
| Bridge Asset:Buggy from PP1 to PP2 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:LocalERC20 from FEP to PP2 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from L1 to PP2 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:LocalERC20 from PP2 to L1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:GasToken from L1 to PP1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP1 to L1 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:GasToken from FEP to PP2 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP2 to FEP targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Weth:WETH from PP2 to PP1 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:LocalERC20 from FEP to PP1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from L1 to FEP targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Buggy is an ERC20 that allows for more than uint256 supply |
| Bridge Asset:NativeEther from PP1 to FEP targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from FEP to PP1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:NativeEther from L1 to PP2 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Weth:WETH from PP2 to L1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:NativeEther from PP1 to FEP targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:LocalERC20 from L1 to FEP targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP2 to PP1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP1 to FEP targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from FEP to L1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:NativeEther from FEP to PP2 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Weth:WETH from PP2 to FEP targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from FEP to L1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:GasToken from PP2 to L1 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP1 to L1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:LocalERC20 from PP1 to L1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from PP2 to PP1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from PP2 to L1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:NativeEther from PP2 to PP1 targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:WETH from PP2 to PP1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Message:NativeEther from PP1 to FEP targeting EOA | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:NativeEther from L1 to PP1 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:GasToken from PP1 to FEP targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from PP1 to PP2 targeting Precompile | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| Bridge Asset:Buggy from PP1 to L1 targeting Contract | LxLy | ✅ | ✅ | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.6/docs/multi-pp-testing/run.sh) | Should be testable using the [bridge-tests-suite](https://github.com/agglayer/e2e/blob/8b65a1e/tests/lxly/bridge-tests-suite.bats) with custom [matrix input](https://github.com/agglayer/e2e/blob/96c5c65/tests/lxly/assets/bridge-tests-suite.json) |
| L1 to L2 Bridge Token with Permit | LxLy | 🚧 | 🚧 | [Link](https://sepolia.etherscan.io/tx/0xa72ef9fc6d54f7059a74fc3bccf21340e75cfa07c52355a7ea309d6521e88374) | This was done manually |
| L1 to L2 Giant Bridge Message | LxLy | ✅ | ✅ | [Link](https://sepolia.etherscan.io/tx/0xf53e7aadb484d67e01938130af22f59452e1d185a95fe078651587020942db3d) | This was done manually but is partially automated |
| Multiple L2 Claims | LxLy | 🚧 | 🚧 | [Link](https://explorer.cdk22.dev.polygon/tx/0xfdc5b72c9945a1d6a249c0dd5d83a1317dafd6f32de23d0571fc953c7fc4f64b) | |
| Multiple L2 Claims Mixing Success and Failures | LxLy | 🚧 | 🚧 | [Link](https://explorer.cdk22.dev.polygon/tx/0x80047c33c5cb619349c6308226cb63ee06a6a29399a709fade3cb766f183e1d8) | |


## AggLayer Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Invalid signature in agglayer certificate | AggLayer | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/473447f7bb4ad3119a2c8c21c2782030671115db/t) | |
| Wrong height certificate in agglayer | AggLayer | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/473447f7bb4ad3119a2c8c21c2782030671115db/tests/agglayer-cert-test.bats#L132) | |
| Certificate replacement in agglayer | AggLayer | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/473447f7bb4ad3119a2c8c21c2782030671115db/tests/agglayer-cert-test.bats#L140) | |
| Valid certificates sent to agglayer | AggLayer | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/473447f7bb4ad3119a2c8c21c2782030671115db/tests/agglayer-cert-test.bats#L45) | |


## CDK Erigon Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Gas limit overflow with normalcy | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/gas-limit-overflow.bats#L10) | |
| Bad 0xFB SENDALL implementation | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L11) | |
| CREATE OOM issue with large size | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L30) | |
| RETURN OOM issue with large size | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L55) | |
| CREATE2 OOM issue with large size | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L80) | |
| Malformed PUSH scenario | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L105) | |
| SHA256 invalid counter estimation | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L135) | |
| zkEVM executable push operand | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L176) | |
| Recursive CREATE transaction | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L207) | |
| Recursive CREATE OOG transaction | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L232) | |
| OOC transactions creating new batches | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L252) | |
| IDENTITY precompile counter issues | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/regression/standard-erigon.bats#L295) | |
| zkEVM Counters match expectations | CDK Erigon | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/heavy/zk-counters-tests.bats) | E.g. fork 12 had the vcounters of fork 9 at first |


## Kurtosis Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Fork 9 validium w/ legacy stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-validium.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ legacy stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-rollup.yml) | |
| Fork 9 validium w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-validium.yml) | |
| Fork 11 rollup w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-rollup.yml) | |
| Fork 11 validium w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 11 validium w/ legacy stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork11-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 12 rollup w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-rollup.yml) | |
| Fork 12 validium w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 12 soverign w/ erigon stack and SP1 | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-sovereign.yml) | |
| Fork 13 rollup w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-rollup.yml) | |
| Fork 13 validium w/ erigon stack and mock prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-validium.yml) | |
| CDK-OP-Stack wit network SP1 prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct-real-prover.yml) | |
| CDK-OP-Stack with mock SP1 prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct.yml) | |
| CDK-OP-Stack without SP1 prover | Kurtosis | ✅ | N/A | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/nightly/op-rollup/op-default.yml) | |


## Execution Layer Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Access list tests | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/main/tests/berlin/eip2930_access_list) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Same block deployment and execution | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/blob/jihwan/cdk-op-geth/tests/custom/same_block_deploy_and_call.py) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-1559 Implementation | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/static/state_tests/stEIP1559) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-6780 Implementation | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/cancun/eip6780_selfdestruct) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Every known opcode | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/frontier/opcodes) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Prover stress tests | Execution Layer | ✅ | ✅ | [Link](https://github.com/agglayer/e2e/blob/f1401faa1db21936557a9ba56add7a606719f089/tests/heavy/prover-stress.bats#L9) | The current implementation in e2e is updated |
| Blob, Accesslist, EIP-1559, EIP-7702 | Execution Layer | ✅ | N/A | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| All polycli cases | Execution Layer | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/polycli-cases/tasks/main.yml) | |
| Pool race conditions | Execution Layer | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/pool-race-conditions/tasks/main.yml) | |
| Railgun deployment | Execution Layer | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/railgun/tasks/main.yml) | Meant to be a complicated deployment |
| Special addresses | Execution Layer | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/transfer-to-special-addresses/tasks/main.yml) | Send funds to all known "special" addresses |
| Smooth crypto test cases | Execution Layer | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/smoothcrypto/tasks/main.yml) | |


## Full System Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Manual acceptance criterial | Full System | 🚧 | 🚧 | [Link](https://www.notion.so/polygontechnology/9dc3c0e78e7940a39c7cfda5fd3ede8f?v=4dfc351d725c4792adb989a4aad8b69e) | |
| Fuzz tests / Stress Tests / Load Tests | Full System | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/main/evm-rpc-tests/misc/fuzzing.sh) | |
| Reliability / Chaos Tests | Full System | ✅ | 🚧 | | |
| Ethereum test suite stress tests | Full System | ✅ | 🚧 | [Link](https://github.com/0xPolygon/jhilliard/blob/main/evm-rpc-tests/misc/run-retest-with-cast.sh) | |


## CDK OP Geth Tests

| Test Name | Target | Is Automated | Is in E2E | Reference | Notes |
|-----------|--------|--------------|-----------|-----------|-------|
| Native bridge is disabled | CDK OP Geth | 🚧 | 🚧 | | |
| Log Review | CDK OP Geth | 🚧 | 🚧 | | Ensure there are no critical errors in the logs other than known benign issues |
| L2 hardfork supports | CDK OP Geth | 🚧 | 🚧 | |  |
