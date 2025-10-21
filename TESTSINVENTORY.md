# Tests Inventory

Table of tests currently implemented or being implemented in the E2E repository.


## LxLy Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Initial setup | [Link](./tests/lxly/bridge-tests-suite.bats#L80) | |
| Process L1 to L2 bridge scenarios and claim deposits in parallel | [Link](./tests/lxly/bridge-tests-suite.bats#L102) | |
| Process L2 to L1 bridge scenarios and claim deposits in parallel | [Link](./tests/lxly/bridge-tests-suite.bats#L327) | |
| Reclaim test funds | [Link](./tests/lxly/bridge-tests-suite.bats#L581) | |
| Run address tester actions | [Link](./tests/lxly/bridge-tests-suite.bats#L550) | |
| bridge L2 ("$NETWORK_TARGET") originated token from L2 to L1 | [Link](./tests/lxly/multi-chain-bridge.bats#L115) | |
| bridge l2 originated token from L2 to L1 and back to L2 | [Link](./tests/lxly/lxly.bats#L117) | |
| bridge native eth from L1 to L2 ("$NETWORK_TARGET") | [Link](./tests/lxly/multi-chain-bridge.bats#L70) | |
| bridge native eth from l1 to l2 | [Link](./tests/lxly/lxly.bats#L31) | |
| cross-chain bridge between different L2 networks (target:"$NETWORK_TARGET") | [Link](./tests/lxly/multi-chain-bridge.bats#L249) | |

## AggLayer Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Agglayer random cert test | [Link](./tests/agglayer/cert-tests.bats#L157) | |
| Agglayer valid cert fake deposit test | [Link](./tests/agglayer/cert-tests.bats#L114) | |
| Agglayer valid cert test | [Link](./tests/agglayer/cert-tests.bats#L73) | |
| admin_getCertificate returns certificate data for valid certificate ID | [Link](./tests/agglayer/admin-tests.bats#L43) | |
| admin_getCertificate returns error for invalid certificate ID | [Link](./tests/agglayer/admin-tests.bats#L101) | |
| admin_removePendingCertificate with non-existent certificate | [Link](./tests/agglayer/admin-tests.bats#L181) | |
| admin_removePendingProof with invalid certificate ID | [Link](./tests/agglayer/admin-tests.bats#L197) | |
| admin_setLatestPendingCertificate with non-existent certificate | [Link](./tests/agglayer/admin-tests.bats#L117) | |
| admin_setLatestPendingCertificate with valid certificate ID | [Link](./tests/agglayer/admin-tests.bats#L133) | |
| admin_setLatestProvenCertificate with non-existent certificate | [Link](./tests/agglayer/admin-tests.bats#L258) | |
| admin_setLatestProvenCertificate with valid certificate ID | [Link](./tests/agglayer/admin-tests.bats#L274) | |
| bridge L2 originated ERC20 from L2 to L1 | [Link](./tests/agglayer/bridges.bats#L112) | |
| bridge native ETH from L1 to L2 | [Link](./tests/agglayer/bridges.bats#L36) | |
| bridge native ETH from L2 to L1 | [Link](./tests/agglayer/bridges.bats#L77) | |
| compare admin and regular API responses for same certificate | [Link](./tests/agglayer/admin-tests.bats#L214) | |
| query interop_getCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L196) | |
| query interop_getEpochConfiguration on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L161) | |
| query interop_getLatestKnownCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L177) | |
| query interop_getLatestPendingCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L237) | |
| query interop_getLatestSettledCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L256) | |
| query interop_getTxStatus on agglayer RPC for latest settled certificate returns done | [Link](./tests/agglayer/bridges.bats#L218) | |

## CDK Erigon Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| RPC and sequencer handle two large transactions | [Link](./tests/cdk-erigon/gas-limit-overflow.bats#L10) | |
| counter overflowing transactions do not create new batches | [Link](./tests/cdk-erigon/standard-erigon.bats#L287) | |
| send 0xFB opcode to sequencer and ensure failure | [Link](./tests/cdk-erigon/standard-erigon.bats#L11) | |
| send CREATE with large size | [Link](./tests/cdk-erigon/standard-erigon.bats#L32) | |
| send CREATE2 oom issue | [Link](./tests/cdk-erigon/standard-erigon.bats#L175) | |
| send CREATE2 with large size | [Link](./tests/cdk-erigon/standard-erigon.bats#L88) | |
| send IDENTITY precompile test | [Link](./tests/cdk-erigon/standard-erigon.bats#L335) | |
| send SHA256 counter | [Link](./tests/cdk-erigon/standard-erigon.bats#L153) | |
| send executable PUSH operand | [Link](./tests/cdk-erigon/standard-erigon.bats#L202) | |
| send exhaustive recursive CREATE transaction | [Link](./tests/cdk-erigon/standard-erigon.bats#L266) | |
| send large RETURN | [Link](./tests/cdk-erigon/standard-erigon.bats#L60) | |
| send malformed PUSH opcode | [Link](./tests/cdk-erigon/standard-erigon.bats#L117) | |
| send recursive CREATE transaction | [Link](./tests/cdk-erigon/standard-erigon.bats#L239) | |

## CDK Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Custom gas token deposit | [Link](./tests/cdk/bridge-e2e.bats#L72) | |
| Custom gas token withdrawal | [Link](./tests/cdk/bridge-e2e.bats#L137) | |
| Deploy and test UniswapV3 contract | [Link](./tests/cdk/basic-e2e.bats#L158) | |
| Native gas token deposit to WETH - BridgeAsset | [Link](./tests/cdk/bridge-e2e.bats#L62) | |
| Native gas token deposit to WETH - BridgeMessage | [Link](./tests/cdk/bridge-e2e.bats#L67) | |
| Send EOA transaction | [Link](./tests/cdk/basic-e2e.bats#L10) | |
| Test Allow List - Sending contracts deploy transaction when address is in allow list | [Link](./tests/cdk/access-list-e2e.bats#L114) | |
| Test Allow List - Sending contracts deploy transaction when address not in allow list | [Link](./tests/cdk/access-list-e2e.bats#L93) | |
| Test Allow List - Sending regular transaction when address is in allow list | [Link](./tests/cdk/access-list-e2e.bats#L102) | |
| Test Allow List - Sending regular transaction when address not in allow list | [Link](./tests/cdk/access-list-e2e.bats#L82) | |
| Test Block List - Sending contracts deploy transaction when address is in block list | [Link](./tests/cdk/access-list-e2e.bats#L72) | |
| Test Block List - Sending contracts deploy transaction when address not in block list | [Link](./tests/cdk/access-list-e2e.bats#L47) | |
| Test Block List - Sending regular transaction when address is in block list | [Link](./tests/cdk/access-list-e2e.bats#L59) | |
| Test Block List - Sending regular transaction when address not in block list | [Link](./tests/cdk/access-list-e2e.bats#L36) | |
| Test ERC20Mock contract | [Link](./tests/cdk/basic-e2e.bats#L48) | |
| Verify batches | [Link](./tests/cdk/e2e.bats#L10) | |

## Pectra Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| EIP-2935: Checking blocks outside historical serve window | [Link](./tests/pectra/eip2935.bats#L129) | |
| EIP-2935: Oldest possible historical block hash from state | [Link](./tests/pectra/eip2935.bats#L116) | |
| EIP-2935: Random historical block hashes from state | [Link](./tests/pectra/eip2935.bats#L94) | |
| EIP-7623: Check gas cost for 0x00 | [Link](./tests/pectra/eip7623.bats#L102) | |
| EIP-7623: Check gas cost for 0x000000 | [Link](./tests/pectra/eip7623.bats#L117) | |
| EIP-7623: Check gas cost for 0x0001 | [Link](./tests/pectra/eip7623.bats#L107) | |
| EIP-7623: Check gas cost for 0x000100 | [Link](./tests/pectra/eip7623.bats#L112) | |
| EIP-7623: Check gas cost for 0x00aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff001100220033004400550066007700880099 | [Link](./tests/pectra/eip7623.bats#L122) | |
| EIP-7623: Check gas cost for 0xffff | [Link](./tests/pectra/eip7623.bats#L127) | |
| EIP-7623: Check gas cost for empty calldata | [Link](./tests/pectra/eip7623.bats#L97) | |
| EIP-7685: RequestsHash in block header | [Link](./tests/pectra/eip7685.bats#L59) | |
| EIP-7691: Max blobs per block | [Link](./tests/pectra/eip7691.bats#L59) | |
| EIP-7702 Delegated contract with log event | [Link](./tests/pectra/eip7702.bats#L127) | |
| G1ADD test vectors KO | [Link](./tests/pectra/eip2537.bats#L153) | |
| G1ADD test vectors OK | [Link](./tests/pectra/eip2537.bats#L148) | |
| G1MSM test vectors KO | [Link](./tests/pectra/eip2537.bats#L192) | |
| G1MSM test vectors OK (long test) | [Link](./tests/pectra/eip2537.bats#L187) | |
| G1MUL test vectors KO | [Link](./tests/pectra/eip2537.bats#L172) | |
| G1MUL test vectors OK | [Link](./tests/pectra/eip2537.bats#L168) | |
| G2ADD test vectors KO | [Link](./tests/pectra/eip2537.bats#L163) | |
| G2ADD test vectors OK | [Link](./tests/pectra/eip2537.bats#L158) | |
| G2MSM test vectors KO | [Link](./tests/pectra/eip2537.bats#L202) | |
| G2MSM test vectors OK (long test) | [Link](./tests/pectra/eip2537.bats#L197) | |
| G2MUL test vectors KO | [Link](./tests/pectra/eip2537.bats#L182) | |
| G2MUL test vectors OK | [Link](./tests/pectra/eip2537.bats#L177) | |
| MAP_FP2_TO_G2 test vectors KO | [Link](./tests/pectra/eip2537.bats#L232) | |
| MAP_FP2_TO_G2 test vectors OK | [Link](./tests/pectra/eip2537.bats#L227) | |
| MAP_FP_TO_G1 test vectors KO | [Link](./tests/pectra/eip2537.bats#L222) | |
| MAP_FP_TO_G1 test vectors OK | [Link](./tests/pectra/eip2537.bats#L217) | |
| PAIRING_CHECK test vectors KO | [Link](./tests/pectra/eip2537.bats#L212) | |
| PAIRING_CHECK test vectors OK | [Link](./tests/pectra/eip2537.bats#L207) | |

## POS Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| add new validator | [Link](./tests/pos/validator.bats#L20) | |
| bridge MATIC/POL from L1 to L2 and confirm L2 MATIC/POL balance increased | [Link](./tests/pos/bridge.bats#L51) | |
| bridge MATIC/POL, ERC20, and ERC721 from L1 to L2 and confirm L2 balances increased | [Link](./tests/pos/bridge.bats#L188) | |
| bridge an ERC721 token from L1 to L2 and confirm L2 ERC721 balance increased | [Link](./tests/pos/bridge.bats#L139) | |
| bridge some ERC20 tokens from L1 to L2 and confirm L2 ERC20 balance increased | [Link](./tests/pos/bridge.bats#L95) | |
| delegate MATIC/POL to a validator | [Link](./tests/pos/validator.bats#L181) | |
| prune TxIndexer | [Link](./tests/pos/heimdall-v2.bats#L86) | |
| remove validator | [Link](./tests/pos/validator.bats#L363) | |
| undelegate MATIC/POL from a validator | [Link](./tests/pos/validator.bats#L275) | |
| update signer | [Link](./tests/pos/validator.bats#L147) | |
| update validator stake | [Link](./tests/pos/validator.bats#L60) | |
| update validator top-up fee | [Link](./tests/pos/validator.bats#L97) | |

## DApps Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| spot check Agora AUSD contract | [Link](./tests/dapps/dapps.bats#L429) | |
| spot check Arachnid's Deterministic Deployment Proxy contract | [Link](./tests/dapps/dapps.bats#L211) | |
| spot check BatchDistributor contract | [Link](./tests/dapps/dapps.bats#L287) | |
| spot check Create2Deployer contract | [Link](./tests/dapps/dapps.bats#L197) | |
| spot check CreateX contract | [Link](./tests/dapps/dapps.bats#L204) | |
| spot check ERC-4337 v0.6.0 EntryPoint contract | [Link](./tests/dapps/dapps.bats#L227) | |
| spot check ERC-4337 v0.6.0 SenderCreator contract | [Link](./tests/dapps/dapps.bats#L234) | |
| spot check ERC-4337 v0.7.0 EntryPoint contract | [Link](./tests/dapps/dapps.bats#L241) | |
| spot check ERC-4337 v0.7.0 SenderCreator contract | [Link](./tests/dapps/dapps.bats#L248) | |
| spot check Morpho AdaptiveCurveIrm contract | [Link](./tests/dapps/dapps.bats#L367) | |
| spot check Morpho Bundler3 contract | [Link](./tests/dapps/dapps.bats#L389) | |
| spot check Morpho Chainlink Oracle contract | [Link](./tests/dapps/dapps.bats#L374) | |
| spot check Morpho Metamorpho Factory contract | [Link](./tests/dapps/dapps.bats#L381) | |
| spot check Morpho Public Allocator contract | [Link](./tests/dapps/dapps.bats#L397) | |
| spot check Morpho blue contract | [Link](./tests/dapps/dapps.bats#L358) | |
| spot check MultiSend contract | [Link](./tests/dapps/dapps.bats#L157) | |
| spot check MultiSendCallOnly contract | [Link](./tests/dapps/dapps.bats#L170) | |
| spot check Multicall1 contract | [Link](./tests/dapps/dapps.bats#L271) | |
| spot check Multicall2 contract | [Link](./tests/dapps/dapps.bats#L279) | |
| spot check Multicall3 contract | [Link](./tests/dapps/dapps.bats#L190) | |
| spot check Permit2 contract | [Link](./tests/dapps/dapps.bats#L218) | |
| spot check PolygonZkEVMBridgeV2 contract | [Link](./tests/dapps/dapps.bats#L262) | |
| spot check RIP-7212 contract | [Link](./tests/dapps/dapps.bats#L298) | |
| spot check Safe contract | [Link](./tests/dapps/dapps.bats#L135) | |
| spot check SafeL2 contract | [Link](./tests/dapps/dapps.bats#L146) | |
| spot check SafeSingletonFactory contract | [Link](./tests/dapps/dapps.bats#L183) | |
| spot check Seaport 1.6 contract | [Link](./tests/dapps/dapps.bats#L306) | |
| spot check Seaport Conduit Controller contract | [Link](./tests/dapps/dapps.bats#L313) | |
| spot check Sushi Router contract | [Link](./tests/dapps/dapps.bats#L322) | |
| spot check Sushi V3 Factory contract | [Link](./tests/dapps/dapps.bats#L329) | |
| spot check Sushi V3 Position Manager contract | [Link](./tests/dapps/dapps.bats#L347) | |
| spot check Universal BTC contract | [Link](./tests/dapps/dapps.bats#L435) | |
| spot check Universal SOL contract | [Link](./tests/dapps/dapps.bats#L451) | |
| spot check Universal XRP contract | [Link](./tests/dapps/dapps.bats#L467) | |
| spot check Yearn AUSD contract | [Link](./tests/dapps/dapps.bats#L404) | |
| spot check Yearn WETH contract | [Link](./tests/dapps/dapps.bats#L416) | |

## Ethereum Test Cases

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| execute ethereum test cases and ensure liveness | [Link](./tests/ethereum-test-cases/ethereum-tests.bats#L216) | |

## Execution Layer Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Call special addresses | [Link](./tests/execution/special-addresses.bats#L17) | |
| Deploy polycli loadtest contracts | [Link](./tests/execution/polycli-cases.bats#L26) | |
| Make conflicting contract calls | [Link](./tests/execution/conflicting-contract-calls.bats#L54) | |
| Make conflicting transaction to pool | [Link](./tests/execution/conflicting-transactions-to-pool.bats#L17) | |
| Perform ERC20 Transfers | [Link](./tests/execution/polycli-cases.bats#L38) | |
| Perform some ERC721 Mints | [Link](./tests/execution/polycli-cases.bats#L43) | |
| Perform some Storage calls in the load tester contract | [Link](./tests/execution/polycli-cases.bats#L61) | |
| Perform some uniswap v3 calls | [Link](./tests/execution/polycli-cases.bats#L95) | |
| Setup Railgun | [Link](./tests/execution/railgun-contracts.bats#L22) | |
| Setup SmoothCryptoLib | [Link](./tests/execution/smooth-crypto-lib.bats#L31) | |
| Testing ECDSAB4 - verify | [Link](./tests/execution/smooth-crypto-lib.bats#L721) | |
| Testing EIP6565 - BasePointMultiply | [Link](./tests/execution/smooth-crypto-lib.bats#L75) | |
| Testing EIP6565 - BasePointMultiply_Edwards | [Link](./tests/execution/smooth-crypto-lib.bats#L122) | |
| Testing EIP6565 - HashInternal | [Link](./tests/execution/smooth-crypto-lib.bats#L248) | |
| Testing EIP6565 - Verify | [Link](./tests/execution/smooth-crypto-lib.bats#L423) | |
| Testing EIP6565 - Verify_LE | [Link](./tests/execution/smooth-crypto-lib.bats#L482) | |
| Testing EIP6565 - ecPow128 | [Link](./tests/execution/smooth-crypto-lib.bats#L541) | |
| Testing RIP7212 - verify | [Link](./tests/execution/smooth-crypto-lib.bats#L672) | |
| Using polycli to call some precompiles | [Link](./tests/execution/polycli-cases.bats#L101) | |
| Using polycli to do some inscriptions | [Link](./tests/execution/polycli-cases.bats#L107) | |

## Load Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| send 10,200 Uniswapv3 swaps sent and mined in 300 seconds | [Link](./tests/polycli-loadtests/polycli-loadtests.bats#L130) | |
| send 20,800 ERC721 mints and confirm mined in 240 seconds | [Link](./tests/polycli-loadtests/polycli-loadtests.bats#L96) | |
| send 41,200 ERC20 transfers and confirm mined in 240 seconds | [Link](./tests/polycli-loadtests/polycli-loadtests.bats#L64) | |
| send 85,700 EOA transfers and confirm mined in 60 seconds | [Link](./tests/polycli-loadtests/polycli-loadtests.bats#L33) | |

## CDK OP Geth Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Check L2 OP Isthmus operator fees | [Link](./tests/op/check-isthmus-fees.bats#L12) | |
| Check L2 OP native bridge is disabled | [Link](./tests/op/check-op-native-bridge.bats#L12) | |
| Check L2 OP vaults totalProcessed wei | [Link](./tests/op/check-isthmus-fees.bats#L55) | |
| Check L2 supported forks | [Link](./tests/op/check-supported-hardforks.bats#L39) | |
| Contract call through forced tx | [Link](./tests/op/forced-txs.bats#L197) | |
| Disable OptimisticMode | [Link](./tests/op/optimistic-mode.bats#L110) | |
| Enable OptimisticMode | [Link](./tests/op/optimistic-mode.bats#L86) | |
| Send a regular EOA forced tx with no l2 funds | [Link](./tests/op/forced-txs.bats#L140) | |
| Send a regular EOA forced tx | [Link](./tests/op/forced-txs.bats#L72) | |
| check address for custom gas token on L2 | [Link](./tests/op/custom-gas-token.bats#L44) | |
| send concurrent transactions and verify DA fee handling | [Link](./tests/op/simple-op-checks.bats#L53) | |
| sweep account with precise gas and DA fee estimation | [Link](./tests/op/simple-op-checks.bats#L19) | |
| test custom gas token bridge from L1 to L2 | [Link](./tests/op/custom-gas-token.bats#L50) | |
| test custom gas token bridge from L2 to L1 | [Link](./tests/op/custom-gas-token.bats#L178) | |

## Full System Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| CPU stress test with matrix operations | [Link](./scenarios/stress-test/container-stress.bats#L201) | |
| Disk Read/Write stress test | [Link](./scenarios/stress-test/container-stress.bats#L242) | |
| I/O stress test | [Link](./scenarios/stress-test/container-stress.bats#L229) | |
| Memory stress test | [Link](./scenarios/stress-test/container-stress.bats#L216) | |
| Run tests combinations | [Link](./scenarios/monitored-tests/monitored-tests.bats#L75) | |

## Other Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Bridge A -> Bridge B -> Claim A -> Claim B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L275) | |
| Bridge A -> Bridge B -> Claim B -> Claim A | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L355) | |
| Bridge asset A -> Claim asset A -> Bridge asset B -> Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L195) | |
| Bridge message A → Bridge asset B → Claim asset A → Claim message B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L10) | |
| Bridge message A → Bridge asset B → Claim message A → Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L71) | |
| Bridge message A → Claim message A → Bridge asset B → Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L133) | |
| Custom gas token deposit L1 -> L2 | [Link](./tests/aggkit/bridge-e2e-custom-gas.bats#L10) | |
| Custom gas token withdrawal L2 -> L1 | [Link](./tests/aggkit/bridge-e2e-custom-gas.bats#L78) | |
| ERC20 token deposit L1 -> L2 | [Link](./tests/aggkit/bridge-e2e.bats#L34) | |
| ERC20 token deposit L2 -> L1 | [Link](./tests/aggkit/bridge-e2e.bats#L116) | |
| L1 → Rollup 1 (custom gas token) → Rollup 2 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L64) | |
| L1 → Rollup 1 (custom gas token) → Rollup 3 -> Rollup 2 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L196) | |
| L1 → Rollup 1 (native) → Rollup 3 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L145) | |
| L1 → Rollup 3 (native/WETH) → Rollup 1 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L16) | |
| Modexp calls not valid for fusaka | [Link](./tests/fusaka/eip7823.bats#L62) | |
| Modexp gas costs | [Link](./tests/fusaka/eip7883.bats#L45) | |
| Modexp regular calls | [Link](./tests/fusaka/eip7823.bats#L42) | |
| Native token transfer L1 -> L2 | [Link](./tests/aggkit/bridge-e2e.bats#L245) | |
| RLP Execution block size limit 10M  | [Link](./tests/fusaka/eip7934.bats#L36) | |
| Test Aggoracle committee | [Link](./tests/aggkit/bridge-e2e-aggoracle-committee.bats#L10) | |
| Test GlobalExitRoot removal | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L31) | |
| Test L2 to L2 bridge | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L15) | |
| Test Sovereign Chain Bridge Events | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L105) | |
| Test Unset claims Events -> claim and unset claim in same cert | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L276) | |
| Test Unset claims Events -> claim in 1 cert, unset claim in 2nd, forcibly set in 3rd | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L349) | |
| Test block gas limit increase to 60M | [Link](./tests/fusaka/eip7935.bats#L19) | |
| Test execute multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call | [Link](./tests/aggkit/claim-reetrancy.bats#L477) | |
| Test new RPC endpoint eth_config | [Link](./tests/fusaka/eip7910.bats#L19) | |
| Test reentrancy protection for bridge claims - should prevent double claiming | [Link](./tests/aggkit/claim-reetrancy.bats#L69) | |
| Test triple claim internal calls -> 1 fail (same global index), 1 success (same global index) and 1 fail (different global index) | [Link](./tests/aggkit/internal-claims.bats#L1355) | |
| Test triple claim internal calls -> 1 fail, 1 success and 1 fail | [Link](./tests/aggkit/internal-claims.bats#L955) | |
| Test triple claim internal calls -> 1 success, 1 fail and 1 success | [Link](./tests/aggkit/internal-claims.bats#L516) | |
| Test triple claim internal calls -> 3 success | [Link](./tests/aggkit/internal-claims.bats#L62) | |
| Test zkCounters | [Link](./tests/zkevm/zk-counters-tests.bats#L10) | |
| Transaction using new CLZ instruction | [Link](./tests/fusaka/eip7939.bats#L19) | |
| Transaction with more than 2^24 gas | [Link](./tests/fusaka/eip7825.bats#L19) | |
| Transfer message L2 to L2 | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L74) | |
| Transfer message | [Link](./tests/aggkit/bridge-e2e.bats#L12) | |
| Verify batches | [Link](./tests/zkevm/batch-verification.bats#L10) | |
| Verify certificate settlement | [Link](./tests/aggkit/e2e-pp.bats#L10) | |
| p256verify call | [Link](./tests/fusaka/eip7951.bats#L46) | |
| prover stress test | [Link](./tests/pessimistic/prover-stress.bats#L10) | |
| query finalized, safe, latest, and pending blocks return expected order | [Link](./tests/evm-rpc/simple-validations.bats#L95) | |
| send ETH and verify pending nonce updates | [Link](./tests/evm-rpc/simple-validations.bats#L64) | |
| send and sweep account with precise gas calculation | [Link](./tests/evm-rpc/simple-validations.bats#L13) | |
| send multiple transactions with same nonce and verify rejection | [Link](./tests/evm-rpc/simple-validations.bats#L168) | |
| send zero priced transactions and confirm rejection | [Link](./tests/evm-rpc/simple-validations.bats#L36) | |
| trigger local balance tree underflow bridge revert | [Link](./tests/pessimistic/local-balance-tree-underflow.bats#L18) | |

## Kurtosis Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Fork 9 validium w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-validium.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork9-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 9 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-rollup.yml) | |
| Fork 9 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork9-cdk-erigon-validium.yml) | |
| Fork 11 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-rollup.yml) | |
| Fork 11 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 11 validium w/ legacy stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.2.31/.github/tests/combinations/fork11-legacy-zkevm-rollup.yml) | Although this is testable using an older Kurtosis tag, it is not actively maintained and tested in the Kurtosis CDK CI anymore. |
| Fork 12 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-rollup.yml) | |
| Fork 12 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork11-cdk-erigon-validium.yml) | |
| Fork 12 soverign w/ erigon stack and SP1 | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork12-cdk-erigon-sovereign.yml) | |
| Fork 13 rollup w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-rollup.yml) | |
| Fork 13 validium w/ erigon stack and mock prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/combinations/fork13-cdk-erigon-validium.yml) | |
| CDK-OP-Stack wit network SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct-real-prover.yml) | |
| CDK-OP-Stack with mock SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/chains/op-succinct.yml) | |
| CDK-OP-Stack without SP1 prover | [Link](https://github.com/0xPolygon/kurtosis-cdk/blob/v0.4.8/.github/tests/nightly/op-rollup/op-default.yml) | |

## External Test References

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Manual acceptance criteria | [Link](https://www.notion.so/polygontechnology/9dc3c0e78e7940a39c7cfda5fd3ede8f?v=4dfc351d725c4792adb989a4aad8b69e) | |
| Access list tests | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/main/tests/berlin/eip2930_access_list) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Same block deployment and execution | [Link](https://github.com/jhkimqd/execution-spec-tests/blob/jihwan/cdk-op-geth/tests/custom/same_block_deploy_and_call.py) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-1559 Implementation | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/static/state_tests/stEIP1559) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| EIP-6780 Implementation | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/cancun/eip6780_selfdestruct) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Every known opcode | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests/frontier/opcodes) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Blob, Accesslist, EIP-1559, EIP-7702 | [Link](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth/tests) | Testable using [Execution Spec Tests](https://github.com/jhkimqd/execution-spec-tests/tree/jihwan/cdk-op-geth) |
| Smooth crypto test cases | [Link](https://github.com/0xPolygon/jhilliard/blob/acbb0546f9b5fef82bb3280983305b812b43318c/evm-rpc-tests/roles/smoothcrypto/tasks/main.yml) | Some functions with [libSCL_eddsaUtils.sol](https://github.com/get-smooth/crypto-lib/blob/main/src/lib/libSCL_eddsaUtils.sol) does not work |
| Ethereum test suite stress tests | [Link](https://github.com/0xPolygon/jhilliard/blob/main/evm-rpc-tests/misc/run-retest-with-cast.sh) | |
