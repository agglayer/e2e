contract-creation-edge-cases.bats
Only tests EOA CREATE, never CREATE2 (no salt-based address prediction test)
No nested creation (contract deploying a contract)
No SELFDESTRUCT during construction, no re-deploy to the same address
No OOG specifically during the code-deposit phase (after runtime returned, before storage commit)

evm-fuzz.bats
Purely a liveness check — it doesn't assert anything about individual tx outcomes (status, gas used, state changes). A node could process all txs incorrectly and still pass.
All calldata fuzz uses all-zero bytes. Non-zero bytes (EIP-2028 cost: 16 vs 4 gas) are tested separately but not mixed.
No EIP-1559 (type-2) or access list (type-1, EIP-2930) transactions anywhere — everything is --legacy.
No nonce-gap stress (tx with nonce N+2 submitted before N+1 — tests mempool ordering/eviction).

evm-state-invariants.bats
No EIP-1559 base-fee burning invariant (sender_decrease = value + priority_feegas + base_feegas, where base_fee is burned, not sent to coinbase).
No coinbase/fee-recipient balance increase check.
No CREATE2 address prediction test (only RLP-based CREATE).
No replay protection check (same raw tx submitted twice shouldn't succeed the second time).
No storage invariant (SSTORE + SLOAD roundtrip consistency).

rpc-concurrent-load.bats
Concurrency level is fixed at 50 — no higher watermark test (100, 500).
No concurrent write/read race: submitting txs and reading state simultaneously.
Only 3 RPC methods tested under load (eth_blockNumber, eth_getBalance, eth_getLogs).

rpc-conformance.bats
eth_getBalance (no conformance test, only concurrent load)
eth_getTransactionByHash, eth_getTransactionByBlockNumberAndIndex
eth_getTransactionCount
eth_getBlockTransactionCountByNumber / ByHash
eth_getStorageAt
eth_maxPriorityFeePerGas, eth_feeHistory (EIP-1559)
eth_getBlockByNumber with fullTransactions=true (only false tested)
net_version, web3_clientVersion
Block field validation (e.g., baseFeePerGas present and non-zero post-London, prevRandao shape)
Bor-specific methods: bor_getSnapshot, bor_getAuthor, bor_getCurrentValidators