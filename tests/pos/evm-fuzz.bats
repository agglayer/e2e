#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    load "../../core/helpers/pos-setup.bash"
    pos_setup
}

# Waits until the chain has advanced at least 30 blocks past start_block, then
# asserts that the chain actually progressed.  Fails with an explicit message if
# the node stalls or the 3-minute deadline expires.
_wait_for_liveness() {
    local start_block="$1"
    local label="${2:-}"
    local deadline=$(( start_block + 30 ))
    local wait_secs=0 max_wait=180

    while true; do
        local current
        current=$(cast block-number --rpc-url "$L2_RPC_URL" 2>/dev/null) || current=0
        if [[ "$current" -ge "$deadline" ]]; then
            break
        fi
        if [[ "$wait_secs" -ge "$max_wait" ]]; then
            echo "Liveness timeout after ${max_wait}s${label:+ ($label)}: stuck at block $current (need $deadline)" >&2
            return 1
        fi
        sleep 2
        wait_secs=$(( wait_secs + 2 ))
    done

    local live_block
    live_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    if [[ -z "$live_block" || "$live_block" -le "$start_block" ]]; then
        echo "Liveness check failed${label:+ ($label)}: block did not advance beyond $start_block, got: ${live_block:-empty}" >&2
        return 1
    fi
    echo "Liveness check passed${label:+ ($label)} at block $live_block" >&3
}

# bats test_tags=evm-stress
@test "fuzz node with edge-case contract creation bytecodes and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # 15 edge-case bytecodes, each sent 7 times = 105 txs
    bytecodes=(
        "fe"
        "00"
        "5b600056"
        "60ff60005260206000f3"
        "60006000fd"
        "60006000f0"
        "3d"
        "7f$(python3 -c "print('00'*32, end='')")56"
        "f4"
        "58"
        "60016001f5"
        "3660006000f0"
        "6000356000f3"
        "60206000f3"
        "60ff"
    )

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    tx_hashes=()

    for bytecode in "${bytecodes[@]}"; do
        # shellcheck disable=SC2034
        for repeat in $(seq 1 7); do
            set +e
            tx_hash=$(cast send \
                --nonce "$nonce" \
                --gas-limit 1000000 \
                --gas-price "$gas_price" \
                --legacy \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                --create "0x${bytecode}" 2>/dev/null)
            set -e
            if [[ -n "$tx_hash" ]]; then
                tx_hashes+=("$tx_hash")
            fi
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted ${#tx_hashes[@]} contract creation txs, waiting for settlement..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "contract-creation fuzz"
}

# bats test_tags=evm-stress
@test "fuzz node with variable-size calldata transactions and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # Calldata sizes (bytes): 0,1,4,16,64,256,1024,2048,4096,8192,16384,32768
    # Each sent 9 times = 108 txs
    sizes=(0 1 4 16 64 256 1024 2048 4096 8192 16384 32768)

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    for size in "${sizes[@]}"; do
        if [[ "$size" -eq 0 ]]; then
            calldata="0x"
        else
            calldata="0x$(python3 -c "print('00'*${size}, end='')")"
        fi

        # shellcheck disable=SC2034
        for repeat in $(seq 1 9); do
            # gas: 21000 + 4*size (zero bytes cost 4 gas each)
            gas_limit=$(( 21000 + 4 * size + 10000 ))
            set +e
            cast send \
                --nonce "$nonce" \
                --gas-limit "$gas_limit" \
                --gas-price "$gas_price" \
                --legacy \
                --data "$calldata" \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                0x0000000000000000000000000000000000000000 &>/dev/null
            set -e
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted 108 variable-calldata txs, waiting for settlement..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "calldata fuzz"
}

# bats test_tags=evm-stress
@test "fuzz node with edge-case gas limits and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    null_addr="0x0000000000000000000000000000000000000000"
    dead_addr="0x000000000000000000000000000000000000dead"

    send_tx() {
        local extra_args=("$@")
        set +e
        cast send \
            --nonce "$nonce" \
            --gas-price "$gas_price" \
            --legacy \
            --async \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" \
            "${extra_args[@]}" &>/dev/null
        set -e
        nonce=$(( nonce + 1 ))
    }

    # 10 variations x 10 repetitions = 100 txs
    # shellcheck disable=SC2034
    for i in $(seq 1 10); do
        send_tx --gas-limit 21000 "$null_addr"
        send_tx --gas-limit 21001 "$null_addr"
        send_tx --gas-limit 100000 "$null_addr"
        send_tx --gas-limit 1000000 "$null_addr"
        send_tx --gas-limit 10000000 "$null_addr"
        send_tx --gas-limit 30000000 "$null_addr"
        send_tx --gas-limit 21000 --value 1 "$null_addr"
        send_tx --gas-limit 21000 --legacy "$null_addr"
        send_tx --gas-limit 50000 --data "0xdeadbeef" "$null_addr"
        send_tx --gas-limit 21000 "$dead_addr"
    done

    echo "Submitted 100 edge-case gas-limit txs, waiting for settlement..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "gas-limit fuzz"
}

# bats test_tags=evm-stress
@test "fuzz node with non-zero calldata transactions and verify liveness" {
    # Non-zero bytes cost 16 gas each (EIP-2028), vs 4 for zero bytes. This exercises
    # a distinct path in the mempool gas accounting and block packing logic.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # Non-zero calldata sizes (bytes): 1, 4, 32, 128, 512, 2048, 8192
    # Each sent 5 times = 35 txs total.
    sizes=(1 4 32 128 512 2048 8192)

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    for size in "${sizes[@]}"; do
        # All-0xff payload: every byte is non-zero, so gas cost is 16 gas/byte.
        calldata="0x$(python3 -c "print('ff'*${size}, end='')")"
        # gas: 21000 intrinsic + 16*size (non-zero bytes) + buffer
        gas_limit=$(( 21000 + 16 * size + 10000 ))

        # shellcheck disable=SC2034
        for repeat in $(seq 1 5); do
            set +e
            cast send \
                --nonce "$nonce" \
                --gas-limit "$gas_limit" \
                --gas-price "$gas_price" \
                --legacy \
                --data "$calldata" \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                0x0000000000000000000000000000000000000000 &>/dev/null
            set -e
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted 35 non-zero-calldata txs, waiting for settlement..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "non-zero calldata fuzz"
}

# bats test_tags=evm-stress
@test "fuzz contract creations and assert individual tx outcomes" {
    # Unlike the liveness-only fuzz tests, this verifies each tx's status, gasUsed
    # bounds, and contractAddress for every contract creation individually.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.5ether "$ephemeral_address" >/dev/null

    # (bytecode | expected_status | description)
    local -a cases=(
        "00|0x1|STOP opcode – success, empty runtime"
        "600160005360016000f3|0x1|RETURN 1 byte runtime"
        "60206000f3|0x1|RETURN 32 zero bytes runtime"
        "60006000fd|0x0|REVERT in constructor"
        "fe|0x0|INVALID opcode"
        "5b600056|0x0|infinite JUMP loop – OOG"
    )

    local failures=0

    for case_str in "${cases[@]}"; do
        IFS='|' read -r bytecode expected_status desc <<< "$case_str"

        set +e
        receipt=$(cast send \
            --legacy \
            --gas-limit 200000 \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" \
            --json \
            --create "0x${bytecode}" 2>/dev/null)
        send_exit=$?
        set -e

        # cast failure (tx rejected at RPC level) is acceptable for expected failures.
        if [[ $send_exit -ne 0 || -z "$receipt" ]]; then
            if [[ "$expected_status" == "0x1" ]]; then
                echo "FAIL [$desc]: expected success but cast send failed" >&2
                failures=$(( failures + 1 ))
            else
                echo "PASS [$desc]: rejected at RPC level" >&3
            fi
            continue
        fi

        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        gas_used_hex=$(echo "$receipt" | jq -r '.gasUsed // "0x0"')
        gas_used=$(printf '%d' "$gas_used_hex")

        if [[ "$tx_status" != "$expected_status" ]]; then
            echo "FAIL [$desc]: expected status=$expected_status, got=$tx_status" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        # gasUsed must be positive and within the gas limit.
        if [[ "$gas_used" -le 0 || "$gas_used" -gt 200000 ]]; then
            echo "FAIL [$desc]: gasUsed=$gas_used out of range [1, 200000]" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        # Successful creations must include a contractAddress.
        if [[ "$expected_status" == "0x1" ]]; then
            contract_addr=$(echo "$receipt" | jq -r '.contractAddress // empty')
            if [[ -z "$contract_addr" || "$contract_addr" == "null" ]]; then
                echo "FAIL [$desc]: success but no contractAddress in receipt" >&2
                failures=$(( failures + 1 ))
                continue
            fi
        fi

        echo "PASS [$desc]: status=$tx_status gasUsed=$gas_used" >&3
    done

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures outcome assertion(s) failed" >&2
        return 1
    fi
}

# bats test_tags=evm-stress
@test "fuzz node with mixed zero/non-zero calldata and verify liveness" {
    # Previous tests use all-zero or all-0xff calldata separately.  This test mixes
    # zero bytes (4 gas each, EIP-2028) and non-zero bytes (16 gas) in the same
    # transaction to exercise the combined gas-accounting path.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    null_addr="0x0000000000000000000000000000000000000000"

    # Mixed patterns at various sizes.
    patterns=()
    # Alternating 00/ff (50 % non-zero)
    for size in 100 500 2000 8000; do
        patterns+=("$(python3 -c "print(('00ff'*${size})[:${size}*2], end='')")")
    done
    # 4-byte non-zero selector + zero-padded ABI payload
    for size in 32 128 512 2048; do
        patterns+=("$(python3 -c "print('deadbeef'+'00'*($size-4), end='')")")
    done
    # Repeating ab00cd00ef00 (50 % non-zero, 3-byte stride)
    for size in 64 256 1024 4096; do
        patterns+=("$(python3 -c "print(('ab00cd00ef00'*${size})[:${size}*2], end='')")")
    done

    for calldata_hex in "${patterns[@]}"; do
        local byte_len=$(( ${#calldata_hex} / 2 ))
        # Worst case: all non-zero → 16 gas/byte, plus intrinsic + buffer.
        local gas_limit=$(( 21000 + 16 * byte_len + 10000 ))

        # shellcheck disable=SC2034
        for repeat in $(seq 1 5); do
            set +e
            cast send \
                --nonce "$nonce" \
                --gas-limit "$gas_limit" \
                --gas-price "$gas_price" \
                --legacy \
                --data "0x${calldata_hex}" \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                "$null_addr" &>/dev/null
            set -e
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted 60 mixed-calldata txs, waiting for settlement..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "mixed calldata fuzz"
}

# bats test_tags=evm-stress
@test "fuzz node with EIP-1559 type-2 transactions and verify processing" {
    # All existing fuzz tests use --legacy (type-0).  This exercises the EIP-1559
    # dynamic fee market (maxFeePerGas / maxPriorityFeePerGas) in the mempool and
    # block builder.

    # Guard: skip if the chain doesn't expose baseFeePerGas (pre-London).
    local latest_base_fee
    latest_base_fee=$(cast block latest --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // empty')
    if [[ -z "$latest_base_fee" ]]; then
        skip "Chain does not expose baseFeePerGas — EIP-1559 not supported"
    fi

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.5ether "$ephemeral_address" >/dev/null

    local base_fee
    base_fee=$(cast base-fee --rpc-url "$L2_RPC_URL")
    null_addr="0x0000000000000000000000000000000000000000"

    # Probe: send a single synchronous type-2 tx to verify the node accepts them.
    # Bor enforces a minimum tip cap (typically 25 gwei).  Use 30 gwei for the probe.
    local probe_priority=30000000000  # 30 gwei
    local probe_max_fee=$(( base_fee * 2 + probe_priority ))

    probe_receipt=$(cast send \
        --gas-limit 21000 \
        --gas-price "$probe_max_fee" \
        --priority-gas-price "$probe_priority" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$null_addr" 2>/dev/null) || {
        skip "Node rejected type-2 (EIP-1559) probe tx — chain may not support dynamic fees"
    }

    if [[ -z "$probe_receipt" ]]; then
        skip "Node returned empty response for type-2 probe tx"
    fi

    probe_status=$(echo "$probe_receipt" | jq -r '.status // "0x0"')
    if [[ "$probe_status" != "0x1" ]]; then
        skip "Type-2 probe tx failed (status=$probe_status) — chain may not support EIP-1559"
    fi
    echo "EIP-1559 probe tx succeeded" >&3

    local start_nonce
    start_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    nonce="$start_nonce"

    # Vary maxPriorityFeePerGas across 4 levels — all above Bor's 25 gwei minimum.
    priority_fees=(30000000000 40000000000 50000000000 75000000000)

    tx_hashes=()

    for priority_fee in "${priority_fees[@]}"; do
        local max_fee=$(( base_fee * 2 + priority_fee ))

        # 3 txs per priority level = 12 txs total.
        # shellcheck disable=SC2034
        for repeat in $(seq 1 3); do
            set +e
            tx_hash=$(cast send \
                --nonce "$nonce" \
                --gas-limit 21000 \
                --gas-price "$max_fee" \
                --priority-gas-price "$priority_fee" \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                "$null_addr" 2>/dev/null)
            set -e
            if [[ -n "$tx_hash" ]]; then
                tx_hashes+=("$tx_hash")
            fi
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted ${#tx_hashes[@]} / 12 EIP-1559 type-2 txs, waiting for settlement..." >&3

    # Need at least half the txs to have been accepted by the mempool.
    if [[ ${#tx_hashes[@]} -lt 6 ]]; then
        echo "Only ${#tx_hashes[@]} / 12 txs accepted by mempool — possible type-2 rejection" >&2
        return 1
    fi

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "EIP-1559 fuzz"

    # Verify nonce advanced (txs were actually processed).
    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    if [[ "$final_nonce" -le "$start_nonce" ]]; then
        echo "Expected nonce to advance after EIP-1559 txs, stuck at: $final_nonce (start=$start_nonce)" >&2
        return 1
    fi
    echo "Nonce advanced from $start_nonce to $final_nonce" >&3

    # Spot-check: first accepted tx must be type-2 (0x2).
    if [[ ${#tx_hashes[@]} -gt 0 ]]; then
        local sample_tx
        sample_tx=$(cast tx "${tx_hashes[0]}" --json --rpc-url "$L2_RPC_URL" 2>/dev/null)
        if [[ -n "$sample_tx" ]]; then
            local tx_type
            tx_type=$(echo "$sample_tx" | jq -r '.type // "0x0"')
            if [[ "$tx_type" != "0x2" ]]; then
                echo "Expected type-2 tx, got type: $tx_type" >&2
                return 1
            fi
        fi
    fi
}

# bats test_tags=evm-stress
@test "nonce-gap stress: out-of-order submission resolves correctly" {
    # Submits transactions with intentional nonce gaps (N+2 before N+1, etc.) to
    # exercise the mempool's pending-queue ordering and gap-fill logic.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    local start_nonce
    start_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    null_addr="0x0000000000000000000000000000000000000000"

    # Submit 5 txs in scrambled order: gaps first, then gap-fillers.
    # Submission order: N+2, N+4, N+0, N+1, N+3
    local -a order=(2 4 0 1 3)
    tx_hashes=()
    accepted=0

    for offset in "${order[@]}"; do
        local send_nonce=$(( start_nonce + offset ))
        set +e
        tx_hash=$(cast send \
            --nonce "$send_nonce" \
            --gas-limit 21000 \
            --gas-price "$gas_price" \
            --legacy \
            --async \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" \
            "$null_addr" 2>/dev/null)
        set -e
        if [[ -n "$tx_hash" ]]; then
            tx_hashes+=("$tx_hash")
            accepted=$(( accepted + 1 ))
        fi
    done

    echo "Submitted $accepted/5 nonce-gap txs (order: ${order[*]}), waiting..." >&3

    local start_block
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    _wait_for_liveness "$start_block" "nonce-gap stress"

    # If all 5 txs were accepted, the mempool must have resolved every gap and the
    # final on-chain nonce should be exactly start_nonce + 5.
    if [[ "$accepted" -eq 5 ]]; then
        local final_nonce
        final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
        local expected_nonce=$(( start_nonce + 5 ))
        if [[ "$final_nonce" -ne "$expected_nonce" ]]; then
            echo "Expected nonce $expected_nonce after 5 gap-ordered txs, got: $final_nonce" >&2
            return 1
        fi
    fi
}
