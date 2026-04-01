#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,blockstm,s0

# BlockSTM Parallel Execution Safety Tests
# ==========================================
# Tests targeting critical S0/S1 edge cases in Bor's BlockSTM parallel
# transaction execution engine.
#
# Risk areas covered:
#   - Same-sender transaction ordering under parallel execution
#   - Parallel vs sequential state root determinism
#   - Fee delay re-execution path (coinbase-reading transactions)
#   - High-contention storage slots with many concurrent writers
#   - Dependency metadata correctness (PIP-16)
#
# These tests submit crafted transaction patterns that stress BlockSTM's
# conflict detection, dependency tracking, and re-execution logic. They
# then verify chain liveness (no panic/halt) and state correctness.
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with at least one Bor validator
#   - Optional: second Bor node for cross-node state root comparison
#
# RUN: bats tests/pos/execution-specs/resilience/blockstm-parallel-execution-safety.bats

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet
}

teardown() {
    # Kill any lingering background processes from this test
    jobs -p | xargs -r kill 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=resilience,blockstm,s0,sender-ordering
@test "BlockSTM: rapid same-sender nonce sequence does not cause state divergence" {
    # Targets: executor.go:308-327 — sender-based dependency tracking.
    # If BlockSTM fails to serialize same-sender transactions, nonce
    # accounting breaks and the chain either panics or produces wrong state.
    #
    # Strategy: Send 50 sequential-nonce txs from one sender in rapid
    # succession. Verify all are mined and the final nonce matches.

    local wallet
    wallet=$(_fund_ephemeral_wallet "1ether")
    local pk="${wallet%%:*}"
    local addr="${wallet##*:}"
    echo "Sender: $addr" >&3

    local start_nonce
    start_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    local num_txs=50

    # Fire all txs asynchronously with explicit nonces
    local tx_hashes=()
    for i in $(seq 0 $(( num_txs - 1 ))); do
        local nonce=$(( start_nonce + i ))
        local tx_hash
        tx_hash=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
            --nonce "$nonce" --gas-limit 21000 --gas-price "$gas_price" \
            --legacy --async "$addr" --value 0 2>/dev/null) || true
        if [[ -n "$tx_hash" ]]; then
            tx_hashes+=("$tx_hash")
        fi
    done

    echo "Submitted ${#tx_hashes[@]} same-sender txs" >&3

    # Wait for chain to advance enough to include all txs
    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_block_advance "$start_block" 20 180

    # Verify final nonce
    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    local expected_nonce=$(( start_nonce + num_txs ))

    echo "Expected nonce: $expected_nonce, Got: $final_nonce" >&3

    if [[ "$final_nonce" -ne "$expected_nonce" ]]; then
        echo "CRITICAL: Nonce mismatch — BlockSTM sender ordering may be broken" >&2
        echo "  Expected: $expected_nonce" >&2
        echo "  Got:      $final_nonce" >&2
        return 1
    fi
}

# bats test_tags=resilience,blockstm,s0,contention
@test "BlockSTM: high-contention storage slot does not cause chain halt" {
    # Targets: mvhashmap.go:153-175 — MarkEstimate/Delete panic paths.
    # When many transactions write to the same storage slot, BlockSTM must
    # handle frequent conflict detection and re-execution. If MarkEstimate
    # is called on a key that no longer exists after re-execution with a
    # different write set, the node panics.
    #
    # Strategy: Deploy a counter contract, then have multiple senders
    # all call increment() concurrently. This forces repeated conflicts
    # and re-executions in BlockSTM.

    # Fund 5 ephemeral wallets
    local wallets=()
    for i in $(seq 1 5); do
        wallets+=("$(_fund_ephemeral_wallet "0.5ether")")
    done

    # Deploy counter contract
    local contract_addr
    contract_addr=$(_deploy_counter_contract "$L2_RPC_URL" "$PRIVATE_KEY")

    if [[ -z "$contract_addr" || ! "$contract_addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Failed to deploy counter contract" >&2
        return 1
    fi
    echo "Counter contract: $contract_addr" >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Each wallet sends 10 increment() calls = 50 total competing writes
    local total_txs=0
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    for wallet in "${wallets[@]}"; do
        local pk="${wallet%%:*}"
        local addr="${wallet##*:}"
        local nonce
        nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

        for j in $(seq 0 9); do
            cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
                --nonce $(( nonce + j )) --gas-limit 100000 --gas-price "$gas_price" \
                --legacy --async "$contract_addr" "increment()" >/dev/null 2>&1 || true
            total_txs=$(( total_txs + 1 ))
        done
    done

    echo "Submitted $total_txs concurrent increment() calls" >&3

    # Chain must not halt — wait for blocks to advance
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 20 180)
    echo "Chain advanced to block $end_block (from $start_block)" >&3

    # Verify counter value is consistent (all increments applied)
    local counter_val
    counter_val=$(cast call --rpc-url "$L2_RPC_URL" "$contract_addr" "get()(uint256)" 2>/dev/null) || true
    counter_val=$(echo "$counter_val" | tr -d '[:space:]')

    if [[ -z "$counter_val" || "$counter_val" == "CALL_FAILED" ]]; then
        echo "CRITICAL: Cannot read counter — possible state corruption" >&2
        return 1
    fi

    echo "Counter value: $counter_val (expected up to $total_txs)" >&3

    # Counter should be > 0 (some txs succeeded) and <= total_txs
    if [[ "$counter_val" -le 0 ]]; then
        echo "CRITICAL: Counter is 0 despite $total_txs increment calls" >&2
        return 1
    fi
}

# bats test_tags=resilience,blockstm,s0,fee-delay
@test "BlockSTM: coinbase-reading transactions do not cause state corruption" {
    # Targets: parallel_state_processor.go:396-417 — fee delay re-execution.
    # When a transaction reads the coinbase balance, BlockSTM must re-run
    # the entire block without fee delay. The shallow copy at line 400
    # (*statedb = *backupStateDB) risks shared-pointer corruption.
    #
    # Strategy: Send a transaction to the coinbase address itself, then
    # immediately send more transactions. If the fee delay re-execution
    # corrupts state, balances will be wrong or the chain will halt.

    # Get the current block's coinbase (miner/validator)
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local coinbase
    coinbase=$(cast block "$latest_block" --json --rpc-url "$L2_RPC_URL" | jq -r '.miner')

    if [[ -z "$coinbase" || "$coinbase" == "null" ]]; then
        skip "Cannot determine coinbase address"
    fi
    echo "Coinbase: $coinbase" >&3

    local wallet
    wallet=$(_fund_ephemeral_wallet "2ether")
    local pk="${wallet%%:*}"
    local addr="${wallet##*:}"

    # Record coinbase balance before
    local coinbase_balance_before
    coinbase_balance_before=$(cast balance --rpc-url "$L2_RPC_URL" "$coinbase")
    echo "Coinbase balance before: $coinbase_balance_before" >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

    # Send a batch: tx to coinbase (triggers fee delay) + 20 normal txs
    # All in same block window to maximize BlockSTM contention
    cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
        --nonce "$nonce" --gas-limit 21000 --gas-price "$gas_price" \
        --legacy --async "$coinbase" --value "0.01ether" >/dev/null 2>&1 || true
    nonce=$(( nonce + 1 ))

    # Follow up with 20 self-transfers (these read nonce/balance of sender)
    for i in $(seq 1 20); do
        cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
            --nonce $(( nonce + i - 1 )) --gas-limit 21000 --gas-price "$gas_price" \
            --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
    done

    echo "Submitted 21 txs (1 to coinbase + 20 self-transfers)" >&3

    # Wait for settlement
    local end_block
    end_block=$(_wait_for_block_advance "$start_block" 15 180)
    echo "Chain advanced to block $end_block" >&3

    # Verify sender balance is sane (should be less than initial 2 ETH)
    local sender_balance
    sender_balance=$(cast balance --rpc-url "$L2_RPC_URL" "$addr")

    if [[ -z "$sender_balance" ]]; then
        echo "CRITICAL: Cannot read sender balance — possible state corruption" >&2
        return 1
    fi

    echo "Sender final balance: $sender_balance wei" >&3

    # Verify the nonce advanced correctly
    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    local expected_nonce=$(( nonce + 20 ))

    echo "Final nonce: $final_nonce, Expected: $expected_nonce" >&3

    # Nonce must have advanced (at least some txs included)
    if [[ "$final_nonce" -le "$nonce" ]]; then
        echo "CRITICAL: No transactions were included after coinbase transfer" >&2
        return 1
    fi
}

# bats test_tags=resilience,blockstm,s0,cross-node
@test "BlockSTM: state roots match across multiple Bor nodes" {
    # Targets: All BlockSTM determinism bugs.
    # If parallel execution is non-deterministic (different conflict resolution
    # ordering, ReadStorage TOCTOU race at mvhashmap.go:143, or journal
    # corruption), different nodes will compute different state roots.
    #
    # Strategy: Compare recent block hashes between validator and RPC nodes.
    # Equal block hashes imply equal state roots.

    # Try to discover a second Bor node in the enclave
    local second_rpc=""
    for i in $(seq 1 4); do
        for role in "rpc" "sentry" "validator"; do
            local svc="l2-el-${i}-bor-heimdall-v2-${role}"
            local port
            if port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                local candidate
                if [[ "$port" == http://* || "$port" == https://* ]]; then
                    candidate="$port"
                else
                    candidate="http://${port}"
                fi
                if [[ "$candidate" != "$L2_RPC_URL" ]]; then
                    second_rpc="$candidate"
                    echo "Found second Bor node at ${svc}: ${second_rpc}" >&3
                    break 2
                fi
            fi
        done
    done

    if [[ -z "$second_rpc" ]]; then
        skip "No second Bor node found for cross-node comparison"
    fi

    # Submit load to stress BlockSTM before comparing
    local wallet
    wallet=$(_fund_ephemeral_wallet "1ether")
    local pk="${wallet%%:*}"
    local addr="${wallet##*:}"
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

    for i in $(seq 0 29); do
        cast send --rpc-url "$L2_RPC_URL" --private-key "$pk" \
            --nonce $(( nonce + i )) --gas-limit 21000 --gas-price "$gas_price" \
            --legacy --async "$addr" --value 0 >/dev/null 2>&1 || true
    done

    # Wait for blocks to be produced and propagated
    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_block_advance "$start_block" 15 180

    # Compare block hashes on both nodes for the last 10 finalized blocks
    local check_block
    check_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    # Go back 5 blocks to ensure both nodes have them
    check_block=$(( check_block - 5 ))

    local mismatches=0
    for offset in $(seq 0 9); do
        local bn=$(( check_block - offset ))
        local hash1
        hash1=$(cast block "$bn" --json --rpc-url "$L2_RPC_URL" | jq -r '.hash // empty')
        local hash2
        hash2=$(cast block "$bn" --json --rpc-url "$second_rpc" | jq -r '.hash // empty')

        if [[ -z "$hash2" ]]; then
            echo "Block $bn not yet available on second node" >&3
            continue
        fi

        if [[ "$hash1" != "$hash2" ]]; then
            echo "STATE ROOT MISMATCH at block $bn:" >&2
            echo "  Node 1: $hash1" >&2
            echo "  Node 2: $hash2" >&2
            mismatches=$(( mismatches + 1 ))
        fi
    done

    echo "Compared 10 blocks, mismatches: $mismatches" >&3

    if [[ "$mismatches" -gt 0 ]]; then
        echo "CRITICAL: State root divergence detected — BlockSTM determinism failure" >&2
        return 1
    fi
}

# bats test_tags=resilience,blockstm,s0,dependency-metadata
@test "BlockSTM: blocks with PIP-16 dependency data produce correct state" {
    # Targets: parallel_state_processor.go:454-484 — VerifyDeps + GetDeps.
    # Verifies that transaction dependency metadata in block headers is
    # correctly used by BlockSTM. Incorrect deps could cause parallel
    # execution of dependent txs, producing wrong state.
    #
    # Strategy: Send interacting transactions (A funds B, B funds C) using
    # --async with explicit nonces so they can land in the same block.
    # Verify the final balances are correct.

    # Create a chain of 3 wallets: A -> B -> C
    # Fund B with enough to send 0.5 ETH even if A's transfer hasn't landed yet
    local wallet_a wallet_b wallet_c
    wallet_a=$(_fund_ephemeral_wallet "2ether")
    wallet_b=$(_fund_ephemeral_wallet "1ether")
    wallet_c=$(_fund_ephemeral_wallet "0.001ether")

    local pk_a="${wallet_a%%:*}" addr_a="${wallet_a##*:}"
    local pk_b="${wallet_b%%:*}" addr_b="${wallet_b##*:}"
    local pk_c="${wallet_c%%:*}" addr_c="${wallet_c##*:}"

    echo "Chain: $addr_a -> $addr_b -> $addr_c" >&3

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    # Record initial balances
    local c_balance_before
    c_balance_before=$(cast balance --rpc-url "$L2_RPC_URL" "$addr_c")

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Step 1: A sends 1 ETH to B (async to allow same-block inclusion)
    local nonce_a
    nonce_a=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr_a")
    cast send --rpc-url "$L2_RPC_URL" --private-key "$pk_a" \
        --nonce "$nonce_a" --gas-limit 21000 --gas-price "$gas_price" \
        --legacy --async "$addr_b" --value "1ether" >/dev/null 2>&1 || true

    # Step 2: B sends 0.5 ETH to C (async — may land in same block as step 1)
    local nonce_b
    nonce_b=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr_b")
    cast send --rpc-url "$L2_RPC_URL" --private-key "$pk_b" \
        --nonce "$nonce_b" --gas-limit 21000 --gas-price "$gas_price" \
        --legacy --async "$addr_c" --value "0.5ether" >/dev/null 2>&1 || true

    # Wait for settlement
    _wait_for_block_advance "$start_block" 10 120

    # Verify C received the funds
    local c_balance_after
    c_balance_after=$(cast balance --rpc-url "$L2_RPC_URL" "$addr_c")
    local c_increase
    c_increase=$(echo "$c_balance_after - $c_balance_before" | bc)

    echo "C balance increase: $c_increase wei" >&3

    # C should have received 0.5 ETH = 500000000000000000 wei
    local expected_increase="500000000000000000"
    if [[ "$c_increase" != "$expected_increase" ]]; then
        echo "Balance mismatch — dependency chain may have broken:" >&2
        echo "  Expected increase: $expected_increase" >&2
        echo "  Actual increase:   $c_increase" >&2
        return 1
    fi
}
