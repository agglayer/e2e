#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    # Load libraries.
    load "../../core/helpers/pos-setup.bash"
    pos_setup

    eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")
    export ETH_RPC_URL="$L2_RPC_URL"
}

# bats test_tags=evm-stress,loadtest
@test "50 concurrent eth_blockNumber requests all succeed" {
    fail_count=0
    pids=()

    for i in $(seq 1 50); do
        cast block-number &>/dev/null &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
        fi
    done

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count / 50 concurrent eth_blockNumber requests failed" >&2
        return 1
    fi
}

# bats test_tags=evm-stress,loadtest
@test "50 concurrent eth_getBalance requests all return valid results" {
    tmpdir=$(mktemp -d)
    pids=()

    for i in $(seq 1 50); do
        out_file="$tmpdir/result_$i"
        cast balance "$eth_address" >"$out_file" 2>/dev/null &
        pids+=($!)
    done

    fail_count=0
    for idx in "${!pids[@]}"; do
        pid="${pids[$idx]}"
        out_file="$tmpdir/result_$(( idx + 1 ))"
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
            continue
        fi
        result=$(cat "$out_file")
        # result should be a non-empty decimal number
        if ! [[ "$result" =~ ^[0-9]+$ ]]; then
            echo "Request $(( idx + 1 )) returned non-numeric result: $result" >&2
            fail_count=$(( fail_count + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count / 50 concurrent eth_getBalance requests failed or returned invalid results" >&2
        return 1
    fi
}

# bats test_tags=evm-stress,loadtest
@test "50 concurrent eth_getLogs requests all return valid arrays" {
    tmpdir=$(mktemp -d)
    pids=()

    for i in $(seq 1 50); do
        out_file="$tmpdir/result_$i"
        cast rpc eth_getLogs '[{"fromBlock": "0x0", "toBlock": "0x0"}]' --rpc-url "$L2_RPC_URL" >"$out_file" 2>/dev/null &
        pids+=($!)
    done

    fail_count=0
    for idx in "${!pids[@]}"; do
        pid="${pids[$idx]}"
        out_file="$tmpdir/result_$(( idx + 1 ))"
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
            continue
        fi
        result_type=$(jq -r 'type' <"$out_file" 2>/dev/null)
        if [[ "$result_type" != "array" ]]; then
            echo "Request $(( idx + 1 )) returned non-array: $(cat "$out_file")" >&2
            fail_count=$(( fail_count + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count / 50 concurrent eth_getLogs requests failed or returned invalid results" >&2
        return 1
    fi
}
