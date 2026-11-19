#!/usr/bin/env bash
# ====================================================================================================
# cdk-erigon FEP -> PP migration with sequenced-but-unverified batches
#
# Reproduces on a fresh kurtosis-cdk devnet the situation Silicon (mainnet rollup ID 10) is in on
# 2026-09-17, and validates the way out end to end:
#
#   1. cdk-erigon validium (fork 12) settling through the legacy cdk-node aggregator via agglayer
#   2. Polygon upgrades agglayer to 0.6.0 -> interop_sendTx is disabled (-10009), verification stops
#   3. the chain keeps sequencing -> lastBatchSequenced runs ahead of lastVerifiedBatch
#   4. a user withdraws L2 -> L1 inside that window (Silicon has 6 such withdrawals)
#   5. initMigration() reverts with AllSequencedMustBeVerified()
#   6. operator stops sequencing and calls rollbackBatches() down to lastVerifiedBatch (no L2 unwind)
#   7. runbook: upgrade cdk-erigon, reconfigure for PP, stop the legacy components
#   8. Polygon: initMigration(rollupID, AggchainECDSAMultisig type, migrateFromLegacyConsensus())
#   9. aggkit aggsender: bootstrap certificate up to the last verified block, then normal certificates
#  10. the withdrawal from step 4 becomes claimable on L1
#
# Everything is driven through the kurtosis CLI (including `kurtosis service exec` for read-only checks
# and for running the contracts tooling inside contracts-001), cast, jq, curl and polycli: no direct
# docker access, no volume surgery. Every command and its output is captured under $EVIDENCE_DIR.
# Devnet internals that are coupled to the pinned kurtosis-cdk ref (service names, private ports,
# the sequencer datadir path/persistent key, root user) are read from the enclave where possible and
# asserted where not.
#
# Resume for debugging: REUSE_ENCLAVE=true START_STEP=<n> ./run.sh
# ====================================================================================================
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    echo "bash >= 4 is required (macOS ships 3.2: brew install bash and put it first in PATH)" >&2
    exit 1
fi

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCENARIO_DIR"
# shellcheck source=../common/log.sh
source ../common/log.sh

# Settings precedence: process environment > .env > env.example. (The shared load_env helper
# exports the file values unconditionally, which would override REUSE_ENCLAVE=true etc.)
load_settings() {
    local f k v
    for f in .env env.example; do
        [[ -f "$f" ]] || continue
        while IFS='=' read -r k v; do
            [[ -z "$k" || "$k" == \#* ]] && continue
            [[ -n "${!k:-}" ]] || export "$k=$v"
        done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$f")
        log_info "loaded defaults from $f (environment values take precedence)"
        break
    done
}
load_settings

: "${ENCLAVE_NAME:=fep-to-pp-rollback}"
: "${KURTOSIS_CDK_REF:=$(cat assets/kurtosis-cdk.ref)}"
: "${KURTOSIS_PARAMS:=assets/kurtosis-params.yml}"
: "${AGGLAYER_IMAGE_AFTER:=ghcr.io/agglayer/agglayer:0.6.0}"
: "${CDK_ERIGON_IMAGE_AFTER:=hermeznetwork/cdk-erigon:v2.61.24}"
: "${AGGKIT_IMAGE:=ghcr.io/agglayer/aggkit:0.8.1}"
: "${MIN_VERIFIED_BATCHES_BEFORE_BREAK:=3}"
: "${MIN_UNVERIFIED_GAP:=4}"
: "${KEEP_ENCLAVE:=false}"
: "${REUSE_ENCLAVE:=false}"
: "${START_STEP:=0}"
: "${STOP_STEP:=99}"
: "${RUN_ID:=$(date -u +%Y%m%dT%H%M%SZ)}"
: "${EVIDENCE_DIR:=$SCENARIO_DIR/evidence/run-$RUN_ID}"

# Fixed by the deployment: kurtosis-cdk creates one rollup with ID 1 / network ID 1.
ROLLUP_ID=1
L2_NETWORK_ID=1
# cast calldata "migrateFromLegacyConsensus()"
MIGRATE_CALLDATA=0x06e76665
# Timeouts (seconds). Generous because the fork-12 prover runs under emulation on arm64 hosts.
T_DEPLOY=3600
T_VERIFY=1800
T_L1_FINALITY=900
T_CERT=1800
T_SERVICE=600

mkdir -p "$EVIDENCE_DIR" "$SCENARIO_DIR/work"
WORK="$SCENARIO_DIR/work"
STEP_NO=0
STOPPED_EARLY=false
if [[ "$REUSE_ENCLAVE" != "true" ]]; then rm -f "$SCENARIO_DIR/work/state.env"; fi

# ---------------------------------------------------------------------------------------- helpers
redact() { # keep evidence free of key material (devnet keys, but still): known values + generic patterns
    sed -E -e "s#${ADMIN_PK:-__none__}#<ADMIN_PRIVATE_KEY>#g" -e "s#${SEQ_PK:-__none__}#<SEQUENCER_PRIVATE_KEY>#g" \
        -e 's#("[A-Za-z0-9_]*private_key":[[:space:]]*")0x[0-9a-fA-F]{64}#\1<redacted>#g' \
        -e 's#("[A-Za-z0-9_]*(password|mnemonic)":[[:space:]]*")[^"]*#\1<redacted>#g' \
        -e 's#(--private-key[= ])0x[0-9a-fA-F]{64}#\1<redacted>#g' \
        -e 's#(PRIVATE_KEY=)"?0x[0-9a-fA-F]{64}#\1<redacted>#g' \
        -e 's#([A-Za-z0-9_]*(mnemonic|password|private_key)[[:space:]]*=[[:space:]]*")[^"]*#\1<redacted>#g'   # starlark-style dumps
}

ev_file() { printf '%s/%02d-%s' "$EVIDENCE_DIR" "$STEP_NO" "$1"; }

# Cross-step state (deposit counts, block numbers, type id) is persisted so a run can be resumed
# with REUSE_ENCLAVE=true START_STEP=<n>.
STATE_FILE="$WORK/state.env"
save_var() { for v in "$@"; do printf '%s=%q\n' "$v" "${!v}" >> "$STATE_FILE"; done; }
load_state() { [[ -f "$STATE_FILE" ]] && { # shellcheck source=/dev/null
    source "$STATE_FILE"; }; return 0; }

# rec <name> <command...>: run a command, append "$ cmd" + output to evidence, propagate exit code.
rec() {
    local name=$1; shift
    local f; f="$(ev_file "$name").txt"
    { printf '$ %s\n' "$*" | redact; } >> "$f"
    local rc=0
    "$@" 2>&1 | redact | tee -a "$f" && rc=0 || rc=$?   # pipefail: the command's own status
    printf '\n[exit=%s]\n\n' "$rc" >> "$f"
    return "$rc"
}

# note <name> <text...>: append free text to an evidence file.
note() { local name=$1; shift; printf '%s\n' "$*" | redact >> "$(ev_file "$name").txt"; }

# wait_until <timeout_s> <interval_s> <description> <command...>: poll until the command exits 0.
wait_until() {
    local timeout=$1 interval=$2 desc=$3; shift 3
    local start=$SECONDS
    until "$@"; do
        if (( SECONDS - start > timeout )); then
            log_error "timed out after ${timeout}s waiting for: $desc"
            return 1
        fi
        sleep "$interval"
    done
    log_info "condition met after $((SECONDS - start))s: $desc"
}

# Predicates for wait_until. They run in this shell, so they see every discovered variable.
p_verified_ge()      { [[ $(last_verified) -ge $1 ]]; }
p_gap_open()         { local s v; s=$(last_sequenced); v=$(last_verified); [[ $s -ge $1 && $((s - v)) -ge $2 ]]; }
p_sequenced_eq()     { [[ $(last_sequenced) -eq $1 ]]; }
p_l1_finalized_ge()  { [[ $(l1_bn finalized) -ge $1 ]]; }
p_block_gt()         { [[ $(cast block-number --rpc-url "$1") -gt $2 ]]; }
p_rpc_up()           { cast block-number --rpc-url "$1" >/dev/null 2>&1; }
p_logs_match()       { klogs "$1" -n "${3:-2000}" --match "$2" 2>/dev/null | grep -q -- "$2"; }
p_logs_regex()       { klogs "$1" -n "${3:-500}" 2>/dev/null | grep -qiE -- "$2"; }
p_virtual_batch_eq() { [[ $(l2_rpc_dec zkevm_virtualBatchNumber) -eq $1 ]]; }
p_virtual_batch_eq_on() { [[ $(cast rpc --rpc-url "$1" zkevm_virtualBatchNumber | tr -d '"' | cast to-dec) -eq $2 ]]; }
p_ler_synced()       { [[ $(rd_field 4) == $(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'getRoot()(bytes32)') ]]; }
p_not_migrating()    { [[ $(l1_call "$ROLLUP_MANAGER" 'isRollupMigrating(uint32)(bool)' "$ROLLUP_ID") == false ]]; }
p_ler_eq()           { [[ $(rd_field 4) == "$1" ]]; }
p_rpc_synced()       { local s r; s=$(cast block-number --rpc-url "$L2_SEQ_RPC"); r=$(cast block-number --rpc-url "$L2_RPC" 2>/dev/null || echo 0); [[ $r -ge $((s - 5)) ]] && cast block --rpc-url "$L2_RPC" "$((s - 5))" --field hash >/dev/null 2>&1; }
p_block_hash_eq()    { [[ $(cast block --rpc-url "$1" "$2" --field hash 2>/dev/null) == "$3" ]]; }
p_jsonrpc_ok()       { curl -sf -X POST -H 'content-type: application/json' --data "$2" "$1" >/dev/null; }

# kurtosis prints "host:port" for ports without an application protocol; every consumer here wants a URL.
kport() { local u; u=$(kurtosis port print "$ENCLAVE_NAME" "$1" "$2"); [[ "$u" == *://* ]] && echo "$u" || echo "http://$u"; }
# Host-side port mappings change every time kurtosis recreates a container (service update/add),
# so they are re-read after each such operation.
refresh_ports() {
    L1_RPC=$(kport "$L1_EL_SERVICE" rpc)
    L2_RPC=$(kport cdk-erigon-rpc-001 rpc)
    L2_SEQ_RPC=$(kport cdk-erigon-sequencer-001 rpc)
    CONTRACTS_URL=$(kport contracts-001 http)
    AGGLAYER_READRPC=$(kport agglayer aglr-readrpc)
    BRIDGE_SVC_URL=$(kport zkevm-bridge-service-001 rpc)
    AGGKIT_RPC=$(kport aggkit-001 rpc 2>/dev/null || true)
}
private_port() { kurtosis service inspect "$ENCLAVE_NAME" "$1" -o json | jq -r --arg p "$2" '.ports[$p].number'; }
# JSON-RPC with literal params (cast rpc would quote numbers as strings)
jsonrpc() { curl -sf -X POST -H 'content-type: application/json' --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}" "$1"; }
p_rpc_alive() { curl -s -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' "$1" 2>/dev/null | grep -q jsonrpc; }
kexec() { kurtosis service exec "$ENCLAVE_NAME" "$1" "$2"; }
klogs() { kurtosis service logs "$ENCLAVE_NAME" "$@"; }

l1_call()   { cast call --rpc-url "$L1_RPC" "$@"; }
l2_rpc_dec() { cast rpc --rpc-url "$L2_RPC" "$@" | tr -d '"' | cast to-dec; }
l1_bn()     { cast block-number --rpc-url "$L1_RPC" "$@"; }
l2_bn()     { cast block-number --rpc-url "$L2_RPC"; }

# Silent sender: private key never appears in evidence. Prints the receipt JSON.
send_as_admin() { cast send --rpc-url "$L1_RPC" --private-key "$ADMIN_PK" --json "$@"; }

rollup_data() {
    l1_call "$ROLLUP_MANAGER" \
        'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' \
        "$ROLLUP_ID" --json | jq -c '(.data? // .)'
}
rd_field() { rollup_data | jq -r ".[$1]"; }  # 4 lastLocalExitRoot 5 lastBatchSequenced 6 lastVerifiedBatch 10 rollupTypeID 11 verifierType
last_sequenced() { rd_field 5; }
last_verified()  { rd_field 6; }

snapshot() { # snapshot <label>: dump L1 rollup-manager and L2 counters as JSON evidence
    local rd; rd=$(rollup_data)
    jq -n --arg label "$1" --argjson rd "$rd" \
        --arg l1_block "$(l1_bn)" --arg l1_finalized "$(l1_bn finalized)" \
        --arg l2_block "$(l2_bn)" --arg l2_batch "$(l2_rpc_dec zkevm_batchNumber)" \
        --arg l2_virtual "$(l2_rpc_dec zkevm_virtualBatchNumber)" --arg l2_verified "$(l2_rpc_dec zkevm_verifiedBatchNumber)" \
        --arg l2_fork "$(l2_rpc_dec zkevm_getForkId)" --arg l2_client "$(cast rpc --rpc-url "$L2_RPC" web3_clientVersion | tr -d '"')" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{label:$label, at:$ts,
          l1:{block:$l1_block, finalized:$l1_finalized},
          rollup_manager:{rollupContract:$rd[0], chainID:$rd[1], forkID:$rd[3], lastLocalExitRoot:$rd[4],
                          lastBatchSequenced:$rd[5], lastVerifiedBatch:$rd[6], lastVerifiedBatchBeforeUpgrade:$rd[9],
                          rollupTypeID:$rd[10], rollupVerifierType:$rd[11]},
          l2:{block:$l2_block, batch:$l2_batch, virtualBatch:$l2_virtual, verifiedBatch:$l2_verified, forkId:$l2_fork, client:$l2_client}}' \
        | tee "$(ev_file "state-$1").json"
}

# bridge_l2_to_l1 <label>: bridge 0.001 native token from L2 to L1 (admin -> admin) and record the deposit.
# Prints "<depositCount> <l2Block> <l2Batch>".
bridge_l2_to_l1() {
    local label=$1
    local dc; dc=$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'depositCount()(uint256)')
    local out
    out=$(polycli ulxly bridge asset --rpc-url "$L2_RPC" --bridge-address "$L2_BRIDGE" \
            --destination-network 0 --destination-address "$ADMIN_ADDR" \
            --private-key "$ADMIN_PK" --value 1000000000000000 --transaction-receipt-timeout 120 2>&1) \
        || { echo "$out" | redact >&2; return 1; }
    echo "$out" | redact > "$(ev_file "bridge-$label").txt"
    local clean; clean=$(sed -E 's/\x1B\[[0-9;]*[JKmsu]//g' <<< "$out")
    local txh; txh=$(sed -n 's/.*txHash=\(0x[a-fA-F0-9]*\).*/\1/p' <<< "$clean" | head -1)
    [[ -n "$txh" ]] || { log_error "could not find txHash in polycli output"; return 1; }
    local blk; blk=$(cast receipt --rpc-url "$L2_RPC" "$txh" --json | jq -r '(.data? // .) | .blockNumber' | xargs cast to-dec)
    local batch; batch=$(cast rpc --rpc-url "$L2_RPC" zkevm_batchNumberByBlockNumber "$(cast to-hex "$blk")" | tr -d '"' | cast to-dec)
    local dc_after; dc_after=$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'depositCount()(uint256)')
    [[ "$dc_after" == "$((dc + 1))" ]] || { log_error "depositCount did not advance ($dc -> $dc_after)"; return 1; }
    echo "$dc $blk $batch $txh"
}

# ---------------------------------------------------------------------------------------- cdk-erigon health
# erigon_health <label>: probe both cdk-erigon nodes the way users and aggkit do and record the answers as
# JSON evidence: eth_*, debug_traceTransaction (aggkit depends on it), eth_getLogs over the rolled-back
# range, the zkevm_* namespace and the metadata of the batch that holds the reference block. Asserts
# what must hold at every stage (both nodes answer, fork 12, reference block hash intact, debug trace
# works); everything else is recorded for the runbook.
erigon_health() {
    local label=$1 out; out="$(ev_file "erigon-health-$label").json"
    local ref_blk=${DEP1_BLOCK:-${DEP0_BLOCK:-1}} ref_hash=${DEP1_BLOCK_HASH:-} ref_tx=${DEP1_TX:-${DEP0_TX:-}}
    local results="[]" node url
    for node in sequencer rpc; do
        if [[ "$node" == sequencer ]]; then url=$L2_SEQ_RPC; else url=$L2_RPC; fi
        local ref_blk_hex; ref_blk_hex=$(cast to-hex "$ref_blk")
        local ref_batch_hex; ref_batch_hex=$(cast rpc --rpc-url "$url" zkevm_batchNumberByBlockNumber "$ref_blk_hex" 2>/dev/null | tr -d '"')
        local batch_json; batch_json=$(cast rpc --rpc-url "$url" zkevm_getBatchByNumber "$ref_batch_hex" 2>/dev/null | jq -c 'del(.blocks, .transactions, .batchL2Data)' 2>/dev/null); [[ -n "$batch_json" ]] || batch_json=null
        local trace="n/a"
        if [[ -n "$ref_tx" ]]; then
            if cast rpc --rpc-url "$url" --raw debug_traceTransaction "[\"$ref_tx\", {\"tracer\":\"callTracer\"}]" >/dev/null 2>&1; then trace=ok; else trace=error; fi
        fi
        local logs_n; logs_n=$(cast logs --rpc-url "$url" --from-block "$ref_blk" --to-block "$ref_blk" --address "$L2_BRIDGE" --json 2>/dev/null | jq 'length' 2>/dev/null); [[ -n "$logs_n" ]] || logs_n=error
        local r; r=$(jq -nc --arg node "$node" --arg url "$url" --argjson ref_blk "$ref_blk" \
            --arg client "$(cast rpc --rpc-url "$url" web3_clientVersion 2>/dev/null | tr -d '"')" \
            --arg chain "$(cast chain-id --rpc-url "$url" 2>/dev/null)" \
            --arg head "$(cast block-number --rpc-url "$url" 2>/dev/null)" \
            --arg ref_hash "$(cast block --rpc-url "$url" "$ref_blk" --field hash 2>/dev/null)" \
            --arg batch "$(cast rpc --rpc-url "$url" zkevm_batchNumber 2>/dev/null | tr -d '"' | cast to-dec 2>/dev/null)" \
            --arg virtual "$(cast rpc --rpc-url "$url" zkevm_virtualBatchNumber 2>/dev/null | tr -d '"' | cast to-dec 2>/dev/null)" \
            --arg verified "$(cast rpc --rpc-url "$url" zkevm_verifiedBatchNumber 2>/dev/null | tr -d '"' | cast to-dec 2>/dev/null)" \
            --arg fork "$(cast rpc --rpc-url "$url" zkevm_getForkId 2>/dev/null | tr -d '"' | cast to-dec 2>/dev/null)" \
            --arg ref_batch "$(cast to-dec "$ref_batch_hex" 2>/dev/null)" \
            --arg virtualized "$(cast rpc --rpc-url "$url" zkevm_isBlockVirtualized "$ref_blk_hex" 2>/dev/null)" \
            --arg consolidated "$(cast rpc --rpc-url "$url" zkevm_isBlockConsolidated "$ref_blk_hex" 2>/dev/null)" \
            --arg deposit_count "$(cast call --rpc-url "$url" "$L2_BRIDGE" 'depositCount()(uint256)' 2>/dev/null)" \
            --arg balance "$(cast balance --rpc-url "$url" "$ADMIN_ADDR" 2>/dev/null)" \
            --arg logs "$logs_n" --arg trace "$trace" --argjson batch_info "$batch_json" \
            '{node:$node, url:$url, web3_clientVersion:$client, eth_chainId:$chain, eth_blockNumber:$head,
              ref_block:$ref_blk, ref_block_hash:$ref_hash, ref_block_batch:$ref_batch,
              zkevm_batchNumber:$batch, zkevm_virtualBatchNumber:$virtual, zkevm_verifiedBatchNumber:$verified, zkevm_getForkId:$fork,
              zkevm_isBlockVirtualized_ref_block:$virtualized, zkevm_isBlockConsolidated_ref_block:$consolidated,
              eth_getLogs_bridge_events_at_ref_block:$logs, debug_traceTransaction_ref_tx:$trace,
              eth_call_bridge_depositCount:$deposit_count, eth_getBalance_admin:$balance,
              zkevm_getBatchByNumber_ref_batch:$batch_info}')
        results=$(jq -c --argjson r "$r" '. + [$r]' <<<"$results")
    done
    jq -n --arg label "$label" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson nodes "$results" '{label:$label, at:$at, nodes:$nodes}' > "$out"
    local bad; bad=$(jq -r --arg h "$ref_hash" '.nodes[] | select(.eth_blockNumber=="" or .zkevm_getForkId!="12" or ($h!="" and .ref_block_hash!=$h) or .debug_traceTransaction_ref_tx=="error") | .node' "$out" | tr '\n' ' ')
    [[ -z "${bad// /}" ]] || { log_error "cdk-erigon health check '$label' failed on: $bad (see $out)"; exit 1; }
    log_info "cdk-erigon health '$label': both nodes answer, fork 12, block $ref_blk hash intact, debug trace ok"
}

# l2_transfer_via <label> <url>: a plain user transaction submitted to that node must be mined. Through the
# rpc node this exercises the forwarding path (pool manager before the PP config, sequencer after).
l2_transfer_via() {
    local label=$1 url=$2 to=0x000000000000000000000000000000000000dEaD rc
    rc=$(cast send --rpc-url "$url" --private-key "$ADMIN_PK" --legacy --value 1 --json "$to" 2>&1) \
        || { echo "$rc" | redact >&2; log_error "L2 transfer via $label ($url) was not accepted"; exit 1; }
    local st blk; st=$(jq -r .status <<<"$rc"); blk=$(jq -r .blockNumber <<<"$rc" | xargs cast to-dec)
    [[ "$st" =~ ^(0x1|1)$ ]] || { log_error "L2 transfer via $label failed: $rc"; exit 1; }
    note "l2-transfer-$label" "cast send via $label: status=$st block=$blk tx=$(jq -r .transactionHash <<<"$rc")"
    log_info "L2 transfer via $label mined in block $blk"
}

# deposit_and_claim_on_l2 <label>: L1 -> L2 deposit claimed on L2, which needs the sequencer to keep
# injecting global exit roots from L1 (the L1InfoTree stage), independently of the L1 rollup state.
deposit_and_claim_on_l2() {
    local label=$1 dep
    dep=$(bridge_l1_to_l2 "$label" 1000000000000000)
    note "deposit-$label" "L1 depositCount=$dep (0.001 ETH to L2)"
    rec "claim-l2-$label" claim_on_l2 "$dep" "$label" || true
    [[ "$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'isClaimed(uint32,uint32)(bool)' "$dep" 0)" == "true" ]] \
        || { log_error "L1 -> L2 deposit $dep ($label) not claimed on L2"; exit 1; }
    log_info "L1 -> L2 deposit $dep claimed on L2 ($label)"
}

# bridge_l1_to_l2 <label> <wei>: deposit native token L1 -> L2 (admin -> admin). Prints "<depositCount>".
# Kurtosis prefunds L2 accounts at genesis, so unlike a real chain the L1 bridge escrow starts empty;
# a real deposit is what makes later L2 -> L1 withdrawals payable on L1.
bridge_l1_to_l2() {
    local label=$1 wei=$2
    local dc; dc=$(cast call --rpc-url "$L1_RPC" "$L1_BRIDGE" 'depositCount()(uint256)')
    local out
    out=$(polycli ulxly bridge asset --rpc-url "$L1_RPC" --bridge-address "$L1_BRIDGE" \
            --destination-network "$L2_NETWORK_ID" --destination-address "$ADMIN_ADDR" \
            --private-key "$ADMIN_PK" --value "$wei" --transaction-receipt-timeout 120 2>&1) \
        || { echo "$out" | redact >&2; return 1; }
    echo "$out" | redact > "$(ev_file "deposit-$label").txt"
    local dc_after; dc_after=$(cast call --rpc-url "$L1_RPC" "$L1_BRIDGE" 'depositCount()(uint256)')
    [[ "$dc_after" == "$((dc + 1))" ]] || { log_error "L1 depositCount did not advance ($dc -> $dc_after)"; return 1; }
    echo "$dc"
}

claim_on_l2() { # claim_on_l2 <depositCount> <label>
    polycli ulxly claim asset --rpc-url "$L2_RPC" --bridge-address "$L2_BRIDGE" --private-key "$ADMIN_PK" \
        --deposit-count "$1" --deposit-network 0 --bridge-service-url "$BRIDGE_SVC_URL" \
        --transaction-receipt-timeout 120 --wait 15m 2>&1 | redact | tee "$(ev_file "claim-l2-$2").txt"
}

claim_on_l1() { # claim_on_l1 <depositCount> <label>
    polycli ulxly claim asset --rpc-url "$L1_RPC" --bridge-address "$L1_BRIDGE" --private-key "$ADMIN_PK" \
        --deposit-count "$1" --deposit-network "$L2_NETWORK_ID" --bridge-service-url "$BRIDGE_SVC_URL" \
        --transaction-receipt-timeout 120 --wait 15m 2>&1 | redact | tee "$(ev_file "claim-$2").txt"
}

service_logs_to_evidence() { # service_logs_to_evidence <label> <service...>
    local label=$1; shift
    for s in "$@"; do
        klogs "$s" -n 400 > "$(ev_file "logs-$label-$s").log" 2>&1 || true
    done
}

render_aggkit_config() { # render_aggkit_config <dest_dir> <max_l2_block> <dry_run>
    local dest=$1 max=$2 dry=$3
    mkdir -p "$dest"
    sed -e "s#REPLACE_L1_URL#$L1_RPC_INTERNAL#" -e "s#REPLACE_L2_URL#$L2_RPC_INTERNAL#" \
        -e "s#REPLACE_ROLLUP_CREATION_BLOCK#$ROLLUP_CREATION_BLOCK#" -e "s#REPLACE_ROLLUP_MANAGER_BLOCK#$ROLLUP_MANAGER_BLOCK#" \
        -e "s#REPLACE_L1_BRIDGE#$L1_BRIDGE#" -e "s#REPLACE_L1_CHAIN_ID#$L1_CHAIN_ID#" -e "s#REPLACE_L1_GER#$L1_GER#" \
        -e "s#REPLACE_ROLLUP_MANAGER#$ROLLUP_MANAGER#" -e "s#REPLACE_POL_TOKEN#$POL_TOKEN#" -e "s#REPLACE_ROLLUP_ADDRESS#$ROLLUP_ADDR#" \
        -e "s#REPLACE_L2_BRIDGE#$L2_BRIDGE#" -e "s#REPLACE_L2_GER#$L2_GER#" \
        -e "s#REPLACE_KEYSTORE_PASSWORD#$KEYSTORE_PASSWORD#" -e "s#REPLACE_MAX_L2_BLOCK#$max#" -e "s#REPLACE_DRY_RUN#$dry#" \
        -e "s#REPLACE_AGGLAYER_GRPC_URL#$AGGLAYER_GRPC_INTERNAL#" \
        assets/aggkit-config.toml.template > "$dest/config.toml"
    cp "$WORK/sequencer.keystore" "$dest/sequencer.keystore"
    sed -e 's/Password = "[^"]*"/Password = "<redacted>"/' "$dest/config.toml" > "$(ev_file "aggkit-config-max${max}-dry${dry}").toml"
}

# ---------------------------------------------------------------------------------------- teardown
cleanup() {
    local rc=$?
    set +e
    if [[ -n "${L1_RPC:-}" ]]; then
        STEP_NO=99
        service_logs_to_evidence final cdk-erigon-sequencer-001 cdk-erigon-rpc-001 cdk-node-001 agglayer aggkit-001 zkevm-bridge-service-001 2>/dev/null
        kurtosis enclave inspect "$ENCLAVE_NAME" > "$(ev_file enclave-inspect).txt" 2>&1
    fi
    if [[ "$KEEP_ENCLAVE" == "true" ]]; then
        log_info "KEEP_ENCLAVE=true, leaving enclave '$ENCLAVE_NAME' running"
    else
        log_info "removing enclave '$ENCLAVE_NAME'"
        kurtosis enclave rm -f "$ENCLAVE_NAME" >/dev/null 2>&1
    fi
    if (( rc != 0 )); then log_error "scenario FAILED (exit $rc), evidence in $EVIDENCE_DIR"
    elif [[ "${STOPPED_EARLY:-false}" == true ]]; then log_info "stopped early at STOP_STEP=$STOP_STEP (not a full pass), evidence in $EVIDENCE_DIR"
    else log_info "scenario PASSED, evidence in $EVIDENCE_DIR"; fi
    exit "$rc"
}
trap cleanup EXIT

run_step() { # run_step <n> <function> <title>
    STEP_NO=$1
    if (( STEP_NO < START_STEP )) && [[ "$STEP_NO" != 0 && "$STEP_NO" != 2 ]]; then log_info "skipping step $STEP_NO ($3)"; return; fi
    if (( STEP_NO > STOP_STEP )); then STOPPED_EARLY=true; log_info "STOP_STEP=$STOP_STEP reached, stopping before step $STEP_NO"; exit 0; fi
    log_block "STEP $STEP_NO: $3"
    "$2"
}

# ================================================================================================
step_00_preflight() {
    for t in kurtosis docker cast jq curl polycli timeout; do
        command -v "$t" >/dev/null || { log_error "missing tool: $t"; exit 1; }
    done
    rec versions bash -c 'kurtosis version; docker version --format "docker {{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}"; cast --version; jq --version; polycli version'
    note versions "host: $(uname -srm)"
    note versions "kurtosis-cdk ref: $KURTOSIS_CDK_REF"
    note versions "params: $(tr '\n' ' ' < "$KURTOSIS_PARAMS" | sed 's/  */ /g')"
    note versions "agglayer after: $AGGLAYER_IMAGE_AFTER | cdk-erigon after: $CDK_ERIGON_IMAGE_AFTER | aggkit: $AGGKIT_IMAGE"
}

step_01_deploy() {
    if [[ "$REUSE_ENCLAVE" == "true" ]] && kurtosis enclave inspect "$ENCLAVE_NAME" >/dev/null 2>&1; then
        log_info "re-using enclave $ENCLAVE_NAME"; return
    fi
    kurtosis enclave rm -f "$ENCLAVE_NAME" >/dev/null 2>&1 || true
    rec kurtosis-run timeout "$T_DEPLOY" kurtosis run --enclave "$ENCLAVE_NAME" --args-file "$KURTOSIS_PARAMS" \
        "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_CDK_REF"
}

step_02_discover() {
    rec enclave-inspect kurtosis enclave inspect "$ENCLAVE_NAME"
    for s in contracts-001 cdk-erigon-sequencer-001 cdk-erigon-rpc-001 cdk-node-001 agglayer \
             cdk-data-availability-001 zkevm-stateless-executor-001 zkevm-prover-001 zkevm-pool-manager-001 zkevm-bridge-service-001; do
        grep -qE "(^|[[:space:]])$s([[:space:]]|$)" "$(ev_file enclave-inspect).txt" || { log_error "expected service $s not found in enclave"; exit 1; }
    done
    L1_EL_SERVICE=$(grep -oE 'el-1-[a-z0-9-]+' "$(ev_file enclave-inspect).txt" | head -1)
    [[ -n "$L1_EL_SERVICE" ]] || { log_error "could not find L1 execution client service"; exit 1; }

    refresh_ports
    # in-enclave URLs for configs consumed by containers: private port numbers come from the services
    L1_RPC_INTERNAL="http://$L1_EL_SERVICE:$(private_port "$L1_EL_SERVICE" rpc)"
    L2_RPC_INTERNAL="http://cdk-erigon-rpc-001:$(private_port cdk-erigon-rpc-001 rpc)"
    AGGLAYER_GRPC_INTERNAL="agglayer:$(private_port agglayer aglr-grpc)"

    curl -sf "$CONTRACTS_URL/opt/output/combined-001.json" > "$WORK/combined.json"
    curl -sf "$CONTRACTS_URL/opt/input/input_args.json" > "$WORK/input_args.json"
    cp "$WORK/combined.json" "$(ev_file combined).json"
    jq 'walk(if type=="object" then with_entries(select(.key|test("private_key|mnemonic|password")|not)) else . end)' "$WORK/input_args.json" > "$(ev_file input-args-redacted).json"

    ROLLUP_MANAGER=$(jq -r .polygonRollupManagerAddress "$WORK/combined.json")
    ROLLUP_ADDR=$(jq -r .rollupAddress "$WORK/combined.json")
    L1_BRIDGE=$(jq -r .polygonZkEVMBridgeAddress "$WORK/combined.json")
    L1_GER=$(jq -r .polygonZkEVMGlobalExitRootAddress "$WORK/combined.json")
    POL_TOKEN=$(jq -r .polTokenAddress "$WORK/combined.json")
    L2_BRIDGE=$(jq -r .polygonZkEVML2BridgeAddress "$WORK/combined.json")
    AGGLAYER_GATEWAY=$(jq -r '.aggLayerGatewayAddress // .AgglayerGateway' "$WORK/combined.json")
    ROLLUP_CREATION_BLOCK=$(jq -r .createRollupBlockNumber "$WORK/combined.json")
    ROLLUP_MANAGER_BLOCK=$(jq -r .deploymentRollupManagerBlockNumber "$WORK/combined.json")
    L1_CHAIN_ID=$(jq -r .args.l1_chain_id "$WORK/input_args.json")
    ADMIN_PK=$(jq -r .args.l2_admin_private_key "$WORK/input_args.json")
    SEQ_PK=$(jq -r .args.l2_sequencer_private_key "$WORK/input_args.json")
    KEYSTORE_PASSWORD=$(jq -r .args.l2_keystore_password "$WORK/input_args.json")
    ADMIN_ADDR=$(cast wallet address --private-key "$ADMIN_PK")
    SEQ_ADDR=$(cast wallet address --private-key "$SEQ_PK")
    L2_GER=$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'globalExitRootManager()(address)')
    export ADMIN_PK SEQ_PK

    # sequencer keystore for aggkit (same key + password the enclave uses for the trusted sequencer)
    rm -f "$WORK/sequencer.keystore"
    cast wallet import --private-key "$SEQ_PK" --unsafe-password "$KEYSTORE_PASSWORD" --keystore-dir "$WORK" sequencer.keystore >/dev/null

    {
        echo "L1_EL_SERVICE=$L1_EL_SERVICE"; echo "L1_RPC=$L1_RPC"; echo "L2_RPC=$L2_RPC"; echo "L2_SEQ_RPC=$L2_SEQ_RPC"
        echo "AGGLAYER_READRPC=$AGGLAYER_READRPC"; echo "BRIDGE_SVC_URL=$BRIDGE_SVC_URL"; echo "CONTRACTS_URL=$CONTRACTS_URL"
        echo "L1_RPC_INTERNAL=$L1_RPC_INTERNAL"; echo "L2_RPC_INTERNAL=$L2_RPC_INTERNAL"; echo "AGGLAYER_GRPC_INTERNAL=$AGGLAYER_GRPC_INTERNAL"
        echo "ROLLUP_MANAGER=$ROLLUP_MANAGER"; echo "ROLLUP_ADDR=$ROLLUP_ADDR"; echo "AGGLAYER_GATEWAY=$AGGLAYER_GATEWAY"
        echo "L1_BRIDGE=$L1_BRIDGE"; echo "L2_BRIDGE=$L2_BRIDGE"; echo "L1_GER=$L1_GER"; echo "L2_GER=$L2_GER"; echo "POL_TOKEN=$POL_TOKEN"
        echo "ROLLUP_CREATION_BLOCK=$ROLLUP_CREATION_BLOCK"; echo "ROLLUP_MANAGER_BLOCK=$ROLLUP_MANAGER_BLOCK"; echo "L1_CHAIN_ID=$L1_CHAIN_ID"
        echo "ADMIN_ADDR=$ADMIN_ADDR"; echo "SEQ_ADDR=$SEQ_ADDR"
    } | tee "$(ev_file env).env"

    # sanity: the admin is the rollup admin and holds UPDATE_ROLLUP_ROLE (Polygon's role on mainnet)
    rec roles bash -c "
      echo rollup.admin=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'admin()(address)')
      echo trustedSequencer=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'trustedSequencer()(address)')
      echo admin_has_UPDATE_ROLLUP_ROLE=\$(cast call --rpc-url $L1_RPC $ROLLUP_MANAGER 'hasRole(bytes32,address)(bool)' \$(cast keccak UPDATE_ROLLUP_ROLE) $ADMIN_ADDR)
      echo ROLLUP_MANAGER_VERSION=\$(cast call --rpc-url $L1_RPC $ROLLUP_MANAGER 'ROLLUP_MANAGER_VERSION()(string)')
      echo rollupTypeCount=\$(cast call --rpc-url $L1_RPC $ROLLUP_MANAGER 'rollupTypeCount()(uint32)')
      echo web3_clientVersion=\$(cast rpc --rpc-url $L2_RPC web3_clientVersion)
      echo zkevm_getForkId=\$(cast rpc --rpc-url $L2_RPC zkevm_getForkId)
    "
    snapshot discovered >/dev/null
}

step_03_baseline() {
    # Legacy path must be healthy: batches sequenced AND verified through cdk-node -> agglayer(interop_sendTx).
    wait_until "$T_VERIFY" 20 "at least $MIN_VERIFIED_BATCHES_BEFORE_BREAK verified batches" p_verified_ge "$MIN_VERIFIED_BATCHES_BEFORE_BREAK"
    snapshot baseline-verifying >/dev/null

    # Users deposit L1 -> L2 (this is also what funds the L1 bridge escrow for later withdrawals).
    local dep_l1; dep_l1=$(bridge_l1_to_l2 pre-break 1000000000000000000)
    note deposit-pre-break "L1 depositCount=$dep_l1 (1 ETH to L2)"
    rec claim-pre-break-l2 claim_on_l2 "$dep_l1" pre-break || true   # a claim sponsor may have claimed it first
    [[ "$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'isClaimed(uint32,uint32)(bool)' "$dep_l1" 0)" == "true" ]] \
        || { log_error "L1 -> L2 deposit $dep_l1 not claimed on L2"; exit 1; }
    rec l1-bridge-balance cast balance --rpc-url "$L1_RPC" "$L1_BRIDGE"

    # A withdrawal that WILL be verified by the legacy path, so the chain has a non-zero settled LER
    # (Silicon: 2451 deposits, lastLocalExitRoot != 0) and we can prove the pre-migration claim path.
    read -r DEP0 DEP0_BLOCK DEP0_BATCH DEP0_TX <<< "$(bridge_l2_to_l1 pre-break)"
    note bridge-pre-break "depositCount=$DEP0 l2Block=$DEP0_BLOCK l2Batch=$DEP0_BATCH tx=$DEP0_TX"
    save_var DEP0 DEP0_BLOCK DEP0_BATCH DEP0_TX
    wait_until "$T_VERIFY" 20 "batch $DEP0_BATCH verified through the legacy aggregator" p_verified_ge "$DEP0_BATCH"
    rec claim-pre-break-l1 claim_on_l1 "$DEP0" pre-break
    snapshot baseline-verified >/dev/null
    erigon_health baseline
    service_logs_to_evidence baseline cdk-node-001 agglayer
}

step_04_break_settlement() {
    # Polygon side: agglayer is upgraded to the release that disabled interop_sendTx.
    rec agglayer-update kurtosis service update "$ENCLAVE_NAME" agglayer --image "$AGGLAYER_IMAGE_AFTER"
    refresh_ports
    wait_until "$T_SERVICE" 5 "upgraded agglayer answering on readrpc" \
        p_jsonrpc_ok "$AGGLAYER_READRPC" '{"jsonrpc":"2.0","id":1,"method":"interop_getEpochConfiguration","params":[]}'
    rec agglayer-version bash -c "kurtosis service exec $ENCLAVE_NAME agglayer 'agglayer --version'"

    # The aggregator keeps producing proofs but every settlement attempt is rejected with -10009.
    wait_until "$T_VERIFY" 15 "cdk-node aggregator logging 'interop_sendTx method is disabled' (-10009)" p_logs_match cdk-node-001 'interop_sendTx method is disabled'
    klogs cdk-node-001 -n 2000 --match 'interop_sendTx method is disabled' | head -5 | tee "$(ev_file cdk-node-10009).txt"

    # Meanwhile a user withdraws. This exit lands in a batch that gets SEQUENCED but never VERIFIED.
    read -r DEP1 DEP1_BLOCK DEP1_BATCH DEP1_TX <<< "$(bridge_l2_to_l1 in-gap)"
    note bridge-in-gap "depositCount=$DEP1 l2Block=$DEP1_BLOCK l2Batch=$DEP1_BATCH tx=$DEP1_TX"
    DEP1_BLOCK_HASH=$(cast block --rpc-url "$L2_RPC" "$DEP1_BLOCK" --field hash)
    note bridge-in-gap "l2BlockHash=$DEP1_BLOCK_HASH (must be unchanged after the L1 rollback)"
    save_var DEP1 DEP1_BLOCK DEP1_BATCH DEP1_BLOCK_HASH DEP1_TX

    wait_until "$T_VERIFY" 20 "withdrawal batch $DEP1_BATCH sequenced on L1 and gap >= $MIN_UNVERIFIED_GAP" p_gap_open "$DEP1_BATCH" "$MIN_UNVERIFIED_GAP"
    snapshot gap-open >/dev/null
    erigon_health gap-open
    log_info "gap: lastBatchSequenced=$(last_sequenced) lastVerifiedBatch=$(last_verified)"
}

step_05_polygon_prep_rollup_type() {
    # Mainnet already has rollup type 14 = AggchainECDSAMultisig. The devnet needs Polygon to add it.
    sed -e "s#REPLACE_ROLLUP_MANAGER#$ROLLUP_MANAGER#" -e "s#REPLACE_ADMIN_PRIVATE_KEY#$ADMIN_PK#" \
        assets/add_rollup_type.json.template > "$WORK/add_rollup_type.json"
    kexec contracts-001 "echo '$(tr -d '\n' < "$WORK/add_rollup_type.json")' > /opt/agglayer-contracts/tools/addRollupType/add_rollup_type.json" >/dev/null
    rec add-rollup-type kexec contracts-001 "cd /opt/agglayer-contracts && npx hardhat run tools/addRollupType/addRollupType.ts --network localhost"
    curl -sf "$CONTRACTS_URL/opt/agglayer-contracts/tools/addRollupType/add_rollup_type_output_ecdsamultisig.json" > "$WORK/add_rollup_type_output.json"
    cp "$WORK/add_rollup_type_output.json" "$(ev_file add-rollup-type-output).json"
    ECDSA_TYPE_ID=$(jq -r .rollupTypeID "$WORK/add_rollup_type_output.json")
    rec rollup-type-check l1_call "$ROLLUP_MANAGER" 'rollupTypeMap(uint32)(address,address,uint64,uint8,bool,bytes32,bytes32)' "$ECDSA_TYPE_ID"
    [[ "$(l1_call "$ROLLUP_MANAGER" 'rollupTypeMap(uint32)(address,address,uint64,uint8,bool,bytes32,bytes32)' "$ECDSA_TYPE_ID" --json | jq -r '(.data? // .)[3]')" == "2" ]] \
        || { log_error "new rollup type $ECDSA_TYPE_ID is not ALGateway (verifierType 2)"; exit 1; }
    log_info "AggchainECDSAMultisig rollup type id: $ECDSA_TYPE_ID"
    save_var ECDSA_TYPE_ID

    # The gateway must route the running agglayer's PP program. Same check Polygon does on mainnet.
    PP_SELECTOR=$(kexec agglayer 'agglayer vkey-selector' | grep -oE '0x[0-9a-fA-F]{8}' | head -1)
    PP_VKEY=$(kexec agglayer 'agglayer vkey' | grep -oE '0x[0-9a-fA-F]{64}' | head -1)
    rec gateway-route l1_call "$AGGLAYER_GATEWAY" 'pessimisticVKeyRoutes(bytes4)(address,bytes32,bool)' "$PP_SELECTOR"
    note gateway-route "agglayer selector=$PP_SELECTOR vkey=$PP_VKEY"
    local routed_vkey; routed_vkey=$(l1_call "$AGGLAYER_GATEWAY" 'pessimisticVKeyRoutes(bytes4)(address,bytes32,bool)' "$PP_SELECTOR" --json | jq -r '(.data? // .)[1]')
    if [[ "$routed_vkey" != "$PP_VKEY" ]]; then
        log_error "gateway has no route for the upgraded agglayer PP vkey (routed=$routed_vkey, agglayer=$PP_VKEY). Polygon would add it with addPessimisticVKeyRoute; not automated here."
        exit 1
    fi
}

step_06_show_blocker() {
    # This is the exact call the runbook asks Polygon to send. It must revert while batches are unverified.
    local sel; sel=$(cast sig 'AllSequencedMustBeVerified()')
    local out rc=0
    out=$(l1_call --from "$ADMIN_ADDR" "$ROLLUP_MANAGER" 'initMigration(uint32,uint32,bytes)' "$ROLLUP_ID" "$ECDSA_TYPE_ID" "$MIGRATE_CALLDATA" 2>&1) || rc=$?
    { echo "\$ cast call --from $ADMIN_ADDR $ROLLUP_MANAGER 'initMigration(uint32,uint32,bytes)' $ROLLUP_ID $ECDSA_TYPE_ID $MIGRATE_CALLDATA"; echo "$out"; echo "[exit=$rc]"; echo "AllSequencedMustBeVerified() selector = $sel"; } > "$(ev_file initMigration-reverts).txt"
    (( rc != 0 )) || { log_error "initMigration unexpectedly succeeded with a sequenced/verified gap"; exit 1; }
    grep -q "${sel#0x}" <<< "$out" || { log_error "initMigration reverted, but not with AllSequencedMustBeVerified(): $out"; exit 1; }
    log_info "initMigration reverts with AllSequencedMustBeVerified() as expected"
}

step_07_stop_sequencing() {
    # Runbook step 1. In kurtosis-cdk the sequence-sender and the aggregator run in one cdk-node
    # container; on Silicon they are separate processes and only the sequence-sender must stop here.
    # The aggregator cannot settle anything any more, so stopping both changes nothing.
    rec stop-cdk-node kurtosis service stop "$ENCLAVE_NAME" cdk-node-001
    # Let any in-flight sequence transaction land: the counter must not move for 30 s.
    local s0 s1 tries=0; s0=$(last_sequenced)
    while :; do
        sleep 30; s1=$(last_sequenced)
        [[ "$s1" == "$s0" ]] && break
        log_info "lastBatchSequenced moved $s0 -> $s1 (in-flight sequence landed), waiting again"
        s0=$s1; tries=$((tries + 1)); (( tries < 20 )) || { log_error "lastBatchSequenced still moving after stopping cdk-node"; exit 1; }
    done
    log_info "lastBatchSequenced stable at $s0 for 30s"
    L1_BLOCK_AT_STOP=$(l1_bn)
    wait_until "$T_L1_FINALITY" 10 "L1 finality past block $L1_BLOCK_AT_STOP" p_l1_finalized_ge "$L1_BLOCK_AT_STOP"
    snapshot sequencing-stopped >/dev/null
}

step_08_rollback() {
    local target; target=$(last_verified)
    local seq; seq=$(last_sequenced)
    (( seq > target )) || { log_error "nothing to roll back (sequenced=$seq verified=$target)"; exit 1; }
    # rollbackBatches requires the target to end a sequence: lastVerifiedBatch always does
    rec sequenced-batch-target l1_call "$ROLLUP_MANAGER" 'getRollupSequencedBatches(uint32,uint64)((bytes32,uint64,uint64))' "$ROLLUP_ID" "$target"
    local before_hash; before_hash=$(cast block --rpc-url "$L2_RPC" "$DEP1_BLOCK" --field hash)
    local l2_before; l2_before=$(l2_bn)
    erigon_health before-rollback

    log_info "rollbackBatches($ROLLUP_ADDR, $target) as rollup admin (sequenced=$seq)"
    local receipt; receipt=$(send_as_admin "$ROLLUP_MANAGER" 'rollbackBatches(address,uint64)' "$ROLLUP_ADDR" "$target")
    echo "$receipt" | jq . > "$(ev_file rollbackBatches-receipt).json"
    ROLLBACK_TX=$(jq -r '.transactionHash' <<< "$receipt")
    ROLLBACK_BLOCK=$(jq -r '.blockNumber' <<< "$receipt" | xargs cast to-dec)
    [[ "$(jq -r .status <<< "$receipt")" =~ ^(0x1|1)$ ]] || { log_error "rollbackBatches tx failed: $ROLLBACK_TX"; exit 1; }
    local topic; topic=$(cast keccak 'RollbackBatches(uint32,uint64,bytes32)')
    jq -e --arg t "$topic" '.logs[] | select(.topics[0]==$t)' <<< "$receipt" >/dev/null || { log_error "no RollbackBatches event in receipt"; exit 1; }
    note rollbackBatches-receipt "tx=$ROLLBACK_TX block=$ROLLBACK_BLOCK event RollbackBatches topic=$topic present"
    save_var ROLLBACK_TX ROLLBACK_BLOCK

    [[ "$(last_sequenced)" == "$target" && "$(last_verified)" == "$target" ]] \
        || { log_error "post-rollback counters wrong: sequenced=$(last_sequenced) verified=$(last_verified)"; exit 1; }
    snapshot rolled-back >/dev/null

    # L2 must be untouched: same block hash for the withdrawal block, chain still advancing.
    local after_hash; after_hash=$(cast block --rpc-url "$L2_RPC" "$DEP1_BLOCK" --field hash)
    [[ "$before_hash" == "$after_hash" && "$after_hash" == "$DEP1_BLOCK_HASH" ]] || { log_error "L2 block $DEP1_BLOCK hash changed across rollback"; exit 1; }
    wait_until 120 5 "L2 still producing blocks after the L1 rollback" p_block_gt "$L2_RPC" "$l2_before"
    note rollbackBatches-receipt "L2 block $DEP1_BLOCK hash unchanged: $after_hash; L2 head $l2_before -> $(l2_bn)"
    erigon_health after-rollback

    # cdk-erigon's L1 syncer reacts to the (finalized) event by trimming its local L1 sequence records only.
    wait_until "$T_L1_FINALITY" 10 "L1 finality past rollback block $ROLLBACK_BLOCK" p_l1_finalized_ge "$ROLLBACK_BLOCK"
    wait_until 600 10 "cdk-erigon rpc node zkevm_virtualBatchNumber back to $target" p_virtual_batch_eq "$target"
    wait_until 600 10 "cdk-erigon sequencer zkevm_virtualBatchNumber back to $target" p_virtual_batch_eq_on "$L2_SEQ_RPC" "$target"
    snapshot rolled-back-erigon-synced >/dev/null
    erigon_health erigon-synced

    # cdk-erigon must keep doing everything else it does for users: accept transactions on both nodes
    # (the rpc node forwards to the pool manager at this point), inject L1 global exit roots so L1 -> L2
    # deposits can be claimed, and keep the rpc node in step with the sequencer through the datastream.
    l2_transfer_via rpc-after-rollback "$L2_RPC"
    l2_transfer_via sequencer-after-rollback "$L2_SEQ_RPC"
    deposit_and_claim_on_l2 after-rollback
    wait_until 120 5 "rpc node in step with the sequencer after the rollback" p_rpc_synced
    service_logs_to_evidence rollback cdk-erigon-sequencer-001 cdk-erigon-rpc-001
}

# erigon_pp_update <service> <role: sequencer|rpc>: what an operator does in one go, bump the image
# and edit config.yaml for PP mode, then restart. Kurtosis mounts files artifacts read-only for the
# container user, so the config is downloaded, edited on the host, uploaded as a new artifact and
# applied together with the new image in a single `kurtosis service update`.
erigon_pp_update() {
    local svc=$1 role=$2
    local old_artifact="cdk-erigon-${role}-config-001" new_artifact="cdk-erigon-${role}-config-pp"
    local dl="$WORK/erigon-$role"; rm -rf "$dl"; mkdir -p "$dl"
    kurtosis files download "$ENCLAVE_NAME" "$old_artifact" "$dl" >/dev/null
    local cfg; cfg=$(find "$dl" -name config.yaml | head -1)
    [[ -n "$cfg" ]] || { log_error "config.yaml not found in artifact $old_artifact"; exit 1; }
    cp "$cfg" "$(ev_file "erigon-config-$role-before").yaml"
    if [[ "$role" == sequencer ]]; then
        # runbook 3.2: remove executors, executor-strict false, disable virtual counters, mock witness
        sed -i.bak -E 's|^(zkevm\.executor-urls:.*)$|# \1|; s|^zkevm\.executor-strict: true$|zkevm.executor-strict: false|; s|^zkevm\.disable-virtual-counters: false$|zkevm.disable-virtual-counters: true|' "$cfg"
    else
        # runbook 3.3: remove pool manager, disable virtual counters, mock witness
        sed -i.bak -E 's|^(zkevm\.pool-manager-url:.*)$|# \1|; s|^zkevm\.disable-virtual-counters: false$|zkevm.disable-virtual-counters: true|' "$cfg"
    fi
    printf '\nzkevm.mock-witness-generation: true\n' >> "$cfg"
    rm -f "$cfg.bak"
    cp "$cfg" "$(ev_file "erigon-config-$role-after").yaml"
    diff -u "$(ev_file "erigon-config-$role-before").yaml" "$(ev_file "erigon-config-$role-after").yaml" > "$(ev_file "erigon-config-$role-diff").txt" || true
    rec "erigon-config-upload-$role" kurtosis files upload "$ENCLAVE_NAME" "$(dirname "$cfg")" --name "$new_artifact"
    # keep every existing mount, swap only the config artifact
    local files
    files=$(kurtosis service inspect "$ENCLAVE_NAME" "$svc" -o json \
        | jq -r --arg old "$old_artifact" --arg new "$new_artifact" \
          '.files | to_entries | map("\(.key):\(.value | map(if . == $old then $new else . end) | join("|"))") | join(",")')
    note "erigon-update-$role" "files mapping: $files"
    if [[ "$role" == sequencer ]]; then
        # The sequencer's datadir is a kurtosis persistent directory. `kurtosis service update` recreates
        # the container WITHOUT it (verified: erigon reopened an empty DB and restarted at block 3), so
        # the sequencer is re-added with a Starlark script that declares the same persistent_key, the
        # way kurtosis-cdk itself declares it (src/chain/cdk-erigon/cdk_erigon.star). Data is kept.
        local datadir; datadir=$(kexec "$svc" "grep -E '^datadir:' /etc/cdk-erigon/config.yaml" | awk '{print $2}')
        datadir="/home/erigon/${datadir#./}"
        local pkey="cdk-erigon-datadir-001"
        kurtosis service inspect "$ENCLAVE_NAME" "$svc" -o json \
          | jq -r -f scripts/readd-service.jq --arg name "$svc" --arg image "$CDK_ERIGON_IMAGE_AFTER" \
               --arg old "$old_artifact" --arg new "$new_artifact" --arg datadir "$datadir" --arg pkey "$pkey" \
               --arg uid 0 --arg gid 0 > "$WORK/readd-$role.star"   # kurtosis-cdk runs cdk-erigon as root (cdk_erigon.star: User(uid=0, gid=0))
        cp "$WORK/readd-$role.star" "$(ev_file "erigon-readd-$role").star"
        rec "erigon-update-$role" kurtosis run --enclave "$ENCLAVE_NAME" "$WORK/readd-$role.star"
    else
        rec "erigon-update-$role" kurtosis service update "$ENCLAVE_NAME" "$svc" --image "$CDK_ERIGON_IMAGE_AFTER" --files "$files"
    fi
    refresh_ports
}

step_09_upgrade_erigon() {
    # Runbook step 3: erigon >= v2.61.24 (v2.61.22/23 added the FEP->PP L1 event handling) + PP config,
    # then stop dac, executors, provers, pool-manager (sequence-sender/aggregator already stopped).
    erigon_pp_update cdk-erigon-sequencer-001 sequencer
    wait_until "$T_SERVICE" 5 "sequencer RPC up on $CDK_ERIGON_IMAGE_AFTER" p_rpc_up "$L2_SEQ_RPC"
    rec erigon-effective-config-sequencer kexec cdk-erigon-sequencer-001 "grep -nE 'executor-urls|executor-strict|disable-virtual-counters|mock-witness-generation' /etc/cdk-erigon/config.yaml"

    erigon_pp_update cdk-erigon-rpc-001 rpc
    wait_until "$T_SERVICE" 5 "rpc node up on $CDK_ERIGON_IMAGE_AFTER" p_rpc_up "$L2_RPC"
    rec erigon-effective-config-rpc kexec cdk-erigon-rpc-001 "grep -nE 'pool-manager-url|disable-virtual-counters|mock-witness-generation' /etc/cdk-erigon/config.yaml"
    # The sequencer's datadir is a persistent kurtosis directory: history must be intact on the new image.
    [[ "$(cast block --rpc-url "$L2_SEQ_RPC" "$DEP1_BLOCK" --field hash)" == "$DEP1_BLOCK_HASH" ]] || { log_error "sequencer history changed across erigon upgrade"; exit 1; }
    # Runbook 3.4: stop dac, executors, provers, pool-manager (sequence-sender/aggregator stopped in step 7).
    rec stop-legacy-components kurtosis service stop "$ENCLAVE_NAME" cdk-data-availability-001 zkevm-stateless-executor-001 zkevm-prover-001 zkevm-pool-manager-001
    # Only now is "without executors" true: the chain must keep growing.
    local h; h=$(cast block-number --rpc-url "$L2_SEQ_RPC")
    wait_until 180 5 "sequencer producing blocks on $CDK_ERIGON_IMAGE_AFTER with executors, prover, DAC and pool manager stopped" p_block_gt "$L2_SEQ_RPC" "$h"
    # The rpc node has no persistent datadir in kurtosis-cdk: it re-syncs from the sequencer datastream.
    wait_until "$T_VERIFY" 10 "rpc node re-synced: has block $DEP1_BLOCK with its original hash" p_block_hash_eq "$L2_RPC" "$DEP1_BLOCK" "$DEP1_BLOCK_HASH"
    wait_until "$T_VERIFY" 10 "rpc node re-synced to the sequencer head" p_rpc_synced
    snapshot erigon-upgraded >/dev/null
    erigon_health erigon-upgraded
    # pool manager is gone: the rpc node must now forward user transactions to the sequencer itself
    l2_transfer_via rpc-pp-mode "$L2_RPC"
    rec erigon-version bash -c "cast rpc --rpc-url $L2_RPC web3_clientVersion; cast rpc --rpc-url $L2_SEQ_RPC web3_clientVersion"
}

aggkit_args() { jq -nc --arg name aggkit-001 --arg image "$AGGKIT_IMAGE" --arg cfg "$1" --argjson replace "$2" \
    '{name:$name, image:$image, config_artifact:$cfg, replace:$replace}'; }

step_10_aggkit_dry_run() {
    # Runbook prerequisite: aggkit (aggsender) in sync-only mode (DryRun=true) before the migration.
    render_aggkit_config "$WORK/aggkit-v1" 0 true
    rec aggkit-upload kurtosis files upload "$ENCLAVE_NAME" "$WORK/aggkit-v1" --name aggkit-config-v1
    # assets/aggkit.star: persistent /data, root user, RPC port (see the script header for why not `service add`)
    rec aggkit-add kurtosis run --enclave "$ENCLAVE_NAME" assets/aggkit.star "$(aggkit_args aggkit-config-v1 false)"
    refresh_ports
    wait_until "$T_SERVICE" 10 "aggkit RPC answering (aggsender running in DryRun mode)" p_rpc_alive "$AGGKIT_RPC"
    service_logs_to_evidence aggkit-dryrun aggkit-001
}

step_11_init_migration() {
    # Runbook step 4: Polygon (UPDATE_ROLLUP_ROLE) migrates the rollup to AggchainECDSAMultisig.
    # Precondition that failed in step 6 now holds:
    [[ "$(last_sequenced)" == "$(last_verified)" ]] || { log_error "sequenced != verified, cannot migrate"; exit 1; }
    local receipt; receipt=$(send_as_admin "$ROLLUP_MANAGER" 'initMigration(uint32,uint32,bytes)' "$ROLLUP_ID" "$ECDSA_TYPE_ID" "$MIGRATE_CALLDATA")
    echo "$receipt" | jq . > "$(ev_file initMigration-receipt).json"
    MIGRATION_BLOCK=$(jq -r '.blockNumber' <<< "$receipt" | xargs cast to-dec)
    [[ "$(jq -r .status <<< "$receipt")" =~ ^(0x1|1)$ ]] || { log_error "initMigration failed"; exit 1; }
    save_var MIGRATION_BLOCK
    rec post-migration-state bash -c "
      echo isRollupMigrating=\$(cast call --rpc-url $L1_RPC $ROLLUP_MANAGER 'isRollupMigrating(uint32)(bool)' $ROLLUP_ID)
      echo threshold=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'threshold()(uint256)')
      echo signers=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'getAggchainSigners()(address[])')
      echo aggchainManager=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'aggchainManager()(address)')
      echo AGGCHAIN_TYPE=\$(cast call --rpc-url $L1_RPC $ROLLUP_ADDR 'AGGCHAIN_TYPE()(bytes2)')
    "
    [[ "$(l1_call "$ROLLUP_MANAGER" 'isRollupMigrating(uint32)(bool)' "$ROLLUP_ID")" == "true" ]] || { log_error "isRollupMigrating is not true"; exit 1; }
    [[ "$(rd_field 11)" == "2" && "$(rd_field 10)" == "$ECDSA_TYPE_ID" ]] || { log_error "rollup not switched to ALGateway/$ECDSA_TYPE_ID"; exit 1; }
    snapshot migrated >/dev/null
    wait_until "$T_L1_FINALITY" 10 "L1 finality past migration block $MIGRATION_BLOCK" p_l1_finalized_ge "$MIGRATION_BLOCK"

    # cdk-erigon's L1 sequencer sync stage sees UpdateRollup(rollupID, newType). If the AddNewRollupType
    # event of that type was processed by >= v2.61.23 the stage logs "received UpdateRollupTopic for PP
    # rollup type, ignoring". If it was processed by an older version (here: the type was added while the
    # sequencer ran v2.61.20; Silicon: mainnet type 14 predates its upgrade) the stage has no PP marker
    # and logs "received UpdateRollupTopic for unknown rollup type" once. Either way the fork must stay
    # 12, block production must continue and the error must not repeat.
    wait_until 600 10 "cdk-erigon sequencer processed UpdateRollupTopic" p_logs_match cdk-erigon-sequencer-001 UpdateRollupTopic 5000
    klogs cdk-erigon-sequencer-001 -n 5000 --match UpdateRollupTopic | tee "$(ev_file erigon-UpdateRollupTopic).txt"
    # RPC nodes do not run the L1 sequencer sync stage (only SequencerZkStages wires it), so this file is
    # expected to stay empty; it is captured to prove exactly that.
    klogs cdk-erigon-rpc-001 -n 5000 --match UpdateRollupTopic 2>/dev/null | tee "$(ev_file erigon-rpc-UpdateRollupTopic).txt" || true
    local errs1 errs2 clean1 clean2
    errs1=$(klogs cdk-erigon-sequencer-001 -n 50000 --match 'unknown rollup type' 2>/dev/null | grep -c 'unknown rollup type' || true)
    clean1=$(klogs cdk-erigon-sequencer-001 -n 50000 --match 'L1 Sequencer sync finished' 2>/dev/null | grep -c 'L1 Sequencer sync finished' || true)
    [[ "$(l2_rpc_dec zkevm_getForkId)" == "12" ]] || { log_error "fork id changed after migration"; exit 1; }
    local h; h=$(l2_bn)
    wait_until 120 5 "L2 still producing blocks after migration" p_block_gt "$L2_RPC" "$h"
    sleep 60
    errs2=$(klogs cdk-erigon-sequencer-001 -n 50000 --match 'unknown rollup type' 2>/dev/null | grep -c 'unknown rollup type' || true)
    clean2=$(klogs cdk-erigon-sequencer-001 -n 50000 --match 'L1 Sequencer sync finished' 2>/dev/null | grep -c 'L1 Sequencer sync finished' || true)
    note erigon-UpdateRollupTopic "'unknown rollup type' log lines: $errs1 right after the event, $errs2 one minute later; 'L1 Sequencer sync finished' lines: $clean1 -> $clean2 (clean passes must continue); zkevm_getForkId=$(l2_rpc_dec zkevm_getForkId)"
    [[ "$errs2" == "$errs1" ]] || { log_error "sequencer keeps failing its L1 sync stage on the UpdateRollup event"; exit 1; }
    (( clean2 > clean1 )) || { log_error "sequencer L1 sync stage did not complete a clean pass after the migration event"; exit 1; }
    h=$(l2_bn)
    wait_until 120 5 "L2 still producing blocks one minute after migration" p_block_gt "$L2_RPC" "$h"
    erigon_health migrated
}

aggkit_reconfigure() { # aggkit_reconfigure <version> <max_l2_block> <dry_run>: new config, same persistent /data
    render_aggkit_config "$WORK/aggkit-$1" "$2" "$3"
    rec "aggkit-upload-$1" kurtosis files upload "$ENCLAVE_NAME" "$WORK/aggkit-$1" --name "aggkit-config-$1"
    rec "aggkit-replace-$1" kurtosis run --enclave "$ENCLAVE_NAME" assets/aggkit.star "$(aggkit_args "aggkit-config-$1" true)"
    refresh_ports
    wait_until "$T_SERVICE" 10 "aggkit RPC answering after reconfig ($1)" p_rpc_alive "$AGGKIT_RPC"
}

step_12_bootstrap_certificate() {
    # Runbook step 7: last verified batch -> last L2 block of it -> MaxL2BlockNumber; DryRun=false.
    local vb_hex vb; vb_hex=$(cast rpc --rpc-url "$L2_RPC" zkevm_verifiedBatchNumber | tr -d '"'); vb=$(cast to-dec "$vb_hex")
    local last_hash; last_hash=$(cast rpc --rpc-url "$L2_RPC" zkevm_getBatchByNumber "$vb_hex" | jq -r '.blocks[-1]')
    MAX_L2_BLOCK=$(cast block --rpc-url "$L2_RPC" "$last_hash" --field number)
    note max-l2-block "zkevm_verifiedBatchNumber=$vb lastBlockHash=$last_hash MaxL2BlockNumber=$MAX_L2_BLOCK (withdrawal block $DEP1_BLOCK must be > this)"
    (( DEP1_BLOCK > MAX_L2_BLOCK )) || { log_error "withdrawal block $DEP1_BLOCK is not after the verified boundary $MAX_L2_BLOCK"; exit 1; }
    # The bootstrap certificate must reproduce exactly the LER the legacy path settled.
    local l1_ler l2_ler; l1_ler=$(rd_field 4); l2_ler=$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'getRoot()(bytes32)' --block "$MAX_L2_BLOCK")
    note max-l2-block "L1 lastLocalExitRoot=$l1_ler  L2 bridge getRoot()@${MAX_L2_BLOCK}=$l2_ler"
    [[ "$l1_ler" == "$l2_ler" ]] || { log_error "LER mismatch at the verified boundary"; exit 1; }

    save_var MAX_L2_BLOCK
    aggkit_reconfigure v2 "$MAX_L2_BLOCK" false
    wait_until "$T_CERT" 15 "bootstrap certificate settled (isRollupMigrating -> false)" p_not_migrating
    rec agglayer-settled-after-bootstrap jsonrpc "$AGGLAYER_READRPC" interop_getLatestSettledCertificateHeader "[$L2_NETWORK_ID]"
    snapshot bootstrap-settled >/dev/null
    service_logs_to_evidence bootstrap aggkit-001 agglayer
}

step_13_normal_certificates() {
    # Runbook step 7.6: lift the block cap; the next certificates carry the exits from the rolled-back range.
    aggkit_reconfigure v3 0 false
    note ler-catch-up "current L2 LER $(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'getRoot()(bytes32)') must become the settled LER on L1 (compared live on every poll)"
    wait_until "$T_CERT" 15 "L1 settled LER catches up with the L2 bridge root (includes the in-gap withdrawal)" p_ler_synced
    note ler-catch-up "settled: L1 lastLocalExitRoot=$(rd_field 4) L2 getRoot()=$(cast call --rpc-url "$L2_RPC" "$L2_BRIDGE" 'getRoot()(bytes32)')"
    rec agglayer-settled-final jsonrpc "$AGGLAYER_READRPC" interop_getLatestSettledCertificateHeader "[$L2_NETWORK_ID]"
    snapshot pp-live >/dev/null
    # L1 -> L2 still works after the migration: the sequencer keeps injecting global exit roots in PP mode
    deposit_and_claim_on_l2 after-migration
    erigon_health pp-live
    service_logs_to_evidence pp-live aggkit-001 agglayer cdk-erigon-sequencer-001
}

step_14_claim_in_gap_withdrawal() {
    # The withdrawal made while verification was broken is now claimable on L1.
    rec claim-in-gap-l1 claim_on_l1 "$DEP1" in-gap
    rec claimed-check l1_call "$L1_BRIDGE" 'isClaimed(uint32,uint32)(bool)' "$DEP1" "$L2_NETWORK_ID"
    [[ "$(l1_call "$L1_BRIDGE" 'isClaimed(uint32,uint32)(bool)' "$DEP1" "$L2_NETWORK_ID")" == "true" ]] || { log_error "deposit $DEP1 not marked claimed on L1"; exit 1; }
    # Final invariants
    [[ "$(cast block --rpc-url "$L2_RPC" "$DEP1_BLOCK" --field hash)" == "$DEP1_BLOCK_HASH" ]] || { log_error "L2 history changed"; exit 1; }
    l2_transfer_via rpc-final "$L2_RPC"
    wait_until 120 5 "rpc node in step with the sequencer at the end" p_rpc_synced
    erigon_health final
    snapshot final >/dev/null
    rec summary bash -c "cat $EVIDENCE_DIR/*state-final.json"
}

# ================================================================================================
load_state
run_step 0  step_00_preflight               "preflight"
run_step 1  step_01_deploy                  "deploy Silicon-like cdk-erigon validium (fork 12) with kurtosis-cdk"
run_step 2  step_02_discover                "discover endpoints, contracts and keys"
run_step 3  step_03_baseline                "legacy path healthy: batches verified via cdk-node -> agglayer, withdrawal claimed"
run_step 4  step_04_break_settlement        "Polygon upgrades agglayer -> interop_sendTx disabled; gap opens; withdrawal in the gap"
run_step 5  step_05_polygon_prep_rollup_type "Polygon prep: AggchainECDSAMultisig rollup type + gateway PP route"
run_step 6  step_06_show_blocker            "initMigration reverts with AllSequencedMustBeVerified()"
run_step 7  step_07_stop_sequencing         "operator stops sequencing"
run_step 8  step_08_rollback                "operator rolls back unverified batches on L1 (no L2 unwind)"
run_step 9  step_09_upgrade_erigon          "operator upgrades cdk-erigon and switches it to PP mode, stops legacy components"
run_step 10 step_10_aggkit_dry_run          "operator starts aggkit aggsender in DryRun mode"
run_step 11 step_11_init_migration          "Polygon: initMigration -> AggchainECDSAMultisig"
run_step 12 step_12_bootstrap_certificate   "aggsender: bootstrap certificate up to the last verified block"
run_step 13 step_13_normal_certificates     "aggsender: normal certificates carry the in-gap exits"
run_step 14 step_14_claim_in_gap_withdrawal "the in-gap withdrawal is claimable on L1"
