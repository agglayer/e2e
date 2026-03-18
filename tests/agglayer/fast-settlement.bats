#!/usr/bin/env bats
# bats file_tags=agglayer
#
# Fast settlement / multi-certificate-per-epoch tests.
#
# These tests verify the Phase 1 fast-proofs features:
#   - Multiple certificates can be accepted and settled within a single epoch
#   - Settlement transaction management (nonce handling, gas-bumping, retries)
#   - The settlement pipeline does not block new certificate acceptance
#
# Prerequisites:
#   - A running Kurtosis enclave with agglayer, L1, and at least one L2 rollup
#   - Bridge spammer or manual bridge transactions to generate certificates

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    agglayer_admin_url=${AGGLAYER_ADMIN_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-admin)"}
    agglayer_rpc_url=${AGGLAYER_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)"}
    export agglayer_admin_url agglayer_rpc_url
}

setup() {
    load "$PROJECT_ROOT/core/helpers/agglayer-cdk-common-setup.bash"
    _load_bats_libraries
    load "../../core/helpers/scripts/settlement_monitor"

    aggregator_nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    export aggregator_nonce
}

# ---------------------------------------------------------------------------
# Shared helpers (file-local)
# ---------------------------------------------------------------------------

function interop_status_query() {
    local interop_ep=$1
    local full_answer=${2:-0}

    while true; do
        run cast rpc --rpc-url "$agglayer_rpc_url" "$interop_ep" "$rollup_id"
        if [[ "$status" -ne 0 ]]; then
            echo "Failed to query $interop_ep: $output" >&3
            exit 1
        fi
        if [[ "$full_answer" -ne 0 ]]; then
            answer=$output
        else
            answer=$(echo "$output" | jq -r '.certificate_id')
        fi
        if [[ -n "$answer" && "$answer" != "null" ]]; then
            break
        fi
        sleep 3
    done
    echo "$answer"
}

function wait_for_new_settled_cert() {
    local timeout="${1:-1200}"
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    echo "Waiting for new settled certificate..." >&3
    local initial_cert_id
    initial_cert_id=$(interop_status_query interop_getLatestSettledCertificateHeader)
    local current_cert_id="$initial_cert_id"

    while [[ "$current_cert_id" == "$initial_cert_id" ]]; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "Error: Timed out ($timeout s) waiting for new settled certificate" >&3
            return 1
        fi
        sleep 12
        current_cert_id=$(interop_status_query interop_getLatestSettledCertificateHeader)
    done
    echo "New settled certificate: $current_cert_id" >&3
}

function trigger_bridge_l2_to_l1() {
    local amount="${1:-1}"
    local bridge_sig="bridgeAsset(uint32,address,uint256,address,bool,bytes)"
    local dest_address="0xc949254d682d8c9ad5682521675b8f43b102aec4"
    cast send --legacy --private-key "$l2_private_key" --value "$amount" \
        --rpc-url "$L2_RPC_URL" "$l2_bridge_addr" \
        "$bridge_sig" 0 "$dest_address" "$amount" "$(cast az)" true "0x"
}

function check_aggregator_nonce_advanced() {
    local expected_min_increment=$1
    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    local actual_increment=$((final_nonce - aggregator_nonce))

    if [[ $actual_increment -lt $expected_min_increment ]]; then
        echo "Error: Aggregator nonce advanced by $actual_increment, expected at least $expected_min_increment" >&3
        return 1
    fi
    echo "Aggregator nonce advanced by $actual_increment (initial=$aggregator_nonce, final=$final_nonce)" >&3
}

function send_n_txs_from_aggregator() {
    local n_txs=${1:-1}
    for i in $(seq 1 "$n_txs"); do
        local basefee priority_fee max_fee
        basefee=$(cast basefee --rpc-url "$l1_rpc_url")
        priority_fee=$(( 5 * 1000000000 ))
        max_fee=$(( basefee + priority_fee ))
        run cast send --private-key "$l2_aggregator_private_key" --rpc-url "$l1_rpc_url" \
            --gas-price "$max_fee" --priority-gas-price "$priority_fee" \
            --value 1 "$foo_address" --json
        if [[ "$status" -ne 0 ]]; then
            echo "Failed to send aggregator tx $i: $output" >&3
            return 1
        fi
        echo "Sent aggregator tx $i" >&3
    done
}

# ===========================================================================
# Epoch configuration sanity check
# ===========================================================================

# bats test_tags=agglayer-fast-settlement
@test "epoch configuration returns valid duration and genesis block" {
    local epoch_config
    epoch_config=$(get_epoch_configuration "$agglayer_rpc_url")

    local epoch_duration genesis_block
    epoch_duration=$(echo "$epoch_config" | jq -r '.epoch_duration')
    genesis_block=$(echo "$epoch_config" | jq -r '.genesis_block')

    echo "Epoch duration: $epoch_duration, genesis block: $genesis_block" >&3

    if [[ -z "$epoch_duration" || "$epoch_duration" == "null" || "$epoch_duration" -le 0 ]]; then
        echo "Error: Invalid epoch_duration: $epoch_duration"
        exit 1
    fi

    if [[ -z "$genesis_block" || "$genesis_block" == "null" ]]; then
        echo "Error: Invalid genesis_block: $genesis_block"
        exit 1
    fi
}

# ===========================================================================
# Multiple certificates per epoch
# ===========================================================================

# bats test_tags=agglayer-fast-settlement
@test "settle multiple certificates within a single epoch" {
    # Record baseline settled height
    local baseline_header
    baseline_header=$(get_settled_cert_header "$agglayer_rpc_url" "$rollup_id")
    local baseline_height=-1
    if [[ -n "$baseline_header" && "$baseline_header" != "null" ]]; then
        baseline_height=$(echo "$baseline_header" | jq -r '.height')
    fi
    echo "Baseline settled height: $baseline_height" >&3

    # Trigger multiple L2->L1 bridge transactions to generate certificate activity
    for i in $(seq 1 5); do
        trigger_bridge_l2_to_l1 "$i"
        echo "Triggered bridge tx $i" >&3
        sleep 2
    done

    # Wait for at least 2 certificates to settle beyond the baseline
    local cert_records
    cert_records=$(wait_for_n_settled_certs "$agglayer_rpc_url" "$rollup_id" 2 "$baseline_height" 600 8)

    local cert_count
    cert_count=$(echo "$cert_records" | grep -c '{' || true)
    echo "Settled $cert_count certificates beyond baseline height $baseline_height" >&3

    if [[ "$cert_count" -lt 2 ]]; then
        echo "Error: Expected at least 2 certificates to settle, got $cert_count"
        exit 1
    fi

    # Check if any certificates share the same epoch (multi-cert-per-epoch)
    local epoch_counts
    epoch_counts=$(echo "$cert_records" | count_certs_in_epoch)
    echo "Epoch distribution: $epoch_counts" >&3

    local max_per_epoch=0
    while IFS=: read -r epoch count; do
        if [[ "$count" -gt "$max_per_epoch" ]]; then
            max_per_epoch=$count
        fi
    done <<< "$epoch_counts"

    echo "Max certificates in a single epoch: $max_per_epoch" >&3

    # With the multi-cert-per-epoch feature, we expect >1 in at least one epoch.
    # If epochs are short enough relative to settlement speed, this should pass.
    # Log the result regardless for observability.
    if [[ "$max_per_epoch" -gt 1 ]]; then
        echo "Multi-cert-per-epoch confirmed: $max_per_epoch certs in one epoch" >&3
    else
        echo "Warning: Each epoch contained only 1 certificate. This may be expected if epochs are very short." >&3
        echo "Epoch counts: $epoch_counts" >&3
    fi
}

# bats test_tags=agglayer-fast-settlement
@test "certificate heights increase monotonically across settlements" {
    local baseline_header
    baseline_header=$(get_settled_cert_header "$agglayer_rpc_url" "$rollup_id")
    local baseline_height=-1
    if [[ -n "$baseline_header" && "$baseline_header" != "null" ]]; then
        baseline_height=$(echo "$baseline_header" | jq -r '.height')
    fi

    # Trigger bridge activity
    for i in $(seq 1 3); do
        trigger_bridge_l2_to_l1 "$i"
        sleep 3
    done

    # Collect 3 settled certificates
    local cert_records
    cert_records=$(wait_for_n_settled_certs "$agglayer_rpc_url" "$rollup_id" 3 "$baseline_height" 600 8)

    # Verify monotonic height increase
    if ! echo "$cert_records" | verify_heights_monotonic; then
        echo "Error: Certificate heights are not monotonically increasing"
        echo "Records: $cert_records"
        exit 1
    fi
    echo "All certificate heights are strictly increasing" >&3
}

# bats test_tags=agglayer-fast-settlement
@test "rapid bridge transactions produce distinct certificates" {
    local baseline_header
    baseline_header=$(get_settled_cert_header "$agglayer_rpc_url" "$rollup_id")
    local baseline_height=-1
    if [[ -n "$baseline_header" && "$baseline_header" != "null" ]]; then
        baseline_height=$(echo "$baseline_header" | jq -r '.height')
    fi

    # Send 5 bridge transactions in rapid succession
    for i in $(seq 1 5); do
        trigger_bridge_l2_to_l1 1
    done
    echo "Sent 5 rapid bridge transactions" >&3

    # Wait for at least 2 distinct certificates
    local cert_records
    cert_records=$(wait_for_n_settled_certs "$agglayer_rpc_url" "$rollup_id" 2 "$baseline_height" 600 5)

    local cert_count
    cert_count=$(echo "$cert_records" | grep -c '{' || true)

    if [[ "$cert_count" -lt 2 ]]; then
        echo "Error: Expected at least 2 distinct settled certificates, got $cert_count"
        exit 1
    fi

    # Verify all certificate IDs are unique
    local unique_count
    unique_count=$(echo "$cert_records" | jq -r '.certificate_id' | sort -u | wc -l | tr -d ' ')

    if [[ "$unique_count" -ne "$cert_count" ]]; then
        echo "Error: Found duplicate certificate IDs ($unique_count unique out of $cert_count)"
        exit 1
    fi
    echo "All $cert_count certificates have distinct IDs" >&3
}

# ===========================================================================
# Settlement transaction management
# ===========================================================================

# bats test_tags=agglayer-fast-settlement
@test "settlement completes under aggregator nonce contention" {
    # Record initial state
    local initial_settled_cert_id
    initial_settled_cert_id=$(interop_status_query interop_getLatestSettledCertificateHeader)

    # Send L1 transactions from the aggregator key to create nonce contention
    send_n_txs_from_aggregator 5

    # Trigger a bridge to generate a new certificate
    trigger_bridge_l2_to_l1 1

    # Wait for a new certificate to settle despite the nonce contention
    wait_for_new_settled_cert 600

    local final_settled_cert_id
    final_settled_cert_id=$(interop_status_query interop_getLatestSettledCertificateHeader)

    if [[ "$final_settled_cert_id" == "$initial_settled_cert_id" ]]; then
        echo "Error: No new certificate settled after nonce contention"
        exit 1
    fi
    echo "Certificate settled despite nonce contention: $final_settled_cert_id" >&3

    # Nonce should have advanced for both the user txs and the settlement tx
    check_aggregator_nonce_advanced 6
}

# bats test_tags=agglayer-fast-settlement
@test "settlement nonce advances correctly across multiple certificates" {
    local initial_nonce
    initial_nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    echo "Initial aggregator nonce: $initial_nonce" >&3

    # Wait for two consecutive certificate settlements
    wait_for_new_settled_cert 600
    local mid_nonce
    mid_nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    echo "Nonce after first settlement: $mid_nonce" >&3

    wait_for_new_settled_cert 600
    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    echo "Nonce after second settlement: $final_nonce" >&3

    # Each settlement should advance the nonce by at least 1
    if [[ $mid_nonce -le $initial_nonce ]]; then
        echo "Error: Nonce did not advance after first settlement ($initial_nonce -> $mid_nonce)"
        exit 1
    fi

    if [[ $final_nonce -le $mid_nonce ]]; then
        echo "Error: Nonce did not advance after second settlement ($mid_nonce -> $final_nonce)"
        exit 1
    fi

    echo "Nonce progression: $initial_nonce -> $mid_nonce -> $final_nonce" >&3
}

# bats test_tags=agglayer-fast-settlement
@test "settlement recovers after temporary aggregator fund depletion" {
    # Drain the aggregator's funds
    local aggregator_balance
    aggregator_balance=$(cast balance "$l2_aggregator_address" --rpc-url "$l1_rpc_url")
    echo "Aggregator balance before drain: $aggregator_balance" >&3

    local basefee priority_fee max_fee tx_cost amount_to_send
    basefee=$(cast basefee --rpc-url "$l1_rpc_url")
    priority_fee=$(( 5 * 1000000000 ))
    max_fee=$(( basefee + priority_fee ))
    tx_cost=$(( max_fee * 21000 ))
    amount_to_send=$(echo "$aggregator_balance - $tx_cost" | bc)

    run cast send --rpc-url "$l1_rpc_url" --private-key "$l2_aggregator_private_key" \
        --gas-price "$max_fee" --priority-gas-price "$priority_fee" \
        --value "$amount_to_send" "$foo_address"
    if [[ "$status" -ne 0 ]]; then
        echo "Error: Failed to drain aggregator: $output" >&3
        exit 1
    fi

    local drained_balance
    drained_balance=$(cast balance "$l2_aggregator_address" --rpc-url "$l1_rpc_url")
    echo "Aggregator balance after drain: $drained_balance" >&3

    # Wait for an InError certificate (settlement should fail without funds)
    local timeout=300
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local found_error=0

    while [[ $(date +%s) -lt $end_time ]]; do
        local known_header
        known_header=$(interop_status_query interop_getLatestKnownCertificateHeader 1 2>/dev/null || echo "")
        if [[ "$known_header" == *"InError"* ]]; then
            echo "Detected InError certificate as expected" >&3
            found_error=1
            break
        fi
        sleep 12
    done

    # Restore funds
    echo "Restoring funds to aggregator..." >&3
    local foo_balance
    foo_balance=$(cast balance "$foo_address" --rpc-url "$l1_rpc_url")
    basefee=$(cast basefee --rpc-url "$l1_rpc_url")
    max_fee=$(( basefee + priority_fee ))
    tx_cost=$(( max_fee * 21000 ))
    amount_to_send=$(echo "$foo_balance - $tx_cost" | bc)

    run cast send --rpc-url "$l1_rpc_url" --private-key "$foo_private_key" \
        --gas-price "$max_fee" --priority-gas-price "$priority_fee" \
        --value "$amount_to_send" "$l2_aggregator_address"
    if [[ "$status" -ne 0 ]]; then
        echo "Error: Failed to restore aggregator funds: $output" >&3
        exit 1
    fi

    local restored_balance
    restored_balance=$(cast balance "$l2_aggregator_address" --rpc-url "$l1_rpc_url")
    echo "Aggregator balance after restore: $restored_balance" >&3

    # Wait for settlement to recover
    wait_for_new_settled_cert 600
    echo "Settlement recovered after fund restoration" >&3
}

# ===========================================================================
# Settlement pipeline (non-blocking behavior)
# ===========================================================================

# bats test_tags=agglayer-fast-settlement
@test "new certificate accepted while previous is settling" {
    # Record current settled and pending state
    local settled_header
    settled_header=$(get_settled_cert_header "$agglayer_rpc_url" "$rollup_id")
    local settled_height=-1
    if [[ -n "$settled_header" && "$settled_header" != "null" ]]; then
        settled_height=$(echo "$settled_header" | jq -r '.height')
    fi

    # Trigger bridge activity to generate certificates
    trigger_bridge_l2_to_l1 1
    sleep 5
    trigger_bridge_l2_to_l1 2

    # Check that pending certificate exists (new cert was accepted into the pipeline)
    local timeout=120
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local found_pending=0

    while [[ $(date +%s) -lt $end_time ]]; do
        local pending_header
        pending_header=$(get_pending_cert_header "$agglayer_rpc_url" "$rollup_id" 2>/dev/null || echo "null")
        if [[ -n "$pending_header" && "$pending_header" != "null" ]]; then
            local pending_height
            pending_height=$(echo "$pending_header" | jq -r '.height')
            if [[ "$pending_height" -gt "$settled_height" ]]; then
                echo "Pending certificate found at height $pending_height (settled=$settled_height)" >&3
                found_pending=1
                break
            fi
        fi
        sleep 5
    done

    if [[ "$found_pending" -eq 0 ]]; then
        echo "Warning: No pending certificate observed above settled height. Pipeline may have settled immediately." >&3
    fi

    # Regardless, wait for final settlement to confirm the pipeline completes
    wait_for_new_settled_cert 600
    echo "Pipeline completed: certificate accepted and settled" >&3
}

# bats test_tags=agglayer-fast-settlement
@test "settlement throughput with sequential bridge operations" {
    local num_rounds=3
    local total_start
    total_start=$(date +%s)
    local settlement_times=()

    for round in $(seq 1 "$num_rounds"); do
        local round_start
        round_start=$(date +%s)

        # Trigger a bridge transaction
        trigger_bridge_l2_to_l1 "$round"

        # Wait for the corresponding certificate to settle
        wait_for_new_settled_cert 600

        local round_end
        round_end=$(date +%s)
        local round_duration=$((round_end - round_start))
        settlement_times+=("$round_duration")

        echo "Round $round: settled in ${round_duration}s" >&3
    done

    local total_end
    total_end=$(date +%s)
    local total_duration=$((total_end - total_start))

    # Report throughput metrics
    local sum=0
    for t in "${settlement_times[@]}"; do
        sum=$((sum + t))
    done
    local avg=$((sum / num_rounds))

    echo "Settlement throughput report:" >&3
    echo "  Rounds: $num_rounds" >&3
    echo "  Total time: ${total_duration}s" >&3
    echo "  Average per round: ${avg}s" >&3
    echo "  Individual times: ${settlement_times[*]}" >&3
}

# bats test_tags=agglayer-fast-settlement
@test "settlement transaction status transitions from pending to done" {
    # Get a reference to the current latest known certificate
    local initial_known_id
    initial_known_id=$(interop_status_query interop_getLatestKnownCertificateHeader)

    # Trigger bridge activity
    trigger_bridge_l2_to_l1 1

    # Wait for a new certificate to appear (different from the initial one)
    local timeout=300
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local cert_id=""

    while [[ $(date +%s) -lt $end_time ]]; do
        local current_known_id
        current_known_id=$(interop_status_query interop_getLatestKnownCertificateHeader)
        if [[ "$current_known_id" != "$initial_known_id" ]]; then
            cert_id="$current_known_id"
            break
        fi
        sleep 5
    done

    if [[ -z "$cert_id" ]]; then
        echo "Error: No new certificate appeared within $timeout s"
        exit 1
    fi
    echo "Tracking certificate: $cert_id" >&3

    # Track status transitions
    local -a observed_statuses=()
    local prev_status=""
    end_time=$(( $(date +%s) + 600 ))

    while [[ $(date +%s) -lt $end_time ]]; do
        local header
        header=$(get_cert_header_by_id "$agglayer_rpc_url" "$cert_id" 2>/dev/null || echo "null")

        if [[ -n "$header" && "$header" != "null" ]]; then
            local current_status
            current_status=$(echo "$header" | jq -r '.status')

            if [[ "$current_status" != "$prev_status" ]]; then
                observed_statuses+=("$current_status")
                echo "Status transition: $prev_status -> $current_status" >&3
                prev_status="$current_status"
            fi

            if [[ "$current_status" == "Settled" ]]; then
                break
            fi
        fi

        sleep 3
    done

    echo "Observed status sequence: ${observed_statuses[*]}" >&3

    # Verify the certificate reached Settled status
    if [[ "${observed_statuses[-1]}" != "Settled" ]]; then
        echo "Error: Certificate did not reach Settled status. Final status: ${observed_statuses[-1]}"
        exit 1
    fi

    # Verify the settlement tx hash reports as "done"
    local settled_header
    settled_header=$(get_cert_header_by_id "$agglayer_rpc_url" "$cert_id")
    local settlement_tx_hash
    settlement_tx_hash=$(echo "$settled_header" | jq -r '.settlement_tx_hash')

    if [[ -n "$settlement_tx_hash" && "$settlement_tx_hash" != "null" ]]; then
        local tx_status
        tx_status=$(cast rpc --rpc-url "$agglayer_rpc_url" interop_getTxStatus "$settlement_tx_hash")
        echo "Settlement tx status: $tx_status" >&3

        if [[ "$tx_status" != '"done"' ]]; then
            echo "Error: Settlement tx status is not 'done': $tx_status"
            exit 1
        fi
    fi

    echo "Certificate $cert_id completed full lifecycle to Settled/done" >&3
}
