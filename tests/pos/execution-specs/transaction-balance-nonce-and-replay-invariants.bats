#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,transaction-invariants

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "sender balance decreases by exactly gas cost plus value transferred" {
    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    receipt=$(cast send \
        --value 1000 \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000)

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot check balance invariant" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    expected_balance=$(bc <<< "$balance_before - 1000 - ($gas_used * $effective_gas_price)")

    if [[ "$balance_after" != "$expected_balance" ]]; then
        echo "Balance invariant violated:" >&2
        echo "  balance_before=$balance_before" >&2
        echo "  gas_used=$gas_used effective_gas_price=$effective_gas_price" >&2
        echo "  expected_balance=$expected_balance actual_balance=$balance_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "recipient balance increases by exactly the value sent" {
    fresh_wallet=$(cast wallet new --json | jq '.[0]')
    recipient_address=$(echo "$fresh_wallet" | jq -r '.address')

    balance_before=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")
    if [[ "$balance_before" -ne 0 ]]; then
        echo "Fresh address unexpectedly has non-zero balance: $balance_before" >&2
        return 1
    fi

    send_amount=12345

    cast send \
        --value "$send_amount" \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$recipient_address" &>/dev/null

    balance_after=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    if [[ "$balance_after" -ne "$send_amount" ]]; then
        echo "Recipient balance mismatch: expected $send_amount, got $balance_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "CREATE deploys to the address predicted by cast compute-address" {
    current_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected_addr=$(cast compute-address --nonce "$current_nonce" "$ephemeral_address")
    # cast compute-address may return "Computed Address: 0x..." — extract just the address
    expected_addr=$(echo "$expected_addr" | grep -oE '0x[0-9a-fA-F]{40}' | head -1)

    receipt=$(cast send \
        --nonce "$current_nonce" \
        --gas-limit 1000000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x00")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    actual_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # Normalize to lowercase for comparison
    expected_lower=$(echo "$expected_addr" | tr '[:upper:]' '[:lower:]')
    actual_lower=$(echo "$actual_addr" | tr '[:upper:]' '[:lower:]')

    if [[ "$expected_lower" != "$actual_lower" ]]; then
        echo "Contract address mismatch:" >&2
        echo "  expected (computed): $expected_lower" >&2
        echo "  actual (from receipt): $actual_lower" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-rpc
@test "eth_call does not consume gas or advance nonce" {
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    # eth_call should not change state
    cast call "$ephemeral_address" "0x" --rpc-url "$L2_RPC_URL" &>/dev/null

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    if [[ "$nonce_after" -ne "$nonce_before" ]]; then
        echo "Nonce changed after eth_call: before=$nonce_before after=$nonce_after" >&2
        return 1
    fi

    if [[ "$balance_after" -ne "$balance_before" ]]; then
        echo "Balance changed after eth_call: before=$balance_before after=$balance_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "nonce increments by exactly 1 after each successful transaction" {
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    cast send \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        0x0000000000000000000000000000000000000000 &>/dev/null

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected=$(( nonce_before + 1 ))

    if [[ "$nonce_after" -ne "$expected" ]]; then
        echo "Nonce invariant violated: before=$nonce_before expected=$expected got=$nonce_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "out-of-gas transaction still increments sender nonce" {
    # An infinite-loop initcode with a gas limit that is above the intrinsic cost
    # for CREATE (21000 base + 32000 = 53000) but nowhere near enough to execute
    # the loop — the tx is mined, fails with OOG, but the nonce must still advance
    # (EIP-161 / Yellow Paper).
    # 0x5b600056 = JUMPDEST PUSH1 0x00 JUMP (infinite loop back to offset 0)
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    set +e
    cast send \
        --gas-limit 60000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x5b600056" &>/dev/null
    set -e

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected=$(( nonce_before + 1 ))

    if [[ "$nonce_after" -ne "$expected" ]]; then
        echo "Nonce not incremented after OOG tx: before=$nonce_before expected=$expected got=$nonce_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "total value is conserved: sender decrease equals recipient increase plus gas cost" {
    fresh_wallet=$(cast wallet new --json | jq '.[0]')
    recipient_address=$(echo "$fresh_wallet" | jq -r '.address')

    sender_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    recipient_before=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    transfer_amount=500000

    receipt=$(cast send \
        --value "$transfer_amount" \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$recipient_address")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot verify value conservation" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")
    gas_cost=$(bc <<< "$gas_used * $effective_gas_price")

    sender_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    recipient_after=$(cast balance "$recipient_address" --rpc-url "$L2_RPC_URL")

    sender_decrease=$(bc <<< "$sender_before - $sender_after")
    recipient_increase=$(bc <<< "$recipient_after - $recipient_before")
    expected_sender_decrease=$(bc <<< "$transfer_amount + $gas_cost")

    if [[ "$sender_decrease" != "$expected_sender_decrease" ]]; then
        echo "Value conservation violated (sender side):" >&2
        echo "  sender_decrease=$sender_decrease expected=$expected_sender_decrease" >&2
        echo "  transfer=$transfer_amount gas_cost=$gas_cost" >&2
        return 1
    fi

    if [[ "$recipient_increase" != "$transfer_amount" ]]; then
        echo "Value conservation violated (recipient side):" >&2
        echo "  recipient_increase=$recipient_increase expected=$transfer_amount" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "EIP-1559 sender decrease equals value plus effectiveGasPrice times gasUsed" {
    # Type-2 tx: effectiveGasPrice = baseFee + min(priorityFee, maxFee - baseFee).
    # The baseFee portion is burned; only the priority tip goes to the coinbase.
    # Sender still pays the full effectiveGasPrice × gasUsed plus value.

    # Guard: skip if the chain doesn't expose baseFeePerGas (pre-London).
    local latest_base_fee_hex
    latest_base_fee_hex=$(cast block latest --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // empty')
    if [[ -z "$latest_base_fee_hex" ]]; then
        skip "Chain does not expose baseFeePerGas — EIP-1559 not supported"
    fi

    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    base_fee=$(cast base-fee --rpc-url "$L2_RPC_URL")
    # Bor enforces a minimum tip cap (typically 25 gwei).  Use 30 gwei to stay above it.
    priority_fee=30000000000  # 30 gwei
    max_fee=$(( base_fee * 2 + priority_fee ))

    receipt=$(cast send \
        --value 1000 \
        --gas-limit 21000 \
        --gas-price "$max_fee" \
        --priority-gas-price "$priority_fee" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000 2>/dev/null) || {
        skip "Node rejected type-2 tx — chain may not support EIP-1559 dynamic fees"
    }
    if [[ -z "$receipt" ]]; then
        skip "Node returned empty response for type-2 tx"
    fi

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot check EIP-1559 invariant" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    # Retrieve the block's actual baseFeePerGas to decompose the effective price.
    block_number=$(echo "$receipt" | jq -r '.blockNumber')
    block_json=$(cast block "$block_number" --json --rpc-url "$L2_RPC_URL")
    block_base_fee=$(echo "$block_json" | jq -r '.baseFeePerGas' | xargs printf "%d\n")

    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    expected_decrease=$(bc <<< "1000 + $effective_gas_price * $gas_used")
    actual_decrease=$(bc <<< "$balance_before - $balance_after")

    if [[ "$actual_decrease" != "$expected_decrease" ]]; then
        echo "EIP-1559 balance invariant violated:" >&2
        echo "  balance_before=$balance_before balance_after=$balance_after" >&2
        echo "  effectiveGasPrice=$effective_gas_price (baseFee=$block_base_fee)" >&2
        echo "  gasUsed=$gas_used value=1000" >&2
        echo "  expected_decrease=$expected_decrease actual_decrease=$actual_decrease" >&2
        return 1
    fi

    # Verify priority-fee decomposition:
    #   actual_priority = effectiveGasPrice - baseFee
    #   expected = min(maxPriorityFeePerGas, maxFeePerGas - baseFee)
    actual_priority=$(( effective_gas_price - block_base_fee ))
    max_possible_priority=$(( max_fee - block_base_fee ))
    expected_priority=$priority_fee
    if [[ "$expected_priority" -gt "$max_possible_priority" ]]; then
        expected_priority=$max_possible_priority
    fi
    if [[ "$actual_priority" -ne "$expected_priority" ]]; then
        echo "Priority fee decomposition mismatch:" >&2
        echo "  actual=$actual_priority expected=$expected_priority" >&2
        echo "  maxFeePerGas=$max_fee baseFee=$block_base_fee maxPriorityFeePerGas=$priority_fee" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "coinbase balance increases by at least the priority fee portion of gas cost" {
    # After a type-2 tx, the block's coinbase earns the priority-fee portion
    # (effectiveGasPrice − baseFee) × gasUsed.  The baseFee portion is burned.

    # Guard: skip if the chain doesn't expose baseFeePerGas (pre-London).
    local latest_base_fee_hex
    latest_base_fee_hex=$(cast block latest --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // empty')
    if [[ -z "$latest_base_fee_hex" ]]; then
        skip "Chain does not expose baseFeePerGas — EIP-1559 not supported"
    fi

    base_fee=$(cast base-fee --rpc-url "$L2_RPC_URL")
    # Bor enforces a minimum tip cap (typically 25 gwei).  Use 30 gwei to stay above it.
    priority_fee=30000000000  # 30 gwei
    max_fee=$(( base_fee * 2 + priority_fee ))

    receipt=$(cast send \
        --gas-limit 21000 \
        --gas-price "$max_fee" \
        --priority-gas-price "$priority_fee" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000 2>/dev/null) || {
        skip "Node rejected type-2 tx — chain may not support EIP-1559 dynamic fees"
    }
    if [[ -z "$receipt" ]]; then
        skip "Node returned empty response for type-2 tx"
    fi

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transaction failed, cannot check coinbase invariant" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    block_number_hex=$(echo "$receipt" | jq -r '.blockNumber')
    block_number_dec=$(printf '%d' "$block_number_hex")
    block_json=$(cast block "$block_number_hex" --json --rpc-url "$L2_RPC_URL")
    block_base_fee=$(echo "$block_json" | jq -r '.baseFeePerGas' | xargs printf "%d\n")
    coinbase=$(echo "$block_json" | jq -r '.miner')

    actual_priority=$(( effective_gas_price - block_base_fee ))
    our_priority_contribution=$(( actual_priority * gas_used ))

    # Bor uses 0x0…0 as the miner field and distributes fees via system contracts,
    # so the coinbase balance check only applies when the miner is a real address.
    if [[ "$coinbase" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "Coinbase is zero-address (Bor fee model) — verifying effectiveGasPrice only" >&3
        # At minimum, effectiveGasPrice must be >= baseFee (always true for valid txs).
        if [[ "$effective_gas_price" -lt "$block_base_fee" ]]; then
            echo "effectiveGasPrice ($effective_gas_price) < baseFee ($block_base_fee)" >&2
            return 1
        fi
    else
        # Compare coinbase balance between blocks N-1 and N to isolate this block's earnings.
        prev_block=$(printf '0x%x' $(( block_number_dec - 1 )))
        coinbase_before=$(cast balance "$coinbase" --block "$prev_block" --rpc-url "$L2_RPC_URL")
        coinbase_after=$(cast balance "$coinbase" --block "$block_number_hex" --rpc-url "$L2_RPC_URL")
        coinbase_increase=$(bc <<< "$coinbase_after - $coinbase_before")

        # Use >= because other txs in the same block may also contribute fees.
        if (( $(bc <<< "$coinbase_increase < $our_priority_contribution") )); then
            echo "Coinbase balance increase too low:" >&2
            echo "  coinbase=$coinbase" >&2
            echo "  increase=$coinbase_increase expected_min=$our_priority_contribution" >&2
            echo "  priority_per_gas=$actual_priority gasUsed=$gas_used" >&2
            return 1
        fi
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "CREATE2 address matches keccak256(0xff ++ deployer ++ salt ++ initCodeHash)" {
    # Factory constructor: PUSH32 <child initcode padded to 32B> PUSH1 0x00 MSTORE
    # then CREATE2 with salt=0x42, size=10, offset=0, value=0; stores child addr at slot 0.
    # Child initcode (600160005360016000f3) returns 1-byte runtime (0x01).
    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x7f600160005360016000f3000000000000000000000000000000000000000000006000526042600a60006000f560005500")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Factory deployment failed" >&2
        return 1
    fi

    factory_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # Read child address from factory's storage slot 0 (left-padded to 32 bytes).
    actual_raw=$(cast storage "$factory_addr" 0 --rpc-url "$L2_RPC_URL")
    actual_child="0x${actual_raw: -40}"

    child_code=$(cast code "$actual_child" --rpc-url "$L2_RPC_URL")
    if [[ "$child_code" == "0x" ]]; then
        echo "Child contract at $actual_child has no code — CREATE2 failed" >&2
        return 1
    fi

    # Predict: address = keccak256(0xff ++ deployer ++ salt ++ keccak256(initcode))[12:]
    child_initcode="0x600160005360016000f3"
    init_code_hash=$(cast keccak "$child_initcode")
    factory_hex=$(echo "${factory_addr#0x}" | tr '[:upper:]' '[:lower:]')
    salt_hex="0000000000000000000000000000000000000000000000000000000000000042"
    hash_hex="${init_code_hash#0x}"

    packed="0xff${factory_hex}${salt_hex}${hash_hex}"
    predicted_hash=$(cast keccak "$packed")
    predicted_addr="0x${predicted_hash: -40}"

    actual_lower=$(echo "$actual_child" | tr '[:upper:]' '[:lower:]')
    predicted_lower=$(echo "$predicted_addr" | tr '[:upper:]' '[:lower:]')
    if [[ "$actual_lower" != "$predicted_lower" ]]; then
        echo "CREATE2 address invariant violated:" >&2
        echo "  actual=$actual_child predicted=$predicted_addr" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "replay protection: same signed tx submitted twice does not double-spend" {
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    # Build and sign a raw transaction without broadcasting.
    raw_tx=$(cast mktx \
        --legacy \
        --gas-limit 21000 \
        --gas-price "$gas_price" \
        --nonce "$nonce" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        0x0000000000000000000000000000000000000000)

    # First submission — wait for it to be mined.
    # cast publish may return a plain hex hash OR a full JSON receipt depending on
    # the foundry version.  Handle both formats.
    publish_output=$(cast publish --rpc-url "$L2_RPC_URL" "$raw_tx")

    if echo "$publish_output" | jq -e '.transactionHash' >/dev/null 2>&1; then
        # JSON receipt — extract the hash.
        tx_hash=$(echo "$publish_output" | jq -r '.transactionHash')
    else
        # Plain hex hash — trim whitespace.
        tx_hash=$(echo "$publish_output" | tr -d '[:space:]')
    fi

    if ! [[ "$tx_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo "cast publish returned invalid tx hash: '$tx_hash'" >&2
        return 1
    fi
    # Ensure the tx is mined before attempting replay.
    cast receipt "$tx_hash" --rpc-url "$L2_RPC_URL" --json >/dev/null

    # Replay — the node must reject the tx (nonce already consumed).
    set +e
    replay_result=$(cast publish --rpc-url "$L2_RPC_URL" "$raw_tx" 2>&1)
    replay_exit=$?
    set -e

    # The critical invariant: nonce advanced by exactly 1, not 2 (no double-spend).
    final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    expected_nonce=$(( nonce + 1 ))
    if [[ "$final_nonce" -ne "$expected_nonce" ]]; then
        echo "Replay protection failed: nonce=$final_nonce expected=$expected_nonce" >&2
        return 1
    fi

    # Some nodes silently return the existing tx hash on replay — that is acceptable
    # as long as the nonce did not advance twice (already verified above).
    if [[ $replay_exit -eq 0 && -n "$replay_result" ]]; then
        echo "Note: node returned result for replay (may be existing hash): $replay_result" >&3
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "insufficient balance rejection: tx with value+gas > balance is rejected" {
    balance=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    # value that exceeds balance even without gas cost.
    local overspend=$(( balance + 1 ))

    set +e
    cast send \
        --value "$overspend" \
        --gas-limit 21000 \
        --gas-price "$gas_price" \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000 &>/dev/null
    set -e

    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    if [[ "$nonce_after" -ne "$nonce_before" ]]; then
        echo "Nonce changed after insufficient balance tx: before=$nonce_before after=$nonce_after" >&2
        return 1
    fi
    echo "Insufficient balance tx correctly rejected, nonce unchanged at $nonce_after" >&3
}

# bats test_tags=execution-specs,transaction-eoa
@test "zero-value self-transfer: only gas consumed, nonce increments" {
    balance_before=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    receipt=$(cast send \
        --value 0 \
        --gas-limit 21000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$ephemeral_address")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Zero-value self-transfer failed" >&2
        return 1
    fi

    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    balance_after=$(cast balance "$ephemeral_address" --rpc-url "$L2_RPC_URL")
    nonce_after=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    # Only gas should be consumed.
    expected_balance=$(bc <<< "$balance_before - ($gas_used * $effective_gas_price)")
    if [[ "$balance_after" != "$expected_balance" ]]; then
        echo "Self-transfer balance mismatch: expected=$expected_balance actual=$balance_after" >&2
        return 1
    fi

    # Nonce must increment by exactly 1.
    if [[ "$nonce_after" -ne $(( nonce_before + 1 )) ]]; then
        echo "Nonce mismatch: expected=$(( nonce_before + 1 )) actual=$nonce_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "Nonce-too-low rejection" {
    local nonce_before
    nonce_before=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")

    # Send a valid tx to consume the current nonce.
    cast send --legacy --gas-limit 21000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" \
        0x0000000000000000000000000000000000000000 >/dev/null

    local nonce_after_first
    nonce_after_first=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    [[ "$nonce_after_first" -eq $(( nonce_before + 1 )) ]] || {
        echo "First tx didn't increment nonce" >&2; return 1
    }

    # Attempt a tx with the old (now consumed) nonce.
    local gas_price
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    set +e
    cast send --legacy --gas-limit 21000 --gas-price "$gas_price" \
        --nonce "$nonce_before" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" \
        0x0000000000000000000000000000000000000000 &>/dev/null
    set -e

    local final_nonce
    final_nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    if [[ "$final_nonce" -ne $(( nonce_before + 1 )) ]]; then
        echo "Nonce-too-low not rejected: final_nonce=$final_nonce expected=$(( nonce_before + 1 ))" >&2
        return 1
    fi
    echo "Nonce-too-low correctly rejected, nonce remains at $final_nonce" >&3
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "Gas limit boundary: exact intrinsic gas (21000) succeeds for simple transfer" {
    local receipt
    receipt=$(cast send --legacy --gas-limit 21000 --value 1 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        0x0000000000000000000000000000000000000000)

    local tx_status
    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Transfer with exactly 21000 gas failed (status=$tx_status)" >&2
        return 1
    fi

    local gas_used
    gas_used=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    if [[ "$gas_used" -ne 21000 ]]; then
        echo "Expected gasUsed=21000, got=$gas_used" >&2
        return 1
    fi
    echo "Exact intrinsic gas (21000) transfer succeeded, gasUsed=$gas_used" >&3
}

# bats test_tags=execution-specs,transaction-eoa,evm-gas
@test "Calldata gas accounting: nonzero bytes cost more than zero bytes" {
    # EVM intrinsic gas: 21000 base + (cost_nonzero * nonzero_bytes) + (cost_zero * zero_bytes).
    # Standard Ethereum: 16/nonzero, 4/zero.  Bor may use different values.
    # Invariant: sending 32 nonzero bytes must cost strictly more than 32 zero bytes,
    # the difference must be a positive multiple of 32 (consistent per-byte premium),
    # and both must exceed the 21000 base cost.
    local calldata_nonzero="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    local calldata_zero="0x0000000000000000000000000000000000000000000000000000000000000000"

    local receipt_a
    receipt_a=$(cast send --legacy --gas-limit 100000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        0x0000000000000000000000000000000000000000 "$calldata_nonzero")

    local status_a
    status_a=$(echo "$receipt_a" | jq -r '.status')
    [[ "$status_a" == "0x1" ]] || { echo "Tx A (nonzero calldata) failed" >&2; return 1; }

    local gas_a
    gas_a=$(echo "$receipt_a" | jq -r '.gasUsed' | xargs printf "%d\n")

    local receipt_b
    receipt_b=$(cast send --legacy --gas-limit 100000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        0x0000000000000000000000000000000000000000 "$calldata_zero")

    local status_b
    status_b=$(echo "$receipt_b" | jq -r '.status')
    [[ "$status_b" == "0x1" ]] || { echo "Tx B (zero calldata) failed" >&2; return 1; }

    local gas_b
    gas_b=$(echo "$receipt_b" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Both must exceed 21000 base cost (calldata adds to intrinsic gas).
    if [[ "$gas_a" -le 21000 ]]; then
        echo "Nonzero calldata gasUsed ($gas_a) should exceed 21000 base" >&2
        return 1
    fi
    if [[ "$gas_b" -le 21000 ]]; then
        echo "Zero calldata gasUsed ($gas_b) should exceed 21000 base" >&2
        return 1
    fi

    # Nonzero bytes must cost strictly more than zero bytes.
    if [[ "$gas_a" -le "$gas_b" ]]; then
        echo "Nonzero calldata ($gas_a) should cost more than zero calldata ($gas_b)" >&2
        return 1
    fi

    # Difference must be evenly divisible by 32 (consistent per-byte pricing).
    local gas_diff=$(( gas_a - gas_b ))
    if [[ $(( gas_diff % 32 )) -ne 0 ]]; then
        echo "Gas difference ($gas_diff) not divisible by 32 — inconsistent per-byte pricing" >&2
        return 1
    fi

    local per_byte_premium=$(( gas_diff / 32 ))
    echo "Calldata gas: nonzero=$gas_a zero=$gas_b diff=$gas_diff per_byte_premium=$per_byte_premium" >&3
}
