#!/usr/bin/env bats
# bats file_tags=agglayer
#
# agglayer 0.6 per-epoch certificate rate-limiting removal.
#
# 0.5.x throttled certificate submission with a per-epoch rate limit. 0.6 replaces that with the new
# settlement service and defaults the send-tx rate limit to "unlimited" (see kurtosis-cdk
# test-configs/agglayer-060-pp.yml). These tests assert (1) the node is configured with the
# per-epoch cap removed, and (2) settlement keeps advancing epoch after epoch without being throttled
# to a stall.
#
# NOTE on scope: the aggsender (aggkit 0.5.4) emits exactly one certificate per epoch, so ">1 cert
# accepted within a single epoch" cannot be produced from natural traffic without the external
# certificate-spammer tool (not available here). The definitive assertion is therefore the config
# (send-tx unlimited, no active per-interval cap); the settlement-advance test corroborates that no
# throttling stall is in effect.

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    export network_id="${l2_network_id:-1}"
    timeout="${SETTLE_TIMEOUT:-1200}"
    retry_interval="${SETTLE_RETRY_INTERVAL:-10}"
    export timeout retry_interval
}

setup() {
    # bats does not propagate functions sourced in setup_file to test bodies; source the shared
    # helper libraries per-test so their functions are available inside each @test.
    # shellcheck source=core/helpers/agglayer-certificates-checks.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/agglayer-certificates-checks.bash"
    # shellcheck source=core/helpers/scripts/kurtosis-helpers.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/scripts/kurtosis-helpers.bash"
}

fail() { echo "❌ $*" >&3; exit 1; }

# bats test_tags=agglayer-rate-limiting
@test "agglayer removes the per-epoch certificate rate limit (send-tx unlimited)" {
    # Reading the node's own config requires a kurtosis-managed agglayer service.
    if [[ -n "${AGGLAYER_READRPC_URL:-}" || -n "${AGGLAYER_RPC_URL:-}" ]]; then
        skip "requires a kurtosis-managed agglayer service (external RPC override is set)"
    fi

    # kurtosis_download_file_exec_method ends in a pipe, so its assignment always exits 0 (bats has
    # no pipefail); check the captured content is non-empty instead of relying on `|| fail`.
    local cfg
    cfg=$(kurtosis_download_file_exec_method "$kurtosis_enclave_name" agglayer /etc/agglayer/config.toml)
    [[ -n "$cfg" ]] || fail "could not read agglayer config.toml from the running node"

    # The send-tx rate limit must be unlimited (per-epoch cap removed).
    if ! echo "$cfg" | grep -Eq '^[[:space:]]*send-tx[[:space:]]*=[[:space:]]*"unlimited"'; then
        echo "$cfg" | grep -A3 '\[rate-limiting\]' >&3 || true
        fail "expected [rate-limiting] send-tx = \"unlimited\" in agglayer config"
    fi

    # There must be NO active (uncommented) per-interval cap re-enabling throttling.
    if echo "$cfg" | grep -Eq '^[[:space:]]*max-per-interval[[:space:]]*='; then
        fail "an active per-interval rate-limit cap is set — per-epoch rate limiting is NOT removed"
    fi
    echo "✅ agglayer configured with per-epoch rate limiting removed (send-tx unlimited)" >&3
}

# bats test_tags=agglayer-rate-limiting
@test "certificate settlement advances across multiple epochs without throttling" {
    check_for_latest_settled_cert || fail "no settled certificate to start from"

    read -r e0 h0 <<<"$(settled_epoch_and_height "$network_id")"
    echo "ℹ️ initial settled epoch=$e0 height=$h0" >&3
    [[ "$e0" != "null" && "$h0" != "null" ]] || fail "could not read initial settled epoch/height"

    # A network that was still per-epoch rate-limited would stall; require at least two further
    # epochs to settle (with the height advancing) within the timeout.
    local target_epoch=$((e0 + 2)) start=$SECONDS e h
    while true; do
        read -r e h <<<"$(settled_epoch_and_height "$network_id")"
        if [[ "$e" != "null" && "$h" != "null" ]] && (( e >= target_epoch && h > h0 )); then
            echo "✅ settlement advanced to epoch=$e height=$h (from epoch=$e0 height=$h0)" >&3
            return 0
        fi
        (( SECONDS - start >= timeout )) && fail "settlement did not advance ${target_epoch}-epoch target within ${timeout}s (stuck at epoch=$e height=$h)"
        sleep "$retry_interval"
    done
}
