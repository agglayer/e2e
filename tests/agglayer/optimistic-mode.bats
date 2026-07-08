#!/usr/bin/env bats
# bats file_tags=agglayer
#
# agglayer 0.6 AggchainFEP optimistic mode.
#
# An AggchainFEP rollup can be toggled into "optimistic mode" by its optimisticModeManager (the
# sovereign admin). In optimistic mode the aggsender settles certificates without a full execution
# proof, so settlement continues (and is faster) while proving is bypassed. These tests assert the
# on-chain toggle works and that settlement keeps advancing across the toggle.
#
# Enclave: FEP (kurtosis-cdk test-configs/agglayer-060-fep.yml, op-succinct mock prover). The file
# self-skips on non-FEP networks (the rollup has no optimisticMode() function there). FEP settlement
# is slower/flakier locally than PP, so the settlement-advance assertions use generous timeouts.

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    export network_id="${l2_network_id:-1}"
    # FEP settlement is slow locally (finality bootstrap); allow a wide window.
    timeout="${SETTLE_TIMEOUT:-1800}"
    retry_interval="${SETTLE_RETRY_INTERVAL:-15}"
    export timeout retry_interval

    # Self-skip unless this is an AggchainFEP rollup (only FEP exposes optimisticMode()).
    if ! cast call "$rollup_address" 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url" >/dev/null 2>&1; then
        export AGGLAYER_OPTIMISTIC_SUPPORTED=0
    else
        export AGGLAYER_OPTIMISTIC_SUPPORTED=1
    fi
}

teardown_file() {
    # Always leave optimistic mode DISABLED (matches a fresh deploy / the CI end-state).
    if [[ "${AGGLAYER_OPTIMISTIC_SUPPORTED:-0}" == "1" ]]; then
        if [[ "$(cast call "$rollup_address" 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url" 2>/dev/null)" == "true" ]]; then
            cast send "$rollup_address" 'disableOptimisticMode()' \
                --rpc-url "$l1_rpc_url" --private-key "$l2_sovereignadmin_private_key" >/dev/null 2>&1 || true
        fi
    fi
}

setup() {
    # bats does not propagate functions sourced in setup_file to test bodies; source the shared
    # cert helpers per-test so their functions are available inside each @test.
    # shellcheck source=core/helpers/agglayer-certificates-checks.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/agglayer-certificates-checks.bash"
}

fail() { echo "❌ $*" >&3; exit 1; }

_optimistic_mode() { cast call "$rollup_address" 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url"; }

_set_optimistic_mode() {  # $1 = enable|disable
    cast send "$rollup_address" "${1}OptimisticMode()" \
        --rpc-url "$l1_rpc_url" --private-key "$l2_sovereignadmin_private_key" >/dev/null \
        || fail "failed to ${1} optimistic mode"
}

# bats test_tags=agglayer-optimistic
@test "optimistic mode can be enabled and disabled by the sovereign admin" {
    [[ "${AGGLAYER_OPTIMISTIC_SUPPORTED:-0}" == "1" ]] || skip "not an AggchainFEP rollup (optimisticMode() unavailable)"

    _set_optimistic_mode enable
    [[ "$(_optimistic_mode)" == "true" ]] || fail "optimisticMode() did not become true after enable"
    echo "✅ optimistic mode enabled" >&3

    _set_optimistic_mode disable
    [[ "$(_optimistic_mode)" == "false" ]] || fail "optimisticMode() did not become false after disable"
    echo "✅ optimistic mode disabled" >&3
}

# bats test_tags=agglayer-optimistic
@test "certificate settlement advances while optimistic mode is enabled" {
    [[ "${AGGLAYER_OPTIMISTIC_SUPPORTED:-0}" == "1" ]] || skip "not an AggchainFEP rollup (optimisticMode() unavailable)"

    # Establish a baseline settled cert (FEP first-settlement can be slow).
    check_for_latest_settled_cert || fail "no settled certificate before enabling optimistic mode"
    local pre_id; pre_id=$(latest_settled_cert_id "$network_id")

    _set_optimistic_mode enable
    [[ "$(_optimistic_mode)" == "true" ]] || fail "optimisticMode() did not become true"

    # In optimistic mode a new certificate must still settle (proving bypassed → forward progress).
    wait_for_new_settled_cert "$pre_id" "$network_id" >/dev/null || fail "no new certificate settled while optimistic mode enabled"
    echo "✅ settlement advanced while optimistic mode enabled" >&3

    # Restore, and confirm settlement still advances after leaving optimistic mode.
    local mid_id; mid_id=$(latest_settled_cert_id "$network_id")
    _set_optimistic_mode disable
    [[ "$(_optimistic_mode)" == "false" ]] || fail "optimisticMode() did not become false"
    wait_for_new_settled_cert "$mid_id" "$network_id" >/dev/null || fail "no new certificate settled after disabling optimistic mode"
    echo "✅ settlement advanced after disabling optimistic mode" >&3
}
