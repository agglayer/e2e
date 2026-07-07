#!/usr/bin/env bash
#
# upgrade-agglayer-060 — verify an agglayer NODE upgrade (stable -> 0.6.0-rc.x) on a live
# Kurtosis-CDK PP devnet, checking that bridging and certificate settlement work both before and
# after the upgrade.
#
# Flow:
#   1. Bring up a PP (pessimistic) OP-stack devnet on the STABLE agglayer image.
#   2. Verify bridging + certificate settlement BEFORE the upgrade.
#   3. Settlement gate (QUIESCE_BEFORE_UPGRADE). Default true: drain all in-flight certificates to
#      null before the swap. rc.4 migrates the DB schema and resumes its OWN (0.6, job-id-tracked)
#      settlement jobs, but it cannot resume a 0.5.x certificate that was already mid-settlement
#      (no job-id -> InError), so a 0.5.1->0.6 upgrade must quiesce first. Set false to swap with
#      settlement in-flight (opt-in; see README).
#   4. Swap the agglayer node container to the RC image, preserving its /etc/agglayer bind-mount
#      (config + keystore(s) + RocksDB). Opening the 0.5.x DB with 0.6 runs the storage schema
#      migration (adds settlement column families).
#   5. Verify migration succeeded and settled state was preserved.
#   6. Re-verify bridging + settlement AFTER the upgrade (a NEW cert must be produced and settled —
#      forward progress past the migration; the aggsender is restarted first if it was quiesced).
#
# The scenario tears down its enclave on exit (set KEEP_ENCLAVE=true to keep it for debugging).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SCRIPT_DIR"

# shellcheck source=../common/load-env.sh
source ../common/load-env.sh
load_env

# ---- configuration (with defaults) ------------------------------------------------------------
: "${ENCLAVE_NAME:=agglayer-upgrade-060}"
: "${KURTOSIS_CDK:=${HOME}/kurtosis-cdk}"
: "${AGGLAYER_IMAGE_STABLE:=ghcr.io/agglayer/agglayer:0.5.1}"
: "${AGGLAYER_IMAGE_RC:=ghcr.io/agglayer/agglayer:0.6.0-rc.4}"
: "${AGGLAYER_READRPC_HOST_PORT:=14444}"
: "${SETTLE_TIMEOUT:=1200}"
: "${SETTLE_RETRY_INTERVAL:=20}"
: "${QUIESCE_TIMEOUT:=1200}"
# Default true: drain all in-flight certificates before the swap. rc.4 cannot resume a certificate
# that was already mid-settlement on 0.5.x (no settlement job-id in the migrated DB -> InError),
# so a 0.5.1->0.6 upgrade must quiesce first. Set false to swap with settlement in-flight (opt-in;
# fails for 0.5.x->0.6 carry-over on rc.4, expected OK for 0.6.x->0.6.y). See README.
: "${QUIESCE_BEFORE_UPGRADE:=true}"
: "${KEEP_ENCLAVE:=false}"
: "${POLYCLI_VERSION:=v0.1.90}"

export ENCLAVE_NAME PROJECT_ROOT
export BATS_LIB_PATH="$PROJECT_ROOT/core/helpers/lib"
export PATH="$PATH:$HOME/go/bin"

# kurtosis_enclave_name, timeout and retry_interval are globals read directly by the sourced
# certificate-settlement helper (core/helpers/agglayer-certificates-checks.bash), not passed as
# args — hence the SC2034 suppressions (shellcheck cannot follow the runtime $PROJECT_ROOT path).
# shellcheck disable=SC2034
kurtosis_enclave_name="$ENCLAVE_NAME"
docker_network_name="kt-$ENCLAVE_NAME"
agglayer_readrpc_url_host="http://127.0.0.1:${AGGLAYER_READRPC_HOST_PORT}"

# shellcheck disable=SC2034
timeout="$SETTLE_TIMEOUT"
# shellcheck disable=SC2034
retry_interval="$SETTLE_RETRY_INTERVAL"
source "$PROJECT_ROOT/core/helpers/agglayer-certificates-checks.bash"

log()  { echo -e "\n\033[1;34m>> $*\033[0m"; }
fail() { echo -e "\033[1;31mFAIL: $*\033[0m" >&2; exit 1; }

# ---- teardown ---------------------------------------------------------------------------------
cleanup() {
    local ec=$?
    if [[ "$KEEP_ENCLAVE" == "true" ]]; then
        echo ">> KEEP_ENCLAVE=true: leaving enclave '$ENCLAVE_NAME' and container 'agglayer' up."
    else
        echo ">> Teardown (exit $ec): removing relaunched container + enclave '$ENCLAVE_NAME'."
        docker rm -f agglayer >/dev/null 2>&1 || true
        kurtosis enclave rm -f "$ENCLAVE_NAME" >/dev/null 2>&1 || true
    fi
    exit "$ec"
}
trap cleanup EXIT

# ---- preflight --------------------------------------------------------------------------------
preflight() {
    log "Preflight checks"
    for bin in kurtosis docker cast bats jq polycli yq; do
        command -v "$bin" >/dev/null 2>&1 || fail "required tool not found on PATH: $bin"
    done
    docker info >/dev/null 2>&1 || fail "docker daemon is not reachable — start Docker first"
    local have; have="$(polycli version 2>&1 | head -1 || true)"
    case "$have" in
        *"$POLYCLI_VERSION"*) : ;;
        *) echo "WARNING: polycli version mismatch (want $POLYCLI_VERSION, got: $have). Bridge/claim flags may differ." >&2 ;;
    esac
    echo "OK"
}

# Return the running kurtosis-managed agglayer container name (agglayer--<uuid>).
kurtosis_agglayer_container() {
    local uuid
    uuid="$(kurtosis service inspect "$ENCLAVE_NAME" agglayer --full-uuid | grep UUID | sed 's/.*: //')"
    echo "agglayer--$uuid"
}

# Run the CI agglayer bats suite (bridging L1<->L2 + interop_* settlement assertions).
# bridges.bats reads core/contracts/bin/*.bin via a repo-root-relative path, so bats must run from
# PROJECT_ROOT. Use a subshell so the caller's CWD stays at $SCRIPT_DIR (chain.yml / load-env rely
# on it).
verify_bridging_and_rpc() {
    log "Bridging + agglayer-RPC verification ($1)"
    ( cd "$PROJECT_ROOT" && bats "tests/agglayer/bridges.bats" \
         "tests/agglayer/rpc-tests.bats" \
         --filter-tags agglayer )
}

# Confirm settlement is live: a settled cert exists and the settled height is advancing.
verify_settlement_live() {
    log "Settlement liveness verification ($1)"
    check_for_latest_settled_cert || fail "no settled certificate ($1)"
    check_height_increase || fail "settled height not advancing ($1)"
}

settled_height() {
    cast rpc --rpc-url "$(_agglayer_readrpc_url)" \
        interop_getLatestSettledCertificateHeader 1 2>/dev/null | jq -r '.height // 0'
}

# ===============================================================================================
preflight

# ---- 1. bring up the base network on the STABLE image -----------------------------------------
log "Launching PP devnet on $AGGLAYER_IMAGE_STABLE (kurtosis-cdk: $KURTOSIS_CDK)"
effective_args="$(mktemp -t agglayer-060-chain.XXXX.yml)"
# Keep AGGLAYER_IMAGE_STABLE authoritative over chain.yml's documented default.
sed "s|^\( *agglayer_image: *\).*|\1${AGGLAYER_IMAGE_STABLE}|" chain.yml > "$effective_args"
kurtosis run --enclave "$ENCLAVE_NAME" --args-file "$effective_args" "$KURTOSIS_CDK"

running_image="$(docker inspect --format '{{.Config.Image}}' "$(kurtosis_agglayer_container)")"
echo "agglayer running image: $running_image"
[[ "$running_image" == "$AGGLAYER_IMAGE_STABLE" ]] || fail "expected $AGGLAYER_IMAGE_STABLE, got $running_image"

# ---- 2. verify BEFORE the upgrade -------------------------------------------------------------
# Pre-swap the node is still Kurtosis-managed, so the helpers resolve the RPC via kurtosis.
unset AGGLAYER_RPC_URL AGGLAYER_READRPC_URL || true
verify_bridging_and_rpc "before upgrade"
verify_settlement_live "before upgrade"
pre_height="$(settled_height)"
echo "pre-upgrade settled height: $pre_height"

# ---- 3. settlement gate before the upgrade ----------------------------------------------------
# Default (true): drain all in-flight certificates before the swap. rc.4 applies the declared
# RocksDB column-family options when reopening the DB and resumes its own job-id-tracked settlement
# jobs, but it canNOT resume a 0.5.x certificate that was already mid-settlement (no settlement
# job-id in the migrated DB -> InError, stalling settlement), so a 0.5.1->0.6 upgrade must quiesce
# first. Set false to swap with settlement IN-FLIGHT (opt-in; verified to fail for 0.5.x carry-over
# on rc.4, expected to work for 0.6.x->0.6.y where job-ids already exist).
quiesced=false
if [[ "$QUIESCE_BEFORE_UPGRADE" == "true" ]]; then
    log "Quiescing settlement before the upgrade (draining in-flight certificates)"
    # Stop the aggsender so no NEW certificates are produced; keep the agglayer node up so any
    # already-pending certificate finishes settling. Best-effort stop of an optional bridge spammer.
    kurtosis service stop "$ENCLAVE_NAME" bridge-spammer-001 >/dev/null 2>&1 || true
    kurtosis service stop "$ENCLAVE_NAME" aggkit-001 || fail "could not stop aggsender aggkit-001"
    # shellcheck disable=SC2034
    timeout="$QUIESCE_TIMEOUT"
    wait_for_null_cert || fail "in-flight settlement did not drain within ${QUIESCE_TIMEOUT}s — refusing to upgrade (would stall on 0.6.0-rc.2)"
    # shellcheck disable=SC2034
    timeout="$SETTLE_TIMEOUT"
    quiesced=true
    echo "settlement quiesced: latest pending certificate is null"
else
    log "Upgrading with settlement IN-FLIGHT (QUIESCE_BEFORE_UPGRADE=false) — exercising rc.4+ inflight migration"
    # Keep the aggsender + spammer running so a certificate is mid-settlement at swap time. Wait
    # (best-effort) for a non-null pending certificate so the in-flight path is actually covered;
    # proceed regardless if the network happens to be idle at swap time.
    # shellcheck disable=SC2034
    timeout="$QUIESCE_TIMEOUT"
    wait_for_non_null_cert || echo "note: no pending certificate appeared within ${QUIESCE_TIMEOUT}s; upgrading anyway (clean-DB migration only)"
    # shellcheck disable=SC2034
    timeout="$SETTLE_TIMEOUT"
    inflight_cert="$(cast rpc --rpc-url "$(_agglayer_readrpc_url)" interop_getLatestPendingCertificateHeader 1 2>/dev/null | jq -c '.' 2>/dev/null || echo null)"
    echo "pending certificate at swap time: $inflight_cert"
fi

# ---- 4. swap the agglayer node to the RC image ------------------------------------------------
log "Upgrading agglayer node -> $AGGLAYER_IMAGE_RC"
kurtosis_container="$(kurtosis_agglayer_container)"
# Preserve the /etc/agglayer bind-mount (config + keystore(s) + RocksDB storage/) and any
# prover/backtrace env from the original container.
etc_agglayer="$(docker inspect "$kurtosis_container" | jq -r '.[0].Mounts[] | select(.Destination == "/etc/agglayer") | .Source')"
[[ -n "$etc_agglayer" && "$etc_agglayer" != "null" ]] || fail "could not find /etc/agglayer mount source on $kurtosis_container"
echo "preserved /etc/agglayer mount: $etc_agglayer"
mapfile -t env_args < <(docker inspect "$kurtosis_container" \
    | jq -r '.[0].Config.Env[] | select(test("^(NETWORK_PRIVATE_KEY|SP1_PRIVATE_KEY|NETWORK_RPC_URL|RUST_BACKTRACE)=")) | "--env\n" + .')

# Stop the old Kurtosis-managed node (freeing the "agglayer" network alias), then relaunch the RC
# image on the same enclave network. There is no standalone agglayer-prover service to update on
# current kurtosis-cdk — the node runs its prover inline. Match kurtosis-cdk's launch exactly:
# entrypoint /usr/local/bin/agglayer, cmd `run --cfg /etc/agglayer/config.toml`.
kurtosis service stop "$ENCLAVE_NAME" agglayer || fail "could not stop the kurtosis agglayer service"
docker run --detach \
    --network "$docker_network_name" \
    --name agglayer \
    -p "${AGGLAYER_READRPC_HOST_PORT}:4444" \
    -v "${etc_agglayer}:/etc/agglayer" \
    "${env_args[@]}" \
    --entrypoint /usr/local/bin/agglayer \
    "$AGGLAYER_IMAGE_RC" \
    run --cfg /etc/agglayer/config.toml

# From here on the node is outside Kurtosis's control; point the helpers/tests at the host port.
export AGGLAYER_RPC_URL="$agglayer_readrpc_url_host"
export AGGLAYER_READRPC_URL="$agglayer_readrpc_url_host"

# ---- 5. migration + startup check -------------------------------------------------------------
log "Waiting for the RC node to open the migrated DB and serve RPC"
deadline=$((SECONDS + 300))
until cast rpc --rpc-url "$AGGLAYER_READRPC_URL" interop_getEpochConfiguration >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        docker logs --tail 200 agglayer || true
        fail "RC agglayer did not become ready within 300s"
    fi
    sleep 5
done
# In quiesced mode an "inflight" mention flags the rc.2 stall we guarded against; in the default
# in-flight mode it is the expected migration/resume path, so only panic/FATAL are fatal there.
fatal_log_pat='panic|FATAL'
[[ "$quiesced" == "true" ]] && fatal_log_pat='panic|inflight|FATAL'
if docker logs agglayer 2>&1 | grep -qiE "$fatal_log_pat"; then
    docker logs --tail 200 agglayer || true
    fail "RC agglayer logged a fatal error (matched /$fatal_log_pat/)"
fi
docker logs agglayer 2>&1 | grep -iE 'migrat' | tail -20 || true
post_up_height="$(settled_height)"
echo "post-upgrade settled height (pre-restart): $post_up_height"
(( post_up_height >= pre_height )) || fail "settled height regressed after migration ($post_up_height < $pre_height)"

# ---- 6. verify AFTER the upgrade --------------------------------------------------------------
log "Re-verifying bridging + settlement after the upgrade"
# Only restart the aggsender/spammer if we quiesced them; in the default in-flight path they were
# left running and reconnect to the relaunched node on their own.
if [[ "$quiesced" == "true" ]]; then
    kurtosis service start "$ENCLAVE_NAME" aggkit-001 || fail "could not restart aggsender aggkit-001"
    kurtosis service start "$ENCLAVE_NAME" bridge-spammer-001 >/dev/null 2>&1 || true
fi
verify_bridging_and_rpc "after upgrade"
verify_settlement_live "after upgrade"

log "SUCCESS: agglayer upgrade ${AGGLAYER_IMAGE_STABLE} -> ${AGGLAYER_IMAGE_RC} verified (bridging + settlement OK before and after)."
