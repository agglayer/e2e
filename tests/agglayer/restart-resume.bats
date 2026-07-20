#!/usr/bin/env bats
# bats file_tags=agglayer
#
# agglayer 0.6 settlement-job persistence across a node restart.
#
# agglayer 0.6 tracks each certificate's settlement as a job-id persisted in RocksDB (the
# settlement_attempt_* column families, agglayer #1630/#1635). A node restart must reopen that DB
# with the declared column options and RESUME the in-flight/settled state — certificates must not be
# parked InError and settlement must keep advancing. This is the single-node analogue of the
# 0.5->0.6 upgrade's job-id concern, and a direct regression test for the rc.5 settlement-storage fix.

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    export network_id="${l2_network_id:-1}"
    # globals consumed by the shared cert-wait helpers
    timeout="${SETTLE_TIMEOUT:-1200}"
    retry_interval="${SETTLE_RETRY_INTERVAL:-10}"
    export timeout retry_interval
}

setup() {
    # bats does not propagate functions sourced in setup_file to test bodies, so source the shared
    # helper libraries here (per-test) to make their functions available inside each @test.
    # shellcheck source=core/helpers/agglayer-certificates-checks.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/agglayer-certificates-checks.bash"
    # shellcheck source=core/helpers/scripts/kurtosis-helpers.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/scripts/kurtosis-helpers.bash"
}

fail() { echo "❌ $*" >&3; exit 1; }

# bats test_tags=agglayer-restart
@test "settlement resumes after an agglayer node restart (0.6 settlement job-id persistence)" {
    # This test restarts the kurtosis-managed `agglayer` service, so it cannot run against an
    # externally-relaunched node (e.g. the upgrade scenario's docker-run node); skip if overridden.
    if [[ -n "${AGGLAYER_READRPC_URL:-}" || -n "${AGGLAYER_RPC_URL:-}" ]]; then
        skip "requires a kurtosis-managed agglayer service (external RPC override is set)"
    fi

    # 1. Baseline: a certificate has settled and settlement is live.
    check_for_latest_settled_cert || fail "no baseline settled certificate before restart"
    local pre_id pre_height
    pre_id=$(latest_settled_cert_id "$network_id")
    pre_height=$(settled_epoch_and_height "$network_id" | awk '{print $2}')
    echo "ℹ️ baseline settled cert: id=$pre_id height=$pre_height" >&3
    [[ "$pre_id" != "null" ]] || fail "baseline settled certificate id is null"

    # 2. Restart the agglayer node (stop, then start the kurtosis service).
    update_kurtosis_service_state agglayer stop || fail "could not stop agglayer service"
    update_kurtosis_service_state agglayer start || fail "could not start agglayer service"

    # 3. Wait for the node to reopen its DB and serve RPC again. _agglayer_readrpc_url re-resolves
    #    the (possibly reassigned) host port on every call, so it follows the restarted service.
    local start=$SECONDS
    until cast rpc --rpc-url "$(_agglayer_readrpc_url)" interop_getEpochConfiguration >/dev/null 2>&1; do
        (( SECONDS - start > 300 )) && fail "agglayer did not serve RPC within 300s after restart"
        sleep 5
    done
    echo "ℹ️ agglayer RPC is back after restart" >&3

    # 4. Settlement must RESUME: a NEW certificate settles after the restart (persisted job-ids let
    #    the node continue rather than stall), and the settled height advances past the baseline.
    wait_for_new_settled_cert "$pre_id" "$network_id" >/dev/null || fail "no new certificate settled after restart"
    check_height_increase || fail "settled height did not advance after restart"

    # 5. No certificate was parked InError as a result of the restart.
    local st; st=$(latest_known_cert_status "$network_id")
    echo "ℹ️ latest known cert status after restart: $st" >&3
    [[ "$st" != *"InError"* ]] || fail "a certificate is InError after the restart: $st"

    # 6. Explicit no-regression of the settled height across the restart.
    local post_height; post_height=$(settled_epoch_and_height "$network_id" | awk '{print $2}')
    echo "ℹ️ post-restart settled height: $post_height (baseline $pre_height)" >&3
    (( post_height >= pre_height )) || fail "settled height regressed after restart ($post_height < $pre_height)"
}
