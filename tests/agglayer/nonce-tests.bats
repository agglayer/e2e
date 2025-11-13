#!/usr/bin/env bats
# bats file_tags=agglayer

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars

    agglayer_admin_url=${AGGLAYER_ADMIN_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-admin)"}
    agglayer_rpc_url=${AGGLAYER_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)"}
    export agglayer_admin_url agglayer_rpc_url
}
function wait_for_new_cert() {
    local timeout=${1:-1200}
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    echo "Waiting for new certificate..." >&3
    inital_proven_certificate_id=$(interop_status_query interop_getLatestSettledCertificateHeader)
    current_proven_certificate_id=$inital_proven_certificate_id
    while [ "$current_proven_certificate_id" == "$inital_proven_certificate_id" ]; do
        echo "Current proven certificate: $current_proven_certificate_id, waiting for new one..." >&3
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "❌ Error: Timed out waiting for new certificate"
            exit 1
        fi
        sleep 12
        current_proven_certificate_id=$(interop_status_query interop_getLatestSettledCertificateHeader)
    done
    echo "✅ Successfully got a new certificate settled: $current_proven_certificate_id" >&3
}

function interop_status_query() {
    local interop_ep=$1
    local full_answer=${2:-0}

    # Iterate until there is one certificate (no null answer)
    while true; do
        run cast rpc --rpc-url "$agglayer_rpc_url" "$interop_ep" "$rollup_id"
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to get latest known certificate header using $interop_ep: $output"
            exit 1
        else
            if [[ "$full_answer" -ne 0 ]]; then
                answer=$output
            else
                answer=$(echo "$output" | jq -r '.certificate_id')
            fi
            if [ -n "$answer" ]; then
                break
            fi
            sleep 3
        fi
    done
    echo $answer
}

# Params: n_txs (default 1), sync (default 1), nonce_offset (default 0), wait_for_asynctx_to_be_mined (default 0),
function send_n_txs_from_aggregator() {
    local n_txs=${1:-1}
    local sync=${2:-1}
    local nonce_offset=${3:-0}
    local wait_for_async_tx_to_be_mined=${4:-0}

    nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$l2_aggregator_address")
    nonce=$((nonce + nonce_offset))

    gas_price_factor=5

    for i in $(seq 0 $(($n_txs - 1))); do
        gas_price=$(cast gas-price --rpc-url "$l1_rpc_url")
        gas_price=$(echo "$gas_price * $gas_price_factor" | bc -l | cut -f 1 -d '.')
        if [[ "$sync" -eq 1 ]]; then
            run cast send --private-key "$l2_aggregator_private_key" --rpc-url "$l1_rpc_url" --gas-price "$gas_price" --value 1 "$foo_address" --json
        else
            run cast send --legacy --private-key "$l2_aggregator_private_key" --rpc-url "$l1_rpc_url" --gas-price "$gas_price" --value 1 --nonce "$((nonce + i))" --async "$foo_address"
        fi
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to send tx $((i + 1)) with aggregator private key: $output" >&3
            exit 1
        else
            if [[ "$sync" -eq 1 ]]; then
                tx_hash=$(echo "$output" | jq -r '.transactionHash')
            else
                tx_hash=$output
            fi
            echo "✅ Successfully sent tx $((i + 1)) with aggregator private key: $tx_hash" >&3
        fi
    done

    if [[ "$wait_for_async_tx_to_be_mined" -eq 1 ]]; then
        last_tx_hash=$tx_hash
        last_tx_was_mined=0
        while [ "$last_tx_was_mined" -eq 0 ]; do
            run cast receipt $last_tx_hash --rpc-url "$l1_rpc_url" --json
            if [ "$status" -eq 0 ]; then
                tx_status=$(echo "$output" | jq -r '.status')
                if [ "$tx_status" == "0x1" ]; then
                    echo "✅ Successfully mined tx $last_tx_hash" >&3
                    last_tx_was_mined=1
                    break
                else
                    echo "Waiting for tx $last_tx_hash to be mined, current status: $tx_status" >&3
                    sleep 2
                fi
            fi
        done
    fi
}

# bats test_tags=agglayer-nonce
@test "wait for a new certificate to be settled" {
    # This actually tests nothing related to nonce, but just to be sure we start with a working network
    wait_for_new_cert
    echo "✅ Successfully got a new certificate settled" >&3
}

# bats test_tags=agglayer-nonce
@test "send a tx using aggregator private key" {
    send_n_txs_from_aggregator
    wait_for_new_cert
    echo "✅ Successfully got a new certificate settled" >&3
}

# bats test_tags=agglayer-nonce
@test "send many txs using aggregator private key" {
    send_n_txs_from_aggregator 10
    wait_for_new_cert
    echo "✅ Successfully got a new certificate settled" >&3
}

# bats test_tags=agglayer-nonce
@test "send many async txs using aggregator private key" {
    send_n_txs_from_aggregator 50 0 0 1
    wait_for_new_cert
    echo "✅ Successfully got a new certificate settled" >&3
}

# bats test_tags=agglayer-nonce
@test "send tx with nonce+1 using aggregator private key" {
    n_txs=1
    send_n_txs_from_aggregator $n_txs 0 1
    for i in {0..$n_txs}; do
        wait_for_new_cert
        echo "✅ Successfully got a new certificate settled" >&3
    done
    # Just in case, to avoid gap nonce
    send_n_txs_from_aggregator
}

# bats test_tags=agglayer-nonce
@test "send txs from nonce+1 to nonce+10 using aggregator private key" {
    n_txs=10
    send_n_txs_from_aggregator $n_txs 0 1
    for i in {0..$n_txs}; do
        wait_for_new_cert
        echo "✅ Successfully got a new certificate settled" >&3
    done
    # Just in case, to avoid gap nonce
    send_n_txs_from_aggregator
}

# bats test_tags=agglayer-nonce
@test "send 1 tx per block for N blocks" {
    n_blocks=100

    initial_block=$(cast bn --rpc-url "$l1_rpc_url")

    target_block=$((initial_block + n_blocks))
    current_block=$initial_block

    echo "✅ Initial block: $initial_block, target block: $target_block" >&3

    while [ "$current_block" -lt "$target_block" ]; do
        send_n_txs_from_aggregator 1
        last_block=$current_block
        echo "✅ Successfully sent tx for block $last_block" >&3
        current_block=$(cast bn --rpc-url "$l1_rpc_url")
        while [ "$current_block" -eq "$last_block" ]; do
            current_block=$(cast bn --rpc-url "$l1_rpc_url")
        done
    done
    wait_for_new_cert
}
