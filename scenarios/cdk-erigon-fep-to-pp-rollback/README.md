# cdk-erigon FEP to PP migration with sequenced-but-unverified batches

Devnet rehearsal of the way out for a cdk-erigon (fork 12) chain whose legacy cdk-node
aggregator can no longer settle proofs because the agglayer it talks to has moved to 0.6.0,
where `interop_sendTx` is permanently disabled (JSON-RPC error `-10009`).

This is the situation Silicon (mainnet rollup ID 10, chain 2355) is in as of 2026-09-17: batches
keep being sequenced, none are verified, and the migration to Pessimistic Proofs that the
[cdk-erigon FEP to PP runbook](https://github.com/agglayer/runbooks/blob/main/upgrades/cdk-erigon_fep-to-pp.md)
describes cannot start because `AgglayerManager.initMigration` reverts with
`AllSequencedMustBeVerified()` while `lastBatchSequenced != lastVerifiedBatch`.

The scenario reproduces the failure and validates the recovery: the chain operator rolls the
unverified batches back on L1 with `rollbackBatches`, which leaves the L2 chain untouched, and the
standard runbook is then applied. See [RUNBOOK.md](./RUNBOOK.md) for the operator-facing procedure
with the outputs captured from a validated run.

## What the scenario does

| Step | Actor | Action | Assertion |
|-----:|-------|--------|-----------|
| 1 | devnet | Deploy a Silicon-like validium with kurtosis-cdk (versions in `assets/kurtosis-params.yml`) | deployment succeeds |
| 2 | devnet | Discover endpoints, contracts and keys from the enclave | all expected services present, admin holds the rollup admin and `UPDATE_ROLLUP_ROLE` |
| 3 | user | Deposit 1 ETH L1 to L2 and claim it on L2 (funds the L1 bridge escrow, as real users do); withdraw L2 to L1; legacy aggregator verifies it through agglayer 0.6.0-rc.5 | `lastVerifiedBatch` advances, claim on L1 succeeds |
| 4 | Polygon | `kurtosis service update` agglayer + agglayer-prover to 0.6.0 | cdk-node logs `-10009`; `lastBatchSequenced` runs ahead |
| 4 | user | Withdraw L2 to L1 inside the unverified window | deposit is in a sequenced, never verified batch |
| 5 | Polygon | Add the `AggchainECDSAMultisig` rollup type (mainnet already has it as type 14); check the gateway PP route | type is `ALGateway`, route matches the running agglayer vkey |
| 6 | Polygon | `initMigration` | reverts with `AllSequencedMustBeVerified()` |
| 7 | operator | Stop sequencing (`cdk-node-001`) | `lastBatchSequenced` stable and finalized |
| 8 | operator | `rollbackBatches(rollup, lastVerifiedBatch)` | counters equal; `RollbackBatches` event; L2 block hashes unchanged; L2 keeps producing blocks; erigon `zkevm_virtualBatchNumber` follows |
| 9 | operator | cdk-erigon image to v2.61.24, PP config (`mock-witness-generation`, no executors, no pool manager), stop DAC/executor/prover/pool-manager | sequencer produces blocks without executors, history intact |
| 10 | operator | aggkit 0.8.1 aggsender in `DryRun` | service up |
| 11 | Polygon | `initMigration(1, ECDSA type, migrateFromLegacyConsensus())` | `isRollupMigrating`, threshold 1, sequencer is sole signer; erigon logs one `UpdateRollupTopic` line (unknown-type error, not repeating, clean sync passes continue), fork stays 12, blocks continue |
| 12 | operator | `MaxL2BlockNumber` = last block of last verified batch, `DryRun=false` | bootstrap certificate settles, `isRollupMigrating` false |
| 13 | operator | `MaxL2BlockNumber = 0` | settled LER on L1 equals L2 bridge root |
| 14 | user | Claim the in-window withdrawal on L1 | `isClaimed` true |

Every command and its output is written under `evidence/run-<timestamp>/`, together with state
snapshots (`state-*.json`) and trimmed service logs.

## Requirements

- kurtosis CLI **1.19.0 or newer** (the pinned kurtosis-cdk uses Starlark types that older engines
  lack; the fury apt repository lags behind, install the release `.deb`/binary), docker, foundry
  (`cast`), `jq`, `curl`, `polycli`, GNU `timeout` (macOS: `brew install coreutils`), bash >= 4
- about 12 GB of memory available to Docker
- an **amd64 host**. The fork 12 `zkevm-prover` image is `linux/amd64` only and compiled for AVX2.
  On Apple Silicon it does not run under Rosetta (exit 132, illegal instruction), and with OrbStack
  switched to QEMU (`orb config set rosetta false`) the x86 agglayer binary becomes too slow for
  kurtosis-cdk's fixed 180 s `agglayer vkey` task. The scenario was validated on `ubuntu-latest`
  GitHub runners through `.github/workflows/scenario-cdk-erigon-fep-to-pp-rollback.yml`.
- optional, for screenshots: Node.js 20+ (`cd scripts && npm install && npx playwright install chromium`)

## Running

```bash
cp env.example .env   # optional overrides
./run.sh              # about 25 minutes on a 4 vCPU amd64 GitHub runner (8 of them for the deployment)
```

The enclave is removed at the end (also on failure). `KEEP_ENCLAVE=true` keeps it for inspection.
`REUSE_ENCLAVE=true START_STEP=<n>` resumes an interrupted run against an existing enclave; do not
edit `run.sh` while a run is in progress (bash reads the script incrementally).

Screenshots of the Kurtosis Enclave Manager for a kept enclave (the SPA renders blank on headless
deep links, so the script clicks through the UI like a user):

```bash
cd scripts && npm install && npx playwright install chromium
node screenshots.mjs fep-to-pp-rollback ../evidence/<run>/screenshots aggkit-001 cdk-erigon-sequencer-001 agglayer cdk-node-001
```

In CI: open a pull request touching this folder, or dispatch the workflow manually; evidence is
uploaded as the `fep-to-pp-rollback-evidence` artifact.

## What is deliberately different from Silicon mainnet

- **agglayer before the break** is `0.6.0-rc.5`, the last build that still accepts
  `interop_sendTx`. Silicon's L1 was on the 0.5.x line; kurtosis-cdk main only renders a
  0.6-line agglayer config, and the mechanics (`interop_sendTx` accepted, then refused with
  `-10009`) are identical.
- **agglayer-prover** runs the mock prover and the contracts use the mock SP1 verifier
  (`zkevm_use_real_verifier: false`). Certificate settlement mechanics are unchanged; proofs are not real.
- **sequence-sender and aggregator** run in one `cdk-node` container in kurtosis-cdk, so they stop
  together. On Silicon only the sequence-sender needs to stop first; the aggregator cannot settle anyway.
- **Polygon-side actions** (`initMigration`, adding the rollup type, gateway route) are executed with
  the devnet admin key, which holds the same roles Polygon's admin holds on mainnet.
- **Rollup type** for `AggchainECDSAMultisig` is created by the scenario; mainnet already has it (type 14).
- **Gap size**: the scenario waits for a handful of unverified batches; Silicon had 118.
- **Sequencer upgrade mechanics**: `kurtosis service update` recreates a container without its
  persistent directories (observed: erigon reopened an empty datadir). The sequencer is therefore
  re-added with a generated Starlark script (`scripts/readd-service.jq`) that declares the same
  `persistent_key` kurtosis-cdk uses, which keeps the chain data. The RPC node, which has no persistent
  datadir, is updated with `kurtosis service update` and re-syncs from the sequencer's datastream.
- **aggkit** is added and reconfigured with a small Starlark script (`assets/aggkit.star`) so that
  `/data` is a persistent directory across config changes, like the runbook's persisted data
  directory. `kurtosis service update` was observed to drop the mount.

## Layout

```
run.sh                              orchestrator (kurtosis CLI incl. `kurtosis service exec`, Starlark, cast, polycli)
env.example                         overridable settings
assets/kurtosis-params.yml          Silicon-like validium definition
assets/kurtosis-cdk.ref             pinned kurtosis-cdk commit
assets/aggkit-config.toml.template  runbook aggkit template with placeholders
assets/add_rollup_type.json.template
assets/aggkit.star                  adds/replaces the aggkit service with a persistent /data
scripts/readd-service.jq            generates the Starlark that re-adds the sequencer with its persistent datadir
scripts/screenshots.mjs             Playwright screenshots of the Kurtosis Enclave Manager
RUNBOOK.md                          operator runbook for Silicon, with validated outputs
evidence/                           outputs, logs, state snapshots and screenshots of the validated run
```
