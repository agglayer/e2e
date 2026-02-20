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

    # Fund with enough for multiple contract deployments.
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=transaction-eoa
@test "deploy single STOP opcode contract succeeds and code at address is non-empty" {
    receipt=$(cast send \
        --create "0x00" \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json)

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
        --create "0x60006000fd" \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json 2>/dev/null)
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
    receipt=$(cast send \
        --create "0x${initcode}" \
        --gas-limit 20000000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json)

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
    receipt=$(cast send \
        --create "0x${initcode}" \
        --gas-limit 20000000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json 2>/dev/null)
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
    receipt=$(cast send \
        --create "0x6160016000f3" \
        --gas-limit 10000000 \
        --legacy \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json 2>/dev/null)
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
