# Tests Inventory

Table of tests currently implemented or being implemented in the E2E repository.


## LxLy Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Initial setup | [Link](./tests/lxly/bridge-tests-suite.bats#L131) | |
| Process bridge scenarios with dynamic network routing and claim deposits in parallel | [Link](./tests/lxly/bridge-tests-suite.bats#L201) | |
| Reclaim test funds | [Link](./tests/lxly/bridge-tests-suite.bats#L430) | |
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
| aggregator with no funds | [Link](./tests/agglayer/nonce-tests.bats#L295) | |
| bridge L2 originated ERC20 from L2 to L1 | [Link](./tests/agglayer/bridges.bats#L112) | |
| bridge native ETH from L1 to L2 | [Link](./tests/agglayer/bridges.bats#L36) | |
| bridge native ETH from L2 to L1 | [Link](./tests/agglayer/bridges.bats#L77) | |
| compare admin and regular API responses for same certificate | [Link](./tests/agglayer/admin-tests.bats#L214) | |
| eth_getTransactionBySenderAndNonce returns a transaction on Reth L1 | [Link](./tests/agglayer/rpc-tests.bats#L11) | |
| eth_getTransactionBySenderAndNonce returns null for unused nonce | [Link](./tests/agglayer/rpc-tests.bats#L73) | |
| query interop_getCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L196) | |
| query interop_getEpochConfiguration on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L161) | |
| query interop_getLatestKnownCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L177) | |
| query interop_getLatestPendingCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L237) | |
| query interop_getLatestSettledCertificateHeader on agglayer RPC returns expected fields | [Link](./tests/agglayer/bridges.bats#L256) | |
| query interop_getTxStatus on agglayer RPC for latest settled certificate returns done | [Link](./tests/agglayer/bridges.bats#L218) | |
| send 1 tx per block until a new certificate settles | [Link](./tests/agglayer/nonce-tests.bats#L266) | |
| send a tx using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L180) | |
| send many async txs using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L199) | |
| send many txs using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L190) | |
| send tx with nonce+1 using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L208) | |
| send tx with nonce+2 using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L222) | |
| send txs from nonce+1 to nonce+11 using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L237) | |
| send txs from nonce+2 to nonce+12 using aggregator private key | [Link](./tests/agglayer/nonce-tests.bats#L251) | |
| wait for a new certificate to be settled | [Link](./tests/agglayer/nonce-tests.bats#L173) | |

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
| EIP-2935: Checking blocks outside historical serve window | [Link](./tests/ethereum-hardforks/pectra/eip2935.bats#L129) | |
| EIP-2935: Oldest possible historical block hash from state | [Link](./tests/ethereum-hardforks/pectra/eip2935.bats#L116) | |
| EIP-2935: Random historical block hashes from state | [Link](./tests/ethereum-hardforks/pectra/eip2935.bats#L94) | |
| EIP-7623: Check gas cost for 0x00 | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L102) | |
| EIP-7623: Check gas cost for 0x000000 | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L117) | |
| EIP-7623: Check gas cost for 0x0001 | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L107) | |
| EIP-7623: Check gas cost for 0x000100 | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L112) | |
| EIP-7623: Check gas cost for 0x00aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff00110022003300440055006600770088009900aa00bb00cc00dd00ee00ff001100220033004400550066007700880099 | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L122) | |
| EIP-7623: Check gas cost for 0xffff | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L127) | |
| EIP-7623: Check gas cost for empty calldata | [Link](./tests/ethereum-hardforks/pectra/eip7623.bats#L97) | |
| EIP-7685: RequestsHash in block header | [Link](./tests/ethereum-hardforks/pectra/eip7685.bats#L59) | |
| EIP-7691: Max blobs per block | [Link](./tests/ethereum-hardforks/pectra/eip7691.bats#L59) | |
| EIP-7702 Delegated contract with log event | [Link](./tests/ethereum-hardforks/pectra/eip7702.bats#L127) | |
| G1ADD test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L153) | |
| G1ADD test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L148) | |
| G1MSM test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L192) | |
| G1MSM test vectors OK (long test) | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L187) | |
| G1MUL test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L172) | |
| G1MUL test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L168) | |
| G2ADD test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L163) | |
| G2ADD test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L158) | |
| G2MSM test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L202) | |
| G2MSM test vectors OK (long test) | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L197) | |
| G2MUL test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L182) | |
| G2MUL test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L177) | |
| MAP_FP2_TO_G2 test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L232) | |
| MAP_FP2_TO_G2 test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L227) | |
| MAP_FP_TO_G1 test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L222) | |
| MAP_FP_TO_G1 test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L217) | |
| PAIRING_CHECK test vectors KO | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L212) | |
| PAIRING_CHECK test vectors OK | [Link](./tests/ethereum-hardforks/pectra/eip2537.bats#L207) | |

## Fusaka Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| Modexp calls not valid for fusaka | [Link](./tests/ethereum-hardforks/fusaka/eip7823.bats#L62) | |
| Modexp gas costs | [Link](./tests/ethereum-hardforks/fusaka/eip7883.bats#L45) | |
| Modexp regular calls | [Link](./tests/ethereum-hardforks/fusaka/eip7823.bats#L42) | |
| RLP Execution block size limit 10M  | [Link](./tests/ethereum-hardforks/fusaka/eip7934.bats#L36) | |
| Test block gas limit increase to 60M | [Link](./tests/ethereum-hardforks/fusaka/eip7935.bats#L19) | |
| Test new RPC endpoint eth_config | [Link](./tests/ethereum-hardforks/fusaka/eip7910.bats#L19) | |
| Transaction using new CLZ instruction | [Link](./tests/ethereum-hardforks/fusaka/eip7939.bats#L19) | |
| Transaction with more than 2^24 gas | [Link](./tests/ethereum-hardforks/fusaka/eip7825.bats#L19) | |
| p256verify call | [Link](./tests/ethereum-hardforks/fusaka/eip7951.bats#L46) | |

## POS Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| 0x01 ecRecover: recovered address matches known signer | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L570) | |
| 0x01 ecRecover: recovers signer from a valid ECDSA signature | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L214) | |
| 0x0100 p256Verify (secp256r1): Wycheproof test vector returns 1 (MadhugiriPro+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L525) | |
| 0x02 SHA-256: 'abc' matches NIST vector | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L560) | |
| 0x02 SHA-256: hash of empty string equals known constant | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L232) | |
| 0x03 RIPEMD-160: hash of empty string equals known constant | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L241) | |
| 0x04 identity: 256-byte patterned data round-trip | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L545) | |
| 0x04 identity: returns input bytes unchanged | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L250) | |
| 0x05 modexp: 2^256 mod 13 equals 3 | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L594) | |
| 0x05 modexp: 8^9 mod 10 equals 8 | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L259) | |
| 0x06 ecAdd (alt_bn128): G + G returns a valid non-zero curve point | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L276) | |
| 0x07 ecMul (alt_bn128): 2·G matches ecAdd(G, G) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L291) | |
| 0x08 ecPairing (alt_bn128): empty input returns 1 (trivial pairing check) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L316) | |
| 0x09 blake2F: EIP-152 test vector 5 (12 rounds, 'abc' message) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L325) | |
| 0x0a KZG point evaluation: active on Cancun+ (rejects invalid input) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L363) | |
| 0x0a KZG: removed after LisovoPro — BALANCE charges cold gas (2600) | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L235) | |
| 0x0a KZG: removed after LisovoPro — EXTCODESIZE charges cold gas | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L259) | |
| 0x0a KZG: removed after LisovoPro — eth_call returns empty | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L209) | |
| 0x0b BLS12-381 G1 Add: identity + G equals G (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L378) | |
| 0x0c BLS12-381 G1 MSM: scalar-1 times G equals G (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L399) | |
| 0x0d BLS12-381 G2 Add: identity + G2 equals G2 (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L417) | |
| 0x0e BLS12-381 G2 MSM: scalar-1 times G2 equals G2 (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L441) | |
| 0x0f BLS12-381 Pairing: e(G1_infinity, G2) returns 1 (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L462) | |
| 0x10 BLS12-381 MapFpToG1: Fp element 1 maps to a non-trivial G1 point (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L485) | |
| 0x11 BLS12-381 MapFp2ToG2: Fp2 element (0,1) maps to a non-trivial G2 point (Prague+) | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L504) | |
| 1.2: BALANCE(0x0a) on-chain at LisovoPro — warm/cold gas baked into state root | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1376) | |
| 1.2: BLS12-381 (0x0b–0x11) active after Madhugiri | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L972) | |
| 1.2: BLS12-381 and p256Verify already active before Madhugiri (via upstream Prague) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L863) | |
| 1.2: BLS12-381 still active at MadhugiriPro | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1051) | |
| 1.2: KZG (0x0a) state before Lisovo | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1170) | |
| 1.2: KZG (0x0a) still inactive before Madhugiri | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L878) | |
| 1.2: KZG point evaluation (0x0a) active in Lisovo era (on-chain tx) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1235) | |
| 1.2: KZG point evaluation (0x0a) is INACTIVE at LisovoPro (known: missing from precompile table) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1335) | |
| 1.2: all precompiles correct at Lisovo | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1270) | |
| 1.2: all precompiles correct at LisovoPro | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1410) | |
| 1.2: all precompiles unchanged at Giugliano (same as LisovoPro) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1610) | |
| 1.2: legacy precompiles (0x01–0x09) active at genesis forks | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L737) | |
| 1.2: legacy precompiles + BLS + p256 still active at Dandeli | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1090) | |
| 1.2: legacy precompiles still active at Rio | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L826) | |
| 1.2: modexp (0x05) correctness at Madhugiri (EIP-7823/7883) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L992) | |
| 1.2: p256Verify (0x0100) active after MadhugiriPro | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1043) | |
| 1.2: p256Verify (0x0100) is DROPPED at Madhugiri (known: missing from Madhugiri precompile table) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L955) | |
| 1.2: p256Verify (0x0100) still inactive in Madhugiri era (before MadhugiriPro re-adds it) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1027) | |
| 1.3: Agra — PUSH0 opcode succeeds in transaction after fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L587) | |
| 1.3: Agra — initcode size limit enforced (EIP-3860) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L607) | |
| 1.3: Ahmedabad — contract > 24KB deploys successfully after fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L695) | |
| 1.3: Ahmedabad — contract > 32KB fails to deploy | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L711) | |
| 1.3: Dandeli — base fee dynamics change with 65% gas target | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1067) | |
| 1.3: Giugliano — base fee remains non-zero through fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1643) | |
| 1.3: Giugliano — bor_getBlockGasParams returns gasTarget and baseFeeChangeDenominator | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1485) | |
| 1.3: Giugliano — bor_getBlockGasParams returns null fields for pre-Giugliano block | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1533) | |
| 1.3: Giugliano — chain progresses smoothly through fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1468) | |
| 1.3: Giugliano — gasTarget is consistent with gasLimit and target percentage | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1572) | |
| 1.3: Lisovo — CLZ opcode reverts in transaction before fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1154) | |
| 1.3: Lisovo — CLZ opcode succeeds and returns correct value after fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1211) | |
| 1.3: LisovoPro — chain progresses smoothly through fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1322) | |
| 1.3: Madhugiri — transaction at exactly 33554432 gas is accepted | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L943) | |
| 1.3: Madhugiri — transaction with gas > 33554432 is rejected (EIP-7825) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L920) | |
| 1.3: Napoli — MCOPY opcode succeeds in transaction after fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L641) | |
| 1.3: Napoli — SELFDESTRUCT no longer removes code (EIP-6780) | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L672) | |
| 1.3: Napoli — TSTORE/TLOAD succeed and produce correct state after fork | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L656) | |
| 1.3: Rio — chain progresses smoothly through fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L808) | |
| 1.3: SHA-256 precompile gas stable across Madhugiri boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1004) | |
| 1.3: base fee exists and is non-zero across all fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1705) | |
| 1.3: blake2F precompile gas stable across Dandeli boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1117) | |
| 1.3: ecRecover precompile gas stable across Lisovo boundary | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1298) | |
| 1.3: no reorgs at fork boundaries — parent hashes are consistent | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1663) | |
| 1.3: timestamps strictly increasing across all fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/parallel-fork-tests.bats#L1685) | |
| 50 concurrent eth_blockNumber requests all succeed and return consistent values | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L15) | |
| 50 concurrent eth_getBalance requests all return valid results | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L59) | |
| 50 concurrent eth_getLogs requests all return valid arrays | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L104) | |
| 50 concurrent requests across additional RPC methods succeed | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L312) | |
| ADDMOD and MULMOD compute correctly | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L959) | |
| ADDRESS returns the contract's own address | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L296) | |
| BALANCE on a random non-precompile address costs cold gas (2600) | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L182) | |
| BALANCE on active precompile 0x01 (ecRecover) costs warm gas (~100), not cold (2600) | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L114) | |
| BALANCE on all active precompiles costs warm gas | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L140) | |
| BASEFEE opcode matches block baseFeePerGas | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L713) | |
| BASEFEE opcode returns value matching block header baseFeePerGas | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L454) | |
| BLOCKHASH(0) returns zero on Bor (genesis hash not available) | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L13) | |
| BYTE opcode extracts correct byte from word | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L910) | |
| BlockSTM: blocks with PIP-16 dependency data produce correct state | [Link](./tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats#L352) | |
| BlockSTM: coinbase-reading transactions do not cause state corruption | [Link](./tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats#L175) | |
| BlockSTM: high-contention storage slot does not cause chain halt | [Link](./tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats#L99) | |
| BlockSTM: rapid same-sender nonce sequence does not cause state divergence | [Link](./tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats#L43) | |
| BlockSTM: state roots match across multiple Bor nodes | [Link](./tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats#L260) | |
| Bor produces blocks on approximately 2-second sprint cadence | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L232) | |
| Bor system contracts (ValidatorContract 0x1000, StateReceiver 0x1001) are callable | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L654) | |
| BorValidatorSet (0x1000) getBorValidators returns non-empty validator list | [Link](./tests/pos/execution-specs/protocol/bor-system-contracts-validator-set-and-mrc20.bats#L49) | |
| BorValidatorSet (0x1000) has deployed code and is callable | [Link](./tests/pos/execution-specs/protocol/bor-system-contracts-validator-set-and-mrc20.bats#L21) | |
| CALL with value to non-existent account skips G_NEW_ACCOUNT on Bor | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L52) | |
| CALLDATASIZE returns correct input length | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L861) | |
| CHAINID returns the correct chain ID (EIP-1344) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L277) | |
| CLZ applied twice gives correct result | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L630) | |
| CLZ gas cost matches MUL (both cost 5 gas) | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L339) | |
| CLZ ignores trailing bits — only leading zeros matter | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L264) | |
| CLZ inside STATICCALL does not modify state | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L550) | |
| CLZ is cheaper than computing leading zeros via binary search | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L382) | |
| CLZ of alternating bit patterns | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L283) | |
| CLZ of consecutive values near power-of-2 boundary | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L587) | |
| CLZ of value with only the lowest bit set in each byte | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L616) | |
| CLZ opcode is active (feature probe) | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L107) | |
| CLZ result can be used by subsequent arithmetic (CLZ + SHR roundtrip) | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L435) | |
| CLZ returns correct values for all single-byte powers of 2 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L219) | |
| CLZ returns correct values for powers of 2 across byte boundaries | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L237) | |
| CLZ with leading zero bytes followed by non-zero byte | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L307) | |
| CLZ works correctly inside CALL context | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L481) | |
| CLZ works correctly inside DELEGATECALL context | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L519) | |
| CLZ(0) returns 256 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L144) | |
| CLZ(0x7FFF...FFFF) returns 1 — all bits set except MSB | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L207) | |
| CLZ(1) returns 255 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L154) | |
| CLZ(2) returns 254 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L164) | |
| CLZ(2^254) returns 1 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L196) | |
| CLZ(2^255) returns 0 — highest bit set | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L185) | |
| CLZ(max uint256) returns 0 | [Link](./tests/pos/execution-specs/evm/eip7939-clz-count-leading-zeros.bats#L174) | |
| CODESIZE returns correct runtime size | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L813) | |
| COINBASE opcode returns block miner address | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L541) | |
| CREATE deploys to the address predicted by cast compute-address | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L77) | |
| CREATE with maximum value transfer in constructor | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L513) | |
| CREATE2 address matches keccak256(0xff ++ deployer ++ salt ++ initCodeHash) | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L389) | |
| CREATE2 deploys child to predicted salt-derived address | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L200) | |
| CREATE2 redeploy after SELFDESTRUCT in creation tx succeeds | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L316) | |
| Calldata gas accounting: nonzero bytes cost more than zero bytes | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L624) | |
| Contract creation receipt has contractAddress field | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1066) | |
| Cross-contract storage isolation: two contracts store different values at slot 0 | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L1017) | |
| DELEGATECALL preserves caller context: msg.sender stored via proxy | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L55) | |
| EIP-1559 sender decrease equals value plus effectiveGasPrice times gasUsed | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L233) | |
| EIP-2930 type-1 access list tx fuzz and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L482) | |
| EXTCODEHASH correctness for EOA, deployed contract, and nonexistent account | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L233) | |
| EXTCODEHASH for empty account returns zero on Bor | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L161) | |
| EXTCODESIZE on active precompile 0x01 (ecRecover) costs warm gas (~100) | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L128) | |
| EXTCODESIZE on all active precompiles costs warm gas | [Link](./tests/pos/execution-specs/precompiles/precompile-warm-cold-gas-and-removal.bats#L161) | |
| Empty batch JSON-RPC returns empty array | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1157) | |
| GASLIMIT opcode matches block gasLimit | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L663) | |
| Gas limit boundary: exact intrinsic gas (21000) succeeds for simple transfer | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L601) | |
| KZG Bor vector: valid proof returns FIELD_ELEMENTS_PER_BLOB || BLS_MODULUS | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L129) | |
| KZG c-kzg vector correct_proof_0_0: zero polynomial at origin | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L144) | |
| KZG c-kzg vector correct_proof_1_0: constant polynomial (twos) at origin | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L164) | |
| KZG c-kzg vector correct_proof_2_0: non-trivial polynomial at origin | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L184) | |
| KZG c-kzg vector correct_proof_3_0: non-trivial polynomial at origin (alt) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L202) | |
| KZG c-kzg vector correct_proof_4_0: Bor's commitment polynomial at origin | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L220) | |
| KZG c-kzg vector incorrect_proof_0_0: wrong proof for zero polynomial | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L364) | |
| KZG point evaluation precompile is active at 0x0a | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L109) | |
| KZG precompile callable from a deployed contract via STATICCALL | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L523) | |
| KZG precompile gas cost is 50000 (EIP-4844) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L466) | |
| KZG rejects 192 bytes of all zeros | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L447) | |
| KZG rejects corrupted proof (bit-flip in Bor vector proof) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L385) | |
| KZG rejects empty input (0 bytes) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L241) | |
| KZG rejects mismatched versioned hash (all zeros) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L326) | |
| KZG rejects mismatched versioned hash (corrupted first byte) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L312) | |
| KZG rejects oversized input (193 bytes — one extra byte) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L282) | |
| KZG rejects truncated input (32 bytes — only versioned hash) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L253) | |
| KZG rejects truncated input (96 bytes — missing commitment and proof) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L265) | |
| KZG rejects undersized input (191 bytes — one byte short) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L296) | |
| KZG rejects versioned hash from different commitment | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L342) | |
| KZG rejects wrong y value (claim mismatch) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L408) | |
| KZG rejects wrong z value (evaluation point mismatch) | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L427) | |
| KZG return value is identical across different valid proofs | [Link](./tests/pos/execution-specs/evm/eip4844-kzg-point-evaluation.bats#L632) | |
| LOG event emission and retrieval via eth_getLogs | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L300) | |
| MCOPY basic non-overlapping copy of 32 bytes | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L145) | |
| MCOPY overlapping backward copy (src > dst) has correct memmove semantics | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L195) | |
| MCOPY overlapping forward copy (src < dst) has correct memmove semantics | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L171) | |
| MCOPY to high offset triggers memory expansion and charges gas | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L241) | |
| MCOPY with zero length is a no-op | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L218) | |
| MRC20 native token wrapper (0x1010) has deployed code and balance function | [Link](./tests/pos/execution-specs/protocol/bor-system-contracts-validator-set-and-mrc20.bats#L88) | |
| Multiple storage slots in one transaction | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L1139) | |
| NUMBER opcode returns correct block number | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L615) | |
| Nonce-too-low rejection | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L565) | |
| OOG during code-deposit phase fails the creation | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L345) | |
| ORIGIN returns the transaction sender EOA | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L315) | |
| P256 Wycheproof test vector #1 (signature malleability) verifies correctly | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L486) | |
| P256 Wycheproof test vector #60 (Shamir edge case) verifies correctly | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L517) | |
| P256 all-zero input returns empty (invalid point) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L167) | |
| P256 empty input returns empty output | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L107) | |
| P256 extra input bytes beyond 160 are ignored (still verifies) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L146) | |
| P256 invalid input still consumes gas (no gas refund on failure) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L389) | |
| P256 invalid signature returns empty output | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L79) | |
| P256 point not on curve returns empty | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L240) | |
| P256 precompile callable from a deployed contract via STATICCALL | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L576) | |
| P256 precompile gas cost is 6900 (PIP-80 doubled from 3450) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L267) | |
| P256 precompile is active at 0x0100 | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L49) | |
| P256 r=0 returns empty (r must be in range 1..n-1) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L191) | |
| P256 s=0 returns empty (s must be in range 1..n-1) | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L216) | |
| P256 truncated input (less than 160 bytes) returns empty output | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L125) | |
| P256 valid signature returns 1 | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L64) | |
| P256 wrong public key for valid signature returns empty | [Link](./tests/pos/execution-specs/precompiles/pip80-p256-precompile-gas-adjustment.bats#L545) | |
| PIP-11: eth_getBlockByNumber 'finalized' returns a valid block | [Link](./tests/pos/execution-specs/protocol/pip11-deterministic-finality-milestones.bats#L17) | |
| PIP-11: finalized block advances as new blocks are produced | [Link](./tests/pos/execution-specs/protocol/pip11-deterministic-finality-milestones.bats#L98) | |
| PIP-11: finalized block number is less than or equal to latest block number | [Link](./tests/pos/execution-specs/protocol/pip11-deterministic-finality-milestones.bats#L58) | |
| PIP-16: block extraData field is non-empty and present | [Link](./tests/pos/execution-specs/protocol/pip16-transaction-dependency-data.bats#L18) | |
| PIP-16: extraData is consistent across multiple recent blocks | [Link](./tests/pos/execution-specs/protocol/pip16-transaction-dependency-data.bats#L49) | |
| PIP-20: StateReceiver (0x1001) has StateCommitted event signature | [Link](./tests/pos/execution-specs/protocol/bor-system-contracts-validator-set-and-mrc20.bats#L174) | |
| PIP-30 probe: deploy 24577-byte runtime to detect active MAX_CODE_SIZE | [Link](./tests/pos/execution-specs/protocol/pip30-increased-max-code-size.bats#L48) | |
| PIP-30: deploy 28000-byte runtime succeeds (between EIP-170 and PIP-30 limits) | [Link](./tests/pos/execution-specs/protocol/pip30-increased-max-code-size.bats#L131) | |
| PIP-30: deploy 32769-byte runtime is rejected (exceeds PIP-30 limit) | [Link](./tests/pos/execution-specs/protocol/pip30-increased-max-code-size.bats#L113) | |
| PIP-30: deploy exactly 32768-byte runtime succeeds at PIP-30 boundary | [Link](./tests/pos/execution-specs/protocol/pip30-increased-max-code-size.bats#L75) | |
| PIP-36: StateReceiver (0x1001) has replayFailedStateSync function | [Link](./tests/pos/execution-specs/protocol/bor-system-contracts-validator-set-and-mrc20.bats#L130) | |
| PIP-45: MRC20 system contract decimals() returns 18 | [Link](./tests/pos/execution-specs/protocol/pip45-matic-to-pol-token-rename.bats#L87) | |
| PIP-45: MRC20 system contract name() returns valid token name | [Link](./tests/pos/execution-specs/protocol/pip45-matic-to-pol-token-rename.bats#L17) | |
| PIP-45: MRC20 system contract symbol() returns valid token symbol | [Link](./tests/pos/execution-specs/protocol/pip45-matic-to-pol-token-rename.bats#L53) | |
| PIP-6/58: base fee change rate is tighter than Ethereum default (1/8) | [Link](./tests/pos/execution-specs/protocol/pip6-pip58-base-fee-change-denominator.bats#L74) | |
| PIP-6/58: base fee changes by at most 1/64 per block (denominator = 64) | [Link](./tests/pos/execution-specs/protocol/pip6-pip58-base-fee-change-denominator.bats#L17) | |
| PIP-6/58: base fee is always positive and non-zero | [Link](./tests/pos/execution-specs/protocol/pip6-pip58-base-fee-change-denominator.bats#L136) | |
| PIP-74: StateSyncTx has expected fields (from, to, input) | [Link](./tests/pos/execution-specs/protocol/pip74-canonical-state-sync-transactions.bats#L68) | |
| PIP-74: blocks with transactions include StateSyncTx in transactionsRoot | [Link](./tests/pos/execution-specs/protocol/pip74-canonical-state-sync-transactions.bats#L126) | |
| PIP-74: scan recent blocks for StateSyncTx (type 0x7F) transactions | [Link](./tests/pos/execution-specs/protocol/pip74-canonical-state-sync-transactions.bats#L33) | |
| PIP-79 active: baseFee deviates from old deterministic formula (Lisovo only) | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L99) | |
| PUSH0 pushes zero onto the stack (EIP-3855) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L55) | |
| Parent hash chain integrity across 5 blocks | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L927) | |
| RETURNDATACOPY copies callee return data correctly | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L383) | |
| RETURNDATASIZE after CALL reflects callee return data length | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L350) | |
| RETURNDATASIZE before any call returns 0 | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L336) | |
| REVERT returns data and does not consume all gas | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L420) | |
| RPC: concurrent request burst does not crash node | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L85) | |
| RPC: creating many filters does not exhaust node resources | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L185) | |
| RPC: debug_traceBlockByNumber does not crash on recent block | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L233) | |
| RPC: heavy eth_call does not crash node | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L145) | |
| RPC: large eth_getLogs range does not crash node | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L40) | |
| RPC: mixed heavy read + write load does not degrade block production | [Link](./tests/pos/execution-specs/resilience/rpc-node-stability.bats#L281) | |
| SAR arithmetic right shift sign-extends negative values (EIP-145) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L108) | |
| SELFBALANCE returns contract's own balance | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L766) | |
| SELFDESTRUCT during construction leaves no code and zero balance | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L308) | |
| SELFDESTRUCT in same tx as creation destroys contract code | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L13) | |
| SELFDESTRUCT inside STATICCALL reverts | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L230) | |
| SELFDESTRUCT on pre-existing contract: code persists post-Cancun | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L56) | |
| SELFDESTRUCT sends balance to beneficiary | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L173) | |
| SELFDESTRUCT to self: balance preserved post-Cancun | [Link](./tests/pos/execution-specs/evm/eip6780-selfdestruct-cancun-restrictions.bats#L121) | |
| SHL left shift: 1 << 4 = 16 (EIP-145) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L74) | |
| SHR right shift: 0xFF >> 4 = 0x0F (EIP-145) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L91) | |
| SIGNEXTEND correctly sign-extends byte 0 of 0x80 | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L126) | |
| SSTORE + SLOAD roundtrip: stored value is retrievable and unwritten slots are zero | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L13) | |
| SSTORE gas refund: clearing a storage slot uses less gas than setting it | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L404) | |
| SSTORE overwrite: new value replaces old | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L1078) | |
| STATICCALL cannot modify state: SSTORE attempt reverts | [Link](./tests/pos/execution-specs/evm/evm-opcode-storage-and-call-correctness.bats#L144) | |
| StateReceiver system contract (0x0000000000000000000000000000000000001001) is callable | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L206) | |
| Sum of receipt gasUsed matches block gasUsed | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L959) | |
| TLOAD returns zero for unset transient slot | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L68) | |
| TSTORE + TLOAD roundtrip returns stored value | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L13) | |
| TSTORE gas cost is less than SSTORE for zero-to-nonzero write | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L388) | |
| TSTORE in DELEGATECALL shares caller transient storage context | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L439) | |
| TSTORE reverted by sub-call REVERT is undone | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L279) | |
| WIT: oversized GetWitness request is rejected | [Link](./tests/pos/execution-specs/resilience/witness-request-bounds.bats#L381) | |
| WIT: oversized GetWitnessMetadata request is rejected | [Link](./tests/pos/execution-specs/resilience/witness-request-bounds.bats#L361) | |
| accumulator stored in slot 0 is non-zero | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L220) | |
| add new validator | [Link](./tests/pos/validator.bats#L44) | |
| all-opcode liveness smoke: deploy contracts exercising major opcode groups | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L832) | |
| base fee adjusts between blocks following EIP-1559 dynamics | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L267) | |
| base fee is present and positive on all recent blocks (PIP-79 invariant) | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L63) | |
| baseFee change rate is tighter than Ethereum mainnet (max ±5% vs ±12.5%) | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L235) | |
| baseFee does not diverge over a long block range | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L364) | |
| baseFee stays within ±5% bounds under transaction load | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L296) | |
| baseFeePerGas field exists in block headers | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L427) | |
| basefee-fork: base fee is at least 7 wei (minimum) across all blocks | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L134) | |
| basefee-fork: base fee is non-zero at all fork boundaries | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L84) | |
| basefee-fork: base fee is within 5% boundary post-Lisovo | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L299) | |
| basefee-fork: base fee transitions smoothly across all fork boundaries | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L525) | |
| basefee-fork: consecutive blocks have valid base fee transition pre-Lisovo | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L196) | |
| basefee-fork: cross-client base fee agreement at fork boundaries | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L462) | |
| basefee-fork: target gas percentage changes at Dandeli | [Link](./tests/pos/execution-specs/protocol/basefee-fork-boundary-validation.bats#L359) | |
| batch JSON-RPC returns array of matching results | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L690) | |
| batch JSON-RPC under concurrent load: 50 concurrent batch requests | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L486) | |
| blake2f precompile (0x09) returns non-trivial output | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L623) | |
| block coinbase (miner field) is zero address on Bor | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L98) | |
| block production continues across validator rotation | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L338) | |
| block timestamp monotonicity across 10 consecutive blocks | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L872) | |
| block-filling stress: rapid-fire large calldata txs | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L793) | |
| bn256 precompiles (ecAdd 0x06, ecMul 0x07) return valid curve points | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L581) | |
| bor_getAuthor returns a valid address for latest block | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L498) | |
| bor_getCurrentValidators returns a non-empty validator list | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L521) | |
| bor_getSnapshot returns snapshot with validator data | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L475) | |
| bridge ERC20 tokens from L1 to L2 via Plasma bridge and confirm ERC20 balance increased on L2 | [Link](./tests/pos/plasma-bridge.bats#L389) | |
| bridge ERC721 token from L1 to L2 via Plasma bridge and confirm ERC721 balance increased on L2 | [Link](./tests/pos/plasma-bridge.bats#L496) | |
| bridge ETH from L1 to L2 via Plasma bridge and confirm MaticWeth balance increased on L2 | [Link](./tests/pos/plasma-bridge.bats#L277) | |
| bridge MATIC from L1 to L2 via Plasma bridge and confirm native tokens balance increased on L2 | [Link](./tests/pos/plasma-bridge.bats#L166) | |
| bridge POL from L1 to L2 via Plasma bridge and confirm native tokens balance increased on L2 | [Link](./tests/pos/plasma-bridge.bats#L128) | |
| chain continues producing blocks across sprint boundaries | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L39) | |
| chain continues producing blocks after heavy all-opcode deployment | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L677) | |
| chain liveness maintained under transaction flood | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L106) | |
| chain produces blocks when no transactions are pending | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L177) | |
| coinbase balance increases by at least the priority fee portion of gas cost | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L313) | |
| concurrent write/read race: tx submissions and state reads do not interfere | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L249) | |
| consecutive block baseFees are within ±5% of each other | [Link](./tests/pos/execution-specs/protocol/pip79-bounded-basefee-validation.bats#L184) | |
| consensus: Heimdall API is reachable and serving span data | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L282) | |
| consensus: block headers have valid structure across sprint boundaries | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L39) | |
| consensus: chain integrity maintained under transaction load | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L427) | |
| consensus: difficulty values follow expected pattern | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L134) | |
| consensus: finalized blocks match across nodes | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L186) | |
| consensus: state sync receipts are deterministic across blocks | [Link](./tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats#L333) | |
| contract-to-contract call fuzz: CALL/STATICCALL/DELEGATECALL | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L740) | |
| cross-client-receipts: cumulative gas used matches for shared blocks | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L445) | |
| cross-client-receipts: gas used in blocks agree at fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L242) | |
| cross-client-receipts: logs root matches at fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L344) | |
| cross-client-receipts: receipt root matches at Lisovo boundary | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L224) | |
| cross-client-receipts: receipt root matches at Madhugiri boundary | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L207) | |
| cross-client-receipts: receipt root matches at Rio boundary | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L194) | |
| cross-client-receipts: receipt status codes agree for system transactions | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L380) | |
| cross-client-receipts: transaction count agrees at fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-receipt-consistency.bats#L279) | |
| cross-client: Bor and Erigon are on the same chain tip (gap ≤ 32 blocks) | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats#L341) | |
| cross-client: Erigon syncs through Dandeli→Lisovo→LisovoPro and agrees with Bor | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats#L298) | |
| cross-client: Erigon syncs through Giugliano and agrees with Bor on block hash | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats#L325) | |
| cross-client: Erigon syncs through Madhugiri forks and agrees with Bor | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats#L285) | |
| cross-client: Erigon syncs through Rio and agrees with Bor at fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/cross-client-state-roots.bats#L272) | |
| delegate to a validator | [Link](./tests/pos/validator.bats#L141) | |
| deploy contract that returns 24577 runtime bytes is rejected by EIP-170 | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L117) | |
| deploy contract that returns exactly 24576 runtime bytes succeeds (EIP-170 boundary) | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L143) | |
| deploy contract that reverts in constructor leaves no code at deployed address | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L41) | |
| deploy contract with 0xEF leading runtime byte is rejected by EIP-3541 | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L174) | |
| deploy initcode exactly at EIP-3860 limit (49152 bytes) succeeds | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L72) | |
| deploy initcode one byte over EIP-3860 limit (49153 bytes) is rejected | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L92) | |
| deploy single STOP opcode contract succeeds and code at address is empty | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L13) | |
| enforce deterministic fallback behavior | [Link](./tests/pos/veblop/invariants.bats#L156) | |
| enforce equal block distribution between block producers at the execution layer | [Link](./tests/pos/veblop/invariants.bats#L116) | |
| enforce equal slot distribution between block producers at the consensus layer | [Link](./tests/pos/veblop/invariants.bats#L68) | |
| enforce minimum one and maximum three selected producers per span | [Link](./tests/pos/veblop/invariants.bats#L34) | |
| eth_call does not consume gas or advance nonce | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L113) | |
| eth_call to plain EOA returns 0x | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L60) | |
| eth_chainId returns a value matching cast chain-id | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L14) | |
| eth_estimateGas for EOA transfer returns 21000 | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L51) | |
| eth_estimateGas for failing call returns error | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L776) | |
| eth_feeHistory returns baseFeePerGas array and oldestBlock | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L321) | |
| eth_gasPrice returns a valid non-zero hex value | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L96) | |
| eth_getBalance at historical block returns correct value | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1108) | |
| eth_getBalance returns non-zero for funded account and zero for unused address | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L161) | |
| eth_getBlockByHash result matches eth_getBlockByNumber for latest block | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L27) | |
| eth_getBlockByNumber 'earliest' returns genesis block | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L548) | |
| eth_getBlockByNumber 'pending' returns valid response | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L573) | |
| eth_getBlockByNumber with fullTransactions=true returns full tx objects | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L359) | |
| eth_getBlockTransactionCountByNumber and ByHash agree on tx count | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L257) | |
| eth_getCode returns 0x for an EOA | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L114) | |
| eth_getCode returns non-empty bytecode for L2 StateReceiver contract | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L123) | |
| eth_getLogs for block 0 to 0 returns a valid array | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L86) | |
| eth_getLogs returns empty array for future block range | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L69) | |
| eth_getLogs with reversed block range returns error or empty array | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L135) | |
| eth_getLogs: MRC20 (0x1010) events are address-indexed in state-sync blocks | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L492) | |
| eth_getLogs: StateReceiver (0x1001) events are address-indexed in state-sync blocks | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L447) | |
| eth_getLogs: address-filtered log count matches receipt log count per address | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L392) | |
| eth_getLogs: all receipt logs are discoverable via eth_getLogs for the same block | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L690) | |
| eth_getLogs: combined address+topic filter returns state-sync logs | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L560) | |
| eth_getLogs: log ordering in address-filtered results matches receipt order | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L529) | |
| eth_getLogs: multi-block range with address filter includes state-sync logs | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L627) | |
| eth_getLogs: range + address + topic filter returns state-sync logs (exact reporter pattern) | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L735) | |
| eth_getLogs: state-sync logs appear when filtering by contract address | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L283) | |
| eth_getLogs: state-sync logs appear when filtering by topic only (no address) | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L360) | |
| eth_getProof returns valid Merkle proof structure | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L826) | |
| eth_getStorageAt returns zero for EOA and valid 32-byte word for contracts | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L286) | |
| eth_getTransactionByHash and ByBlockNumberAndIndex return consistent tx data | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L191) | |
| eth_getTransactionCount returns hex nonce matching cast nonce | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L237) | |
| eth_getTransactionReceipt has all required EIP fields | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L733) | |
| eth_getTransactionReceipt returns null for unknown transaction hash | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L42) | |
| eth_getUncleCountByBlockNumber returns 0 (PoS has no uncles) | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1050) | |
| eth_maxPriorityFeePerGas returns a valid hex value | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L310) | |
| eth_sendRawTransaction rejects invalid signature | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L623) | |
| eth_sendRawTransaction rejects wrong chainId | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L649) | |
| eth_syncing returns false on synced node | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L602) | |
| every-opcode contract deploys successfully | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L209) | |
| finality: all nodes agree on finalized block hash | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L293) | |
| finality: finality depth is reasonable | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L533) | |
| finality: finalized block number is non-zero and advancing | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L160) | |
| finality: finalized blocks have immutable hashes | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L471) | |
| finality: milestone block hash matches bor finalized range | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L386) | |
| finality: safe <= finalized <= latest block ordering | [Link](./tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats#L221) | |
| fuzz contract creations and assert individual tx outcomes | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L233) | |
| fuzz node with EIP-1559 type-2 transactions and verify processing | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L368) | |
| fuzz node with edge-case contract creation bytecodes and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L43) | |
| fuzz node with edge-case gas limits and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L143) | |
| fuzz node with mixed zero/non-zero calldata and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L312) | |
| fuzz node with non-zero calldata transactions and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L189) | |
| fuzz node with variable-size calldata transactions and verify liveness | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L98) | |
| fuzz scan: no unknown precompiles in 0x0001..PRECOMPILE_FUZZ_MAX | [Link](./tests/pos/execution-specs/precompiles/precompile-correctness-and-discovery.bats#L58) | |
| gRPC EXPLOIT: ChainSetHead rewinds the node's chain | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L185) | |
| gRPC EXPLOIT: DebugPprof exposes runtime heap profile | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L466) | |
| gRPC EXPLOIT: PeersList exposes full network topology | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L305) | |
| gRPC EXPLOIT: PeersRemove evicts many peers without authentication | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L327) | |
| gRPC aftermath: target node can be restored after rewind | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L504) | |
| gRPC recon: Status returns current block (proves unauthenticated read) | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L172) | |
| gRPC recon: reflection lists all services without authentication | [Link](./tests/pos/execution-specs/resilience/grpc-admin-exposure.bats#L163) | |
| gas-metering: CALL to cold address costs 2600 gas across all forks | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L346) | |
| gas-metering: MaxTxGas (30M) enforced at Madhugiri | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L161) | |
| gas-metering: SSTORE from zero to non-zero gas cost is 20000 at all forks | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L244) | |
| gas-metering: cross-client gas agreement for identical transactions | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L712) | |
| gas-metering: gas refund cap is correctly applied | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L417) | |
| gas-metering: intrinsic gas for contract creation consistent across forks | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L528) | |
| gas-metering: simple ETH transfer gas is 21000 across all forks | [Link](./tests/pos/execution-specs/evm/gas-metering-fork-transitions.bats#L625) | |
| gasUsed <= gasLimit for latest block | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L907) | |
| higher concurrency watermark: 100 and 500 concurrent eth_blockNumber requests | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L205) | |
| insufficient balance rejection: tx with value+gas > balance is rejected | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L496) | |
| intermediate accumulator written to slot 0x11235813 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L234) | |
| isolate the current block producer mid-span to trigger a producer rotation | [Link](./tests/pos/veblop/faults.bats#L89) | |
| large return data in constructor near EIP-170 limit (24000 bytes) succeeds | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L576) | |
| latest block contains required post-London fields and valid shapes | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L427) | |
| legacy precompiles (ecrecover, sha256, ripemd160, identity) produced results | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L485) | |
| log data contains 'John was here' payload | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L320) | |
| logsBloom is zero for genesis block (no log-emitting txs) | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1024) | |
| mixed concurrent RPC methods succeed without interfering with each other | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L144) | |
| modexp precompile (0x05) returns expected result | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L555) | |
| multi-sender concurrent fuzz: 10 wallets fire txs simultaneously | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L608) | |
| multi-sender concurrent tx submissions: 10 wallets x 5 txs each | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L411) | |
| multiple CREATEs in single transaction: factory creates 5 children | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L453) | |
| nested contract creation: constructor deploys child via CREATE | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L263) | |
| net_version returns a non-empty numeric string | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L401) | |
| nonce increments by exactly 1 after each successful transaction | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L135) | |
| nonce replacement stress: higher gas replaces pending tx | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L672) | |
| nonce-gap stress: out-of-order submission resolves correctly | [Link](./tests/pos/execution-specs/transactions/evm-transaction-fuzzing-and-liveness.bats#L553) | |
| out-of-gas transaction still increments sender nonce | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L155) | |
| precompile-fork-safety: KZG (0x0a) IS active at Lisovo block | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L199) | |
| precompile-fork-safety: KZG (0x0a) is NOT active at LisovoPro | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L260) | |
| precompile-fork-safety: KZG (0x0a) is NOT active before Lisovo | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L173) | |
| precompile-fork-safety: P256Verify (0x0100) gas cost at Lisovo | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L352) | |
| precompile-fork-safety: P256Verify (0x0100) gas cost pre-Lisovo | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L308) | |
| precompile-fork-safety: cross-client precompile consistency at Lisovo | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L540) | |
| precompile-fork-safety: gas estimation changes correctly at KZG boundary | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L494) | |
| precompile-fork-safety: precompile set changes are consistent across all nodes | [Link](./tests/pos/execution-specs/precompiles/precompile-fork-transition-safety.bats#L391) | |
| prune TxIndexer | [Link](./tests/pos/heimdall-v2.bats#L86) | |
| receipt contains 5 log entries from LOG0 through LOG4 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L286) | |
| recipient balance increases by exactly the value sent | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L48) | |
| remove validator | [Link](./tests/pos/validator.bats#L308) | |
| replay protection: same signed tx submitted twice does not double-spend | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L440) | |
| runtime code is 32 bytes and matches accumulator in slot 0 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L260) | |
| sender balance decreases by exactly gas cost plus value transferred | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L13) | |
| sha3Uncles field is empty-list RLP hash (PoS has no uncles) | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L1006) | |
| spam messages at the consensus layer and ensure the protocol handles them gracefully | [Link](./tests/pos/veblop/faults.bats#L149) | |
| sprint-boundary: no reorg at Giugliano fork (sprint+span boundary) | [Link](./tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats#L246) | |
| sprint-boundary: no reorg at Rio fork (exact sprint boundary) | [Link](./tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats#L203) | |
| sprint-boundary: producer at fork block matches bor_getSignersAtHash | [Link](./tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats#L219) | |
| sprint-boundary: timestamps strictly increasing across all sprint-aligned fork boundaries | [Link](./tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats#L285) | |
| sprint-boundary: validator set is consistent on Bor and Erigon at each sprint-aligned fork | [Link](./tests/pos/execution-specs/fork-transitions/sprint-boundary-fork-tests.bats#L262) | |
| stack depth limit: 1024 nested calls revert | [Link](./tests/pos/execution-specs/evm/contract-creation-and-deployment-limits.bats#L374) | |
| state sync events do not halt block production | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L287) | |
| state-consistency: all Bor nodes are reachable and producing blocks | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L285) | |
| state-consistency: all nodes agree on block hashes at Dandeli fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L342) | |
| state-consistency: all nodes agree on block hashes at Giugliano fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L362) | |
| state-consistency: all nodes agree on block hashes at Lisovo fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L348) | |
| state-consistency: all nodes agree on block hashes at LisovoPro fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L355) | |
| state-consistency: all nodes agree on block hashes at Madhugiri fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L330) | |
| state-consistency: all nodes agree on block hashes at MadhugiriPro fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L336) | |
| state-consistency: all nodes agree on block hashes at Rio fork boundary | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L325) | |
| state-consistency: all supported fork boundaries pass cross-node comparison | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L369) | |
| state-consistency: devnet has advanced past the last supported fork | [Link](./tests/pos/execution-specs/fork-transitions/fork-state-consistency.bats#L299) | |
| state-sync tx: from is zero address (0x0) | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L198) | |
| state-sync tx: gas, gasPrice, value, and nonce are all zero | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L222) | |
| state-sync tx: receipt exists and has at least one log | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L255) | |
| state-sync tx: to is zero address (0x0) | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L210) | |
| state-sync tx: type is 0x7f (StateSyncTx / PIP-74) | [Link](./tests/pos/execution-specs/rpc/statesync-getlogs-address-index.bats#L186) | |
| sustained RPC load over 30 seconds with monotonic block advancement | [Link](./tests/pos/execution-specs/rpc/rpc-concurrent-load-and-stress.bats#L536) | |
| system-contract-safety: MRC20 (POL) balance query works across all forks | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L256) | |
| system-contract-safety: StateReceiver contract code exists at all fork boundaries | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L203) | |
| system-contract-safety: ValidatorSet returns same set on all nodes | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L312) | |
| system-contract-safety: ValidatorSet.currentSpanNumber() returns valid span at all forks | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L486) | |
| system-contract-safety: ValidatorSet.getValidators() returns valid set at each fork boundary | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L127) | |
| system-contract-safety: system contract code hash unchanged across fork boundaries | [Link](./tests/pos/execution-specs/protocol/system-contract-fork-safety.bats#L398) | |
| total value is conserved: sender decrease equals recipient increase plus gas cost | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L183) | |
| trace covers CALL, CALLCODE, DELEGATECALL, STATICCALL | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L433) | |
| trace covers CREATE and CREATE2 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L442) | |
| trace covers DUP1-DUP16 and SWAP1-SWAP16 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L411) | |
| trace covers LOG0-LOG4 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L424) | |
| trace covers PUSH0 through PUSH32 | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L397) | |
| trace covers arithmetic, comparison, and bitwise opcodes | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L347) | |
| trace covers blob opcodes (BLOBHASH, BLOBBASEFEE) | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L474) | |
| trace covers environment and block info opcodes | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L359) | |
| trace covers memory, storage, and flow control opcodes | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L378) | |
| trace covers sub-contract terminal opcodes (STOP, REVERT, INVALID, SELFDESTRUCT) | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L460) | |
| trace covers transient storage (TSTORE, TLOAD) | [Link](./tests/pos/execution-specs/evm/every-opcode-coverage.bats#L451) | |
| transaction at node-reported gas price succeeds | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L139) | |
| transaction with trivially low gas price (1 wei) is rejected | [Link](./tests/pos/execution-specs/evm/bor-chain-specific-evm-behavior.bats#L112) | |
| transactions consuming significant gas do not halt chain | [Link](./tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats#L226) | |
| transient storage clears between transactions | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L112) | |
| transient storage is isolated per contract address | [Link](./tests/pos/execution-specs/evm/eip1153-tstore-tload-transient-storage.bats#L199) | |
| type 0 (legacy) receipt has correct type and gasPrice field | [Link](./tests/pos/execution-specs/transactions/transaction-types-and-gas-pricing.bats#L13) | |
| type 1 (EIP-2930) access list reduces gas for warm storage access | [Link](./tests/pos/execution-specs/transactions/transaction-types-and-gas-pricing.bats#L48) | |
| type 1 access list with multiple storage keys is accepted | [Link](./tests/pos/execution-specs/transactions/transaction-types-and-gas-pricing.bats#L202) | |
| type 2 (EIP-1559) effectiveGasPrice = baseFee + min(priorityFee, maxFee - baseFee) | [Link](./tests/pos/execution-specs/transactions/transaction-types-and-gas-pricing.bats#L125) | |
| type 2 maxFeePerGas below baseFee is rejected | [Link](./tests/pos/execution-specs/transactions/transaction-types-and-gas-pricing.bats#L170) | |
| undelegate from a validator | [Link](./tests/pos/validator.bats#L216) | |
| update signer | [Link](./tests/pos/validator.bats#L334) | |
| update validator stake | [Link](./tests/pos/validator.bats#L79) | |
| update validator top-up fee | [Link](./tests/pos/validator.bats#L103) | |
| warm COINBASE access costs less than cold access to arbitrary address (EIP-3651) | [Link](./tests/pos/execution-specs/evm/evm-opcodes-cancun-shanghai-eips.bats#L452) | |
| web3_clientVersion returns a non-empty version string | [Link](./tests/pos/execution-specs/rpc/rpc-method-conformance-and-validation.bats#L412) | |
| withdraw ERC20 tokens from L2 to L1 via Plasma bridge and confirm ERC20 balance increased on L1 | [Link](./tests/pos/plasma-bridge.bats#L426) | |
| withdraw ERC721 token from L2 to L1 via Plasma bridge and confirm ERC721 balance increased on L1 | [Link](./tests/pos/plasma-bridge.bats#L540) | |
| withdraw MaticWeth from L2 via Plasma bridge and confirm ETH balance increased on L1 | [Link](./tests/pos/plasma-bridge.bats#L313) | |
| withdraw native tokens from L2 via Plasma bridge and confirm POL balance increased on L1 | [Link](./tests/pos/plasma-bridge.bats#L203) | |
| withdraw validator rewards | [Link](./tests/pos/validator.bats#L286) | |
| zero-value self-transfer: only gas consumed, nonce increments | [Link](./tests/pos/execution-specs/transactions/transaction-balance-nonce-and-replay-invariants.bats#L525) | |

## Heimdall Tests

| Test Name | Reference | Notes |
|-----------|-----------|-------|
| checkpoint-range: all checkpoint block ranges are contiguous | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L202) | |
| checkpoint-range: all checkpoint root hashes are unique | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L467) | |
| checkpoint-range: checkpoint ranges do not overlap | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L286) | |
| checkpoint-range: checkpoint timestamps are monotonically increasing | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L415) | |
| checkpoint-range: first checkpoint starts at block 0 or expected genesis | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L333) | |
| checkpoint-range: latest checkpoint end is close to current bor block | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L368) | |
| checkpoint-range: no checkpoint has end_block < start_block | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-range-invariants.bats#L249) | |
| heimdall bor: current Bor block is within the latest span's block range | [Link](./tests/pos/heimdall/bor/span-in-turn.bats#L184) | |
| heimdall bor: each span producer has a non-empty valid signer address | [Link](./tests/pos/heimdall/bor/span-in-turn.bats#L286) | |
| heimdall bor: latest span has a non-zero block range (start_block < end_block) | [Link](./tests/pos/heimdall/bor/span-in-turn.bats#L136) | |
| heimdall bor: span selected_producers have no duplicate signer addresses | [Link](./tests/pos/heimdall/bor/span-in-turn.bats#L230) | |
| heimdall bridge: Heimdall block height is not lagging behind CometBFT tip | [Link](./tests/pos/heimdall/clerk/bridge-sync.bats#L336) | |
| heimdall bridge: at least one checkpoint has been acknowledged on L1 | [Link](./tests/pos/heimdall/clerk/bridge-sync.bats#L313) | |
| heimdall bridge: clerk event record ID does not exceed L1 state counter | [Link](./tests/pos/heimdall/clerk/bridge-sync.bats#L221) | |
| heimdall bridge: clerk has processed at least one state sync event | [Link](./tests/pos/heimdall/clerk/bridge-sync.bats#L188) | |
| heimdall bridge: event records are being processed in a timely manner | [Link](./tests/pos/heimdall/clerk/bridge-sync.bats#L255) | |
| heimdall checkpoint: ACK count is monotonically increasing over time | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-safety.bats#L188) | |
| heimdall checkpoint: Bor has the end_block of the latest checkpoint | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-chain-integrity.bats#L392) | |
| heimdall checkpoint: chain contiguity — checkpoint[i].start_block == checkpoint[i-1].end_block + 1 for latest 5 | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-chain-integrity.bats#L242) | |
| heimdall checkpoint: checkpoint sequence has no numbering gaps in latest 10 | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-safety.bats#L289) | |
| heimdall checkpoint: latest checkpoint is well-formed (proposer, start_block, end_block, root_hash present) | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-chain-integrity.bats#L204) | |
| heimdall checkpoint: no two consecutive checkpoints have the same root hash | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-safety.bats#L439) | |
| heimdall checkpoint: proposer address is non-empty and well-formed | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-safety.bats#L223) | |
| heimdall checkpoint: proposer is in active validator set | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-chain-integrity.bats#L346) | |
| heimdall checkpoint: root hash length is exactly 32 bytes (66 hex chars with 0x) | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-safety.bats#L374) | |
| heimdall checkpoint: root_hash is non-zero | [Link](./tests/pos/heimdall/consensus-correctness/checkpoint-chain-integrity.bats#L303) | |
| heimdall clerk: each event record has required non-empty fields (id, contract, tx_hash) | [Link](./tests/pos/heimdall/consensus-correctness/statesync-event-ordering.bats#L220) | |
| heimdall clerk: event record list is sorted by ID in strictly ascending order | [Link](./tests/pos/heimdall/consensus-correctness/statesync-event-ordering.bats#L134) | |
| heimdall clerk: latest-id endpoint is consistent with event record list | [Link](./tests/pos/heimdall/consensus-correctness/statesync-event-ordering.bats#L275) | |
| heimdall clerk: no duplicate IDs in event record list | [Link](./tests/pos/heimdall/consensus-correctness/statesync-event-ordering.bats#L182) | |
| heimdall consensus: all active validators have strictly positive voting power | [Link](./tests/pos/heimdall/consensus-correctness/consensus-liveness.bats#L247) | |
| heimdall consensus: chain is live and advancing | [Link](./tests/pos/heimdall/consensus-correctness/consensus-liveness.bats#L210) | |
| heimdall consensus: commit includes an entry for every validator in the active set | [Link](./tests/pos/heimdall/consensus-correctness/consensus-liveness.bats#L304) | |
| heimdall consensus: quorum of voting power committed each block | [Link](./tests/pos/heimdall/consensus-correctness/consensus-liveness.bats#L456) | |
| heimdall consensus: recent blocks decided at round 0 | [Link](./tests/pos/heimdall/consensus-correctness/consensus-liveness.bats#L399) | |
| heimdall milestone: chain contiguity — milestone[i].start_block == milestone[i-1].end_block + 1 for latest 5 | [Link](./tests/pos/heimdall/consensus-correctness/milestone-finality.bats#L295) | |
| heimdall milestone: end_block is not ahead of current Bor chain tip | [Link](./tests/pos/heimdall/consensus-correctness/milestone-finality.bats#L360) | |
| heimdall milestone: hash matches Bor block hash at end_block (oracle test) | [Link](./tests/pos/heimdall/consensus-correctness/milestone-finality.bats#L237) | |
| heimdall milestone: latest milestone is well-formed (proposer, start_block, end_block, hash present) | [Link](./tests/pos/heimdall/consensus-correctness/milestone-finality.bats#L199) | |
| heimdall milestone: latest milestone's end_block is within recent Bor history | [Link](./tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats#L472) | |
| heimdall milestone: milestone ID is monotonically increasing | [Link](./tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats#L403) | |
| heimdall node: chain ID is non-empty and consistent across endpoints | [Link](./tests/pos/heimdall/consensus-correctness/node-health.bats#L130) | |
| heimdall node: has at least one connected peer | [Link](./tests/pos/heimdall/consensus-correctness/node-health.bats#L256) | |
| heimdall node: is not catching up (fully synced) | [Link](./tests/pos/heimdall/consensus-correctness/node-health.bats#L178) | |
| heimdall node: latest block height is a positive integer | [Link](./tests/pos/heimdall/consensus-correctness/node-health.bats#L216) | |
| heimdall span: bor cross-check — bor_getAuthor(block) is in current span's selected_producers | [Link](./tests/pos/heimdall/consensus-correctness/span-validator-set.bats#L397) | |
| heimdall span: contiguity — span[i].start_block == span[i-1].end_block + 1 for latest 5 spans | [Link](./tests/pos/heimdall/consensus-correctness/span-validator-set.bats#L207) | |
| heimdall span: latest span is well-formed (id, start_block, end_block, selected_producers present) | [Link](./tests/pos/heimdall/consensus-correctness/span-validator-set.bats#L170) | |
| heimdall span: next span is being prepared before current span ends | [Link](./tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats#L295) | |
| heimdall span: producer count — 1 <= len(selected_producers) <= len(validator_set) | [Link](./tests/pos/heimdall/consensus-correctness/span-validator-set.bats#L362) | |
| heimdall span: producer membership — every selected_producer is in validator_set | [Link](./tests/pos/heimdall/consensus-correctness/span-validator-set.bats#L300) | |
| heimdall span: selected_producers count is non-zero and within validator set size | [Link](./tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats#L536) | |
| heimdall span: span duration meets minimum sprint length requirement | [Link](./tests/pos/heimdall/consensus-correctness/span-milestone-safety.bats#L241) | |
| heimdall stake: CometBFT validator set matches Heimdall active validator set | [Link](./tests/pos/heimdall/stake/validator-set-safety.bats#L411) | |
| heimdall stake: active validator set is never empty | [Link](./tests/pos/heimdall/stake/validator-set-safety.bats#L148) | |
| heimdall stake: all active validators have non-empty signer addresses | [Link](./tests/pos/heimdall/stake/validator-state.bats#L216) | |
| heimdall stake: all active validators have unique validator IDs | [Link](./tests/pos/heimdall/stake/validator-state.bats#L162) | |
| heimdall stake: no more than N validators jailed simultaneously | [Link](./tests/pos/heimdall/stake/validator-set-safety.bats#L201) | |
| heimdall stake: reported total voting power matches sum of individual validators | [Link](./tests/pos/heimdall/stake/validator-state.bats#L270) | |
| heimdall stake: validator proposer priority values are within safe range | [Link](./tests/pos/heimdall/stake/validator-set-safety.bats#L334) | |
| heimdall stake: validator set count is non-zero and consistent with CometBFT | [Link](./tests/pos/heimdall/stake/validator-state.bats#L363) | |
| heimdall stake: validator voting power is within safe integer bounds | [Link](./tests/pos/heimdall/stake/validator-set-safety.bats#L256) | |
| milestone-checkpoint: all recent milestones reference blocks within checkpoint ranges | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L437) | |
| milestone-checkpoint: latest milestone block <= latest checkpoint end_block | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L272) | |
| milestone-checkpoint: milestone block hash matches Bor RPC | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L378) | |
| milestone-checkpoint: milestone block height references a real Bor block | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L319) | |
| milestone-checkpoint: milestone count is positive and increasing | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L354) | |
| milestone-checkpoint: no gap between last milestone and current block > expected interval | [Link](./tests/pos/heimdall/consensus-correctness/milestone-checkpoint-consistency.bats#L543) | |
| span-sprint: all validators in current span have non-zero power | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L399) | |
| span-sprint: block producer at span boundary is in span's producer list | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L331) | |
| span-sprint: consecutive spans are contiguous | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L519) | |
| span-sprint: current block height is within active span range | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L603) | |
| span-sprint: current span has valid structure | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L182) | |
| span-sprint: span producer list matches Bor validator set | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L249) | |
| span-sprint: span transitions have no block production gap | [Link](./tests/pos/heimdall/bor/span-sprint-boundary-safety.bats#L455) | |
| statesync-consistency: all records have valid tx_hash and contract fields | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L193) | |
| statesync-consistency: event record IDs are strictly sequential | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L117) | |
| statesync-consistency: event records are in chronological order | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L140) | |
| statesync-consistency: latest record ID from API matches paginated count | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L215) | |
| statesync-consistency: no duplicate event record IDs | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L157) | |
| statesync-consistency: record count matches latest record ID | [Link](./tests/pos/heimdall/clerk/statesync-sequential-consistency.bats#L173) | |

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
| Setup SmoothCryptoLib | [Link](./tests/execution/smooth-crypto-lib.bats#L26) | |
| Testing ECDSAB4 - verify | [Link](./tests/execution/smooth-crypto-lib.bats#L422) | |
| Testing EIP6565 - BasePointMultiply | [Link](./tests/execution/smooth-crypto-lib.bats#L50) | |
| Testing EIP6565 - BasePointMultiply_Edwards | [Link](./tests/execution/smooth-crypto-lib.bats#L97) | |
| Testing EIP6565 - HashInternal | [Link](./tests/execution/smooth-crypto-lib.bats#L141) | |
| Testing EIP6565 - Verify | [Link](./tests/execution/smooth-crypto-lib.bats#L201) | |
| Testing EIP6565 - Verify_LE | [Link](./tests/execution/smooth-crypto-lib.bats#L260) | |
| Testing EIP6565 - ecPow128 | [Link](./tests/execution/smooth-crypto-lib.bats#L319) | |
| Testing RIP7212 - verify | [Link](./tests/execution/smooth-crypto-lib.bats#L373) | |

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
| Disable OptimisticMode | [Link](./tests/op/optimistic-mode.bats#L98) | |
| Enable OptimisticMode | [Link](./tests/op/optimistic-mode.bats#L74) | |
| Rotate OP batcher key | [Link](./tests/op/rotate-op-keys.bats#L16) | |
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
| Add single validator to committee | [Link](./tests/aggkit/aggsender-committee-updates.bats#L108) | |
| Bridge A -> Bridge B -> Claim A -> Claim B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L274) | |
| Bridge A -> Bridge B -> Claim B -> Claim A | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L354) | |
| Bridge asset A -> Claim asset A -> Bridge asset B -> Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L194) | |
| Bridge message A → Bridge asset B → Claim asset A → Claim message B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L10) | |
| Bridge message A → Bridge asset B → Claim message A → Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L71) | |
| Bridge message A → Claim message A → Bridge asset B → Claim asset B | [Link](./tests/aggkit/bridge-e2e-nightly.bats#L132) | |
| Custom gas token deposit L1 -> L2 | [Link](./tests/aggkit/bridge-e2e-custom-gas.bats#L10) | |
| Custom gas token withdrawal L2 -> L1 | [Link](./tests/aggkit/bridge-e2e-custom-gas.bats#L78) | |
| ERC20 token deposit L1 -> L2 | [Link](./tests/aggkit/bridge-e2e.bats#L33) | |
| ERC20 token deposit L2 -> L1 | [Link](./tests/aggkit/bridge-e2e.bats#L115) | |
| Inject LatestBlock-N GER - A case PP (another test) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L933) | |
| L1 → Rollup 1 (custom gas token) → Rollup 2 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L64) | |
| L1 → Rollup 1 (custom gas token) → Rollup 3 -> Rollup 2 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L196) | |
| L1 → Rollup 1 (native) → Rollup 3 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L145) | |
| L1 → Rollup 3 (native/WETH) → Rollup 1 | [Link](./tests/aggkit/bridge-e2e-3-chains.bats#L16) | |
| Measure certificate generation intervals | [Link](./tests/aggkit/trigger-cert-modes.bats#L130) | |
| Native token transfer L1 -> L2 | [Link](./tests/aggkit/bridge-e2e.bats#L243) | |
| Remove single validator from committee | [Link](./tests/aggkit/aggsender-committee-updates.bats#L147) | |
| Test Aggoracle committee | [Link](./tests/aggkit/bridge-e2e-aggoracle-committee.bats#L10) | |
| Test L2 to L2 bridge | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L15) | |
| Test Sovereign Chain Bridge Events | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L48) | |
| Test execute multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call | [Link](./tests/aggkit/claim-reetrancy.bats#L472) | |
| Test inject invalid GER on L2 (bridges are valid) | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L212) | |
| Test invalid GER injection case A (FEP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L825) | |
| Test invalid GER injection case A (PP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L716) | |
| Test invalid GER injection case B2 (FEP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L396) | |
| Test invalid GER injection case B2 (PP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L38) | |
| Test reentrancy protection for bridge claims - should prevent double claiming | [Link](./tests/aggkit/claim-reetrancy.bats#L67) | |
| Test triple claim internal calls -> 1 fail (same global index), 1 success (same global index) and 1 fail (different global index) | [Link](./tests/aggkit/internal-claims.bats#L1344) | |
| Test triple claim internal calls -> 1 fail, 1 success and 1 fail | [Link](./tests/aggkit/internal-claims.bats#L946) | |
| Test triple claim internal calls -> 1 success, 1 fail and 1 success | [Link](./tests/aggkit/internal-claims.bats#L509) | |
| Test triple claim internal calls -> 3 success | [Link](./tests/aggkit/internal-claims.bats#L57) | |
| Test zkCounters | [Link](./tests/zkevm/zk-counters-tests.bats#L10) | |
| Transfer message L2 to L2 | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L68) | |
| Transfer message | [Link](./tests/aggkit/bridge-e2e.bats#L11) | |
| Verify batches | [Link](./tests/zkevm/batch-verification.bats#L10) | |
| Verify certificate settlement | [Link](./tests/aggkit/e2e-pp.bats#L10) | |
| bridge transaction is indexed and autoclaimed on L2 | [Link](./tests/bridge-hub-api.bats#L14) | |
| bridge transaction is indexed on L1 | [Link](./tests/bridge-hub-api.bats#L95) | |
| foo | [Link](./tests/foo.bats#L10) | |
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
