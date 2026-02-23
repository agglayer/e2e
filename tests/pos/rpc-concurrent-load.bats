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

# bats test_tags=evm-stress,loadtest
@test "higher concurrency watermark: 100 and 500 concurrent eth_blockNumber requests" {
    # Existing tests cap at 50.  This ramps to 100 and 500 to probe connection-pool
    # limits, goroutine exhaustion, and fd pressure on the RPC node.
    for concurrency in 100 500; do
        tmpdir=$(mktemp -d)
        pids=()

        for i in $(seq 1 "$concurrency"); do
            curl -s -X POST \
                -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                "$L2_RPC_URL" >"$tmpdir/result_$i" 2>/dev/null &
            pids+=($!)
        done

        fail_count=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                fail_count=$(( fail_count + 1 ))
            fi
        done

        # Validate every JSON-RPC response contains a hex block number.
        for i in $(seq 1 "$concurrency"); do
            result=$(jq -r '.result // empty' <"$tmpdir/result_$i" 2>/dev/null)
            if [[ -z "$result" ]] || ! [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
                fail_count=$(( fail_count + 1 ))
            fi
        done

        rm -rf "$tmpdir"

        # Allow up to 5 % failure rate at elevated concurrency (connection limits, timeouts).
        max_failures=$(( concurrency * 5 / 100 ))
        if [[ "$fail_count" -gt "$max_failures" ]]; then
            echo "$fail_count / $concurrency requests failed at concurrency=$concurrency (max allowed: $max_failures)" >&2
            return 1
        fi

        echo "Concurrency $concurrency: $fail_count failures (max $max_failures)" >&3
    done
}

# bats test_tags=evm-stress,loadtest
@test "concurrent write/read race: tx submissions and state reads do not interfere" {
    # Submits transactions and reads state simultaneously.  Read operations must
    # always return valid results even while the mempool and state trie are being
    # mutated by concurrent writes.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    nonce=$(cast nonce "$ephemeral_address")
    gas_price=$(cast gas-price)

    tmpdir=$(mktemp -d)
    pids=()

    # 20 async tx submissions (writes) — sends to the zero address.
    for i in $(seq 1 20); do
        cast send \
            --nonce $(( nonce + i - 1 )) \
            --gas-limit 21000 \
            --gas-price "$gas_price" \
            --legacy \
            --async \
            --private-key "$ephemeral_private_key" \
            0x0000000000000000000000000000000000000000 >"$tmpdir/tx_$i" 2>/dev/null &
        pids+=($!)
    done

    # 30 concurrent reads (balance, block number, nonce) fired at the same time.
    for i in $(seq 1 30); do
        (
            case $(( i % 3 )) in
                0) cast balance "$ephemeral_address" ;;
                1) cast block-number ;;
                2) cast nonce "$ephemeral_address" ;;
            esac
        ) >"$tmpdir/read_$i" 2>/dev/null &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # Every read must have returned a valid non-negative integer.
    read_fails=0
    for i in $(seq 1 30); do
        result=$(cat "$tmpdir/read_$i" 2>/dev/null)
        if [[ -z "$result" ]] || ! [[ "$result" =~ ^[0-9]+$ ]]; then
            echo "Read $i returned invalid result: '${result:-empty}'" >&2
            read_fails=$(( read_fails + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    # Allow up to 10 % read failures under concurrent write pressure.
    if [[ "$read_fails" -gt 3 ]]; then
        echo "$read_fails / 30 read operations failed during concurrent tx submissions" >&2
        return 1
    fi

    echo "Write/read race: 30 reads during 20 writes, $read_fails failures" >&3
}

# bats test_tags=evm-stress,loadtest
@test "50 concurrent requests across additional RPC methods succeed" {
    # Existing tests only cover eth_blockNumber, eth_getBalance, and eth_getLogs.
    # This adds eth_getTransactionCount, eth_chainId, eth_gasPrice, eth_getCode,
    # and eth_estimateGas (10 concurrent each = 50 total).
    tmpdir=$(mktemp -d)
    pids=()

    # eth_getTransactionCount
    for i in $(seq 1 10); do
        cast nonce "$eth_address" >"$tmpdir/nonce_$i" 2>/dev/null &
        pids+=($!)
    done
    # eth_chainId
    for i in $(seq 1 10); do
        cast chain-id >"$tmpdir/chainid_$i" 2>/dev/null &
        pids+=($!)
    done
    # eth_gasPrice
    for i in $(seq 1 10); do
        cast gas-price >"$tmpdir/gasprice_$i" 2>/dev/null &
        pids+=($!)
    done
    # eth_getCode (zero-address → no code)
    for i in $(seq 1 10); do
        cast code 0x0000000000000000000000000000000000000000 >"$tmpdir/code_$i" 2>/dev/null &
        pids+=($!)
    done
    # eth_estimateGas (simple transfer)
    for i in $(seq 1 10); do
        cast estimate --from "$eth_address" 0x0000000000000000000000000000000000000001 >"$tmpdir/estimate_$i" 2>/dev/null &
        pids+=($!)
    done

    fail_count=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            fail_count=$(( fail_count + 1 ))
        fi
    done

    # Validate each response category.
    first_nonce="" first_chainid=""

    for i in $(seq 1 10); do
        # eth_getTransactionCount: numeric, all identical (no concurrent writes).
        val=$(cat "$tmpdir/nonce_$i" 2>/dev/null)
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "eth_getTransactionCount $i returned non-numeric: '$val'" >&2
            fail_count=$(( fail_count + 1 ))
        elif [[ -z "$first_nonce" ]]; then
            first_nonce="$val"
        elif [[ "$val" != "$first_nonce" ]]; then
            echo "eth_getTransactionCount inconsistency: $i=$val vs first=$first_nonce" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        # eth_chainId: numeric, all must be identical.
        val=$(cat "$tmpdir/chainid_$i" 2>/dev/null)
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "eth_chainId $i returned non-numeric: '$val'" >&2
            fail_count=$(( fail_count + 1 ))
        elif [[ -z "$first_chainid" ]]; then
            first_chainid="$val"
        elif [[ "$val" != "$first_chainid" ]]; then
            echo "eth_chainId inconsistency: $i=$val vs first=$first_chainid" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        # eth_gasPrice: positive integer.
        val=$(cat "$tmpdir/gasprice_$i" 2>/dev/null)
        if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -eq 0 ]]; then
            echo "eth_gasPrice $i returned invalid: '$val'" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        # eth_getCode at zero-address: must be "0x" (no code).
        val=$(cat "$tmpdir/code_$i" 2>/dev/null)
        if [[ "$val" != "0x" ]]; then
            echo "eth_getCode $i for zero-address expected '0x', got: '$val'" >&2
            fail_count=$(( fail_count + 1 ))
        fi

        # eth_estimateGas: positive integer (simple transfer ≈ 21000).
        val=$(cat "$tmpdir/estimate_$i" 2>/dev/null)
        if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -eq 0 ]]; then
            echo "eth_estimateGas $i returned invalid: '$val'" >&2
            fail_count=$(( fail_count + 1 ))
        fi
    done

    rm -rf "$tmpdir"

    if [[ "$fail_count" -ne 0 ]]; then
        echo "$fail_count failures across 50 additional RPC method requests" >&2
        return 1
    fi
}
