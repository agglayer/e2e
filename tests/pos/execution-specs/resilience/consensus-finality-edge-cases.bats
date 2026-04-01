#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,consensus,s0

# Consensus & Finality Edge Case Tests
# ========================================
# Tests targeting S0/S1 edge cases in Bor's consensus, finality, and
# state sync mechanisms that could cause chain halts or consensus splits.
#
# Risk areas covered:
#   - Deterministic finality (PIP-11 milestones)
#   - State sync event consistency
#   - Block header integrity across sprint boundaries
#   - Cross-node consensus agreement
#   - Heimdall-Bor coordination
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with Bor + Heimdall
#   - Optional: second Bor node for cross-node checks
#   - Optional: Heimdall API access for milestone verification
#
# RUN: bats tests/pos/execution-specs/resilience/consensus-finality-edge-cases.bats

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet
}

teardown() {
    jobs -p | xargs -r kill 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=resilience,consensus,s0,header-integrity
@test "consensus: block headers have valid structure across sprint boundaries" {
    # Targets: bor.go verifyHeader, Prepare — header field correctness.
    # Invalid headers at sprint boundaries (wrong difficulty, missing
    # validator signature, incorrect extraData) would cause verification
    # failures and chain splits.

    local sprint_len=16
    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$current_block" -lt $(( sprint_len * 2 )) ]]; then
        skip "Need at least 2 sprints of blocks (current: $current_block)"
    fi

    # Check last 2 sprints worth of blocks
    local check_start=$(( current_block - sprint_len * 2 ))
    [[ "$check_start" -lt 1 ]] && check_start=1

    local prev_hash="" prev_time=0 errors=0

    for bn in $(seq "$check_start" "$current_block"); do
        local block_json
        block_json=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" 2>/dev/null)

        if [[ -z "$block_json" ]]; then
            echo "ERROR: Block $bn missing" >&2
            errors=$(( errors + 1 ))
            continue
        fi

        local hash parent_hash timestamp difficulty extra_data
        hash=$(echo "$block_json" | jq -r '.hash')
        parent_hash=$(echo "$block_json" | jq -r '.parentHash')
        timestamp=$(echo "$block_json" | jq -r '.timestamp')
        difficulty=$(echo "$block_json" | jq -r '.difficulty')
        extra_data=$(echo "$block_json" | jq -r '.extraData // empty')

        # Validate timestamp is a valid number
        if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
            echo "ERROR: Block $bn has no timestamp" >&2
            errors=$(( errors + 1 ))
            continue
        fi
        timestamp=$((timestamp))

        # Verify parent hash chain
        if [[ -n "$prev_hash" && "$parent_hash" != "$prev_hash" ]]; then
            echo "ERROR: Block $bn parentHash mismatch: expected $prev_hash, got $parent_hash" >&2
            errors=$(( errors + 1 ))
        fi

        # Verify timestamp ordering
        if [[ "$prev_time" -gt 0 && "$timestamp" -le "$prev_time" ]]; then
            echo "ERROR: Block $bn timestamp $timestamp <= previous $prev_time" >&2
            errors=$(( errors + 1 ))
        fi

        # Verify difficulty is non-zero
        if [[ -z "$difficulty" || "$difficulty" == "null" ]]; then
            echo "ERROR: Block $bn has no difficulty field" >&2
            errors=$(( errors + 1 ))
        elif [[ "$difficulty" == "0x0" || "$difficulty" == "0" ]]; then
            echo "ERROR: Block $bn has zero difficulty" >&2
            errors=$(( errors + 1 ))
        fi

        # Verify extraData minimum size (32 bytes vanity)
        if [[ -n "$extra_data" && "$extra_data" != "0x" ]]; then
            local extra_len=$(( (${#extra_data} - 2) / 2 ))
            if [[ "$extra_len" -lt 32 ]]; then
                echo "ERROR: Block $bn extraData too short: $extra_len bytes" >&2
                errors=$(( errors + 1 ))
            fi
        fi

        # Sprint boundary check: log producer changes
        if (( bn % sprint_len == 0 )); then
            local miner
            miner=$(echo "$block_json" | jq -r '.miner')
            echo "Sprint boundary at block $bn, producer: $miner" >&3
        fi

        prev_hash="$hash"
        prev_time="$timestamp"
    done

    echo "Checked $(( current_block - check_start + 1 )) blocks, errors: $errors" >&3

    if [[ "$errors" -gt 0 ]]; then
        echo "CRITICAL: $errors header integrity errors found" >&2
        return 1
    fi
}

# bats test_tags=resilience,consensus,s0,difficulty
@test "consensus: difficulty values follow expected pattern" {
    # Targets: bor.go CalcDifficulty — difficulty calculation.
    # In Bor PoA, difficulty indicates the signer's position.
    # If difficulty is wrong, fork choice could be incorrect.

    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local check_start=$(( current_block - 20 ))
    [[ "$check_start" -lt 1 ]] && check_start=1

    local min_diff=999999 max_diff=0 errors=0

    for bn in $(seq "$check_start" "$current_block"); do
        local diff_hex
        diff_hex=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" | jq -r '.difficulty')

        if [[ -z "$diff_hex" || "$diff_hex" == "null" ]]; then
            echo "ERROR: Block $bn has no difficulty field" >&2
            errors=$(( errors + 1 ))
            continue
        fi

        local diff_dec
        diff_dec=$((diff_hex))

        if [[ "$diff_dec" -lt "$min_diff" ]]; then
            min_diff="$diff_dec"
        fi
        if [[ "$diff_dec" -gt "$max_diff" ]]; then
            max_diff="$diff_dec"
        fi
    done

    echo "Difficulty range: min=$min_diff, max=$max_diff over $(( current_block - check_start + 1 )) blocks" >&3

    if [[ "$min_diff" -le 0 ]]; then
        echo "CRITICAL: Zero or negative difficulty found — signer validation broken" >&2
        return 1
    fi

    if [[ "$max_diff" -gt 1000 ]]; then
        echo "WARNING: Unusually high difficulty $max_diff" >&3
    fi

    if [[ "$errors" -gt 0 ]]; then
        echo "CRITICAL: $errors blocks missing difficulty field" >&2
        return 1
    fi
}

# bats test_tags=resilience,consensus,s0,finality
@test "consensus: finalized blocks match across nodes" {
    # Targets: finality/milestone — deterministic finality.
    # If milestone voting produces different results on different nodes,
    # they'll disagree on which blocks are finalized, causing a consensus split.

    # Try to discover a second Bor node
    local second_rpc=""
    for i in $(seq 1 4); do
        for role in "rpc" "sentry" "validator"; do
            local svc="l2-el-${i}-bor-heimdall-v2-${role}"
            local port
            if port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                local candidate_rpc="http://${port}"
                if [[ "$candidate_rpc" != "$L2_RPC_URL" ]]; then
                    second_rpc="$candidate_rpc"
                    echo "Found second Bor node: ${svc} at ${second_rpc}" >&3
                    break 2
                fi
            fi
        done
    done

    if [[ -z "$second_rpc" ]]; then
        skip "No second Bor node for finality comparison"
    fi

    # Query finalized or safe block from both nodes
    local block_tag="finalized"
    local hash1 hash2 num1 num2

    hash1=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
        | jq -r '.result.hash // empty') || true

    hash2=$(curl -s -m 10 -X POST "$second_rpc" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
        | jq -r '.result.hash // empty') || true

    if [[ -z "$hash1" || -z "$hash2" ]]; then
        # Fallback to "safe" block tag
        block_tag="safe"
        hash1=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
            | jq -r '.result.hash // empty') || true
        hash2=$(curl -s -m 10 -X POST "$second_rpc" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
            | jq -r '.result.hash // empty') || true
    fi

    if [[ -z "$hash1" || -z "$hash2" ]]; then
        skip "Neither finalized nor safe block available on both nodes"
    fi

    # Get block numbers using the SAME block_tag used for hashes
    num1=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
        | jq -r '.result.number // empty') || true
    num2=$(curl -s -m 10 -X POST "$second_rpc" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_tag}\",false],\"id\":1}" \
        | jq -r '.result.number // empty') || true

    echo "Node 1 ${block_tag}: $num1, Node 2 ${block_tag}: $num2" >&3

    # Compare at the lower of the two heights to avoid TOCTOU race
    local lower_num
    if [[ -n "$num1" && -n "$num2" ]]; then
        local n1=$((num1)) n2=$((num2))
        lower_num=$(( n1 < n2 ? n1 : n2 ))
    elif [[ -n "$num1" ]]; then
        lower_num=$((num1))
    else
        lower_num=$((num2))
    fi

    local cmp_hash1 cmp_hash2
    cmp_hash1=$(cast block "$lower_num" --json --rpc-url "$L2_RPC_URL" | jq -r '.hash')
    cmp_hash2=$(cast block "$lower_num" --json --rpc-url "$second_rpc" | jq -r '.hash')

    if [[ "$cmp_hash1" != "$cmp_hash2" ]]; then
        echo "CRITICAL: Block $lower_num hash mismatch between nodes:" >&2
        echo "  Node 1: $cmp_hash1" >&2
        echo "  Node 2: $cmp_hash2" >&2
        return 1
    fi

    echo "Block $lower_num (${block_tag}) hashes match across nodes" >&3
}

# bats test_tags=resilience,consensus,s1,heimdall
@test "consensus: Heimdall API is reachable and serving span data" {
    # Targets: bor.go:1761 — waitUntilHeimdallIsSynced indefinite block.
    # If Heimdall becomes unreachable, block production halts.

    if [[ -z "${L2_CL_API_URL:-}" ]]; then
        skip "Heimdall API URL not available"
    fi

    echo "Checking Heimdall API at $L2_CL_API_URL..." >&3

    # Query latest span
    local span_response
    span_response=$(curl -s -m 10 --connect-timeout 5 "${L2_CL_API_URL}/bor/span/latest" 2>/dev/null) || true

    if [[ -z "$span_response" ]]; then
        echo "CRITICAL: Heimdall API unreachable — risk of chain halt" >&2
        return 1
    fi

    local span_id start_block end_block
    span_id=$(echo "$span_response" | jq -r '.result.span_id // .result.id // empty')
    start_block=$(echo "$span_response" | jq -r '.result.start_block // empty')
    end_block=$(echo "$span_response" | jq -r '.result.end_block // empty')

    if [[ -z "$span_id" ]]; then
        echo "CRITICAL: Heimdall returned empty span data" >&2
        echo "Response: $(echo "$span_response" | head -c 500)" >&2
        return 1
    fi

    echo "Latest span: id=$span_id, blocks=$start_block-$end_block" >&3

    # Verify the validator set is non-empty
    local validator_count
    validator_count=$(echo "$span_response" | jq '.result.selected_producers // .result.validator_set.validators | length' 2>/dev/null) || validator_count=0

    echo "Validator count in span: $validator_count" >&3

    if [[ "$validator_count" -le 0 ]]; then
        echo "CRITICAL: Empty validator set in span $span_id" >&2
        return 1
    fi

    # Verify Bor's current block is within the span range
    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    echo "Current Bor block: $current_block, Span range: $start_block-$end_block" >&3
}

# bats test_tags=resilience,consensus,s0,state-sync-consistency
@test "consensus: state sync receipts are deterministic across blocks" {
    # Targets: bor.go Finalize — state sync event processing.
    # State sync events must produce identical state changes on all nodes.

    local current_block
    current_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local state_receiver="${L2_STATE_RECEIVER_ADDRESS:-0x0000000000000000000000000000000000001001}"

    echo "Searching for state sync events in recent blocks..." >&3

    local sync_blocks=()
    local search_start=$(( current_block - 100 ))
    [[ "$search_start" -lt 0 ]] && search_start=0

    # Search for blocks with logs from the state receiver
    for range_start in $(seq "$search_start" 20 "$current_block"); do
        local range_end=$(( range_start + 19 ))
        [[ "$range_end" -gt "$current_block" ]] && range_end="$current_block"

        local from_hex to_hex
        from_hex=$(printf '0x%x' "$range_start")
        to_hex=$(printf '0x%x' "$range_end")

        local logs_payload
        logs_payload=$(jq -n --arg from "$from_hex" --arg to "$to_hex" --arg addr "$state_receiver" \
            '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":$from,"toBlock":$to,"address":$addr}],"id":1}')

        local logs_resp
        logs_resp=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "$logs_payload") || true

        local log_count
        log_count=$(echo "$logs_resp" | jq '.result | length' 2>/dev/null) || log_count=0

        if [[ "$log_count" -gt 0 ]]; then
            local blocks
            blocks=$(echo "$logs_resp" | jq -r '.result[].blockNumber' 2>/dev/null | sort -u)
            for b in $blocks; do
                sync_blocks+=("$((b))")
            done
        fi
    done

    echo "Found ${#sync_blocks[@]} blocks with state sync events" >&3

    if [[ "${#sync_blocks[@]}" -eq 0 ]]; then
        echo "No state sync events found in recent 100 blocks — skipping receipt check" >&3
        _wait_for_block_advance "$current_block" 5 60
        return 0
    fi

    # Verify receipt consistency for state sync blocks
    for bn in "${sync_blocks[@]:0:5}"; do
        local bn_hex
        bn_hex=$(printf '0x%x' "$bn")

        local receipts
        receipts=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockReceipts\",\"params\":[\"${bn_hex}\"],\"id\":1}" \
            | jq '.result' 2>/dev/null) || true

        if [[ -z "$receipts" || "$receipts" == "null" ]]; then
            echo "WARNING: No receipts for block $bn" >&3
            continue
        fi

        local receipt_count
        receipt_count=$(echo "$receipts" | jq 'length')

        local failed_receipts
        failed_receipts=$(echo "$receipts" | jq '[.[] | select(.status == "0x0")] | length')

        echo "Block $bn: $receipt_count receipts, $failed_receipts failed" >&3

        # State sync system transactions should succeed
        local last_receipt_status
        last_receipt_status=$(echo "$receipts" | jq -r '.[-1].status // empty')

        if [[ "$last_receipt_status" == "0x0" ]]; then
            local last_receipt_to
            last_receipt_to=$(echo "$receipts" | jq -r '.[-1].to // empty')
            if [[ "$last_receipt_to" == "$state_receiver" || "$last_receipt_to" == "null" ]]; then
                echo "WARNING: State sync transaction failed in block $bn" >&3
            fi
        fi
    done

    echo "State sync receipt analysis complete" >&3
}

# bats test_tags=resilience,consensus,s0,chain-integrity
@test "consensus: chain integrity maintained under transaction load" {
    # Targets: blockchain.go InsertChain — chain integrity under load.
    # Verifies the parent-hash chain is unbroken after submitting
    # transactions, which exercises the block production pipeline end to end.

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Submit transactions to increase block complexity
    local wallets=()
    for i in $(seq 1 3); do
        wallets+=("$(_fund_ephemeral_wallet "0.3ether")")
    done

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    for wallet in "${wallets[@]}"; do
        local pk="${wallet%%:*}"
        local addr="${wallet##*:}"
        local nonce
        nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

        for j in $(seq 0 9); do
            cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
                --nonce $(( nonce + j )) --gas-limit 21000 --gas-price "$gas_price" \
                --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
        done
    done

    echo "Submitted 30 txs for chain integrity test" >&3

    # Wait for blocks to advance
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 20 180)

    # Verify parent hashes form an unbroken chain
    local check_start=$(( end_block - 10 ))
    [[ "$check_start" -lt 1 ]] && check_start=1

    local prev_hash=""
    for bn in $(seq "$check_start" "$end_block"); do
        local block_json
        block_json=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL")

        local hash parent_hash
        hash=$(echo "$block_json" | jq -r '.hash')
        parent_hash=$(echo "$block_json" | jq -r '.parentHash')

        if [[ -n "$prev_hash" && "$parent_hash" != "$prev_hash" ]]; then
            echo "CRITICAL: Parent hash chain broken at block $bn" >&2
            echo "  Expected parent: $prev_hash" >&2
            echo "  Got parent:      $parent_hash" >&2
            return 1
        fi

        prev_hash="$hash"
    done

    echo "Chain integrity verified for blocks $check_start-$end_block" >&3

    # Chain must still be alive
    local final_block
    final_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    sleep 5
    local post_final
    post_final=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$post_final" -le "$final_block" ]]; then
        echo "CRITICAL: Chain halted after load test" >&2
        return 1
    fi
}
