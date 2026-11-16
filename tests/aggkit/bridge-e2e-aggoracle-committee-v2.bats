#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034,SC2155

# Tests specific to the AggOracle committee v2 (aggkit AggOracle in `committee` mode).
#
# aggkit asks the GER validators (ger_validator_signer services) to sign the L1 GER and injects it in the L2
# through the AggOracleCommittee v2 only when `threshold` validators have signed it. These tests stop and start
# the validators with kurtosis and check what aggkit does: whether the GER reaches the L2 GER manager (and the
# bridge can be claimed) or not.
#
# Requirements:
#   - An environment deployed with the committee v2 (kurtosis-cdk `use_agg_oracle_committee_v2: true`) where the
#     GER updater of the L2 GER manager is the AggOracleCommittee v2.
#   - ENCLAVE_NAME set, and the `kurtosis` and `docker` CLIs available (as for the other tests that stop services).
#
# Optional environment variables:
#   - AGGORACLE_COMMITTEE_V2_VALIDATOR_SERVICES: space separated kurtosis service names of the validators.
#     By default they are the hosts of the URLs registered in the committee.
#   - AGGORACLE_COMMITTEE_V2_NO_INJECTION_WAIT: seconds to wait to confirm that a GER is not injected (default 120).

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
    _committee_v2_resolve
    stopped_validators_file="$BATS_TEST_TMPDIR/stopped_validators"
    : >"$stopped_validators_file"
}

# The validators stopped by a test are always started again, even if the test fails, so one failure does not
# break the tests that run after it.
teardown() {
    local service
    while read -r service; do
        [[ -n "$service" ]] || continue
        update_kurtosis_service_state "$service" "start" || echo "⚠️ could not start $service" >&3
    done <"${stopped_validators_file:-/dev/null}"
}

# Resolves the AggOracleCommittee v2 that is the GER updater of the L2, its threshold and its validator services.
# Exports: committee_addr, committee_threshold, validator_services (array).
_committee_v2_resolve() {
    committee_addr=$(cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" 'globalExitRootUpdater() (address)')
    [[ -n "$committee_addr" ]] || fail "could not read the GER updater of $l2_ger_addr"

    local version
    version=$(cast call --rpc-url "$L2_RPC_URL" "$committee_addr" 'version() (string)' 2>/dev/null | tr -d '"') || true
    if [[ "$version" != v2.* ]]; then
        fail "the GER updater $committee_addr is not an AggOracleCommittee v2 (version: '${version:-none}')"
    fi

    committee_threshold=$(cast call --rpc-url "$L2_RPC_URL" "$committee_addr" 'threshold() (uint256)' | awk '{print $1}')

    if [[ -n "${AGGORACLE_COMMITTEE_V2_VALIDATOR_SERVICES:-}" ]]; then
        read -r -a validator_services <<<"$AGGORACLE_COMMITTEE_V2_VALIDATOR_SERVICES"
    else
        local validators_info
        validators_info=$(cast call --rpc-url "$L2_RPC_URL" "$committee_addr" 'getValidatorsInfo() ((address,string)[])')
        mapfile -t validator_services < <(grep -oE 'https?://[^:/", ]+' <<<"$validators_info" | sed -E 's#https?://##')
    fi
    export committee_addr committee_threshold

    echo "committee: $committee_addr (version $version), threshold: $committee_threshold, validators: ${validator_services[*]}" >&3
    (("${#validator_services[@]}" >= committee_threshold)) ||
        fail "the committee has a threshold ($committee_threshold) greater than its validators (${#validator_services[*]})"
}

# _stop_validators <count>: stops the first <count> validators and remembers them to start them in teardown.
_stop_validators() {
    local count="$1"
    local i service
    for ((i = 0; i < count; i++)); do
        service="${validator_services[$i]}"
        echo "$service" >>"$stopped_validators_file"
        update_kurtosis_service_state "$service" "stop" || fail "could not stop $service"
    done
}

# _start_stopped_validators: starts the validators stopped by the test and forgets them.
_start_stopped_validators() {
    local service
    while read -r service; do
        [[ -n "$service" ]] || continue
        update_kurtosis_service_state "$service" "start" || fail "could not start $service"
    done <"$stopped_validators_file"
    : >"$stopped_validators_file"
}

# _bridge_eth_l1_to_l2: bridges ETH from L1 to L2 (not claimed) and prints the bridge tx hash.
_bridge_eth_l1_to_l2() {
    destination_addr=$sender_addr
    destination_net=$l2_rpc_network_id
    amount=$(cast --to-unit "0.01ether" wei)
    meta_bytes="0x"
    bridge_asset "$native_token_addr" "$l1_rpc_url" "$l1_bridge_addr"
}

# _claim_on_l2 <bridge_tx_hash> <label>: waits for the bridge to be claimable and claims it on L2.
_claim_on_l2() {
    process_bridge_claim "$2" "$l1_rpc_network_id" "$1" "$l2_rpc_network_id" "$l2_bridge_addr" \
        "$aggkit_bridge_url" "$aggkit_bridge_url" "$L2_RPC_URL" "$sender_addr"
}

# _l2_ger_timestamp <ger>: prints the value of globalExitRootMap in the L2 GER manager (0 if not injected).
_l2_ger_timestamp() {
    cast call --rpc-url "$L2_RPC_URL" "$l2_ger_addr" 'globalExitRootMap(bytes32) (uint256)' "$1" | awk '{print $1}'
}

@test "AggOracle committee v2: the L2 GER updater is a committee v2 with all its validators serving" {
    # setup already checked that the updater is a committee v2 whose threshold is not greater than its validators
    local service port
    for service in "${validator_services[@]}"; do
        port=$(kurtosis port print "$ENCLAVE_NAME" "$service" rest) || fail "validator $service has no rest port"
        run curl -sf --max-time 10 "$port/health"
        assert_success
    done
}

@test "AggOracle committee v2: bridge L1 to L2 is claimable with all the validators up" {
    echo "Step 1: bridging ETH from L1 to L2..." >&3
    run _bridge_eth_l1_to_l2
    assert_success
    local bridge_tx_hash=$output

    echo "Step 2: claiming it on L2 (needs the GER injected through the committee)..." >&3
    run _claim_on_l2 "$bridge_tx_hash" "aggoracle_committee_v2 all up: $LINENO"
    assert_success
}

@test "AggOracle committee v2: the GER is still injected with one validator down" {
    ((${#validator_services[@]} > committee_threshold)) ||
        skip "the committee has no spare validator (validators: ${#validator_services[@]}, threshold: $committee_threshold)"

    echo "Step 1: stopping one validator (${validator_services[0]})..." >&3
    _stop_validators 1

    echo "Step 2: bridging ETH from L1 to L2..." >&3
    run _bridge_eth_l1_to_l2
    assert_success
    local bridge_tx_hash=$output

    echo "Step 3: claiming it on L2 with the signatures of the remaining validators..." >&3
    run _claim_on_l2 "$bridge_tx_hash" "aggoracle_committee_v2 one down: $LINENO"
    assert_success
}

@test "AggOracle committee v2: the GER is not injected below the threshold and it is when the validators are back" {
    # the validators to stop so that the threshold can not be reached: all but threshold-1
    local to_stop=$((${#validator_services[@]} - committee_threshold + 1))
    local wait_seconds="${AGGORACLE_COMMITTEE_V2_NO_INJECTION_WAIT:-120}"

    echo "Step 1: stopping $to_stop of ${#validator_services[@]} validators (threshold: $committee_threshold)..." >&3
    _stop_validators "$to_stop"

    echo "Step 2: bridging ETH from L1 to L2 (without claiming)..." >&3
    run _bridge_eth_l1_to_l2
    assert_success
    local bridge_tx_hash=$output

    local l1_latest_ger
    l1_latest_ger=$(cast call --rpc-url "$l1_rpc_url" "$l1_ger_addr" 'getLastGlobalExitRoot() (bytes32)')
    log "🔍 Latest L1 GER: $l1_latest_ger"

    echo "Step 3: waiting ${wait_seconds}s to check that the GER is not injected without the threshold..." >&3
    sleep "$wait_seconds"
    assert_equal "$(_l2_ger_timestamp "$l1_latest_ger")" "0"
    run cast call --rpc-url "$L2_RPC_URL" "$committee_addr" 'injectedGERs(bytes32) (bool)' "$l1_latest_ger"
    assert_success
    assert_output "false"

    echo "Step 4: starting the validators again..." >&3
    _start_stopped_validators

    echo "Step 5: claiming the bridge, it must succeed once aggkit gets the signatures..." >&3
    run _claim_on_l2 "$bridge_tx_hash" "aggoracle_committee_v2 below threshold: $LINENO"
    assert_success
}
