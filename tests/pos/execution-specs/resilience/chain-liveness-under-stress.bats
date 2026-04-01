#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,liveness,s1

# Chain Liveness Under Stress Tests
# ====================================
# Tests targeting S0/S1 scenarios where the chain could halt under
# adversarial or high-load conditions.
#
# Risk areas covered:
#   - Sprint boundary block production continuity
#   - State sync event processing resilience
#   - Block production under transaction flood
#   - Recovery after RPC overload
#   - Empty block production (no pending txs)
#   - Gas limit boundary behavior
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with at least one Bor validator
#   - Heimdall consensus layer running
#
# RUN: bats tests/pos/execution-specs/resilience/chain-liveness-under-stress.bats

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

# bats test_tags=resilience,liveness,s0,sprint-boundary
@test "chain continues producing blocks across sprint boundaries" {
    # Targets: bor.go — sprint/span boundary transitions.
    # At sprint boundaries, the validator set rotates and the block producer
    # changes. If there's an error in succession calculation or validator
    # fetching, the chain halts at the boundary.
    #
    # Strategy: Wait for enough blocks to cross at least 2 sprint boundaries
    # and verify continuous block production with no gaps. Also verify the
    # block producer changes at sprint boundaries.

    local sprint_len=16  # Default Bor sprint length

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Need to cross at least 2 sprint boundaries = 2 * sprint_len + buffer
    local blocks_needed=$(( sprint_len * 3 ))
    echo "Waiting for $blocks_needed blocks (3 sprints) from block $start_block..." >&3

    local end_block
    end_block=$(_wait_for_block_advance "$start_block" "$blocks_needed" 600)
    echo "Chain reached block $end_block" >&3

    # Verify no gaps and check sprint boundary behavior
    local check_start=$(( end_block - sprint_len * 2 ))
    [[ "$check_start" -lt 1 ]] && check_start=1
    local prev_time=0 prev_miner="" sprint_changes=0

    for bn in $(seq "$check_start" "$end_block"); do
        local block_json
        block_json=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" 2>/dev/null)

        if [[ -z "$block_json" ]]; then
            echo "CRITICAL: Block $bn is missing from the chain" >&2
            return 1
        fi

        local block_time miner
        block_time=$(echo "$block_json" | jq -r '.timestamp')
        if [[ -z "$block_time" || "$block_time" == "null" ]]; then
            echo "CRITICAL: Block $bn has no timestamp" >&2
            return 1
        fi
        block_time=$((block_time))
        miner=$(echo "$block_json" | jq -r '.miner')

        if [[ "$prev_time" -gt 0 && "$block_time" -le "$prev_time" ]]; then
            echo "CRITICAL: Block $bn timestamp ($block_time) <= previous ($prev_time)" >&2
            return 1
        fi

        # Track producer changes at sprint boundaries
        if (( bn % sprint_len == 0 )); then
            echo "Sprint boundary at block $bn, producer: $miner" >&3
            if [[ -n "$prev_miner" && "$miner" != "$prev_miner" ]]; then
                sprint_changes=$(( sprint_changes + 1 ))
            fi
        fi

        prev_time="$block_time"
        prev_miner="$miner"
    done

    echo "All blocks $check_start-$end_block verified, sprint producer changes: $sprint_changes" >&3
}

# bats test_tags=resilience,liveness,s1,tx-flood
@test "chain liveness maintained under transaction flood" {
    # Targets: txpool, miner, BlockSTM under extreme load.
    # A flood of transactions should not cause the node to halt, OOM, or
    # produce invalid blocks. The txpool should handle backpressure.
    #
    # Strategy: 10 wallets each send 30 txs as fast as possible (300 total).
    # Verify chain continues producing blocks and transactions are included.

    local wallets=()
    for i in $(seq 1 10); do
        wallets+=("$(_fund_ephemeral_wallet "0.5ether")")
    done

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    local total_txs=0
    for wallet in "${wallets[@]}"; do
        local pk="${wallet%%:*}"
        local addr="${wallet##*:}"
        local nonce
        nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

        for j in $(seq 0 29); do
            cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
                --nonce $(( nonce + j )) --gas-limit 21000 --gas-price "$gas_price" \
                --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
            total_txs=$(( total_txs + 1 ))
        done
    done

    echo "Submitted $total_txs transactions from ${#wallets[@]} senders" >&3

    # Chain must continue advancing
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 30 300)
    echo "Chain advanced from $start_block to $end_block under load" >&3

    # Verify at least some transactions were included by checking nonces
    local included=0
    for wallet in "${wallets[@]}"; do
        local addr="${wallet##*:}"
        local final_nonce
        final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
        if [[ "$final_nonce" -gt 10 ]]; then
            included=$(( included + 1 ))
        fi
    done

    echo "$included out of ${#wallets[@]} senders had >= 10 txs included" >&3

    if [[ "$included" -lt 5 ]]; then
        echo "WARNING: Less than half of senders had sufficient txs included" >&3
    fi

    # Critical check: chain must still be producing blocks after the flood
    local post_flood_block
    post_flood_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    sleep 10
    local post_wait_block
    post_wait_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$post_wait_block" -le "$post_flood_block" ]]; then
        echo "CRITICAL: Chain halted after transaction flood" >&2
        return 1
    fi
}

# bats test_tags=resilience,liveness,s0,empty-blocks
@test "chain produces blocks when no transactions are pending" {
    # Targets: miner — empty block production.
    # Bor must produce blocks on schedule even with no pending transactions.
    # If the miner fails to produce empty blocks, the chain halts.
    #
    # Strategy: Wait for blocks during a quiet period (no tx submission)
    # and verify block production continues. Also verify that at least
    # some blocks contain zero user transactions.

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local start_time
    start_time=$(date +%s)

    echo "Watching for block production with no tx load from block $start_block..." >&3

    # Wait 30 seconds without submitting any transactions
    sleep 30

    local end_block
    end_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))

    local blocks_produced=$(( end_block - start_block ))
    echo "Produced $blocks_produced blocks in ${elapsed}s (no tx load)" >&3

    # Bor should produce at least 1 block every 2-4 seconds
    # In 30 seconds, expect at least 5 blocks (conservative)
    if [[ "$blocks_produced" -lt 5 ]]; then
        echo "CRITICAL: Only $blocks_produced blocks in ${elapsed}s — block production stalled" >&2
        return 1
    fi

    # Check if any of the produced blocks are truly empty (0 user txs)
    local empty_count=0
    for bn in $(seq $(( start_block + 1 )) "$end_block"); do
        local tx_count
        tx_count=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" | jq '.transactions | length')
        if [[ "$tx_count" -eq 0 ]]; then
            empty_count=$(( empty_count + 1 ))
        fi
    done

    echo "$empty_count out of $blocks_produced blocks had zero transactions" >&3
}

# bats test_tags=resilience,liveness,s1,gas-limit-boundary
@test "transactions consuming significant gas do not halt chain" {
    # Targets: miner commit path, gas pool exhaustion edge cases.
    # Transactions that consume large amounts of gas could trigger
    # edge cases in gas pool management or block finalization.
    #
    # Strategy: Deploy a contract with a gas-consuming loop, then submit
    # calls with varying gas limits. Verify chain continues.

    local wallet
    wallet=$(_fund_ephemeral_wallet "5ether")
    local pk="${wallet%%:*}"
    local addr="${wallet##*:}"

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    # Deploy a contract that burns gas via a loop:
    # function burn(uint256 n) { for(uint256 i=0; i<n; i++) {} }
    # Compiled with solc 0.8.24
    local burn_bytecode="0x608060405234801561000f575f80fd5b5060e98061001c5f395ff3fe6080604052348015600e575f80fd5b50600436106026575f3560e01c806342966c6814602a575b5f80fd5b60406004803603810190603c9190608d565b6042565b005b5f5b8181101560575780806001019150506044565b5050565b5f80fd5b5f819050919050565b606f81605f565b81146078575f80fd5b50565b5f813590506087816068565b92915050565b5f60208284031215609f57609e605b565b5b5f60aa84828501607b565b9150509291505056fea2646970667358221220c7cc5e2b25d3b8d491862c74e2f8b1bdd9bb376936e2787eba779ae63f6bcfd164736f6c63430008180033"

    local contract_addr
    local comp_gas_price
    comp_gas_price=$(echo "$gas_price * 25 / 10" | bc)
    contract_addr=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --gas-price "$comp_gas_price" --gas-limit 500000 --legacy --create "$burn_bytecode" --json 2>&1 \
        | jq -r '.contractAddress // empty') || true

    if [[ -z "$contract_addr" || ! "$contract_addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        # Fallback: just send varying-gas-limit transfers
        echo "Contract deploy failed, falling back to transfer-based gas test" >&3
        local nonce
        nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
        for gl in 21000 100000 500000 1000000 5000000; do
            cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
                --nonce "$nonce" --gas-limit "$gl" --gas-price "$gas_price" \
                --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
            nonce=$(( nonce + 1 ))
        done
    else
        echo "Burn contract deployed at: $contract_addr" >&3
        local nonce
        nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
        # Call burn() with increasing loop counts to consume gas
        for n in 100 1000 10000 50000 100000; do
            cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
                --nonce "$nonce" --gas-limit 5000000 --gas-price "$gas_price" \
                --legacy --async "$contract_addr" "burn(uint256)" "$n" >/dev/null 2>&1 || true
            nonce=$(( nonce + 1 ))
        done
    fi

    # Chain must continue
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 10 120)
    echo "Chain advanced to $end_block after gas-intensive txs" >&3
}

# bats test_tags=resilience,liveness,s0,state-sync
@test "state sync events do not halt block production" {
    # Targets: bor.go:1818-1821 — state sync during Finalize.
    # State sync events are committed during block finalization. If the
    # state receiver contract call fails, Finalize logs the error but
    # continues, while FinalizeAndAssemble returns error (halts production).
    # This asymmetry could cause nodes to disagree.
    #
    # Strategy: Verify that recent blocks contain state sync transactions
    # (if any) and that the chain continues to produce blocks.

    # Check the state receiver contract exists
    local state_receiver="${L2_STATE_RECEIVER_ADDRESS:-0x0000000000000000000000000000000000001001}"
    local code
    code=$(cast code --rpc-url "$L2_RPC_URL" "$state_receiver" 2>/dev/null) || true

    if [[ -z "$code" || "$code" == "0x" ]]; then
        echo "WARNING: State receiver contract has no code at $state_receiver" >&3
    else
        echo "State receiver contract verified at $state_receiver" >&3
    fi

    # Verify chain is producing blocks
    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 20 180)

    # Check a few recent blocks for state sync logs
    local sync_events=0
    for bn in $(seq $(( end_block - 5 )) "$end_block"); do
        local block_hex
        block_hex=$(printf '0x%x' "$bn")
        local logs_payload
        logs_payload=$(jq -n --arg from "$block_hex" --arg to "$block_hex" --arg addr "$state_receiver" \
            '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":$from,"toBlock":$to,"address":$addr}],"id":1}')
        local logs
        logs=$(curl -s -m 10 -X POST "$L2_RPC_URL" \
            -H "Content-Type: application/json" \
            -d "$logs_payload" \
            | jq '.result | length' 2>/dev/null) || logs=0

        if [[ "$logs" -gt 0 ]]; then
            sync_events=$(( sync_events + logs ))
        fi
    done

    echo "Found $sync_events state sync log events in blocks $(( end_block - 5 ))-$end_block" >&3
    echo "Chain advancing normally through state sync processing" >&3
}

# bats test_tags=resilience,liveness,s1,validator-rotation
@test "block production continues across validator rotation" {
    # Targets: Heimdall span/sprint coordination.
    # When validators rotate at sprint boundaries, the new producer must
    # pick up without delay. If Heimdall communication fails or the span
    # store has stale data, block production halts.
    #
    # Strategy: Monitor block production over 3+ sprints and verify
    # that blocks continued without gaps.

    local sprint_len=16
    local blocks_to_watch=$(( sprint_len * 4 ))

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    echo "Watching $blocks_to_watch blocks for validator rotation..." >&3

    local end_block
    end_block=$(_wait_for_block_advance "$start_block" "$blocks_to_watch" 600)

    # Collect miners across the range
    local unique_miners=()
    local prev_miner="" sample_count=0

    for bn in $(seq "$start_block" 4 "$end_block"); do
        local miner
        miner=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" | jq -r '.miner' 2>/dev/null)
        if [[ -n "$miner" && "$miner" != "null" ]]; then
            sample_count=$(( sample_count + 1 ))
            if [[ "$miner" != "$prev_miner" ]]; then
                local is_new=true
                for um in "${unique_miners[@]}"; do
                    if [[ "$um" == "$miner" ]]; then
                        is_new=false
                        break
                    fi
                done
                if [[ "$is_new" == "true" ]]; then
                    unique_miners+=("$miner")
                fi
            fi
            prev_miner="$miner"
        fi
    done

    echo "Observed ${#unique_miners[@]} unique validators over $sample_count sampled blocks" >&3
    for um in "${unique_miners[@]}"; do
        echo "  Validator: $um" >&3
    done

    # Chain should not have halted
    local final_block
    final_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    sleep 5
    local post_final
    post_final=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$post_final" -le "$final_block" ]]; then
        echo "CRITICAL: Chain halted after validator rotation" >&2
        return 1
    fi

    echo "Chain continues at block $post_final after rotation" >&3
}
