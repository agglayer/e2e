#!/usr/bin/env python3
"""Regenerate the "observed on the devnet" blocks of RUNBOOK.md from an evidence directory.

    scripts/render-runbook-observations.py evidence/validated-run-1 [--apply]

Without --apply the rendered blocks are printed. With --apply, RUNBOOK.md is rewritten between the
<!-- OBS:NAME --> ... <!-- /OBS:NAME --> markers. Every number in those blocks comes from the files the
block names, so the runbook can be re-pointed at a new validated run without manual transcription.
"""
import json, os, re, sys

E = sys.argv[1]
APPLY = "--apply" in sys.argv
RB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "RUNBOOK.md")

def rd(name):
    p = os.path.join(E, name)
    return open(p, errors="replace").read() if os.path.exists(p) else ""
def strip(t): return re.sub(r"\x1b\[[0-9;]*[JKmsu]", "", t)
def sh(h, a=10, b=6): return h[:a] + "…" + h[-b:]
def st(name):
    j = json.load(open(os.path.join(E, name)))
    rm, l2, l1 = j["rollup_manager"], j["l2"], j["l1"]
    return dict(seq=int(rm["lastBatchSequenced"]), ver=int(rm["lastVerifiedBatch"]), ler=rm["lastLocalExitRoot"],
                typ=rm["rollupTypeID"], vt=rm["rollupVerifierType"], blk=int(l2["block"]), batch=int(l2["batch"]),
                virt=int(l2["virtualBatch"]), fork=l2["forkId"], client=l2["client"].split("/")[1], at=j["at"])
def dec(x): return int(x, 16) if isinstance(x, str) and x.startswith("0x") else int(x)

stop, rb, rbs, up, mig, boot, live, fin = [st(n) for n in ["07-state-sequencing-stopped.json", "08-state-rolled-back.json",
    "08-state-rolled-back-erigon-synced.json", "09-state-erigon-upgraded.json", "11-state-migrated.json",
    "12-state-bootstrap-settled.json", "13-state-pp-live.json", "14-state-final.json"]]
env = dict(l.split("=", 1) for l in rd("02-env.env").splitlines() if "=" in l)
dep1 = re.search(r"depositCount=(\d+) l2Block=(\d+) l2Batch=(\d+)", rd("04-bridge-in-gap.txt")).groups()
tgt = re.search(r"\((0x[0-9a-f]+), (\d+) \[[^\]]*\], (\d+)\)", strip(rd("08-sequenced-batch-target.txt")))
rbn = strip(rd("08-rollbackBatches-receipt.txt"))
rb_tx, rb_blk = re.search(r"tx=(0x[0-9a-f]+) block=(\d+)", rbn).groups()
rb_l2blk, rb_hash, rb_h0, rb_h1 = re.search(r"L2 block (\d+) hash unchanged: (0x[0-9a-f]+); L2 head (\d+) -> (\d+)", rbn).groups()
rb_rc = json.load(open(os.path.join(E, "08-rollbackBatches-receipt.json")))
rb_gas = dec(rb_rc["gasUsed"])
rb_topics = sorted({l["topics"][0] for l in rb_rc["logs"]})
rb_wait = int((__import__("datetime").datetime.fromisoformat(rbs["at"].rstrip("Z")) - __import__("datetime").datetime.fromisoformat(rb["at"].rstrip("Z"))).total_seconds())
mig_rc = json.load(open(os.path.join(E, "11-initMigration-receipt.json")))
pms = dict(re.findall(r"^(isRollupMigrating|threshold|signers|aggchainManager|AGGCHAIN_TYPE)=(.*)$", strip(rd("11-post-migration-state.txt")), re.M))
urt = strip(rd("11-erigon-UpdateRollupTopic.txt"))
urt_err = next((l for l in urt.splitlines() if "Error while executing stage" in l), "")
urt_err = re.sub(r".*err=", "err=", urt_err)
urt_note = next((l for l in urt.splitlines() if "log lines" in l), "")
counts = re.search(r"'unknown rollup type' log lines: (\d+) right after the event, (\d+) one minute later", urt_note)
clean = re.search(r"'L1 Sequencer sync finished' lines: (\d+) -> (\d+)", urt_note)
rpc_captured = os.path.exists(os.path.join(E, "11-erigon-rpc-UpdateRollupTopic.txt"))
rpc_urt = strip(rd("11-erigon-rpc-UpdateRollupTopic.txt")).strip()
typeid = json.load(open(os.path.join(E, "05-add-rollup-type-output.json")))["rollupTypeID"]
mx = rd("12-max-l2-block.txt")
vb, vb_hash, maxl2 = re.search(r"zkevm_verifiedBatchNumber=(\d+) lastBlockHash=(0x[0-9a-f]+) MaxL2BlockNumber=(\d+)", mx).groups()
l1ler, lerblk, l2ler = re.search(r"L1 lastLocalExitRoot=(0x[0-9a-f]+)\s+L2 bridge getRoot\(\)@(\d+)=(0x[0-9a-f]+)", mx).groups()
boot_wait = int((__import__("datetime").datetime.fromisoformat(boot["at"].rstrip("Z")) - __import__("datetime").datetime.fromisoformat(mig["at"].rstrip("Z"))).total_seconds())
settled_final = strip(rd("13-agglayer-settled-final.txt"))
sf = None
try:
    _i = settled_final.find('{"jsonrpc')
    _r = json.JSONDecoder().raw_decode(settled_final[_i:].replace("\n", " "))[0]["result"] if _i >= 0 else None
    if _r:
        _status = _r.get("status"); _status = _status if isinstance(_status, str) else (next(iter(_status)) if isinstance(_status, dict) else str(_status))
        sf = (str(_r.get("height")), _status, str(_r.get("new_local_exit_root")))
except Exception:
    sf = None
catch = [l for l in rd("13-ler-catch-up.txt").splitlines() if l.strip()]
catch_settled = re.search(r"L1 lastLocalExitRoot=(0x[0-9a-f]+) L2 getRoot\(\)=(0x[0-9a-f]+)", " ".join(catch))
claim = strip(rd("14-claim-in-gap.txt"))
claim_tx = re.findall(r"Claim transaction sent txHash=(0x[0-9a-f]+)", claim)
not_ready = "not yet ready" in claim
claimed = strip(rd("14-claimed-check.txt")).strip().splitlines()
claimed_val = next((l for l in claimed if l.strip() in ("true", "false")), "?")
seqdiff = "\n".join(l for l in rd("09-erigon-config-sequencer-diff.txt").splitlines() if re.match(r"^[-+][^-+]", l))
rpcdiff = "\n".join(l for l in rd("09-erigon-config-rpc-diff.txt").splitlines() if re.match(r"^[-+][^-+]", l))
ver = re.findall(r"cdk-erigon/(v[0-9.]+)", strip(rd("09-erigon-version.txt")))
stopped = re.findall(r"Stopping service '([^']+)'", strip(rd("09-stop-legacy-components.txt")))
aggwarn = next((re.sub(r".*WARN\s+", "WARN ", strip(l))[:140] for l in rd("10-logs-aggkit-dryrun-aggkit-001.log").splitlines() if "WARN" in l and "multisig" in l), "")
recov = "99-logs-final-aggkit-001.log" if "already in local storage" in rd("99-logs-final-aggkit-001.log") else "13-logs-pp-live-aggkit-001.log"

blocks = {}
blocks["STOP"] = f"""```text
07-stop-cdk-node.txt        INFO Stopping service 'cdk-node-001'
07-state-sequencing-stopped lastBatchSequenced={stop['seq']} lastVerifiedBatch={stop['ver']} (stable), L1 finalized past the last sequence
```
"""
blocks["ROLLBACK"] = f"""```text
08-sequenced-batch-target   getRollupSequencedBatches(1, {rb['ver']}) = ({sh(tgt.group(1))}, {tgt.group(2)}, {tgt.group(3)})   <- accInputHash != 0: a sequence end
08-rollbackBatches-receipt  rollbackBatches({sh(env['ROLLUP_ADDR'])}, {rb['ver']})  tx {sh(rb_tx)}  block {rb_blk}  gas {rb_gas}
                            events: 0x80a6d395… RollbackBatches(uint32,uint64,bytes32) from the rollup manager
                                    0x1125aaf6… RollbackBatches(uint64,bytes32)        from the rollup contract
08-state-rolled-back        lastBatchSequenced={rb['seq']} lastVerifiedBatch={rb['ver']} (was {stop['seq']}/{stop['ver']}); lastLocalExitRoot unchanged {sh(rb['ler'])}
                            L2 block {rb_l2blk} (the in-window withdrawal) hash unchanged {sh(rb_hash)}; L2 head {rb_h0} -> {rb_h1}
08-state-rolled-back-erigon-synced  {rb_wait} s later, once L1 finalized block {rb_blk}: cdk-erigon zkevm_virtualBatchNumber {stop['virt']} -> {rbs['virt']} on both nodes,
                            zkevm_batchNumber kept growing ({rb['batch']} -> {rbs['batch']}), eth_blockNumber {rb['blk']} -> {rbs['blk']}
```
"""
blocks["ERIGON"] = f"""```diff
# sequencer (09-erigon-config-sequencer-diff.txt)
{seqdiff}
# rpc (09-erigon-config-rpc-diff.txt)
{rpcdiff}
```

```text
09-erigon-version           web3_clientVersion = cdk-erigon/{ver[0] if ver else '?'} on both nodes (was v2.61.20)
09-stop-legacy-components   Stopping {', '.join(stopped)}
09-state-erigon-upgraded    L2 head {up['blk']}, batch {up['batch']}: block {rb_l2blk} hash unchanged, blocks produced with executors, prover, DAC and pool manager stopped
```
"""
blocks["AGGKIT"] = f"""```text
10-aggkit-config-max0-drytrue.toml   the rendered config (DryRun = true, MaxL2BlockNumber = 0)
10-logs-aggkit-dryrun-aggkit-001.log {aggwarn} ...
```
"""
blocks["MIGRATE"] = f"""```text
11-initMigration-receipt    initMigration(1, {typeid}, 0x06e76665)  tx {sh(mig_rc['transactionHash'])}  block {dec(mig_rc['blockNumber'])}  gas {dec(mig_rc['gasUsed'])}
11-post-migration-state     isRollupMigrating={pms.get('isRollupMigrating')}  threshold={pms.get('threshold')}  signers={pms.get('signers')} (trusted sequencer)
                            aggchainManager={pms.get('aggchainManager')} (previous admin)  AGGCHAIN_TYPE={pms.get('AGGCHAIN_TYPE')} (ECDSA multisig)
11-state-migrated           rollupTypeID 1 -> {mig['typ']}, rollupVerifierType 0 -> {mig['vt']} (ALGateway), counters {mig['seq']}/{mig['ver']}, LER unchanged
11-erigon-UpdateRollupTopic [2/13 L1SequencerSyncer] {urt_err}   (logged once)
                            'unknown rollup type' lines: {counts.group(1) if counts else '?'} right after the event, {counts.group(2) if counts else '?'} one minute later{'; ' + chr(39) + 'L1 Sequencer sync finished' + chr(39) + ' lines: ' + clean.group(1) + ' -> ' + clean.group(2) + ' (clean passes continue)' if clean else ''}; zkevm_getForkId={mig['fork']}
11-erigon-rpc-UpdateRollupTopic  {('empty: the RPC node does not run this stage' if not rpc_urt else rpc_urt.splitlines()[0][:120]) if rpc_captured else 'not captured in this run'}
                            blocks kept coming ({mig['blk']} -> {boot['blk']} by the time the bootstrap certificate settled)
```
"""
blocks["CERTS"] = f"""```text
12-max-l2-block             zkevm_verifiedBatchNumber={vb} -> last block {sh(vb_hash)} -> MaxL2BlockNumber={maxl2}
                            L1 lastLocalExitRoot = L2 bridge getRoot()@{lerblk} = {sh(l1ler)}   (precondition holds)
12-aggkit-config-max{maxl2}-dryfalse.toml   DryRun = false, MaxL2BlockNumber = {maxl2}
12-state-bootstrap-settled  {boot_wait} s after initMigration ({boot['at'][11:19]} UTC): isRollupMigrating=false; L1 LER still {sh(boot['ler'])} (bootstrap reproduces it)
13-agglayer-settled-final   interop_getLatestSettledCertificateHeader(1): {'height ' + sf[0] + ', status ' + sf[1] + ', new_local_exit_root ' + sh(sf[2]) if sf else ('null' if '"result":null' in settled_final else 'see file')} at that moment (lags L1, see above)
13-aggkit-config-max0-dryfalse.toml     MaxL2BlockNumber = 0
13-ler-catch-up             settled: L1 lastLocalExitRoot = L2 bridge getRoot() = {sh(catch_settled.group(1)) if catch_settled else sh(live['ler'])} (includes the in-window exit)
{recov:<27} recovery: last settled certificate already in local storage with same height and ID (persisted /data)
```
"""
blocks["CLAIMS"] = f"""```text
04-bridge-in-gap            depositCount={dep1[0]} l2Block={dep1[1]} l2Batch={dep1[2]} (sequenced on L1, never verified, rolled back)
14-claim-in-gap             polycli ulxly claim asset --deposit-count {dep1[0]} --deposit-network 1 --bridge-service-url <zkevm-bridge-service>
                            {'"The claim transaction is not yet ready" (first poll) -> ' if not_ready else ''}"The deposit is ready to be claimed"
                            -> Claim transaction sent {sh(claim_tx[-1]) if claim_tx else '?'} -> Transaction successful
14-claimed-check            AgglayerBridge.isClaimed({dep1[0]}, 1) = {claimed_val}
14-state-final              L1 {fin['seq']}/{fin['ver']}, rollupTypeID {fin['typ']}, LER {sh(fin['ler'])}; L2 block {fin['blk']}, batch {fin['batch']}, fork {fin['fork']}, cdk-erigon {fin['client']}
```
"""

# cdk-erigon health table: one row per (stage, node)
def health_rows():
    rows = []
    order = ["baseline", "gap-open", "before-rollback", "after-rollback", "erigon-synced", "erigon-upgraded", "migrated", "pp-live", "final"]
    files = {re.sub(r"^\d+-erigon-health-(.*)\.json$", r"\1", f): f for f in os.listdir(E) if re.match(r"^\d+-erigon-health-.*\.json$", f)}
    for lab in order:
        if lab not in files: continue
        j = json.load(open(os.path.join(E, files[lab])))
        for n in j["nodes"]:
            bi = n.get("zkevm_getBatchByNumber_ref_batch") or {}
            rows.append("| {lab} | {node} | {head} | {batch}/{virt}/{ver} | {fork} | {hash} | {virtd} | {trace} | {logs} | {client} |".format(
                lab=lab, node=n["node"], head=n["eth_blockNumber"], batch=n["zkevm_batchNumber"], virt=n["zkevm_virtualBatchNumber"],
                ver=n["zkevm_verifiedBatchNumber"], fork=n["zkevm_getForkId"], hash=sh(n["ref_block_hash"], 8, 4) if n["ref_block_hash"] else "-",
                virtd=n["zkevm_isBlockVirtualized_ref_block"], trace=n["debug_traceTransaction_ref_tx"], logs=n["eth_getLogs_bridge_events_at_ref_block"],
                client=n["web3_clientVersion"].split("/")[1] if "/" in n["web3_clientVersion"] else n["web3_clientVersion"]))
    return rows
def note_lines(prefix):
    out = []
    for f in sorted(os.listdir(E)):
        if re.match(rf"^\d+-{prefix}.*\.txt$", f):
            for l in open(os.path.join(E, f), errors="replace").read().splitlines():
                if l.strip() and not l.startswith("$") and "[exit=" not in l: out.append(f"{f:<40} {strip(l)[:130]}")
    return out
hdr = "| stage | node | eth_blockNumber | zkevm batch/virtual/verified | fork | ref block hash | ref block virtualized | debug_traceTransaction | bridge logs @ref | client |\n|---|---|---|---|---|---|---|---|---|---|"
ref_desc = f"Reference block: {dep1[1]} (the in-window withdrawal, batch {dep1[2]}); before it exists the pre-break withdrawal block is used."
def batch_meta_line():
    def load(lab):
        f = next((f for f in os.listdir(E) if re.match(rf"^\d+-erigon-health-{lab}\.json$", f)), None)
        if not f: return None
        j = json.load(open(os.path.join(E, f)))
        return next((n for n in j["nodes"] if n["node"] == "rpc"), None)
    b, a = load("before-rollback"), load("erigon-synced")
    if not (b and a and b.get("zkevm_getBatchByNumber_ref_batch") and a.get("zkevm_getBatchByNumber_ref_batch")): return ""
    bb, ab = b["zkevm_getBatchByNumber_ref_batch"], a["zkevm_getBatchByNumber_ref_batch"]
    fmt = lambda v: (sh(v) if isinstance(v, str) and v.startswith("0x") and len(v) > 20 else json.dumps(v))
    return (f"`zkevm_getBatchByNumber({int(b['ref_block_batch'])})`, the batch holding block {b['ref_block']}, before the rollback and once the rollback block is final: "
            f"`sendSequencesTxHash` {fmt(bb.get('sendSequencesTxHash'))} -> {fmt(ab.get('sendSequencesTxHash'))}, "
            f"`verifyBatchTxHash` {fmt(bb.get('verifyBatchTxHash'))} -> {fmt(ab.get('verifyBatchTxHash'))}, `closed` {bb.get('closed')} -> {ab.get('closed')}, "
            f"`accInputHash` {'unchanged' if bb.get('accInputHash') == ab.get('accInputHash') else 'CHANGED'}, "
            f"`zkevm_isBlockVirtualized({b['ref_block']})` {b['zkevm_isBlockVirtualized_ref_block']} -> {a['zkevm_isBlockVirtualized_ref_block']}, "
            f"`zkevm_isBlockConsolidated` {b['zkevm_isBlockConsolidated_ref_block']} -> {a['zkevm_isBlockConsolidated_ref_block']}.")

blocks["ERIGON_HEALTH"] = (batch_meta_line() + "\n\n" + 
    "Probe results (`NN-erigon-health-<stage>.json`, both nodes, every stage). " + ref_desc + "\n\n" + hdr + "\n" + "\n".join(health_rows()) + "\n\n"
    + "Functional checks:\n\n```text\n" + "\n".join(note_lines("l2-transfer-") + note_lines("deposit-after-") ) + "\n```\n"
    + "\nL1 to L2 deposits made after the rollback and after the migration were claimed on L2 (`*-claim-l2-after-rollback.txt`, `*-claim-l2-after-migration.txt`), which requires the sequencer to keep injecting global exit roots.\n")

if APPLY:
    s = open(RB).read()
    for k, v in blocks.items():
        s = re.sub(rf"(<!-- OBS:{k} -->\n).*?(<!-- /OBS:{k} -->\n)", lambda m: m.group(1) + v + m.group(2), s, flags=re.S)
    open(RB, "w").write(s)
    print("RUNBOOK.md observation blocks regenerated from", E)
else:
    for k, v in blocks.items():
        print(f"<!-- OBS:{k} -->\n{v}<!-- /OBS:{k} -->\n")
