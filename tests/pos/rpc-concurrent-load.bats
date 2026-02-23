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
@test "50 concurrent eth_blockNumber requests all succeed and return consistent values" {
    tmpdir=$(mktemp -d)
    pids=()

    for i in $(seq 1 50); do
        cast block-number >"$tmpdir/bn_$i" 2>/dev/null &
        pids+=($!)
    done

    fail_count=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
        fi
    done

    if [[ "$fail_count" -ne 0 ]]; then
        rm -rf "$tmpdir"
        echo "$fail_count / 50 concurrent eth_blockNumber requests failed" >&2
        return 1
    fi

    # All returned block numbers must be within 2 of each other: they were fired
    # within milliseconds of each other so they should all reflect the same (or at
    # most one neighbouring) block.
    max_block=0 min_block=999999999
    for i in $(seq 1 50); do
        bn=$(cat "$tmpdir/bn_$i" 2>/dev/null)
        if [[ "$bn" =~ ^[0-9]+$ ]]; then
            [[ "$bn" -gt "$max_block" ]] && max_block="$bn"
            [[ "$bn" -lt "$min_block" ]] && min_block="$bn"
        fi
    done
    rm -rf "$tmpdir"

    block_spread=$(( max_block - min_block ))
    echo "Block number spread across 50 concurrent requests: $block_spread (min=$min_block max=$max_block)" >&3
    if [[ "$block_spread" -gt 2 ]]; then
        echo "Block numbers diverged by $block_spread across concurrent requests — possible RPC inconsistency" >&2
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
    first_balance=""
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
            continue
        fi
        # All 50 requests target the same address with no concurrent writes;
        # every response must return the identical balance.
        if [[ -z "$first_balance" ]]; then
            first_balance="$result"
        elif [[ "$result" != "$first_balance" ]]; then
            echo "Balance inconsistency: request $(( idx + 1 )) returned $result but first was $first_balance" >&2
            fail_count=$(( fail_count + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count / 50 concurrent eth_getBalance requests failed or returned inconsistent results" >&2
        return 1
    fi
}

# bats test_tags=evm-stress,loadtest
@test "50 concurrent eth_getLogs requests all return valid arrays" {
    tmpdir=$(mktemp -d)
    pids=()

    for i in $(seq 1 50); do
        out_file="$tmpdir/result_$i"
        # curl is used instead of `cast rpc` because cast rpc has issues handling
        # concurrent background subshells reliably; curl makes a plain HTTP POST
        # and always writes the full JSON-RPC envelope to stdout.
        curl -s -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":"0x0","toBlock":"0x0"}],"id":1}' \
            "$L2_RPC_URL" >"$out_file" 2>/dev/null &
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
        result_type=$(jq -r 'if .result != null then (.result | type) else "error" end' <"$out_file" 2>/dev/null)
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

# bats test_tags=evm-stress,loadtest
@test "mixed concurrent RPC methods succeed without interfering with each other" {
    # Fire eth_blockNumber, eth_getBalance, and eth_getLogs simultaneously to check
    # that multiplexing different method handlers on the same node doesn't cause
    # cross-request corruption, dropped responses, or panics.
    # 20 goroutines × 3 methods = 60 concurrent in-flight requests.
    tmpdir=$(mktemp -d)
    pids=()

    for i in $(seq 1 20); do
        cast block-number \
            >"$tmpdir/bn_$i" 2>/dev/null &
        pids+=($!)

        cast balance "$eth_address" \
            >"$tmpdir/bal_$i" 2>/dev/null &
        pids+=($!)

        curl -s -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":"0x0","toBlock":"0x0"}],"id":1}' \
            "$L2_RPC_URL" >"$tmpdir/log_$i" 2>/dev/null &
        pids+=($!)
    done

    fail_count=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
        fi
    done

    # Validate shape of each response type.
    for i in $(seq 1 20); do
        bn=$(cat "$tmpdir/bn_$i" 2>/dev/null)
        if ! [[ "$bn" =~ ^[0-9]+$ ]]; then
            echo "eth_blockNumber request $i returned non-numeric: $bn" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        bal=$(cat "$tmpdir/bal_$i" 2>/dev/null)
        if ! [[ "$bal" =~ ^[0-9]+$ ]]; then
            echo "eth_getBalance request $i returned non-numeric: $bal" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        log_type=$(jq -r 'if .result != null then (.result | type) else "error" end' <"$tmpdir/log_$i" 2>/dev/null)
        if [[ "$log_type" != "array" ]]; then
            echo "eth_getLogs request $i returned non-array: $(cat "$tmpdir/log_$i")" >&2
            fail_count=$(( fail_count + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count failures across 60 mixed concurrent RPC requests" >&2
        return 1
    fi
}
