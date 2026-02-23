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

    # Fund with 1 ETH: the EIP-170 boundary test deploys 24576 bytes of code which
    # costs ~5 M gas in code-deposit fees; at ~25 Gwei that is ~0.125 ETH per test.
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=transaction-eoa
@test "deploy single STOP opcode contract succeeds and code at address is empty" {
    # CREATE base gas is 53K; STOP costs 0 execution gas.  Explicit --gas-limit
    # avoids auto-estimation (which Bor rejects when simulating empty balances) and
    # --legacy sidesteps EIP-1559 maxFeePerGas × blockGasLimit balance pre-checks.
    receipt=$(cast send \
        --legacy \
        --gas-limit 60000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x00")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success (0x1), got: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    # STOP opcode (0x00) produces empty runtime (no RETURN), so deployed code == 0x
    if [[ "$deployed_code" != "0x" ]]; then
        echo "Expected empty runtime (0x) for STOP-only constructor, got: $deployed_code" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
@test "deploy contract that reverts in constructor leaves no code at deployed address" {
    # 0x60006000fd = PUSH1 0x00 PUSH1 0x00 REVERT
    set +e
    receipt=$(cast send \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60006000fd" 2>/dev/null)
    send_exit=$?
    set -e

    # The tx may be accepted but fail, or cast may report failure.
    # Either way, if we got a receipt check its status; if not, that's also acceptable.
    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        contract_addr=$(echo "$receipt" | jq -r '.contractAddress // empty')

        if [[ "$tx_status" == "0x1" && -n "$contract_addr" ]]; then
            # Tx succeeded but constructor reverted — check code is empty
            deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
            if [[ "$deployed_code" != "0x" ]]; then
                echo "Expected no code after constructor revert, got: $deployed_code" >&2
                return 1
            fi
        fi
        # status 0x0 means constructor revert was enforced at EVM level — pass
    fi
    # cast failure (send_exit != 0) also means the node rejected it — pass
}

# bats test_tags=evm-gas
@test "deploy initcode exactly at EIP-3860 limit (49152 bytes) succeeds" {
    initcode=$(python3 -c "print('00'*49152, end='')")
    # EIP-7623 (Prague) floor data gas cost for 49152 zero bytes:
    #   floor = 21000 + 10 × 49152 = 512520
    # Plus EIP-3860 word cost: 2 × 1536 words = 3072.  600K clears both.
    receipt=$(cast send \
        --gas-limit 600000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for 49152-byte initcode (EIP-3860 limit), got: $tx_status" >&2
        return 1
    fi
}

# bats test_tags=evm-gas
@test "deploy initcode one byte over EIP-3860 limit (49153 bytes) is rejected" {
    initcode=$(python3 -c "print('00'*49153, end='')")
    set +e
    # Same EIP-7623 floor applies (49153 tokens → min 512530).  600K clears the
    # floor so the rejection comes from EIP-3860, not from insufficient gas.
    receipt=$(cast send \
        --gas-limit 600000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 49153-byte initcode (over EIP-3860 limit), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 both indicate the node rejected it — pass
}

# bats test_tags=evm-gas
@test "deploy contract that returns 24577 runtime bytes is rejected by EIP-170" {
    # 0x6160016000f3 = PUSH2 0x6001 PUSH1 0x00 RETURN
    # Returns 0x6001 = 24577 bytes of zeroed memory as runtime, exceeding EIP-170 (24576 byte limit)
    set +e
    # Rejection happens after RETURN (memory expansion ~3K gas) but before code deposit;
    # actual consumption is <60K.  200K is ample and keeps fee well under the node cap.
    receipt=$(cast send \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6160016000f3" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 24577-byte runtime (over EIP-170 limit), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 — node rejected oversized runtime — pass
}

# bats test_tags=evm-gas
@test "deploy contract that returns exactly 24576 runtime bytes succeeds (EIP-170 boundary)" {
    # 0x6160006000f3 = PUSH2 0x6000 PUSH1 0x00 RETURN
    # Returns exactly 24576 (0x6000) bytes of zeroed memory — the EIP-170 maximum.
    # This is the boundary case: 24576 must succeed while 24577 (tested above) must fail.
    # Code-deposit cost: 200 gas/byte × 24576 bytes = 4,915,200 gas, plus ~57K overhead.
    # 5,500,000 covers the actual spend; at ~25 Gwei that is ~0.14 ETH — within the
    # 1 ETH wallet balance and below the node's 0.42 ETH txfeecap.
    receipt=$(cast send \
        --gas-limit 5500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6160006000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for exactly 24576-byte runtime (at EIP-170 limit), got: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    # Strip leading 0x and divide char count by 2 to get byte length.
    deployed_len=$(( (${#deployed_code} - 2) / 2 ))
    if [[ "$deployed_len" -ne 24576 ]]; then
        echo "Expected 24576-byte deployed runtime at EIP-170 boundary, got ${deployed_len} bytes" >&2
        return 1
    fi
}

# bats test_tags=transaction-eoa
@test "deploy contract with 0xEF leading runtime byte is rejected by EIP-3541" {
    # EIP-3541 (London+): any contract creation whose first byte of runtime code is 0xEF
    # must be rejected. This protects the EOF container format prefix.
    # Initcode: PUSH1 0xEF  PUSH1 0x00  MSTORE8  PUSH1 0x01  PUSH1 0x00  RETURN
    # Stores byte 0xEF at mem[0] then returns 1 byte of runtime → runtime starts with 0xEF.
    set +e
    receipt=$(cast send \
        --gas-limit 1000000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60ef60005360016000f3" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 0xEF-prefixed runtime (EIP-3541), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 — node correctly rejected EF-prefixed runtime — pass
}
