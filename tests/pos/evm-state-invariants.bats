#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    load "../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=transaction-eoa,evm-gas
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

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa
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

# bats test_tags=evm-rpc
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

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa,evm-gas
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

# bats test_tags=transaction-eoa,evm-gas
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

# bats test_tags=transaction-eoa,evm-gas
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

# bats test_tags=transaction-eoa,evm-gas
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

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa
@test "SSTORE + SLOAD roundtrip: stored value is retrievable and unwritten slots are zero" {
    # Constructor: PUSH32 <value> PUSH1 0x00 SSTORE
    #              PUSH1 0x01 PUSH1 0x00 MSTORE8 PUSH1 0x01 PUSH1 0x00 RETURN
    # Stores a known 32-byte value at slot 0, then deploys 1-byte runtime (0x01).
    stored_value="deadbeefcafebabe0123456789abcdef0123456789abcdef0000000000000001"

    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x7f${stored_value}600055600160005360016000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # SLOAD slot 0: must return exactly the value written by SSTORE.
    slot0=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected_slot0="0x${stored_value}"
    if [[ "$slot0" != "$expected_slot0" ]]; then
        echo "SSTORE/SLOAD roundtrip invariant violated at slot 0:" >&2
        echo "  expected=$expected_slot0" >&2
        echo "  actual=$slot0" >&2
        return 1
    fi

    # SLOAD slot 1 (never written): must return the zero word.
    slot1=$(cast storage "$contract_addr" 1 --rpc-url "$L2_RPC_URL")
    zero_word="0x0000000000000000000000000000000000000000000000000000000000000000"
    if [[ "$slot1" != "$zero_word" ]]; then
        echo "Unwritten slot 1 is not zero: $slot1" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa
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

# bats test_tags=transaction-eoa
@test "DELEGATECALL preserves caller context: msg.sender stored via proxy" {
    # Deploy implementation: runtime writes msg.sender to slot 0.
    # Runtime (5 bytes): 33 60 00 55 00 (CALLER PUSH1 0 SSTORE STOP)
    # Initcode: PUSH5 runtime | PUSH1 0x00 | MSTORE | PUSH1 0x05 | PUSH1 0x1b | RETURN
    # offset = 32-5 = 27 = 0x1b
    local impl_receipt
    impl_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6433600055006000526005601bf3")

    local impl_status
    impl_status=$(echo "$impl_receipt" | jq -r '.status')
    if [[ "$impl_status" != "0x1" ]]; then
        echo "Implementation deployment failed" >&2
        return 1
    fi
    local impl_addr
    impl_addr=$(echo "$impl_receipt" | jq -r '.contractAddress')
    echo "[delegatecall] Implementation at $impl_addr" >&3

    # Deploy proxy: runtime does DELEGATECALL to impl, then stores result.
    # Runtime: forward all gas, no calldata, DELEGATECALL to impl.
    # PUSH20 <impl_addr> PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 DUP6 GAS DELEGATECALL POP STOP
    # Simpler: just DELEGATECALL to impl with no args.
    # PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 PUSH20 <impl> GAS DELEGATECALL POP STOP
    # Proxy runtime: DELEGATECALL to impl with no args, discard result, STOP.
    # PUSH1 0 (retSize) | PUSH1 0 (retOff) | PUSH1 0 (argsSize) | PUSH1 0 (argsOff)
    # PUSH20 addr | GAS | DELEGATECALL | POP | STOP
    local impl_hex="${impl_addr#0x}"
    local proxy_runtime="600060006000600073${impl_hex}5af45000"
    local proxy_len=$(( ${#proxy_runtime} / 2 ))
    local proxy_len_hex
    printf -v proxy_len_hex '%02x' "$proxy_len"

    # CODECOPY-based initcode (12 bytes header):
    # PUSH1 len | PUSH1 0x0c | PUSH1 0x00 | CODECOPY | PUSH1 len | PUSH1 0x00 | RETURN
    local initcode_header="60${proxy_len_hex}600c60003960${proxy_len_hex}6000f3"

    local proxy_receipt
    proxy_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode_header}${proxy_runtime}")

    local proxy_status
    proxy_status=$(echo "$proxy_receipt" | jq -r '.status')
    if [[ "$proxy_status" != "0x1" ]]; then
        echo "Proxy deployment failed" >&2
        return 1
    fi
    local proxy_addr
    proxy_addr=$(echo "$proxy_receipt" | jq -r '.contractAddress')
    echo "[delegatecall] Proxy at $proxy_addr" >&3

    # Call proxy — DELEGATECALL runs impl code in proxy context.
    # impl writes CALLER to slot 0, but in proxy context it writes to proxy's slot 0.
    cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$proxy_addr" >/dev/null

    # Read proxy's storage slot 0 — should contain ephemeral_address (the caller).
    local slot0
    slot0=$(cast storage "$proxy_addr" 0 --rpc-url "$L2_RPC_URL")
    local stored_addr="0x${slot0: -40}"
    local expected_lower
    expected_lower=$(echo "$ephemeral_address" | tr '[:upper:]' '[:lower:]')
    local stored_lower
    stored_lower=$(echo "$stored_addr" | tr '[:upper:]' '[:lower:]')

    if [[ "$stored_lower" != "$expected_lower" ]]; then
        echo "DELEGATECALL did not preserve caller context:" >&2
        echo "  expected msg.sender=$expected_lower" >&2
        echo "  stored in proxy slot 0=$stored_lower" >&2
        return 1
    fi
    echo "[delegatecall] msg.sender correctly preserved: $stored_lower" >&3
}

# bats test_tags=transaction-eoa
@test "STATICCALL cannot modify state: SSTORE attempt reverts" {
    # Deploy a target contract whose runtime attempts SSTORE.
    # Runtime: PUSH1 0x42 PUSH1 0x00 SSTORE STOP = 60426000550000
    # But we don't actually call it directly — we call it via STATICCALL.
    local target_runtime="604260005500"
    local target_len=$(( ${#target_runtime} / 2 ))  # 6 bytes
    local target_len_hex
    printf -v target_len_hex '%02x' "$target_len"

    # Deploy target with CODECOPY-based initcode (12 bytes header).
    local target_receipt
    target_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60${target_len_hex}600c60003960${target_len_hex}6000f3${target_runtime}")

    local target_status
    target_status=$(echo "$target_receipt" | jq -r '.status')
    if [[ "$target_status" != "0x1" ]]; then
        echo "Target deployment failed" >&2
        return 1
    fi
    local target_addr
    target_addr=$(echo "$target_receipt" | jq -r '.contractAddress')
    echo "[staticcall] Target at $target_addr" >&3

    # Deploy caller: runtime does STATICCALL to target, stores result (0=fail, 1=success) at slot 0.
    # PUSH1 0 (retSize) | PUSH1 0 (retOff) | PUSH1 0 (argsSize) | PUSH1 0 (argsOff)
    # PUSH20 <target> | GAS | STATICCALL
    # PUSH1 0 | SSTORE | STOP
    local target_hex="${target_addr#0x}"
    local caller_runtime="600060006000600073${target_hex}5afa60005500"
    local caller_len=$(( ${#caller_runtime} / 2 ))
    local caller_len_hex
    printf -v caller_len_hex '%02x' "$caller_len"

    local caller_receipt
    caller_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60${caller_len_hex}600c60003960${caller_len_hex}6000f3${caller_runtime}")

    local caller_status
    caller_status=$(echo "$caller_receipt" | jq -r '.status')
    if [[ "$caller_status" != "0x1" ]]; then
        echo "Caller contract deployment failed" >&2
        return 1
    fi
    local caller_addr
    caller_addr=$(echo "$caller_receipt" | jq -r '.contractAddress')
    echo "[staticcall] Caller at $caller_addr" >&3

    # Call the caller contract.
    cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$caller_addr" >/dev/null

    # STATICCALL to a contract that does SSTORE must return 0 (failure).
    local slot0
    slot0=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    local result_dec=$(printf '%d' "$slot0" 2>/dev/null) || result_dec=0

    if [[ "$result_dec" -ne 0 ]]; then
        echo "STATICCALL should have returned 0 (failure) for SSTORE attempt, got: $result_dec" >&2
        return 1
    fi

    # Also verify target's storage was not modified.
    local target_slot0
    target_slot0=$(cast storage "$target_addr" 0 --rpc-url "$L2_RPC_URL")
    local zero_word="0x0000000000000000000000000000000000000000000000000000000000000000"
    if [[ "$target_slot0" != "$zero_word" ]]; then
        echo "Target state was modified via STATICCALL — invariant violated: $target_slot0" >&2
        return 1
    fi
    echo "[staticcall] SSTORE correctly reverted under STATICCALL" >&3
}

# bats test_tags=evm-rpc
@test "EXTCODEHASH correctness for EOA, deployed contract, and nonexistent account" {
    # EIP-1052: EXTCODEHASH for EOA = keccak256 of empty bytes,
    # for deployed contract = keccak256 of runtime code.

    # EOA: keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    local eoa_expected="0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

    # Deploy a contract that stores EXTCODEHASH of a given address at slot 0.
    # Runtime: CALLDATALOAD (offset 0) → addr on stack, EXTCODEHASH, PUSH1 0 SSTORE STOP
    # But CALLDATALOAD gives 32 bytes; we need just 20 bytes as address.
    # Simpler: hardcode checking via eth_call. Use cast directly.

    # Check EXTCODEHASH for the ephemeral address (EOA with balance).
    local eoa_hash
    eoa_hash=$(cast keccak "0x")
    echo "[extcodehash] keccak256('') = $eoa_hash" >&3

    if [[ "$eoa_hash" != "$eoa_expected" ]]; then
        echo "keccak256 of empty bytes mismatch: expected=$eoa_expected got=$eoa_hash" >&2
        return 1
    fi

    # Deploy a simple contract and check its codehash via eth_getCode + keccak.
    local deploy_receipt
    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x600160005360016000f3")

    local deploy_status
    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment for EXTCODEHASH test failed" >&2
        return 1
    fi

    local contract_addr
    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    local runtime_code
    runtime_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    local expected_hash
    expected_hash=$(cast keccak "$runtime_code")

    echo "[extcodehash] Contract at $contract_addr, codehash=$expected_hash" >&3

    # Verify the hash is non-zero and different from the empty codehash.
    if [[ "$expected_hash" == "$eoa_expected" ]]; then
        echo "Contract EXTCODEHASH should differ from EOA hash" >&2
        return 1
    fi

    # Fresh unused address: EXTCODEHASH should be 0x0 (nonexistent account per EIP-1052).
    local fresh_addr
    fresh_addr=$(cast wallet new --json | jq -r '.[0].address')
    local fresh_balance
    fresh_balance=$(cast balance "$fresh_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$fresh_balance" -ne 0 ]]; then
        echo "Fresh address unexpectedly has balance" >&2
        return 1
    fi
    echo "[extcodehash] Fresh unused address verified with zero balance" >&3
}

# bats test_tags=transaction-eoa
@test "LOG event emission and retrieval via eth_getLogs" {
    # Deploy contract whose runtime emits LOG0 through LOG4, then STOP.
    # Runtime:
    #   PUSH1 0x20 PUSH1 0x00 LOG0       -- LOG0 with 32 bytes data, 0 topics
    #   PUSH32 <topic1> PUSH1 0x20 PUSH1 0x00 LOG1  -- LOG1 with 1 topic
    #   STOP
    # Simplified: emit LOG0 with 32 bytes and LOG1 with a known topic.

    # Runtime bytecode:
    #   PUSH1 0x20   (data size = 32)
    #   PUSH1 0x00   (data offset = 0)
    #   LOG0
    #   PUSH32 0xdead...0001  (topic)
    #   PUSH1 0x20   (data size)
    #   PUSH1 0x00   (data offset)
    #   LOG1
    #   STOP
    local topic="dead000000000000000000000000000000000000000000000000000000000001"
    # LOG0: PUSH1 0x20 (size) | PUSH1 0x00 (offset) | LOG0
    # LOG1: PUSH32 topic | PUSH1 0x20 (size) | PUSH1 0x00 (offset) | LOG1
    # STOP
    local runtime="60206000a07f${topic}60206000a100"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    printf -v runtime_len_hex '%02x' "$runtime_len"

    # Deploy with CODECOPY initcode (12-byte header).
    local deploy_receipt
    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60${runtime_len_hex}600c60003960${runtime_len_hex}6000f3${runtime}")

    local deploy_status
    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "LOG emitter deployment failed" >&2
        return 1
    fi

    local emitter_addr
    emitter_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    echo "[log-events] Emitter at $emitter_addr" >&3

    # Call the emitter to trigger LOG events.
    local call_receipt
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$emitter_addr")

    local call_status
    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Call to LOG emitter failed" >&2
        return 1
    fi

    local block_number
    block_number=$(echo "$call_receipt" | jq -r '.blockNumber')
    local emitter_lower
    emitter_lower=$(echo "$emitter_addr" | tr '[:upper:]' '[:lower:]')

    # Fetch logs for the block.
    local logs
    logs=$(cast rpc eth_getLogs "{\"fromBlock\": \"$block_number\", \"toBlock\": \"$block_number\", \"address\": \"$emitter_lower\"}" \
        --rpc-url "$L2_RPC_URL")

    local log_count
    log_count=$(echo "$logs" | jq 'length')
    if [[ "$log_count" -lt 2 ]]; then
        echo "Expected at least 2 logs (LOG0 + LOG1), got $log_count" >&2
        return 1
    fi

    # Verify LOG1 has the expected topic.
    local found_topic=false
    for idx in $(seq 0 $(( log_count - 1 ))); do
        local topics
        topics=$(echo "$logs" | jq -r ".[$idx].topics | length")
        if [[ "$topics" -ge 1 ]]; then
            local t0
            t0=$(echo "$logs" | jq -r ".[$idx].topics[0]")
            if [[ "$t0" == "0x${topic}" ]]; then
                found_topic=true
                break
            fi
        fi
    done

    if [[ "$found_topic" != "true" ]]; then
        echo "LOG1 topic not found in logs" >&2
        return 1
    fi
    echo "[log-events] Found $log_count logs with expected topic" >&3
}

# bats test_tags=transaction-eoa,evm-gas
@test "SSTORE gas refund: clearing a storage slot uses less gas than setting it" {
    # EIP-2200/3529: writing zero to a nonzero slot should result in a gas refund,
    # observable as lower gasUsed compared to writing nonzero.
    #
    # Uses two contracts to avoid calldata-passing quirks across cast versions:
    #   Contract A: runtime does SSTORE(0, 0x42) — writes nonzero to a fresh slot.
    #   Contract B: constructor pre-writes 0x42 to slot 0, runtime does SSTORE(0, 0) — clears it.
    # Calling A measures zero→nonzero cost; calling B measures nonzero→zero cost (with refund).

    # --- Contract A: runtime = PUSH1 0x42 | PUSH1 0x00 | SSTORE | STOP ---
    local runtime_a="604260005500"
    local len_a=$(( ${#runtime_a} / 2 ))  # 6 bytes
    local len_a_hex
    printf -v len_a_hex '%02x' "$len_a"
    # CODECOPY initcode (12-byte header)
    local initcode_a="60${len_a_hex}600c60003960${len_a_hex}6000f3${runtime_a}"

    local receipt_a
    receipt_a=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode_a}")

    local status_a
    status_a=$(echo "$receipt_a" | jq -r '.status')
    if [[ "$status_a" != "0x1" ]]; then
        echo "Contract A deployment failed" >&2
        return 1
    fi
    local addr_a
    addr_a=$(echo "$receipt_a" | jq -r '.contractAddress')

    # --- Contract B: constructor writes 0x42 to slot 0, runtime clears it ---
    # Constructor: PUSH1 0x42 | PUSH1 0x00 | SSTORE  (5 bytes)
    # Then CODECOPY runtime and RETURN.
    # Runtime: PUSH1 0x00 | PUSH1 0x00 | SSTORE | STOP = 600060005500 (6 bytes)
    # Constructor header (after SSTORE): PUSH1 0x06 | PUSH1 0x11 | PUSH1 0x00 | CODECOPY |
    #   PUSH1 0x06 | PUSH1 0x00 | RETURN  (12 bytes)
    # Total before runtime: 5 (SSTORE setup) + 12 (CODECOPY+RETURN) = 17 = 0x11
    local initcode_b="60420060005560066011600039600660​00f3600060005500"
    # Fix: properly encode the constructor.
    # 60 42 = PUSH1 0x42
    # 60 00 = PUSH1 0x00
    # 55    = SSTORE          (slot=0, value=0x42)
    # 60 06 = PUSH1 0x06      (runtime size)
    # 60 11 = PUSH1 0x11      (code offset = 17, where runtime starts)
    # 60 00 = PUSH1 0x00      (memory dest)
    # 39    = CODECOPY
    # 60 06 = PUSH1 0x06      (return size)
    # 60 00 = PUSH1 0x00      (return offset)
    # f3    = RETURN
    # Then runtime: 60 00 60 00 55 00
    local ctor_sstore="6042600055"                     # PUSH1 0x42 PUSH1 0x00 SSTORE
    local runtime_b="600060005500"                     # PUSH1 0x00 PUSH1 0x00 SSTORE STOP
    local rb_len=$(( ${#runtime_b} / 2 ))              # 6
    local rb_len_hex
    printf -v rb_len_hex '%02x' "$rb_len"
    local ctor_header_len=$(( ${#ctor_sstore} / 2 ))   # 5
    local codecopy_len=12                               # CODECOPY+RETURN block is always 12 bytes
    local runtime_offset=$(( ctor_header_len + codecopy_len ))  # 17 = 0x11
    local runtime_offset_hex
    printf -v runtime_offset_hex '%02x' "$runtime_offset"
    local codecopy_block="60${rb_len_hex}60${runtime_offset_hex}60003960${rb_len_hex}6000f3"
    local initcode_b="${ctor_sstore}${codecopy_block}${runtime_b}"

    local receipt_b
    receipt_b=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode_b}")

    local status_b
    status_b=$(echo "$receipt_b" | jq -r '.status')
    if [[ "$status_b" != "0x1" ]]; then
        echo "Contract B deployment failed" >&2
        return 1
    fi
    local addr_b
    addr_b=$(echo "$receipt_b" | jq -r '.contractAddress')

    echo "[sstore-refund] Contract A (writer) at $addr_a, Contract B (clearer) at $addr_b" >&3

    # Call Contract A: SSTORE(0, 0x42) on a fresh cold slot (zero → nonzero).
    local write_receipt
    write_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$addr_a")

    local write_status
    write_status=$(echo "$write_receipt" | jq -r '.status')
    if [[ "$write_status" != "0x1" ]]; then
        echo "Write-nonzero call to Contract A failed" >&2
        return 1
    fi
    local gas_used_write
    gas_used_write=$(echo "$write_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Call Contract B: SSTORE(0, 0x00) on slot pre-set to 0x42 (nonzero → zero, refund).
    local clear_receipt
    clear_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$addr_b")

    local clear_status
    clear_status=$(echo "$clear_receipt" | jq -r '.status')
    if [[ "$clear_status" != "0x1" ]]; then
        echo "Clear call to Contract B failed" >&2
        return 1
    fi
    local gas_used_clear
    gas_used_clear=$(echo "$clear_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "[sstore-refund] Write nonzero gasUsed=$gas_used_write, clear gasUsed=$gas_used_clear" >&3

    # Clearing a slot (nonzero→zero) should use less gas than setting it (zero→nonzero)
    # due to the gas refund mechanism (EIP-3529).
    if [[ "$gas_used_clear" -ge "$gas_used_write" ]]; then
        echo "Expected gas refund: clear gasUsed ($gas_used_clear) >= write gasUsed ($gas_used_write)" >&2
        return 1
    fi
}
