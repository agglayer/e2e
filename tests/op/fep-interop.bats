#!/usr/bin/env bats
# bats file_tags=op-fep
# shellcheck disable=SC2154,SC2034
#
# Phase-1 "fast interop" (aggchain-proof / FEP) end-to-end checks.
#
# Complements tests/op/optimistic-mode.bats (which exercises the optimistic-mode
# TOGGLE) by asserting the *default* fast-interop state and the interop certificate
# surface that nothing else proves today:
#   - the chain's aggsender runs in AggchainProof (FEP) mode,
#   - an aggchain-proof certificate genuinely reaches Settled with coherent fields,
#   - the settlement is anchored by a real, successful L1 transaction,
#   - the interop_* read RPCs are self-consistent (certificate id round-trips).
#
# Read-only (no bridging, no funding, no spammer binary): cast + jq only, so it is
# fast and CI-appropriate against a kurtosis-cdk op-succinct FEP enclave
# (consensus_contract_type=fep, op_succinct_mock=true).

setup() {
    export DISABLE_FUNDING=true   # read-only test: skip wallet funding (agglayer-cdk-common-setup.bash)
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup    # -> aggsender_mode, aggsender_mode_is_fep, l2_rpc_network_id, l1_rpc_url

    # agglayer-certificates-checks.bash keys off $kurtosis_enclave_name; the common
    # setup only exports ENCLAVE_NAME, so mirror it.
    export kurtosis_enclave_name="${kurtosis_enclave_name:-$ENCLAVE_NAME}"
    load '../../core/helpers/agglayer-certificates-checks.bash'

    agglayer_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)"
    export agglayer_rpc_url

    # FEP first-cert settlement is slow from a cold enclave (finality warm-up + proving).
    # The reusable e2e workflow runs bats immediately after `kurtosis run` with no
    # pre-wait, so give the cert-check helpers generous headroom. They short-circuit
    # instantly once a settled cert exists, so a warm enclave stays fast.
    timeout=${TIMEOUT:-1800}
    retry_interval=${RETRY_INTERVAL:-15}
}

# bats test_tags=fep-interop
@test "aggsender runs in AggchainProof (fast-interop / FEP) mode" {
    assert_equal "$aggsender_mode" "AggchainProof"
    assert_equal "$aggsender_mode_is_fep" "1"
}

# bats test_tags=fep-interop
@test "interop_getEpochConfiguration returns a coherent epoch config" {
    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getEpochConfiguration
    assert_success
    local dur gen
    dur=$(jq -r '.epoch_duration' <<<"$output")
    gen=$(jq -r '.genesis_block' <<<"$output")
    assert_regex "$dur" '^[0-9]+$'   # standalone (not &&-left) so a non-numeric value fails the test
    (( dur > 0 ))
    assert_regex "$gen" '^[0-9]+$'
}

# bats test_tags=fep-interop
@test "an aggchain-proof certificate settles with coherent fields anchored on L1" {
    check_for_latest_settled_cert   # bounded wait; short-circuits if one already exists

    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$l2_rpc_network_id"
    assert_success
    local hdr="$output" cert_id tx height
    assert_equal "$(jq -r '.status' <<<"$hdr")" "Settled"
    assert_equal "$(jq -r '.network_id' <<<"$hdr")" "$l2_rpc_network_id"
    cert_id=$(jq -r '.certificate_id' <<<"$hdr")
    tx=$(jq -r '.settlement_tx_hash' <<<"$hdr")
    height=$(jq -r '.height' <<<"$hdr")
    assert_regex "$cert_id" '^0x[0-9a-fA-F]{64}$'
    assert_regex "$tx" '^0x[0-9a-fA-F]{64}$'
    [[ "$height" =~ ^[0-9]+$ ]]

    # on-L1 anchoring: the settlement tx is a mined, successful L1 transaction
    # (use the JSON receipt: status is the hex quantity "0x1"; the plain
    #  `cast receipt <tx> status` field prints "1 (success)", which is brittle to match)
    run cast receipt --rpc-url "$l1_rpc_url" --json "$tx"
    assert_success
    assert_equal "$(jq -r '.status' <<<"$output")" "0x1"
}

# bats test_tags=fep-interop
@test "interop_getCertificateHeader round-trips the settled certificate id" {
    check_for_latest_settled_cert
    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$l2_rpc_network_id"
    assert_success
    local cert_id; cert_id=$(jq -r '.certificate_id' <<<"$output")

    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getCertificateHeader "$cert_id"
    assert_success
    assert_equal "$(jq -r '.certificate_id' <<<"$output")" "$cert_id"
    assert_equal "$(jq -r '.network_id' <<<"$output")" "$l2_rpc_network_id"
    assert_equal "$(jq -r '.status' <<<"$output")" "Settled"
}

# bats test_tags=fep-interop
@test "latest known certificate height >= latest settled height" {
    # Read settled FIRST, then known: known is monotonic and always >= settled, so
    # reading it last avoids a spurious failure if a cert settles between the two calls.
    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestSettledCertificateHeader "$l2_rpc_network_id"
    assert_success
    local settled; settled=$(jq -r '.height' <<<"$output")
    run cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$l2_rpc_network_id"
    assert_success
    local known; known=$(jq -r '.height' <<<"$output")
    (( known >= settled ))
}
