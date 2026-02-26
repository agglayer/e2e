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
| 0x01 ecRecover: recovered address matches known signer | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L570) | |
| 0x01 ecRecover: recovers signer from a valid ECDSA signature | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L214) | |
| 0x0100 p256Verify (secp256r1): Wycheproof test vector returns 1 (MadhugiriPro+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L525) | |
| 0x02 SHA-256: 'abc' matches NIST vector | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L560) | |
| 0x02 SHA-256: hash of empty string equals known constant | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L232) | |
| 0x03 RIPEMD-160: hash of empty string equals known constant | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L241) | |
| 0x04 identity: 256-byte patterned data round-trip | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L545) | |
| 0x04 identity: returns input bytes unchanged | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L250) | |
| 0x05 modexp: 2^256 mod 13 equals 3 | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L594) | |
| 0x05 modexp: 8^9 mod 10 equals 8 | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L259) | |
| 0x06 ecAdd (alt_bn128): G + G returns a valid non-zero curve point | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L276) | |
| 0x07 ecMul (alt_bn128): 2·G matches ecAdd(G, G) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L291) | |
| 0x08 ecPairing (alt_bn128): empty input returns 1 (trivial pairing check) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L316) | |
| 0x09 blake2F: EIP-152 test vector 5 (12 rounds, 'abc' message) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L325) | |
| 0x0a KZG point evaluation: active on Cancun+ (rejects invalid input) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L363) | |
| 0x0b BLS12-381 G1 Add: identity + G equals G (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L378) | |
| 0x0c BLS12-381 G1 MSM: scalar-1 times G equals G (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L399) | |
| 0x0d BLS12-381 G2 Add: identity + G2 equals G2 (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L417) | |
| 0x0e BLS12-381 G2 MSM: scalar-1 times G2 equals G2 (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L441) | |
| 0x0f BLS12-381 Pairing: e(G1_infinity, G2) returns 1 (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L462) | |
| 0x10 BLS12-381 MapFpToG1: Fp element 1 maps to a non-trivial G1 point (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L485) | |
| 0x11 BLS12-381 MapFp2ToG2: Fp2 element (0,1) maps to a non-trivial G2 point (Prague+) | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L504) | |
| 50 concurrent eth_blockNumber requests all succeed and return consistent values | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L14) | |
| 50 concurrent eth_getBalance requests all return valid results | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L58) | |
| 50 concurrent eth_getLogs requests all return valid arrays | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L103) | |
| 50 concurrent requests across additional RPC methods succeed | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L316) | |
| ADDMOD and MULMOD compute correctly | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L964) | |
| ADDRESS returns the contract's own address | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L300) | |
| BASEFEE opcode matches block baseFeePerGas | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L718) | |
| BLOCKHASH(0) returns zero on Bor (genesis hash not available) | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L18) | |
| BYTE opcode extracts correct byte from word | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L915) | |
| Bor produces blocks on approximately 2-second sprint cadence | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L237) | |
| BorValidatorSet (0x1000) getBorValidators returns non-empty validator list | [Link](./tests/pos/execution-specs/bor-system-contracts-validator-set-and-mrc20.bats#L49) | |
| BorValidatorSet (0x1000) has deployed code and is callable | [Link](./tests/pos/execution-specs/bor-system-contracts-validator-set-and-mrc20.bats#L21) | |
| CALL with value to non-existent account skips G_NEW_ACCOUNT on Bor | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L57) | |
| CALLDATASIZE returns correct input length | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L866) | |
| CHAINID returns the correct chain ID (EIP-1344) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L281) | |
| CODESIZE returns correct runtime size | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L818) | |
| COINBASE opcode returns block miner address | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L546) | |
| CREATE deploys to the address predicted by cast compute-address | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L82) | |
| CREATE with maximum value transfer in constructor | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L520) | |
| CREATE2 address matches keccak256(0xff ++ deployer ++ salt ++ initCodeHash) | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L394) | |
| CREATE2 deploys child to predicted salt-derived address | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L207) | |
| CREATE2 redeploy after SELFDESTRUCT in creation tx succeeds | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L321) | |
| Calldata gas accounting: nonzero bytes cost more than zero bytes | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L629) | |
| Contract creation receipt has contractAddress field | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L1036) | |
| Cross-contract storage isolation: two contracts store different values at slot 0 | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L1022) | |
| DELEGATECALL preserves caller context: msg.sender stored via proxy | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L60) | |
| EIP-1559 sender decrease equals value plus effectiveGasPrice times gasUsed | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L238) | |
| EIP-2930 type-1 access list tx fuzz and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L523) | |
| EXTCODEHASH correctness for EOA, deployed contract, and nonexistent account | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L238) | |
| EXTCODEHASH for empty account returns zero on Bor | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L166) | |
| Empty batch JSON-RPC returns empty array | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L1114) | |
| GASLIMIT opcode matches block gasLimit | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L668) | |
| Gas limit boundary: exact intrinsic gas (21000) succeeds for simple transfer | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L606) | |
| LOG event emission and retrieval via eth_getLogs | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L305) | |
| MCOPY basic non-overlapping copy of 32 bytes | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L149) | |
| MCOPY overlapping backward copy (src > dst) has correct memmove semantics | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L199) | |
| MCOPY overlapping forward copy (src < dst) has correct memmove semantics | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L175) | |
| MCOPY to high offset triggers memory expansion and charges gas | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L245) | |
| MCOPY with zero length is a no-op | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L222) | |
| MRC20 native token wrapper (0x1010) has deployed code and balance function | [Link](./tests/pos/execution-specs/bor-system-contracts-validator-set-and-mrc20.bats#L88) | |
| Multiple storage slots in one transaction | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L1144) | |
| NUMBER opcode returns correct block number | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L620) | |
| Nonce-too-low rejection | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L570) | |
| OOG during code-deposit phase fails the creation | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L352) | |
| ORIGIN returns the transaction sender EOA | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L319) | |
| PIP-11: eth_getBlockByNumber 'finalized' returns a valid block | [Link](./tests/pos/execution-specs/pip11-deterministic-finality-milestones.bats#L17) | |
| PIP-11: finalized block advances as new blocks are produced | [Link](./tests/pos/execution-specs/pip11-deterministic-finality-milestones.bats#L98) | |
| PIP-11: finalized block number is less than or equal to latest block number | [Link](./tests/pos/execution-specs/pip11-deterministic-finality-milestones.bats#L58) | |
| PIP-16: block extraData field is non-empty and present | [Link](./tests/pos/execution-specs/pip16-transaction-dependency-data.bats#L18) | |
| PIP-16: extraData is consistent across multiple recent blocks | [Link](./tests/pos/execution-specs/pip16-transaction-dependency-data.bats#L49) | |
| PIP-20: StateReceiver (0x1001) has StateCommitted event signature | [Link](./tests/pos/execution-specs/bor-system-contracts-validator-set-and-mrc20.bats#L174) | |
| PIP-30 probe: deploy 24577-byte runtime to detect active MAX_CODE_SIZE | [Link](./tests/pos/execution-specs/pip30-increased-max-code-size.bats#L55) | |
| PIP-30: deploy 28000-byte runtime succeeds (between EIP-170 and PIP-30 limits) | [Link](./tests/pos/execution-specs/pip30-increased-max-code-size.bats#L138) | |
| PIP-30: deploy 32769-byte runtime is rejected (exceeds PIP-30 limit) | [Link](./tests/pos/execution-specs/pip30-increased-max-code-size.bats#L120) | |
| PIP-30: deploy exactly 32768-byte runtime succeeds at PIP-30 boundary | [Link](./tests/pos/execution-specs/pip30-increased-max-code-size.bats#L82) | |
| PIP-36: StateReceiver (0x1001) has replayFailedStateSync function | [Link](./tests/pos/execution-specs/bor-system-contracts-validator-set-and-mrc20.bats#L130) | |
| PIP-45: MRC20 system contract decimals() returns 18 | [Link](./tests/pos/execution-specs/pip45-matic-to-pol-token-rename.bats#L87) | |
| PIP-45: MRC20 system contract name() returns valid token name | [Link](./tests/pos/execution-specs/pip45-matic-to-pol-token-rename.bats#L17) | |
| PIP-45: MRC20 system contract symbol() returns valid token symbol | [Link](./tests/pos/execution-specs/pip45-matic-to-pol-token-rename.bats#L53) | |
| PIP-6/58: base fee change rate is tighter than Ethereum default (1/8) | [Link](./tests/pos/execution-specs/pip6-pip58-base-fee-change-denominator.bats#L74) | |
| PIP-6/58: base fee changes by at most 1/64 per block (denominator = 64) | [Link](./tests/pos/execution-specs/pip6-pip58-base-fee-change-denominator.bats#L17) | |
| PIP-6/58: base fee is always positive and non-zero | [Link](./tests/pos/execution-specs/pip6-pip58-base-fee-change-denominator.bats#L136) | |
| PIP-74: StateSyncTx has expected fields (from, to, input) | [Link](./tests/pos/execution-specs/pip74-canonical-state-sync-transactions.bats#L68) | |
| PIP-74: blocks with transactions include StateSyncTx in transactionsRoot | [Link](./tests/pos/execution-specs/pip74-canonical-state-sync-transactions.bats#L126) | |
| PIP-74: scan recent blocks for StateSyncTx (type 0x7F) transactions | [Link](./tests/pos/execution-specs/pip74-canonical-state-sync-transactions.bats#L33) | |
| PUSH0 pushes zero onto the stack (EIP-3855) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L59) | |
| Parent hash chain integrity across 5 blocks | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L903) | |
| RETURNDATACOPY copies callee return data correctly | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L387) | |
| RETURNDATASIZE after CALL reflects callee return data length | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L354) | |
| RETURNDATASIZE before any call returns 0 | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L340) | |
| REVERT returns data and does not consume all gas | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L424) | |
| SAR arithmetic right shift sign-extends negative values (EIP-145) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L112) | |
| SELFBALANCE returns contract's own balance | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L771) | |
| SELFDESTRUCT during construction leaves no code and zero balance | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L315) | |
| SELFDESTRUCT in same tx as creation destroys contract code | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L18) | |
| SELFDESTRUCT inside STATICCALL reverts | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L235) | |
| SELFDESTRUCT on pre-existing contract: code persists post-Cancun | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L61) | |
| SELFDESTRUCT sends balance to beneficiary | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L178) | |
| SELFDESTRUCT to self: balance preserved post-Cancun | [Link](./tests/pos/execution-specs/eip6780-selfdestruct-cancun-restrictions.bats#L126) | |
| SHL left shift: 1 << 4 = 16 (EIP-145) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L78) | |
| SHR right shift: 0xFF >> 4 = 0x0F (EIP-145) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L95) | |
| SIGNEXTEND correctly sign-extends byte 0 of 0x80 | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L130) | |
| SSTORE + SLOAD roundtrip: stored value is retrievable and unwritten slots are zero | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L18) | |
| SSTORE gas refund: clearing a storage slot uses less gas than setting it | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L409) | |
| SSTORE overwrite: new value replaces old | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L1083) | |
| STATICCALL cannot modify state: SSTORE attempt reverts | [Link](./tests/pos/execution-specs/evm-opcode-storage-and-call-correctness.bats#L149) | |
| StateReceiver system contract (0x0000000000000000000000000000000000001001) is callable | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L211) | |
| Sum of receipt gasUsed matches block gasUsed | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L935) | |
| TLOAD returns zero for unset transient slot | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L73) | |
| TSTORE + TLOAD roundtrip returns stored value | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L18) | |
| TSTORE gas cost is less than SSTORE for zero-to-nonzero write | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L393) | |
| TSTORE in DELEGATECALL shares caller transient storage context | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L444) | |
| TSTORE reverted by sub-call REVERT is undone | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L284) | |
| add new validator | [Link](./tests/pos/validator.bats#L20) | |
| all-opcode liveness smoke: deploy contracts exercising major opcode groups | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L896) | |
| base fee adjusts between blocks following EIP-1559 dynamics | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L272) | |
| batch JSON-RPC returns array of matching results | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L678) | |
| batch JSON-RPC under concurrent load: 50 concurrent batch requests | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L483) | |
| block coinbase (miner field) is zero address on Bor | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L103) | |
| block timestamp monotonicity across 10 consecutive blocks | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L848) | |
| block-filling stress: rapid-fire large calldata txs | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L851) | |
| bor_getAuthor returns a valid address for latest block | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L486) | |
| bor_getCurrentValidators returns a non-empty validator list | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L509) | |
| bor_getSnapshot returns snapshot with validator data | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L463) | |
| bridge MATIC/POL from L1 to L2 and confirm L2 MATIC/POL balance increased | [Link](./tests/pos/bridge.bats#L51) | |
| bridge MATIC/POL, ERC20, and ERC721 from L1 to L2 and confirm L2 balances increased | [Link](./tests/pos/bridge.bats#L188) | |
| bridge an ERC721 token from L1 to L2 and confirm L2 ERC721 balance increased | [Link](./tests/pos/bridge.bats#L139) | |
| bridge some ERC20 tokens from L1 to L2 and confirm L2 ERC20 balance increased | [Link](./tests/pos/bridge.bats#L95) | |
| coinbase balance increases by at least the priority fee portion of gas cost | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L318) | |
| concurrent write/read race: tx submissions and state reads do not interfere | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L248) | |
| contract-to-contract call fuzz: CALL/STATICCALL/DELEGATECALL | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L792) | |
| delegate MATIC/POL to a validator | [Link](./tests/pos/validator.bats#L181) | |
| deploy contract that returns 24577 runtime bytes is rejected by EIP-170 | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L124) | |
| deploy contract that returns exactly 24576 runtime bytes succeeds (EIP-170 boundary) | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L150) | |
| deploy contract that reverts in constructor leaves no code at deployed address | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L48) | |
| deploy contract with 0xEF leading runtime byte is rejected by EIP-3541 | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L181) | |
| deploy initcode exactly at EIP-3860 limit (49152 bytes) succeeds | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L79) | |
| deploy initcode one byte over EIP-3860 limit (49153 bytes) is rejected | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L99) | |
| deploy single STOP opcode contract succeeds and code at address is empty | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L20) | |
| enforce deterministic fallback behavior | [Link](./tests/pos/veblop/invariants.bats#L156) | |
| enforce equal block distribution between block producers at the execution layer | [Link](./tests/pos/veblop/invariants.bats#L116) | |
| enforce equal slot distribution between block producers at the consensus layer | [Link](./tests/pos/veblop/invariants.bats#L68) | |
| enforce minimum one and maximum three selected producers per span | [Link](./tests/pos/veblop/invariants.bats#L34) | |
| eth_call does not consume gas or advance nonce | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L118) | |
| eth_call to plain EOA returns 0x | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L60) | |
| eth_chainId returns a value matching cast chain-id | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L14) | |
| eth_estimateGas for EOA transfer returns 21000 | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L51) | |
| eth_estimateGas for failing call returns error | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L758) | |
| eth_feeHistory returns baseFeePerGas array and oldestBlock | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L315) | |
| eth_gasPrice returns a valid non-zero hex value | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L96) | |
| eth_getBalance at historical block returns correct value | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L1072) | |
| eth_getBalance returns non-zero for funded account and zero for unused address | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L161) | |
| eth_getBlockByHash result matches eth_getBlockByNumber for latest block | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L27) | |
| eth_getBlockByNumber 'earliest' returns genesis block | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L536) | |
| eth_getBlockByNumber 'pending' returns valid response | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L561) | |
| eth_getBlockByNumber with fullTransactions=true returns full tx objects | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L353) | |
| eth_getBlockTransactionCountByNumber and ByHash agree on tx count | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L251) | |
| eth_getCode returns 0x for an EOA | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L114) | |
| eth_getCode returns non-empty bytecode for L2 StateReceiver contract | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L123) | |
| eth_getLogs for block 0 to 0 returns a valid array | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L86) | |
| eth_getLogs returns empty array for future block range | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L69) | |
| eth_getLogs with reversed block range returns error or empty array | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L135) | |
| eth_getProof returns valid Merkle proof structure | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L802) | |
| eth_getStorageAt returns zero for EOA and valid 32-byte word for contracts | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L280) | |
| eth_getTransactionByHash and ByBlockNumberAndIndex return consistent tx data | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L191) | |
| eth_getTransactionCount returns hex nonce matching cast nonce | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L231) | |
| eth_getTransactionReceipt has all required EIP fields | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L721) | |
| eth_getTransactionReceipt returns null for unknown transaction hash | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L42) | |
| eth_getUncleCountByBlockNumber returns 0 (PoS has no uncles) | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L1020) | |
| eth_maxPriorityFeePerGas returns a valid hex value | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L304) | |
| eth_sendRawTransaction rejects invalid signature | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L611) | |
| eth_sendRawTransaction rejects wrong chainId | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L637) | |
| eth_syncing returns false on synced node | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L590) | |
| fuzz contract creations and assert individual tx outcomes | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L256) | |
| fuzz node with EIP-1559 type-2 transactions and verify processing | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L403) | |
| fuzz node with edge-case contract creation bytecodes and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L42) | |
| fuzz node with edge-case gas limits and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L154) | |
| fuzz node with mixed zero/non-zero calldata and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L341) | |
| fuzz node with non-zero calldata transactions and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L206) | |
| fuzz node with variable-size calldata transactions and verify liveness | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L103) | |
| fuzz scan: no unknown precompiles in 0x0001..PRECOMPILE_FUZZ_MAX | [Link](./tests/pos/execution-specs/precompile-correctness-and-discovery.bats#L58) | |
| gasUsed <= gasLimit for latest block | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L883) | |
| higher concurrency watermark: 100 and 500 concurrent eth_blockNumber requests | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L204) | |
| insufficient balance rejection: tx with value+gas > balance is rejected | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L501) | |
| isolate the current block producer mid-span to trigger a producer rotation | [Link](./tests/pos/veblop/faults.bats#L89) | |
| large return data in constructor near EIP-170 limit (24000 bytes) succeeds | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L576) | |
| latest block contains required post-London fields and valid shapes | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L415) | |
| logsBloom is zero for genesis block (no log-emitting txs) | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L994) | |
| mixed concurrent RPC methods succeed without interfering with each other | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L143) | |
| multi-sender concurrent fuzz: 10 wallets fire txs simultaneously | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L661) | |
| multi-sender concurrent tx submissions: 10 wallets x 5 txs each | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L415) | |
| multiple CREATEs in single transaction: factory creates 5 children | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L460) | |
| nested contract creation: constructor deploys child via CREATE | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L270) | |
| net_version returns a non-empty numeric string | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L389) | |
| nonce increments by exactly 1 after each successful transaction | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L140) | |
| nonce replacement stress: higher gas replaces pending tx | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L718) | |
| nonce-gap stress: out-of-order submission resolves correctly | [Link](./tests/pos/execution-specs/evm-transaction-fuzzing-and-liveness.bats#L600) | |
| out-of-gas transaction still increments sender nonce | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L160) | |
| prune TxIndexer | [Link](./tests/pos/heimdall-v2.bats#L86) | |
| recipient balance increases by exactly the value sent | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L53) | |
| remove validator | [Link](./tests/pos/validator.bats#L363) | |
| replay protection: same signed tx submitted twice does not double-spend | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L445) | |
| sender balance decreases by exactly gas cost plus value transferred | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L18) | |
| sha3Uncles field is empty-list RLP hash (PoS has no uncles) | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L976) | |
| spam messages at the consensus layer and ensure the protocol handles them gracefully | [Link](./tests/pos/veblop/faults.bats#L149) | |
| stack depth limit: 1024 nested calls revert | [Link](./tests/pos/execution-specs/contract-creation-and-deployment-limits.bats#L381) | |
| sustained RPC load over 30 seconds with monotonic block advancement | [Link](./tests/pos/execution-specs/rpc-concurrent-load-and-stress.bats#L533) | |
| total value is conserved: sender decrease equals recipient increase plus gas cost | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L188) | |
| transaction at node-reported gas price succeeds | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L144) | |
| transaction with trivially low gas price (1 wei) is rejected | [Link](./tests/pos/execution-specs/bor-chain-specific-evm-behavior.bats#L117) | |
| transient storage clears between transactions | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L117) | |
| transient storage is isolated per contract address | [Link](./tests/pos/execution-specs/eip1153-tstore-tload-transient-storage.bats#L204) | |
| type 0 (legacy) receipt has correct type and gasPrice field | [Link](./tests/pos/execution-specs/transaction-types-and-gas-pricing.bats#L18) | |
| type 1 (EIP-2930) access list reduces gas for warm storage access | [Link](./tests/pos/execution-specs/transaction-types-and-gas-pricing.bats#L53) | |
| type 1 access list with multiple storage keys is accepted | [Link](./tests/pos/execution-specs/transaction-types-and-gas-pricing.bats#L207) | |
| type 2 (EIP-1559) effectiveGasPrice = baseFee + min(priorityFee, maxFee - baseFee) | [Link](./tests/pos/execution-specs/transaction-types-and-gas-pricing.bats#L130) | |
| type 2 maxFeePerGas below baseFee is rejected | [Link](./tests/pos/execution-specs/transaction-types-and-gas-pricing.bats#L175) | |
| undelegate MATIC/POL from a validator | [Link](./tests/pos/validator.bats#L275) | |
| update signer | [Link](./tests/pos/validator.bats#L147) | |
| update validator stake | [Link](./tests/pos/validator.bats#L60) | |
| update validator top-up fee | [Link](./tests/pos/validator.bats#L97) | |
| warm COINBASE access costs less than cold access to arbitrary address (EIP-3651) | [Link](./tests/pos/execution-specs/evm-opcodes-cancun-shanghai-eips.bats#L456) | |
| web3_clientVersion returns a non-empty version string | [Link](./tests/pos/execution-specs/rpc-method-conformance-and-validation.bats#L400) | |
| zero-value self-transfer: only gas consumed, nonce increments | [Link](./tests/pos/execution-specs/transaction-balance-nonce-and-replay-invariants.bats#L530) | |

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
| Modexp calls not valid for fusaka | [Link](./tests/fusaka/eip7823.bats#L62) | |
| Modexp gas costs | [Link](./tests/fusaka/eip7883.bats#L45) | |
| Modexp regular calls | [Link](./tests/fusaka/eip7823.bats#L42) | |
| Native token transfer L1 -> L2 | [Link](./tests/aggkit/bridge-e2e.bats#L243) | |
| RLP Execution block size limit 10M  | [Link](./tests/fusaka/eip7934.bats#L36) | |
| Remove single validator from committee | [Link](./tests/aggkit/aggsender-committee-updates.bats#L147) | |
| Test Aggoracle committee | [Link](./tests/aggkit/bridge-e2e-aggoracle-committee.bats#L10) | |
| Test L2 to L2 bridge | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L15) | |
| Test Sovereign Chain Bridge Events | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L48) | |
| Test block gas limit increase to 60M | [Link](./tests/fusaka/eip7935.bats#L19) | |
| Test execute multiple claimMessages via testClaim with internal reentrancy and bridgeAsset call | [Link](./tests/aggkit/claim-reetrancy.bats#L472) | |
| Test inject invalid GER on L2 (bridges are valid) | [Link](./tests/aggkit/bridge-sovereign-chain-e2e.bats#L212) | |
| Test invalid GER injection case A (FEP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L825) | |
| Test invalid GER injection case A (PP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L716) | |
| Test invalid GER injection case B2 (FEP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L396) | |
| Test invalid GER injection case B2 (PP mode) | [Link](./tests/aggkit/latest-n-injected-ger.bats#L38) | |
| Test new RPC endpoint eth_config | [Link](./tests/fusaka/eip7910.bats#L19) | |
| Test reentrancy protection for bridge claims - should prevent double claiming | [Link](./tests/aggkit/claim-reetrancy.bats#L67) | |
| Test triple claim internal calls -> 1 fail (same global index), 1 success (same global index) and 1 fail (different global index) | [Link](./tests/aggkit/internal-claims.bats#L1344) | |
| Test triple claim internal calls -> 1 fail, 1 success and 1 fail | [Link](./tests/aggkit/internal-claims.bats#L946) | |
| Test triple claim internal calls -> 1 success, 1 fail and 1 success | [Link](./tests/aggkit/internal-claims.bats#L509) | |
| Test triple claim internal calls -> 3 success | [Link](./tests/aggkit/internal-claims.bats#L57) | |
| Test zkCounters | [Link](./tests/zkevm/zk-counters-tests.bats#L10) | |
| Transaction using new CLZ instruction | [Link](./tests/fusaka/eip7939.bats#L19) | |
| Transaction with more than 2^24 gas | [Link](./tests/fusaka/eip7825.bats#L19) | |
| Transfer message L2 to L2 | [Link](./tests/aggkit/bridge-e2e-2-chains.bats#L68) | |
| Transfer message | [Link](./tests/aggkit/bridge-e2e.bats#L11) | |
| Verify batches | [Link](./tests/zkevm/batch-verification.bats#L10) | |
| Verify certificate settlement | [Link](./tests/aggkit/e2e-pp.bats#L10) | |
| bridge transaction is indexed and autoclaimed on L2 | [Link](./tests/bridge-hub-api.bats#L14) | |
| bridge transaction is indexed on L1 | [Link](./tests/bridge-hub-api.bats#L95) | |
| foo | [Link](./tests/foo.bats#L10) | |
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
