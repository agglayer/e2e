#!/usr/bin/env bats
# bats file_tags=agglayer
#
# agglayer 0.6 ecdsa-multisig aggchain: AggSender signer committee + threshold.
#
# The ecdsa-multisig consensus (AggchainECDSAMultisig) registers a signer committee and a signing
# threshold on the rollup contract; certificates must carry a valid committee signature before
# agglayer accepts and settles them. These tests assert the on-chain committee/threshold are
# configured consistently (and match the deployment parameters) and that a multisig-signed
# certificate actually settles.
#
# Enclave: ecdsa-multisig (kurtosis-cdk .github/tests/op-reth/sovereign-ecdsa-multisig.yml —
# use_agg_sender_validator: True, total 1, threshold 1). The file self-skips on non-ecdsa-multisig
# rollups (getAggchainSignerInfos() reverts / returns no signers there).

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    export network_id="${l2_network_id:-1}"
    timeout="${SETTLE_TIMEOUT:-1200}"
    retry_interval="${SETTLE_RETRY_INTERVAL:-10}"
    export timeout retry_interval

    # Deployment intent (for cross-checking the on-chain committee). Best-effort: never let a
    # download failure abort setup_file (which would fail every test instead of letting them self-skip).
    local crp
    crp=$(curl -s "$(kurtosis port print "$kurtosis_enclave_name" contracts-001 http)/opt/zkevm/create_rollup_parameters.json" 2>/dev/null || true)
    export expected_threshold="$(echo "$crp" | jq -r '.aggchainParams.threshold // empty' 2>/dev/null)"
    export expected_signers="$(echo "$crp" | jq -r '(.aggchainParams.signers // []) | length' 2>/dev/null)"
}

setup() {
    # shellcheck source=core/helpers/agglayer-certificates-checks.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/agglayer-certificates-checks.bash"
}

fail() { echo "❌ $*" >&3; exit 1; }

# Echo the committee signer addresses (one per line) from the AggchainECDSAMultisig rollup contract.
_committee_signers() {
    cast call "$rollup_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url" 2>/dev/null \
        | grep -oiE '0x[0-9a-f]{40}'
}

# bats test_tags=agglayer-multisig
@test "ecdsa-multisig rollup exposes a consistent signer committee and threshold" {
    local signers count
    # `|| true`: _committee_signers ends in `grep`, which exits 1 when there are no matches (any
    # non-ecdsa-multisig rollup). Without this, the assignment would ABORT the test instead of
    # letting it self-skip below.
    signers=$(_committee_signers || true)
    count=$(echo "$signers" | grep -c '0x' || true)
    [[ "$count" -ge 1 ]] || skip "no ecdsa-multisig signer committee on this rollup (not an ecdsa-multisig aggchain)"
    echo "ℹ️ committee has $count signer(s):" >&3
    echo "$signers" >&3

    # No zero-address signers.
    if echo "$signers" | grep -qiE '^0x0{40}$'; then
        fail "committee contains the zero address as a signer"
    fi

    # Threshold must be sane: 1 <= threshold <= committee size.
    local threshold
    threshold=$(cast call "$rollup_address" "threshold()(uint256)" --rpc-url "$l1_rpc_url" 2>/dev/null | awk '{print $1}')
    [[ -n "$threshold" ]] || fail "could not read multisig threshold() from the rollup"
    echo "ℹ️ multisig threshold: $threshold (committee size $count)" >&3
    (( threshold >= 1 )) || fail "threshold ($threshold) must be >= 1"
    (( threshold <= count )) || fail "threshold ($threshold) exceeds committee size ($count)"

    # On-chain committee must match the deployment parameters (create_rollup_parameters.json).
    if [[ -n "${expected_signers:-}" && "$expected_signers" != "null" ]]; then
        (( count == expected_signers )) || fail "on-chain committee size ($count) != deployed ($expected_signers)"
    fi
    if [[ -n "${expected_threshold:-}" && "$expected_threshold" != "null" ]]; then
        (( threshold == expected_threshold )) || fail "on-chain threshold ($threshold) != deployed ($expected_threshold)"
    fi
    echo "✅ committee/threshold consistent and match deployment params" >&3
}

# bats test_tags=agglayer-multisig
@test "a multisig-signed certificate is accepted and settles" {
    local count; count=$(_committee_signers | grep -c '0x' || true)
    [[ "$count" -ge 1 ]] || skip "no ecdsa-multisig signer committee on this rollup"

    # With the committee threshold satisfied by the running validator(s), the aggsender's
    # multisig-signed certificate is accepted by agglayer and settles, and settlement keeps advancing.
    check_for_latest_settled_cert || fail "no multisig-signed certificate settled"
    check_height_increase || fail "settled height did not advance for the multisig aggchain"
}
