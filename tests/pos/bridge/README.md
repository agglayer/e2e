# Polygon PoS bridge e2e

End-to-end tests for the two Polygon PoS <-> Ethereum bridges. These suites run against a `kurtosis-pos` devnet and exercise real bridge + withdraw round-trips on the deployed contracts.

## The two bridges

Polygon PoS has always had two bridges in production, targeting different token classes:

| Bridge | Governing contract on L1 | Token classes it carries | On-chain L2 representation |
|---|---|---|---|
| **Plasma** | `DepositManagerProxy` / `WithdrawManagerProxy` | POL, MATIC, ETH, ERC20, ERC721 | Native gas token at `0x…1010` and child copies |
| **PoS (pos bridge)** | `RootChainManagerProxy` / `ChildChainManagerProxy` | ERC20, ERC721, ERC1155, ETH | Per-type child token contracts (`ChildERC20`, `ChildERC721`, `ChildERC1155`, `MaticWETH`) |

The two bridges aren't interchangeable. A given token maps to exactly one.

### Why both?

Plasma is the older design. It was the original PoS bridge — low-throughput, single native-gas-token pathway, deposits via `DepositManager.depositERC20(...)` and withdrawals via Plasma exits with an exit period. It's the only path for **POL, MATIC, and the L2 native gas token** because the L2 side is a precompile at `0x…1010`, not a contract the PoS bridge can mint into.

PoS (pos-portal, at `maticnetwork/pos-portal`) came later for everything else. It's a generic ERC-standard bridge: a single `RootChainManager` fronts a pluggable set of token **predicates** (`ERC20Predicate`, `ERC721Predicate`, `ERC1155Predicate`, `EtherPredicate`, plus `Mintable*` variants), each responsible for locking the L1 side and validating the exit proof. The L2 side is a real contract (`ChildERC20`, etc.) that mints on deposit state-sync and burns on withdrawal.

### Confirmation that POL / MATIC are plasma-only

Verified against Ethereum mainnet on `RootChainManagerProxy` (`0xA0c68C638235ee32657e8f720a23ceC1bFc77C77`):

```
rootToChildToken(0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6) = 0x0   # POL
rootToChildToken(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0) = 0x0   # MATIC
```

No child mapping → pos-portal does not bridge either token. Those flows only exist under Plasma.

## Bridge-vs-withdraw flow shape

Both suites follow the same skeleton; the entry points and the withdraw path differ.

| Stage | Plasma | PoS |
|---|---|---|
| Bridge (L1 → L2) | approve `DepositManagerProxy`, then `depositERC20(token, amount)` | approve the specific predicate, then `RootChainManager.depositFor(user, rootToken, abi.encode(args))` |
| Bridge ETH | wraps into `MaticWeth` on L2 via `DepositManager` path | `RootChainManager.depositEtherFor(user)` with `msg.value`; shows up as `MaticWETH` on L2 |
| Withdraw phase 1 | `L1_ERC20_PREDICATE_ADDRESS.startExitWithBurntTokens(payload)` | `RootChainManagerProxy.exit(payload)` (one-shot) |
| Withdraw phase 2 | `WithdrawManagerProxy.processExits(token)` after `HALF_EXIT_PERIOD` | — (`exit` releases funds directly) |
| Checkpoint wait | Yes | Yes |
| Exit payload format | `polycli pos exit-proof` | Same `polycli pos exit-proof` — both bridges consume the same `ExitPayloadReader` layout |
| L2 burn (native) | `0x…1010.withdraw(amount)` (log-index **1** — `Withdraw` event) | n/a (no native path in PoS) |
| L2 burn (ERC20) | child token `withdraw` | child token `withdraw` (log-index **0** — `Transfer` to `0x0`) |
| L2 burn (ERC721) | child token `withdraw` | `ChildERC721.withdraw(tokenId)` |
| L2 burn (ERC1155) | n/a | `ChildERC1155.withdrawSingle(id, amount)` / `withdrawBatch(ids, amounts)` |

## Files

- [`plasma.bats`](./plasma.bats) — Plasma bridge suite. Covers POL, MATIC, ETH, ERC20, ERC721.
- [`pos.bats`](./pos.bats) — pos bridge suite. Covers ETH, ERC20, ERC721, ERC1155.

Shared helpers (state-sync waiters, exit-payload generation, address resolution) live in `../../core/helpers/pos-setup.bash` and `../../core/helpers/scripts/eventually.bash`.

## Test scoreboard

| # | Token & direction | Plasma | PoS | Notes |
|---|---|---|---|---|
| 1 | bridge POL (L1 → L2) | ✅ | n/a | plasma-only |
| 2 | bridge MATIC (L1 → L2) | ✅ | n/a | plasma-only |
| 3 | bridge ETH (L1 → L2) | ✅ | ✅ | different entry point |
| 4 | bridge ERC20 (L1 → L2) | ✅ | ✅ | |
| 5 | bridge ERC721 (L1 → L2) | ✅ | ✅ | |
| 6 | bridge ERC1155 (L1 → L2) | n/a | ✅ | PoS-only |
| 7 | withdraw native → POL (L2 → L1) | ✅ | n/a | plasma-only (native burn) |
| 8 | withdraw ETH via MaticWETH (L2 → L1) | ✅ | ✅ | |
| 9 | withdraw ERC20 (L2 → L1) | ✅ | ✅ | |
| 10 | withdraw ERC721 (L2 → L1) | ✅ | ✅ | |
| 11 | withdraw ERC1155 (L2 → L1) | n/a | ✅ | PoS-only |

Coverage is complete for each bridge's actual on-chain responsibilities — the asymmetries (`n/a` cells) reflect what the bridge does on mainnet, not missing test cases. Mintable predicate variants (`MintableERC20`/`721`/`1155`) are deployed but not yet tested in either suite.

## Running

Both suites assume a live `kurtosis-pos` devnet named `pos-2` (override with `ENCLAVE_NAME`):

```bash
# from internal/e2e
export BATS_LIB_PATH="$PWD/core/helpers/lib"
ENCLAVE_NAME=pos-2 bats tests/pos/bridge/plasma.bats
ENCLAVE_NAME=pos-2 bats tests/pos/bridge/pos.bats
```

Run a subset by tag:

```bash
ENCLAVE_NAME=pos-2 bats tests/pos/bridge/pos.bats --filter-tags pos-bridge
ENCLAVE_NAME=pos-2 bats tests/pos/bridge/plasma.bats --filter-tags withdraw
```

Withdraws take several minutes per test — each needs a fresh L1 checkpoint to cover the burn block before the exit proof can be built. Plasma withdraws wait an additional `HALF_EXIT_PERIOD` seconds after queuing.

## History

- **2017-2020** — Plasma bridge deployed as the only PoS L1↔L2 pathway.
- **2020-2021** — `pos-portal` built to generalise the bridge for ERC20/721/1155/Ether. Two bridges co-exist ever since; each token class is assigned to one.
- **July 2021** — typed-tx (EIP-1559) support added to `ERC20PredicateBurnOnly` / `ERC721PredicateBurnOnly` (commit `2e3d42c8`). The non-burn-only variants (`ERC20Predicate`, `ERC721Predicate`) never got the fix — they still call `toList()` on the raw typed receipt and silently revert for typed burns.
- **September 2024** — MATIC → POL migration. POL and MATIC remain plasma-bridged; pos-portal mappings for both are zero on mainnet today. `DepositManager` was upgraded to auto-convert deposited MATIC to POL and to pay out POL on native withdraws.
- **May 2025** — pos-portal migrated its test infra from Truffle to Hardhat. The deploy migration scripts (`scripts/1_initial_migration.js` through `5_initialize_child_chain_contracts.js`) were left in place but are no longer wired to a runner — pos-portal has no maintained end-to-end deploy path at HEAD. `kurtosis-pos` deploys it through its own Foundry-based orchestration (`pos-contract-deployer` image).
