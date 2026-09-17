# Runbook: cdk-erigon FEP to PP when batches are sequenced but no longer verified

**Applies to:** cdk-erigon chains on fork 12 or 13 whose cdk-node aggregator settles through the
Agglayer and that now see `-10009 The interop_sendTx method is disabled`. Written for Silicon
(mainnet rollup ID 10, chain 2355) and validated end to end on a kurtosis-cdk devnet that mirrors
its versions. Every command below was run there; outputs are quoted from `evidence/` in this folder.

This runbook is the companion of
[upgrades/cdk-erigon_fep-to-pp.md](https://github.com/agglayer/runbooks/blob/main/upgrades/cdk-erigon_fep-to-pp.md).
It adds the part that runbook assumes away: step 2 there ("wait until the aggregator verifies all
sequenced batches") is impossible once the agglayer is on 0.6.0, and `initMigration` refuses to run
while any sequenced batch is unverified.

**Contents**

0. [Why the standard runbook cannot start](#0-why-the-standard-runbook-cannot-start)
1. [Read the chain's state](#1-read-the-chains-state-anyone-read-only)
2. [Stop sequencing now](#2-stop-sequencing-now-chain-operator)
3. [Roll the unverified batches back on L1](#3-roll-the-unverified-batches-back-on-l1-chain-operator)
   - [3b. What the rollback does to cdk-erigon](#3b-what-the-rollback-does-to-cdk-erigon-observed)
4. [Upgrade cdk-erigon and switch it to PP mode](#4-upgrade-cdk-erigon-and-switch-it-to-pp-mode-chain-operator)
5. [Start aggkit in sync-only mode](#5-start-aggkit-in-sync-only-mode-chain-operator)
6. [Migrate the rollup to AggchainECDSAMultisig](#6-migrate-the-rollup-to-aggchainecdsamultisig-polygon)
7. [Bootstrap certificate, then normal certificates](#7-bootstrap-certificate-then-normal-certificates-chain-operator)
8. [Withdrawals made during the outage](#8-withdrawals-made-during-the-outage)
9. [Risks and what the rollback does not touch](#9-risks-and-what-the-rollback-does-not-touch)
- [Appendix A. Devnet used for validation](#appendix-a-devnet-used-for-validation)
- [Appendix B. Evidence index](#appendix-b-evidence-index)

Actors: **chain operator** (Silicon) holds the rollup admin and trusted sequencer keys and runs
cdk-erigon, cdk-node, DAC, prover and aggkit. **Polygon** holds `UPDATE_ROLLUP_ROLE` on the rollup
manager and runs the Agglayer. Steps say who acts.


## 0. Why the standard runbook cannot start

`AgglayerManager.initMigration` (agglayer-contracts v12.2.3, the version deployed on mainnet as
`ROLLUP_MANAGER_VERSION = "v1.0.0"`) has three preconditions:

```solidity
// contracts/AgglayerManager.sol
require(rollup.rollupVerifierType == VerifierType.StateTransition, OnlyStateTransitionChains());
if (rollup.lastBatchSequenced != rollup.lastVerifiedBatch) {
    revert AllSequencedMustBeVerified();
}
require(rollupTypeMap[newRollupTypeID].rollupVerifierType != VerifierType.StateTransition,
        NewRollupTypeMustBePessimisticOrALGateway());
```

Since agglayer 0.6.0 (`interop_sendTx` disabled since 0.6.0-rc.6 on 2026-07-08, GA on 2026-09-15)
the cdk-node aggregator cannot settle anything: its only Agglayer settlement path is that method,
and its other backend (`SettlementBackend = "l1"`) needs the trusted-aggregator role that only the
Agglayer's key holds. Any chain that kept sequencing therefore has `lastBatchSequenced >
lastVerifiedBatch` and `initMigration` reverts. Agglayer 0.5.x is sunset, so the gap cannot be closed
by verifying.

The rollup manager offers a second way to make the counters equal:

```solidity
function rollbackBatches(IPolygonRollupBase rollupContract, uint64 targetBatch) external nonReentrant {
    // callable by the rollup admin or by UPDATE_ROLLUP_ROLE
    ...
    if (targetBatch >= lastBatchSequenced || targetBatch < rollup.lastVerifiedBatch) revert RollbackBatchIsNotValid();
    // deletes sequencedBatches[] above targetBatch, sets lastBatchSequenced = targetBatch,
    // then rollupContract.rollbackBatches(targetBatch, accInputHash) which only resets lastAccInputHash
```

It touches sequencing bookkeeping only. `lastLocalExitRoot`, the global exit root, the bridge and
every balance are untouched. cdk-erigon reacts to the `RollbackBatches` L1 event by deleting its
local copies of the L1 sequence records (`hermezDb.RollbackSequences` in
`zk/stages/stage_l1_syncer.go`) and does **not** unwind any L2 block. After the rollback the chain
migrates to Pessimistic Proofs exactly as the standard runbook describes, and the blocks that were in
the rolled-back batches are covered by the first normal PP certificates.

The rest of this document is that procedure, in order, with the outputs observed on the devnet.


## 1. Read the chain's state (anyone, read-only)

Read the counters on the rollup manager. The numbers below are Silicon on 2026-09-17 around 03:40 UTC
(mainnet, rollup ID 10); they move while the chain keeps sequencing (by 10:00 UTC the same day:
76066 sequenced, 7 pending exits), so re-read them right before every step that uses them.

```bash
export ETH_RPC_URL=https://ethereum-rpc.publicnode.com
RM=0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2   # AgglayerManager (rollup manager) mainnet
cast call $RM 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 10 --json \
  | jq '{rollupContract:.[0], chainID:.[1], forkID:.[3], lastLocalExitRoot:.[4], lastBatchSequenced:.[5], lastVerifiedBatch:.[6], rollupTypeID:.[10], verifierType:.[11]}'
```

```json
{"rollupContract":"0x419dcD0f72ebAFd3524b65a97ac96699C7fBebdB","chainID":2355,"forkID":12,
 "lastLocalExitRoot":"0x0f7970e95aa749649aaa607d06fbb73901cc223f73bbe6cf4b9104618261bcde",
 "lastBatchSequenced":76058,"lastVerifiedBatch":75940,"rollupTypeID":7,"verifierType":0}
```

`verifierType 0` is `StateTransition` (legacy proofs), `rollupTypeID 7` is `PolygonValidiumEtrog`
fork 12. The gap was 118 batches. Batch 75940 was sequenced on 2026-09-15 13:07 UTC, one hour after
the agglayer 0.6.0 release; batch 76058 on 2026-09-17 03:18 UTC.

Confirm the L2 side agrees and find the boundary block, the value the aggkit config will need later:

```bash
export ETH_RPC_URL=https://rpc.silicon.network
cast rpc zkevm_verifiedBatchNumber | tr -d '"' | cast to-dec              # 75940
cast rpc zkevm_getBatchByNumber 75940 --json | jq -r '.blocks[-1]'        # 0xbe12366226b28319875e291bef07cb890942a05b52b90a0bc66353face148e66
cast block 0xbe12366226b28319875e291bef07cb890942a05b52b90a0bc66353face148e66 --field number   # 20758138
cast call 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe 'getRoot()(bytes32)' --block 20758138     # 0x0f7970e9...61bcde
```

The L2 bridge root at the boundary block must equal `lastLocalExitRoot` on L1. For Silicon it does.
If it does not, stop: the bootstrap certificate of step 7 cannot be built and the situation needs
investigation before anything else.

Count the withdrawals that will be delayed (deposits made on L2 after the boundary):

```bash
cast call 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe 'depositCount()(uint256)' --block 20758138  # 2451
cast call 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe 'depositCount()(uint256)'                   # 2457 -> 6 pending exits
```

Sunk cost of the rollback: `getBatchFee()` on the rollup manager is 0.1 POL per batch, so
118 batches are 11.8 POL that stay in the rollup manager instead of being paid out as aggregator
reward. No forced batches were ever used on Silicon (`lastForceBatch() == 0`).


## 2. Stop sequencing now (chain operator)

Stop the **sequence-sender** first. Every batch sequenced from now on would be rolled back and its
0.1 POL fee lost, and cdk-node would immediately re-sequence the rolled-back range after step 3 if
it were still running. Leave the sequencer (cdk-erigon) running: users keep using the chain.

```bash
# Silicon: whatever supervises cdk-node's sequence-sender (systemd unit / docker compose service)
docker compose stop sequence-sender      # or: systemctl stop cdk-sequence-sender
```

Then wait until the last sequence transaction is finalized and the counter no longer moves:

```bash
export ETH_RPC_URL=https://ethereum-rpc.publicnode.com
RM=0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2
cast call $RM 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 10 --json | jq '{seq:.[5], ver:.[6]}'
cast block-number finalized      # must be past the block of the last sequence tx
```

The aggregator may stay up or be stopped now; it cannot settle anything and is stopped for good in
step 4 anyway. In the devnet both run in one container and were stopped together:

<!-- OBS:STOP -->
```text
07-stop-cdk-node.txt        INFO Stopping service 'cdk-node-001'
07-state-sequencing-stopped lastBatchSequenced=33 lastVerifiedBatch=20 (stable), L1 finalized past the last sequence
```
<!-- /OBS:STOP -->


## 3. Roll the unverified batches back on L1 (chain operator)

`rollbackBatches` is callable by the rollup's admin (Silicon's admin key
`0xef5D7af5dbBeE845860E75cE8f8e8fE7F6e8dBF7`) or by Polygon's `UPDATE_ROLLUP_ROLE` holder. No
timelock is involved. Re-read `lastVerifiedBatch` immediately before sending and use it as the target.

```bash
export ETH_RPC_URL=https://ethereum-rpc.publicnode.com
RM=0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2
ROLLUP=0x419dcD0f72ebAFd3524b65a97ac96699C7fBebdB
TARGET=$(cast call $RM 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 10 --json | jq -r '.[6]')
# the target must end a sequence: accInputHash != 0
cast call $RM 'getRollupSequencedBatches(uint32,uint64)((bytes32,uint64,uint64))' 10 $TARGET
# simulate first
cast call --from <ADMIN_ADDRESS> $RM 'rollbackBatches(address,uint64)' $ROLLUP $TARGET
# send (admin key or hardware wallet / safe)
cast send --private-key <ADMIN_KEY> $RM 'rollbackBatches(address,uint64)' $ROLLUP $TARGET
```

Verify:

```bash
cast call $RM 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 10 --json | jq '{seq:.[5], ver:.[6]}'   # equal now
# two events in the receipt: the rollup manager's RollbackBatches(uint32,uint64,bytes32) and the
# consensus contract's RollbackBatches(uint64,bytes32); cdk-erigon reacts to the second one
cast receipt <TX> --json | jq -r '.logs[] | .topics[0] + " " + .address'
#   0x80a6d395a55aed8126079cb8247f0a6848b1440ca2cdca3b4386f250c3529402 <rollup manager>
#   0x1125aaf62d132d8e2d02005114f8fc360ff204c3105e4f1a700a1340dc55d5b1 <rollup contract>
# L2 untouched: same head progression, same block hashes
export ETH_RPC_URL=https://rpc.silicon.network
cast block-number; cast block 20758139 --field hash
# once the rollback block is finalized on L1, cdk-erigon trims its local sequence records:
cast rpc zkevm_virtualBatchNumber | tr -d '"' | cast to-dec    # == TARGET
```

Simulated on mainnet on 2026-09-17 (read-only `eth_call`, nothing sent): `rollbackBatches(0x419dcD0f…, 75940)`
from Silicon's admin `0xef5D7af5…` returns success; from any other address it reverts with
`NotAllowedAddress()` (`0x1a06d0fe`). `initMigration(10, 14, 0x06e76665)` from a role holder reverts today
with `AllSequencedMustBeVerified()` (`0xcc862d4a`), as expected before the rollback.

Observed on the devnet (rollup ID 1):

<!-- OBS:ROLLBACK -->
```text
08-sequenced-batch-target   getRollupSequencedBatches(1, 20) = (0xe670fb90…a8e4b4, 1789642507, 16)   <- accInputHash != 0: a sequence end
08-rollbackBatches-receipt  rollbackBatches(0x414e9E22…530E4e, 20)  tx 0xb66baa89…1ac130  block 410  gas 78668
                            events: 0x80a6d395… RollbackBatches(uint32,uint64,bytes32) from the rollup manager
                                    0x1125aaf6… RollbackBatches(uint64,bytes32)        from the rollup contract
08-state-rolled-back        lastBatchSequenced=20 lastVerifiedBatch=20 (was 33/20); lastLocalExitRoot unchanged 0xf04f3ef7…bd16eb
                            L2 block 155 (the in-window withdrawal) hash unchanged 0x7f0e8569…477b62; L2 head 212 -> 213
08-state-rolled-back-erigon-synced  60 s later, once L1 finalized block 410: cdk-erigon zkevm_virtualBatchNumber 33 -> 20 on both nodes,
                            zkevm_batchNumber kept growing (44 -> 48), eth_blockNumber 213 -> 233
```
<!-- /OBS:ROLLBACK -->

Between sending and finality nothing else is required; cdk-erigon adjusts its local sequence records on
its own once the block is final.


## 3b. What the rollback does to cdk-erigon (observed)

The question the aggkit team raised: does the L1 `rollbackBatches` call disturb cdk-erigon? On the
devnet the two nodes (sequencer and RPC) were probed before the call, right after it, after L1 finality
and at every later stage, and asked to do real work in between.

What changes: once the block with the `RollbackBatches` event is final, cdk-erigon's `L1Syncer` stage
deletes its local records of the rolled-back L1 sequences. `zkevm_virtualBatchNumber` drops to the
target on both nodes and `zkevm_isBlockVirtualized` for a block in the rolled-back range flips from
`true` to `false`. Nothing else moves: `zkevm_batchNumber` (local batches) keeps growing, block hashes
in the rolled-back range are identical, `eth_getLogs` over that range still returns the bridge events,
`debug_traceTransaction` (which aggkit relies on) keeps working, and the RPC node keeps following the
sequencer through the datastream.

What keeps working, tested by doing it: user transactions submitted to the RPC node (forwarded to the
pool manager before the PP config, to the sequencer after it) and to the sequencer are mined; L1 to L2
deposits made after the rollback and again after the migration are claimed on L2, so the sequencer's
`L1InfoTree` stage keeps injecting global exit roots throughout.

<!-- OBS:ERIGON_HEALTH -->
<!-- /OBS:ERIGON_HEALTH -->

## 4. Upgrade cdk-erigon and switch it to PP mode (chain operator)

This is step 3 of the standard runbook. v2.61.22 and v2.61.23 ("fep to pp changes") added the
FEP-to-PP handling the standard runbook relies on: the PP-mode flags below and recording new rollup
types as PP so that the `UpdateRollup` event of step 6 is ignored. For a rollup type that was added on
L1 **before** the upgrade (Silicon: type 14) that last part does not apply, and v2.61.20 and v2.61.24
handle the event identically: one `unknown rollup type` error, see step 6. Upgrade anyway, before
Polygon sends `initMigration`, and follow the restart rule in step 6.

Sequencer (`hermeznetwork/cdk-erigon:v2.61.24` or newer):

```yaml
# zkevm.executor-urls: ...            # remove executors
zkevm.executor-strict: false
zkevm.disable-virtual-counters: true
zkevm.mock-witness-generation: true
```

RPC nodes:

```yaml
# zkevm.pool-manager-url: ...         # remove pool manager
zkevm.mock-witness-generation: true
zkevm.disable-virtual-counters: true
```

Restart sequencer and RPCs, check `web3_clientVersion`, `eth_blockNumber` advancing and
`zkevm_getForkId` still 12. Then stop: dac, sequence-sender, aggregator, executors, provers,
pool-manager.

Devnet: the config artifact is downloaded, edited and re-uploaded (Kurtosis mounts config artifacts
read-only inside the container). The RPC node gets image and config in one `kurtosis service update`
and re-syncs from the sequencer's datastream. The sequencer is re-added with a generated Starlark
script that declares its persistent datadir, because `kurtosis service update` recreates containers
without persistent directories (observed once: erigon reopened an empty datadir and restarted at
block 3, which is exactly the failure mode an operator must avoid on a real chain: never start the
new sequencer image against an empty datadir). Then the legacy components are stopped:

<!-- OBS:ERIGON -->
```diff
# sequencer (09-erigon-config-sequencer-diff.txt)
-zkevm.disable-virtual-counters: false
+zkevm.disable-virtual-counters: true
-zkevm.executor-strict: true
+zkevm.executor-strict: false
-zkevm.executor-urls: zkevm-stateless-executor-001:50071
+# zkevm.executor-urls: zkevm-stateless-executor-001:50071
+zkevm.mock-witness-generation: true
# rpc (09-erigon-config-rpc-diff.txt)
-zkevm.disable-virtual-counters: false
+zkevm.disable-virtual-counters: true
-zkevm.pool-manager-url: http://zkevm-pool-manager-001:8545
+# zkevm.pool-manager-url: http://zkevm-pool-manager-001:8545
+zkevm.mock-witness-generation: true
```

```text
09-erigon-version           web3_clientVersion = cdk-erigon/v2.61.24 on both nodes (was v2.61.20)
09-stop-legacy-components   Stopping cdk-data-availability-001, zkevm-stateless-executor-001, zkevm-prover-001, zkevm-pool-manager-001
09-state-erigon-upgraded    L2 head 246, batch 51: block 155 hash unchanged, blocks produced with executors, prover, DAC and pool manager stopped
```
<!-- /OBS:ERIGON -->


## 5. Start aggkit in sync-only mode (chain operator)

Prerequisite section of the standard runbook: aggkit 0.8.1, `--components=aggsender`, the
`config.toml` template from the runbook with `DryRun = true` and `MaxL2BlockNumber = 0`. The
signer is the trusted sequencer keystore, because `migrateFromLegacyConsensus()` makes the trusted
sequencer the sole signer with threshold 1. `L2URL` must expose `debug_*`.

Values for Silicon: `rollupCreationBlockNumber`, `rollupManagerCreationBlockNumber` and
`genesisBlockNumber` have the same names and meaning in the existing cdk-node configuration; copy them
from there, together with the L1/L2 contract addresses. The Agglayer gRPC endpoint per environment is
listed in the standard runbook (mainnet `grpc-agglayer.polygon.technology:443`, `UseTLS = true`).

Sync time: aggkit indexes the L1 info tree from the rollup manager's creation block and the L2 bridge
from genesis (Silicon: about 20.8 M L2 blocks, 2458 deposits). Start it days ahead, not hours; the
116-block devnet cannot show how long mainnet takes. It is synced when the aggsender log shows it
building certificates, on the devnet `dry run mode enabled, skipping sending certificate`
(`10-logs-aggkit-dryrun-aggkit-001.log` shows the pre-migration warning instead, see below).

**Add `Mode = "PessimisticProof"` under `[AggSender]`.** The standard runbook's template relies on
aggkit's default `Mode = "Auto"`, which reads the consensus type from the rollup contract. Before
`initMigration` the contract is still `PolygonValidiumEtrog`, the call reverts and aggkit exits with
`aggsender mode is AUTO, but can't get contract mode from rollup contract`. Observed on the devnet;
`Auto` resolves `AggchainECDSAMultisig` to `PessimisticProof` anyway (aggkit
`aggsender/query/multisig_committee_query.go`), so the explicit value is correct before and after.

The template used in the devnet is `assets/aggkit-config.toml.template`; the rendered devnet config
(secrets redacted) is in the evidence folder.

<!-- OBS:AGGKIT -->
```text
10-aggkit-config-max0-drytrue.toml   the rendered config (DryRun = true, MaxL2BlockNumber = 0)
10-logs-aggkit-dryrun-aggkit-001.log WARN flows/builder_flow_factory.go:235	error getting multisig committee: failed to query the signatures threshold for block -2 (rollupAddr 0 ...
```
<!-- /OBS:AGGKIT -->

The warning is expected before the migration: the rollup is still a `PolygonValidiumEtrog` and has no
multisig committee to read. aggsender keeps running, synchronising L1 and the L2 bridge.


## 6. Migrate the rollup to AggchainECDSAMultisig (Polygon)

**Who can send it.** `initMigration` is `onlyRole(UPDATE_ROLLUP_ROLE)`. Verified on mainnet on
2026-09-17: the role is held by the Agglayer admin `0x242daE44F5d8fb54B198D03a94dA45B5a4413e21`, a
Gnosis Safe 1.3.0 with a **5-of-9** signer threshold and no timelock, and by the Polygon timelock
`0xEf1462451C30Ea7aD8555386226059Fe837CA4EF` (`getMinDelay()` = 259200 s, 3 days). Silicon's admin does
not hold it. The standard runbook's `cast send --private-key ${ADMIN_PKEY}` stands for that Safe
transaction: Polygon has to collect 5 signatures, so the Safe transaction should be prepared and signed
while step 3 is being finalised and executed right after. That is what keeps the window between step 3
and this step short. If Polygon has to go through the timelock instead, the operation must be
**scheduled** 3 days before the rollback (the precondition is only checked at execution), Silicon stays
without sequencing for those 3 days, and the pending withdrawals wait that much longer. Agree on the
path and the signing schedule with Polygon before step 2.

Polygon sends, once `lastBatchSequenced == lastVerifiedBatch`:

```bash
# rollup type: latest AggchainECDSAMultisig (mainnet: 14). Data: cast calldata "migrateFromLegacyConsensus()"
cast send --private-key $ADMIN_PKEY $AGGLAYER_MANAGER "initMigration(uint32,uint32,bytes)" 10 14 0x06e76665
```

Effects to verify on L1:

```bash
cast call $RM 'isRollupMigrating(uint32)(bool)' 10             # true until the bootstrap certificate settles
cast call $ROLLUP 'threshold()(uint256)'                        # 1
cast call $ROLLUP 'getAggchainSigners()(address[])'             # [trusted sequencer]
cast call $RM 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 10 --json | jq '{type:.[10], verifierType:.[11]}'   # 14, 2 (ALGateway)
```

On the sequencer, cdk-erigon logs one line about the `UpdateRollup` event (see the devnet observation
below) and the fork stays 12. Wait for L1 finality of the migration transaction before the next step.

**Restart rule (sequencer only).** Only the sequencer runs the `L1SequencerSyncer` stage; RPC nodes
follow the sequencer through the datastream and never process `UpdateRollup` (verified: the stage is
wired only in cdk-erigon's `SequencerZkStages`, and the devnet RPC node logged nothing about the event,
`11-erigon-rpc-UpdateRollupTopic.txt` is empty). The error is one-shot only because the stage keeps its
in-memory position past the migration block and saves progress on the next clean pass. A sequencer
restarted before that clean pass re-reads the event from its saved progress, fails the stage on every
pass (about every 15 s) and, because the staged sync aborts the remaining stages, stops producing
blocks. So: do not restart the sequencer between `initMigration` and the first
`L1 Sequencer sync finished` logged after the error (on the devnet the count of that line kept growing,
8 to 12 in the minute after the event). There is no validated recovery in this runbook for a sequencer
stuck in that loop; involve the cdk-erigon team (resetting the L1 sequencer sync stage progress to
before the `AddNewRollupType` block is the expected fix, untested here).

<!-- OBS:MIGRATE -->
```text
11-initMigration-receipt    initMigration(1, 2, 0x06e76665)  tx 0x15016603…d7050c  block 468  gas 295060
11-post-migration-state     isRollupMigrating=true  threshold=1  signers=[0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed] (trusted sequencer)
                            aggchainManager=0xE34aaF64b29273B7D567FCFc40544c014EEe9970 (previous admin)  AGGCHAIN_TYPE=0x0000 (ECDSA multisig)
11-state-migrated           rollupTypeID 1 -> 2, rollupVerifierType 0 -> 2 (ALGateway), counters 20/20, LER unchanged
11-erigon-UpdateRollupTopic [2/13 L1SequencerSyncer] err="[2/13 L1SequencerSyncer] received UpdateRollupTopic for unknown rollup type: 2"   (logged once)
                            'unknown rollup type' lines: 2 right after the event, 2 one minute later; 'L1 Sequencer sync finished' lines: 8 -> 12 (clean passes continue); zkevm_getForkId=12
11-erigon-rpc-UpdateRollupTopic  empty: the RPC node does not run this stage
                            blocks kept coming (249 -> 300 by the time the bootstrap certificate settled)
```
<!-- /OBS:MIGRATE -->

Why "unknown rollup type" and not "PP rollup type, ignoring": cdk-erigon only records a rollup type as
PP when a version >= v2.61.23 processes its `AddNewRollupType` event (`zk/stages/stage_l1_sequencer_sync.go`,
`WritePPRollupType`). Here the type was added while the sequencer ran v2.61.20, which stored it with fork 0
and no PP marker; v2.61.20 itself errors the same way on `UpdateRollup`. Silicon is in the same position:
mainnet type 14 was added long before its upgrade. The v2.61.24 stage fails once on that L1 block, the
syncer continues from the next block, the fork history is never touched, and the sequencer keeps producing.
Expect that one error line at migration and apply the restart rule above. RPC nodes do not run this
stage and log nothing about the event.


## 7. Bootstrap certificate, then normal certificates (chain operator)

Step 7 of the standard runbook. The first certificate after a legacy migration is a "bootstrap
certificate": the rollup manager requires its `newLocalExitRoot` to equal the last legacy
`lastLocalExitRoot`, so it must cover exactly the L2 blocks up to the last block of the last verified
batch (the boundary block from step 1; Silicon: 20758138).

```toml
[AggSender]
MaxL2BlockNumber = 20758138   # last L2 block of zkevm_verifiedBatchNumber
DryRun = false
```

Restart aggkit, watch the certificate be sent and settled. **Use L1 as the source of truth**:
`isRollupMigrating(rollupID)` flips to false and `CompletedMigration` is emitted. The Agglayer's
`interop_getLatestSettledCertificateHeader` lags L1 by up to an epoch (on the devnet it still returned
`null` when L1 already showed the migration completed, and height 0 when L1 already held the height-1
root). Then:

```toml
[AggSender]
MaxL2BlockNumber = 0
```

Restart again. The next certificate starts at boundary + 1 and carries every bridge exit made since,
including those from the rolled-back batches. When the L1 `lastLocalExitRoot` equals the L2 bridge
`getRoot()`, everything is settled.

<!-- OBS:CERTS -->
```text
12-max-l2-block             zkevm_verifiedBatchNumber=20 -> last block 0x827942ec…5cf6d8 -> MaxL2BlockNumber=96
                            L1 lastLocalExitRoot = L2 bridge getRoot()@96 = 0xf04f3ef7…bd16eb   (precondition holds)
12-aggkit-config-max96-dryfalse.toml   DryRun = false, MaxL2BlockNumber = 96
12-state-bootstrap-settled  152 s after initMigration (11:05:01 UTC): isRollupMigrating=false; L1 LER still 0xf04f3ef7…bd16eb (bootstrap reproduces it)
13-agglayer-settled-final   interop_getLatestSettledCertificateHeader(1): height 0, status Settled, new_local_exit_root 0xf04f3ef7…bd16eb at that moment (lags L1, see above)
13-aggkit-config-max0-dryfalse.toml     MaxL2BlockNumber = 0
13-ler-catch-up             settled: L1 lastLocalExitRoot = L2 bridge getRoot() = 0xbbe91da5…3ae050 (includes the in-window exit)
13-logs-pp-live-aggkit-001.log recovery: last settled certificate already in local storage with same height and ID (persisted /data)
```
<!-- /OBS:CERTS -->


## 8. Withdrawals made during the outage

Users who withdrew during the outage (Silicon: 6 exits, deposit counts 2451 to 2456) can claim on
L1 once the certificate that carries their exit is settled. The claim itself is the normal
`claimAsset` with a merkle proof from the bridge service; nothing special is required.

<!-- OBS:CLAIMS -->
```text
04-bridge-in-gap            depositCount=1 l2Block=155 l2Batch=32 (sequenced on L1, never verified, rolled back)
14-claim-in-gap             polycli ulxly claim asset --deposit-count 1 --deposit-network 1 --bridge-service-url <zkevm-bridge-service>
                            "The deposit is ready to be claimed"
                            -> Claim transaction sent 0xf65da7f9…57bf28 -> Transaction successful
14-claimed-check            AgglayerBridge.isClaimed(1, 1) = true
14-state-final              L1 20/20, rollupTypeID 2, LER 0xbbe91da5…3ae050; L2 block 328, batch 67, fork 12, cdk-erigon v2.61.24
```
<!-- /OBS:CLAIMS -->

The bridge service used was the legacy `zkevm-bridge-service` v0.6.4-RC2 that was already running for the
validium; it indexes the `VerifyBatchesTrustedAggregator` event emitted for PP certificates as well.


## 9. Risks and what the rollback does not touch

**What `rollbackBatches` changes**

- rollup manager: `sequencedBatches[]` entries above the target are deleted, `lastBatchSequenced`
  and `totalSequencedBatches` are lowered
- consensus contract (`PolygonValidiumEtrog`): `lastAccInputHash` is reset to the target's
- nothing else: `lastLocalExitRoot`, GER, L1 bridge escrow, bridge mappings, POL balances untouched
- cdk-erigon: the L1 syncer deletes its local `L1SEQUENCES` records above the target. No L2 unwind,
  no reorg, the RPC stays up. `zkevm_virtualBatchNumber` drops to the target; `zkevm_batchNumber` and
  `eth_blockNumber` keep growing. (Verified on the devnet: block hash of the in-window withdrawal
  block unchanged across rollback, erigon upgrade and migration.)

**Funds**

- Withdrawals in the rolled-back range are delayed, not lost. They are settled by the second
  certificate after migration and become claimable then (step 8).
- L1 to L2 deposits keep working throughout: the sequencer keeps injecting global exit roots.
- Batch fees already paid for the rolled-back batches stay in the rollup manager (Silicon: 11.8 POL).

**Operational risks, and the mitigation in this procedure**

- Sequence-sender still running when rolling back: cdk-node follows L1's counter and re-sequences the
  same batches immediately, recreating the gap and paying fees again. Step 2 stops it first and step 3
  waits for the counter to be stable and finalized.
- Sequencing new content for the same batch numbers: only the trusted sequencer key can sequence, and
  after `initMigration` the consensus contract is `AggchainECDSAMultisig`, which has no
  `sequenceBatches`. Keep the window between step 3 and step 6 short.
- cdk-erigon older than v2.61.22 at migration time: the `UpdateRollup` event carries the new rollup
  type's `forkID = 0`; v2.61.22 and v2.61.23 added the handling that ignores it for PP types
  (`received UpdateRollupTopic for PP rollup type, ignoring`). Step 4 upgrades before step 6.
- Wrong `MaxL2BlockNumber`: the bootstrap certificate is rejected on L1 with `InvalidNewLocalExitRoot`
  and nothing is lost. Step 7 derives it from `zkevm_verifiedBatchNumber` and checks the L2 root
  against L1 before enabling sending.
- Runtime user and datadir permissions: the new sequencer container must run as the same user that
  wrote the datadir. (Observed on the devnet: kurtosis-cdk runs cdk-erigon as root; a re-added
  container running as the image's default `erigon` user died with `nodekey: permission denied`.)
- Rolling back to a batch that is not a sequence end reverts with `RollbackBatchIsNotEndOfSequence`.
  `lastVerifiedBatch` always ends a sequence, because verification requires
  `sequencedBatches[finalNewBatch].accInputHash != 0`.

**What changes for good**

Pessimistic Proofs do not prove the L2 state on L1; they enforce bridge accounting. The 118
rolled-back batches simply join the same regime as every future block. For a validium the L1 never
held their data anyway. The rollback is in principle reversible by re-sequencing the same batches (for a validium
this needs fresh DAC signatures; not exercised here); `initMigration` is not reversible.


## Appendix A. Devnet used for validation

The procedure was validated with `run.sh` in this folder against a kurtosis-cdk enclave
(`assets/kurtosis-params.yml`, kurtosis-cdk pinned in `assets/kurtosis-cdk.ref`):

| Component | Silicon mainnet (2026-09-17) | Devnet before | Devnet after |
|---|---|---|---|
| consensus | `PolygonValidiumEtrog`, fork 12, rollup type 7, DAC | `PolygonValidiumEtrog`, fork 12, rollup type 1, DAC | `AggchainECDSAMultisig` |
| contracts | AgglayerManager `v1.0.0` (agglayer-contracts v12.x) | agglayer-contracts v12.2.3 | same |
| cdk-erigon | v2.61.20 | `hermeznetwork/cdk-erigon:v2.61.20` | `hermeznetwork/cdk-erigon:v2.61.24` |
| cdk-node | 0.5.4-rc1 | `ghcr.io/0xpolygon/cdk:0.5.4-rc1` | stopped |
| zkevm-prover | fork 12 | `hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12` (mock proofs) | stopped |
| agglayer | 0.5.x, then 0.6.0 GA on 2026-09-15 | `ghcr.io/agglayer/agglayer:0.6.0-rc.5` (last build accepting `interop_sendTx`) | `ghcr.io/agglayer/agglayer:0.6.0` |
| aggkit | none | none | `ghcr.io/agglayer/aggkit:0.8.1` (runbook version) |
| L1 | Ethereum mainnet | ethereum-package reth + lighthouse, 2 s slots | same |

Known differences and why they do not change the procedure:

- The devnet agglayer goes 0.6.0-rc.5 to 0.6.0 rather than 0.5.x to 0.6.0, because kurtosis-cdk main
  renders a 0.6-line agglayer config. Both transitions have the same effect on cdk-node:
  `interop_sendTx` accepted, then refused with `-10009`.
- Proofs are mock proofs and the SP1 verifier is a mock verifier. The certificate flow, the
  `isRollupMigrating` bootstrap logic and the L1 events are the real contracts' behaviour.
- kurtosis-cdk runs sequence-sender and aggregator in one `cdk-node` container; both stop together.
- Polygon-side calls (`initMigration`, `addRollupType`) are sent with the devnet admin key, which
  holds `UPDATE_ROLLUP_ROLE` and the rollup admin role exactly as Polygon's admin key does on mainnet.
- The sequencer's image and config change is applied by re-adding the Kurtosis service with the same
  `persistent_key` (`scripts/readd-service.jq`); on Silicon it is a normal restart with the datadir
  volume attached.
- aggkit is added and reconfigured through `assets/aggkit.star`, which keeps `/data` as a persistent
  directory across config changes, matching the runbook's persisted data directory.
- Validation host: GitHub Actions `ubuntu-latest` (Linux amd64, 4 vCPU), see `00-versions.txt`. The
  author's Apple Silicon machine could not host the enclave: the fork-12 prover image is amd64-only
  and compiled for AVX2 (exit 132 under Rosetta), and with OrbStack switched to QEMU the x86 agglayer
  binary exceeds kurtosis-cdk's fixed 180 s `agglayer vkey` task. On amd64 Linux nothing is needed.
- Runs of the scenario on GitHub Actions, all passed with the same invariants (sequenced > verified before the
  rollback, equal after; same exit roots because the devnet deposits are deterministic; `AllSequencedMustBeVerified`
  selector `0xcc862d4a`; one-shot erigon error; claim true):
  [35201843011](https://github.com/agglayer/e2e/actions/runs/35201843011) (37/24),
  [35204567044](https://github.com/agglayer/e2e/actions/runs/35204567044) (38/24),
  [35207232742](https://github.com/agglayer/e2e/actions/runs/35207232742) (33/20, first run with the
  clean-pass and RPC-node checks of step 6),
  [35209534700](https://github.com/agglayer/e2e/actions/runs/35209534700) (37/21) and
  [35211930721](https://github.com/agglayer/e2e/actions/runs/35211930721) (33/20, the committed evidence).
- Failed development runs that back "observed" statements in this document:
  [35190176306](https://github.com/agglayer/e2e/actions/runs/35190176306) (empty datadir after
  `kurtosis service update`, erigon restarted at block 3),
  [35192294074](https://github.com/agglayer/e2e/actions/runs/35192294074) (`nodekey: permission denied`
  when the re-added sequencer did not run as root),
  [35196161889](https://github.com/agglayer/e2e/actions/runs/35196161889) (aggkit `Auto` mode exit).
- The contracts image tag is `agglayer-contracts:v12.2.3`; the repository checkout inside it reports
  `v12.2.0` in `05-add-rollup-type-output.json`. `ROLLUP_MANAGER_VERSION()` is `v1.0.0` in both the
  devnet and mainnet.


## Appendix B. Evidence index

Directory `evidence/validated-run-1/`, produced by `run.sh` in GitHub Actions run
[35211930721](https://github.com/agglayer/e2e/actions/runs/35211930721) (ubuntu-latest, amd64) on
2026-09-17, enclave created 10:43:56 UTC, scenario passed 11:06:25 UTC. File names are prefixed with the
step number. `state-*.json` files are snapshots of the rollup manager and L2 counters.

| Step | Files |
|-----:|-------|
| 0 | `00-versions.txt` tool versions, kurtosis-cdk ref, images |
| 1 | `01-kurtosis-run.txt` full kurtosis-cdk deployment log |
| 2 | `02-enclave-inspect.txt`, `02-env.env`, `02-combined.json` (contract addresses), `02-roles.txt`, `02-input-args-redacted.json` |
| 3 | `03-deposit-pre-break.txt`, `03-claim-pre-break-l2.txt`, `03-l1-bridge-balance.txt`, `03-bridge-pre-break.txt`, `03-claim-pre-break.txt` (L1 claim), `03-state-baseline-*.json`, cdk-node and agglayer logs |
| 4 | `04-agglayer-update.txt`, `04-agglayer-version.txt`, `04-cdk-node-10009.txt`, `04-bridge-in-gap.txt`, `04-state-gap-open.json` |
| 5 | `05-add-rollup-type.txt`, `05-add-rollup-type-output.json`, `05-rollup-type-check.txt`, `05-gateway-route.txt` |
| 6 | `06-initMigration-reverts.txt` |
| 7 | `07-stop-cdk-node.txt`, `07-state-sequencing-stopped.json` |
| 8 | `08-sequenced-batch-target.txt`, `08-rollbackBatches-receipt.{json,txt}`, `08-state-rolled-back*.json`, erigon logs |
| 9 | `09-erigon-config-*-{before,after}.yaml`, `09-erigon-config-*-diff.txt`, `09-erigon-readd-sequencer.star`, `09-erigon-update-*.txt`, `09-erigon-effective-config-*.txt`, `09-erigon-version.txt`, `09-stop-legacy-components.txt`, `09-state-erigon-upgraded.json` |
| 10 | `10-aggkit-config-max0-drytrue.toml`, `10-aggkit-add.txt`, `10-logs-aggkit-dryrun-aggkit-001.log` |
| 11 | `11-initMigration-receipt.json`, `11-post-migration-state.txt`, `11-erigon-UpdateRollupTopic.txt`, `11-state-migrated.json` |
| 12 | `12-max-l2-block.txt`, `12-aggkit-config-max116-dryfalse.toml`, `12-aggkit-replace-v2.txt`, `12-agglayer-settled-after-bootstrap.txt`, `12-state-bootstrap-settled.json`, aggkit and agglayer logs |
| 13 | `13-aggkit-config-max0-dryfalse.toml`, `13-ler-catch-up.txt`, `13-agglayer-settled-final.txt`, `13-state-pp-live.json`, logs |
| 14 | `14-claim-in-gap.txt`, `14-claimed-check.txt`, `14-state-final.json`, `14-summary.txt` |
| end | `99-enclave-inspect.txt`, `99-logs-final-*.log`, `screenshots/` (Kurtosis Enclave Manager: enclave list, enclave overview, service and logs pages for aggkit, agglayer, cdk-node, sequencer and rpc, captured with Playwright while the enclave was still running) |

Secrets: private keys are replaced by `<ADMIN_PRIVATE_KEY>` / `<SEQUENCER_PRIVATE_KEY>` and every
`*_private_key`, `*password*` and `*mnemonic*` value dumped by kurtosis-cdk or ethereum-package by `<redacted>`,
all by `run.sh` itself while recording. The committed directory is the CI artifact of run 35211930721, unmodified.
The redacted values are the public kurtosis-cdk devnet defaults anyway.
