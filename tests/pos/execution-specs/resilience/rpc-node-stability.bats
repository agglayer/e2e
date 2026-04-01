#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,rpc,s1

# RPC Node Stability Under Adversarial Load
# =============================================
# Tests targeting S1 scenarios where RPC abuse could crash the node
# or exhaust resources, indirectly halting block production.
#
# Risk areas covered:
#   - Unbounded eth_getLogs queries
#   - Large eth_call state reads
#   - Concurrent RPC connection exhaustion
#   - Debug trace resource consumption
#   - Filter/subscription leak
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with at least one Bor node
#
# RUN: bats tests/pos/execution-specs/resilience/rpc-node-stability.bats

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet
}

teardown() {
    jobs -p | xargs -r kill 2>/dev/null || true
    [[ -n "${_test_tmpdir:-}" && -d "${_test_tmpdir:-}" ]] && rm -rf "$_test_tmpdir"
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=resilience,rpc,s1,getlogs
@test "RPC: large eth_getLogs range does not crash node" {
    # Targets: eth/filters — unbounded log queries.
    # A large block range in eth_getLogs could cause memory exhaustion.
    # The node should either return results within limits or return an
    # error, but must NOT crash.

    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Requesting eth_getLogs for blocks 0 to $current_block..." >&3

    local current_hex
    current_hex=$(printf '0x%x' "$current_block")

    local response
    response=$(curl -s -m 30 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x0\",\"toBlock\":\"${current_hex}\"}],\"id\":1}") || true

    if [[ -n "$response" ]]; then
        local has_error
        has_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
        if [[ -n "$has_error" ]]; then
            echo "Node returned error (expected): $(echo "$has_error" | head -c 200)" >&3
        else
            local result_count
            result_count=$(echo "$response" | jq '.result | length' 2>/dev/null) || result_count="unknown"
            echo "Node returned $result_count logs" >&3
        fi
    else
        echo "Request timed out or failed — checking node health" >&3
    fi

    # Critical: node must still be alive after the heavy query
    sleep 2
    _assert_rpc_alive "$L2_RPC_URL" "after large getLogs"

    # Verify block production continues
    local post_block
    post_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_block_advance "$post_block" 3 30
    echo "Node survived large getLogs query and continues producing blocks" >&3
}

# bats test_tags=resilience,rpc,s1,concurrent
@test "RPC: concurrent request burst does not crash node" {
    # Targets: rpc/server — connection and goroutine limits.
    # A burst of concurrent RPC requests should not exhaust goroutines
    # or cause the node to become unresponsive.

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Sending 100 concurrent eth_blockNumber requests..." >&3

    _test_tmpdir=$(mktemp -d)
    local pids=()

    for i in $(seq 1 100); do
        curl -s -m 10 --connect-timeout 5 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            > "${_test_tmpdir}/resp_${i}.json" 2>/dev/null &
        pids+=($!)
    done

    # Wait for all requests to complete
    local completed=0 failed=0
    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            completed=$(( completed + 1 ))
        else
            failed=$(( failed + 1 ))
        fi
    done

    echo "Completed: $completed, Failed: $failed" >&3

    # Count successful responses
    local success=0
    for f in "${_test_tmpdir}"/resp_*.json; do
        if [[ -f "$f" ]]; then
            local result
            result=$(jq -r '.result // empty' "$f" 2>/dev/null)
            if [[ -n "$result" ]]; then
                success=$(( success + 1 ))
            fi
        fi
    done

    rm -rf "$_test_tmpdir"
    _test_tmpdir=""

    echo "$success out of 100 requests returned valid results" >&3

    # Node must still be alive
    sleep 2
    _assert_rpc_alive "$L2_RPC_URL" "after concurrent burst"

    # Block production must continue
    _wait_for_block_advance "$start_block" 3 30
    echo "Node survived concurrent burst" >&3
}

# bats test_tags=resilience,rpc,s1,heavy-eth-call
@test "RPC: heavy eth_call does not crash node" {
    # Targets: core/vm, ethapi — state access during eth_call.
    # A complex eth_call that reads many state slots should not crash
    # the node or consume unbounded memory.

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Generate a 32KB calldata payload
    local large_calldata
    large_calldata="0x$(python3 -c "print('00' * 32768)")"
    if [[ -z "$large_calldata" || "$large_calldata" == "0x" ]]; then
        skip "python3 not available for calldata generation"
    fi

    echo "Sending eth_call with 32KB calldata..." >&3

    local response
    response=$(curl -s -m 30 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"0x0000000000000000000000000000000000000001\",\"data\":\"${large_calldata}\",\"gas\":\"0x7A120\"},\"latest\"],\"id\":1}") || true

    if [[ -n "$response" ]]; then
        local has_error
        has_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
        if [[ -n "$has_error" ]]; then
            echo "eth_call returned error (expected): $(echo "$has_error" | head -c 200)" >&3
        else
            echo "eth_call succeeded" >&3
        fi
    fi

    # Critical: node must survive
    sleep 2
    _assert_rpc_alive "$L2_RPC_URL" "after heavy eth_call"
    _wait_for_block_advance "$start_block" 3 30
    echo "Node survived heavy eth_call" >&3
}

# bats test_tags=resilience,rpc,s1,filter-leak
@test "RPC: creating many filters does not exhaust node resources" {
    # Targets: eth/filters — filter/subscription management.
    # Creating many eth_newFilter subscriptions could leak resources
    # if not properly cleaned up or bounded.

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Creating 200 eth_newFilter subscriptions..." >&3

    local filter_ids=()
    for i in $(seq 1 200); do
        local response
        response=$(curl -s -m 5 --connect-timeout 2 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_newFilter","params":[{"fromBlock":"latest"}],"id":1}') || true

        local filter_id
        filter_id=$(echo "$response" | jq -r '.result // empty' 2>/dev/null)
        if [[ -n "$filter_id" ]]; then
            filter_ids+=("$filter_id")
        fi
    done

    echo "Created ${#filter_ids[@]} filters" >&3

    # Node must still be alive WITH all filters still open
    _assert_rpc_alive "$L2_RPC_URL" "with 200 open filters"

    # Block production must continue with filters alive
    _wait_for_block_advance "$start_block" 3 30
    echo "Node survived filter creation burst with all filters open" >&3

    # Clean up filters
    local cleaned=0
    for fid in "${filter_ids[@]}"; do
        local payload
        payload=$(jq -n --arg fid "$fid" '{"jsonrpc":"2.0","method":"eth_uninstallFilter","params":[$fid],"id":1}')
        curl -s -m 2 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1 || true
        cleaned=$(( cleaned + 1 ))
    done

    echo "Cleaned up $cleaned filters" >&3
}

# bats test_tags=resilience,rpc,s1,trace
@test "RPC: debug_traceBlockByNumber does not crash on recent block" {
    # Targets: eth/tracers — tracer resource consumption.
    # Tracing a block with many transactions could trigger OOM or panic
    # in the tracer if gas accounting is incorrect.

    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Pick a block that's a few blocks old (more likely to have txs)
    local trace_block=$(( current_block - 3 ))
    if [[ "$trace_block" -lt 1 ]]; then
        trace_block=1
    fi

    local trace_hex
    trace_hex=$(printf '0x%x' "$trace_block")
    echo "Tracing block $trace_block ($trace_hex)..." >&3

    local response
    response=$(curl -s -m 30 --connect-timeout 5 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"debug_traceBlockByNumber\",\"params\":[\"${trace_hex}\",{\"tracer\":\"callTracer\"}],\"id\":1}") || true

    if [[ -n "$response" ]]; then
        local has_error
        has_error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$has_error" ]]; then
            echo "Trace returned error: $has_error" >&3
        else
            local trace_count
            trace_count=$(echo "$response" | jq '.result | length' 2>/dev/null) || trace_count="unknown"
            echo "Trace returned $trace_count results" >&3
        fi
    else
        echo "Trace request timed out" >&3
    fi

    # Critical: node must survive
    sleep 2
    _assert_rpc_alive "$L2_RPC_URL" "after block trace"

    local post_block
    post_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_block_advance "$post_block" 3 30
    echo "Node survived block tracing" >&3
}

# bats test_tags=resilience,rpc,s1,mixed-load
@test "RPC: mixed heavy read + write load does not degrade block production" {
    # Targets: Overall node stability under mixed workload.
    # Simultaneous heavy RPC reads and transaction submissions should
    # not starve the block production goroutines.

    local wallet
    wallet=$(_fund_ephemeral_wallet "1ether")
    local pk="${wallet%%:*}"
    local addr="${wallet##*:}"

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local start_time
    start_time=$(date +%s)

    # Submit transactions (async)
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

    for i in $(seq 0 19); do
        cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
            --nonce $(( nonce + i )) --gas-limit 21000 --gas-price "$gas_price" \
            --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
    done

    # Concurrent heavy read queries (backgrounded)
    _test_tmpdir=$(mktemp -d)

    for i in $(seq 1 20); do
        local bn=$(( start_block - i ))
        [[ "$bn" -lt 0 ]] && bn=0
        local bn_hex
        bn_hex=$(printf '0x%x' "$bn")
        curl -s -m 10 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${bn_hex}\",true],\"id\":1}" \
            > "${_test_tmpdir}/block_${i}.json" 2>/dev/null &
    done

    wait

    rm -rf "$_test_tmpdir"
    _test_tmpdir=""

    # Measure block production rate
    sleep 20
    local end_block
    end_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    local blocks_produced=$(( end_block - start_block ))

    echo "Produced $blocks_produced blocks in ${elapsed}s under mixed load" >&3

    # Chain must not have halted
    if [[ "$blocks_produced" -lt 3 ]]; then
        echo "CRITICAL: Block production nearly halted under mixed load" >&2
        return 1
    fi
}
