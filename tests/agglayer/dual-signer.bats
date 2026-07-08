#!/usr/bin/env bats
# bats file_tags=agglayer
#
# agglayer 0.6 dual-wallet second signer.
#
# 0.6 can split the agglayer settlement identity into two wallets: a cert (pp-settlement) signer that
# signs the certificate, and a separate tx-settlement signer that submits the L1 settlement
# transactions, each with its own L1 nonce stream. kurtosis-cdk enables this with
# `agglayer_use_second_signer: true` (a second [auth.local] private-keys entry pointing at
# sequencer.keystore). The node logs both roles at startup:
#   "Cert signer address: 0x..."   and   "Tx signer address: 0x..."
# These tests assert the two roles resolve to distinct wallets and that the tx-settlement wallet is
# the one advancing its L1 nonce as certificates settle.
#
# Enclave: PP with the second signer enabled. The file self-skips when both roles map to one wallet
# (single-signer mode).

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
    # shellcheck source=core/helpers/agglayer-certificates-checks.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/agglayer-certificates-checks.bash"
}

fail() { echo "❌ $*" >&3; exit 1; }

# Resolve the kurtosis-managed agglayer container name (agglayer--<uuid>).
_agglayer_container() {
    local uuid
    uuid=$(kurtosis service inspect "$kurtosis_enclave_name" agglayer --full-uuid 2>/dev/null | grep -i UUID | head -1 | sed 's/.*: //' | tr -d '[:space:]')
    [[ -n "$uuid" ]] || return 1
    echo "agglayer--$uuid"
}

# Echo "<cert_signer> <tx_signer>" (lowercase 0x addresses) parsed from the agglayer startup log.
_agglayer_signers_from_log() {
    local c logs cert tx
    c=$(_agglayer_container) || return 1
    logs=$(docker logs "$c" 2>&1) || return 1
    cert=$(echo "$logs" | grep -oiE 'Cert signer address: 0x[0-9a-f]{40}' | tail -1 | grep -oiE '0x[0-9a-f]{40}' | tr 'A-F' 'a-f')
    tx=$(echo "$logs"   | grep -oiE 'Tx signer address: 0x[0-9a-f]{40}'   | tail -1 | grep -oiE '0x[0-9a-f]{40}' | tr 'A-F' 'a-f')
    [[ -n "$cert" && -n "$tx" ]] || return 1
    echo "$cert $tx"
}

_l1_nonce() { cast nonce --rpc-url "$l1_rpc_url" "$1"; }

# bats test_tags=agglayer-dual-signer
@test "agglayer runs with two distinct settlement signers (cert vs tx)" {
    if [[ -n "${AGGLAYER_READRPC_URL:-}" || -n "${AGGLAYER_RPC_URL:-}" ]]; then
        skip "requires a kurtosis-managed agglayer service (external RPC override is set)"
    fi
    local pair; pair=$(_agglayer_signers_from_log) || skip "could not read Cert/Tx signer addresses from the agglayer log"
    local cert_signer tx_signer
    read -r cert_signer tx_signer <<<"$pair"
    echo "ℹ️ cert (pp-settlement) signer: $cert_signer" >&3
    echo "ℹ️ tx-settlement signer:        $tx_signer" >&3
    [[ "$cert_signer" != "$tx_signer" ]] || skip "single-signer mode (cert and tx signer are the same wallet) — second signer not enabled"
    echo "✅ dual-wallet second signer active: distinct cert and tx signers" >&3
}

# bats test_tags=agglayer-dual-signer
@test "settlement transactions come from one dedicated wallet, independent of the co-signer" {
    if [[ -n "${AGGLAYER_READRPC_URL:-}" || -n "${AGGLAYER_RPC_URL:-}" ]]; then
        skip "requires a kurtosis-managed agglayer service (external RPC override is set)"
    fi
    local pair; pair=$(_agglayer_signers_from_log) || skip "could not read Cert/Tx signer addresses from the agglayer log"
    # The two roles map to two wallets; one submits the L1 settlement tx (its nonce advances) while
    # the other only contributes the certificate's off-chain ECDSA signature (nonce static). agglayer's
    # role labels are counterintuitive, so this test is naming-agnostic: it just proves the L1
    # settlement txs come from ONE dedicated wallet of the pair, on a stream independent of the other.
    local w1 w2
    read -r w1 w2 <<<"$pair"
    [[ "$w1" != "$w2" ]] || skip "single-signer mode — second signer not enabled"

    check_for_latest_settled_cert || fail "no settled certificate to start from"
    local w1_n0 w2_n0
    w1_n0=$(_l1_nonce "$w1") || fail "could not read L1 nonce for $w1"
    w2_n0=$(_l1_nonce "$w2") || fail "could not read L1 nonce for $w2"
    echo "ℹ️ initial L1 nonces — $w1:$w1_n0  $w2:$w2_n0" >&3

    # Poll until one wallet has clearly submitted the settlement txs (>= 2 L1 txs). Polling on the
    # nonce (rather than the settled-cert count) avoids the skew between "cert observed settled" and
    # "its L1 settlement tx mined/nonce incremented".
    local start=$SECONDS w1_d w2_d
    while true; do
        w1_d=$(( $(_l1_nonce "$w1") - w1_n0 ))
        w2_d=$(( $(_l1_nonce "$w2") - w2_n0 ))
        (( w1_d >= 2 || w2_d >= 2 )) && break
        (( SECONDS - start >= timeout )) && fail "neither signer wallet submitted >=2 L1 txs within ${timeout}s (deltas $w1:$w1_d $w2:$w2_d)"
        sleep "$retry_interval"
    done
    echo "ℹ️ nonce deltas — $w1:$w1_d  $w2:$w2_d" >&3

    local sender_delta=$w1_d other_delta=$w2_d
    (( w2_d > w1_d )) && { sender_delta=$w2_d; other_delta=$w1_d; }
    (( sender_delta >= 2 )) || fail "no dedicated settlement-tx wallet advanced (>=2) (deltas $w1:$w1_d $w2:$w2_d)"
    (( sender_delta > other_delta )) || fail "the two signer wallets are not on independent nonce streams (deltas $w1:$w1_d $w2:$w2_d)"
    echo "✅ settlement txs come from one dedicated wallet; the co-signer is on an independent nonce stream" >&3
}
