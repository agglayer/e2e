#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,eip1153

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "TSTORE + TLOAD roundtrip returns stored value" {
    # Deploy contract whose runtime:
    #   PUSH1 0x42  PUSH1 0x00  TSTORE   (5d)  — store 0x42 at transient slot 0
    #   PUSH1 0x00  TLOAD (5c)                  — load transient slot 0
    #   PUSH1 0x00  SSTORE                      — persist to storage slot 0 for verification
    #   STOP
    # Opcodes: 60 42 60 00 5d 60 00 5c 60 00 55 00
    runtime="604260005d60005c60005500"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"

    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    # Call the contract to execute TSTORE + TLOAD
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Contract call failed: $call_status" >&2
        return 1
    fi

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    if [[ "$stored_dec" -ne 66 ]]; then  # 0x42 = 66
        echo "TSTORE/TLOAD roundtrip failed: expected 66 (0x42), got $stored_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "TLOAD returns zero for unset transient slot" {
    # Deploy contract whose runtime:
    #   PUSH1 0x01  TLOAD   — load transient slot 1 (never written)
    #   PUSH1 0x00  SSTORE  — persist to storage slot 0
    #   STOP
    runtime="60015c60005500"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"

    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    call_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Contract call failed: $call_status" >&2
        return 1
    fi

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$stored" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "TLOAD of unset slot should be 0, got: $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "transient storage clears between transactions" {
    # Deploy contract that:
    #   - On first call: TSTORE 0x99 at slot 0, then SSTORE the TLOAD of slot 0 to storage slot 0
    #   - On second call: just TLOAD slot 0 and SSTORE to storage slot 1
    # After second call, storage slot 1 should be 0 (transient storage cleared).
    #
    # Runtime: We use CALLVALUE to distinguish calls (send 1 wei on first, 0 on second).
    # if CALLVALUE > 0: TSTORE(0, 0x99), SSTORE(0, TLOAD(0))
    # else: SSTORE(1, TLOAD(0))
    #
    # Byte layout:
    #   Byte 0:  34        CALLVALUE
    #   Byte 1:  60 0e     PUSH1 0x0e (jump target = 14)
    #   Byte 3:  57        JUMPI
    #   Byte 4:  60 00     PUSH1 0x00
    #   Byte 6:  5c        TLOAD
    #   Byte 7:  60 01     PUSH1 0x01
    #   Byte 9:  55        SSTORE
    #   Byte 10: 00        STOP
    #   Byte 11: 00 00 00  padding to offset 14
    #   Byte 14: 5b        JUMPDEST
    #   Byte 15: 60 99     PUSH1 0x99
    #   Byte 17: 60 00     PUSH1 0x00
    #   Byte 19: 5d        TSTORE
    #   Byte 20: 60 00     PUSH1 0x00
    #   Byte 22: 5c        TLOAD
    #   Byte 23: 60 00     PUSH1 0x00
    #   Byte 25: 55        SSTORE
    #   Byte 26: 00        STOP
    runtime="34600e5760005c600155000000005b609960005d60005c60005500"

    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"

    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    # First call: send 1 wei to trigger TSTORE path
    cast send \
        --legacy \
        --gas-limit 200000 \
        --value 1 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$contract_addr" >/dev/null

    # Verify slot 0 was written (TSTORE + TLOAD roundtrip in same tx)
    slot0=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    slot0_dec=$(printf "%d" "$slot0")
    if [[ "$slot0_dec" -ne 153 ]]; then  # 0x99 = 153
        echo "First call TSTORE/TLOAD failed: slot0=$slot0_dec expected=153" >&2
        return 1
    fi

    # Second call: send 0 wei to trigger TLOAD-only path
    cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$contract_addr" >/dev/null

    # Slot 1 should be 0 — transient storage was cleared between txs
    slot1=$(cast storage "$contract_addr" 1 --rpc-url "$L2_RPC_URL")
    if [[ "$slot1" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "Transient storage not cleared between txs: slot1=$slot1 (expected 0)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "transient storage is isolated per contract address" {
    # Verify that transient storage is per-address within a SINGLE transaction.
    # Deploy B: TLOAD(0) → SSTORE(0, result) → STOP
    # Deploy A: TSTORE(0, 0xAA) → CALL B → STOP
    # When A calls B in the same tx, B's TLOAD(0) reads B's own transient
    # storage (never written), so it should return 0, not A's 0xAA.

    # Contract B runtime:
    #   PUSH1 0xFF PUSH1 0x01 SSTORE   — sentinel: write 0xFF to slot 1 to prove B ran
    #   PUSH1 0x00 TLOAD PUSH1 0x00 SSTORE STOP  — store TLOAD(0) at slot 0
    # 60 ff 60 01 55 60 00 5c 60 00 55 00
    b_runtime="60ff60015560005c60005500"
    b_len=$(( ${#b_runtime} / 2 ))
    b_len_hex=$(printf "%02x" "$b_len")
    b_initcode="60${b_len_hex}600c60003960${b_len_hex}6000f3${b_runtime}"

    # Deploy B first (A needs B's address)
    b_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --create "0x${b_initcode}")
    b_addr=$(echo "$b_receipt" | jq -r '.contractAddress')
    b_addr_hex="${b_addr#0x}"

    # Contract A runtime:
    #   PUSH1 0xAA  PUSH1 0x00  TSTORE       — write 0xAA to A's transient slot 0
    #   PUSH1 0x00 (retSize)  PUSH1 0x00 (retOffset)
    #   PUSH1 0x00 (argsSize) PUSH1 0x00 (argsOffset)
    #   PUSH1 0x00 (value)    PUSH20 <B>  GAS  CALL
    #   POP  STOP
    a_runtime="60aa60005d"          # TSTORE(0, 0xAA)
    a_runtime+="6000600060006000"   # retSize, retOff, argsSz, argsOff
    a_runtime+="6000"               # value = 0
    a_runtime+="73${b_addr_hex}"    # PUSH20 B addr
    a_runtime+="5af1"               # GAS CALL
    a_runtime+="5000"               # POP STOP

    a_len=$(( ${#a_runtime} / 2 ))
    a_len_hex=$(printf "%02x" "$a_len")
    a_initcode="60${a_len_hex}600c60003960${a_len_hex}6000f3${a_runtime}"

    # Deploy A
    a_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --create "0x${a_initcode}")
    a_addr=$(echo "$a_receipt" | jq -r '.contractAddress')

    # Call A — single tx: A does TSTORE(0, 0xAA) then CALLs B
    call_receipt=$(cast send --legacy --gas-limit 300000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        "$a_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Call to A failed: $call_status" >&2
        return 1
    fi

    # Verify B actually executed by checking its sentinel value in slot 1
    sentinel=$(cast storage "$b_addr" 1 --rpc-url "$L2_RPC_URL")
    sentinel_dec=$(printf "%d" "$sentinel")
    if [[ "$sentinel_dec" -ne 255 ]]; then  # 0xFF = 255
        echo "B did not execute: sentinel slot 1 = $sentinel_dec (expected 255)" >&2
        return 1
    fi

    # B stored TLOAD(0) at its persistent slot 0. Should be 0 (B's own
    # transient storage was never written, even though A wrote 0xAA to A's).
    stored=$(cast storage "$b_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$stored" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "Transient storage leaked across contracts: B's slot 0 = $stored (expected 0)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "TSTORE reverted by sub-call REVERT is undone" {
    # Deploy contract A that:
    #   1. TSTORE(0, 0xBB) — initial value
    #   2. CALLs contract B which does TSTORE(0, 0xCC) then REVERT
    #   3. TLOAD(0) and SSTORE to persistent slot 0
    # Result: slot 0 should be 0xBB (B's write was reverted).
    #
    # This requires two contracts. For simplicity, we test with a single contract
    # that calls itself: first entry TSTORE(0, 0xBB), then CALL self with data,
    # second entry (has calldata) TSTORE(0, 0xCC) + REVERT,
    # back in first entry: TLOAD(0) → SSTORE(0).
    #
    # Runtime:
    #   CALLDATASIZE PUSH1 <else> JUMPI  — branch on whether we have calldata
    #   — no calldata (first entry):
    #     PUSH1 0xBB PUSH1 0x00 TSTORE
    #     PUSH1 0x00 PUSH1 0x00 PUSH1 0x01 PUSH1 0x00 ADDRESS GAS CALL  (call self with 1 byte data)
    #     POP
    #     PUSH1 0x00 TLOAD PUSH1 0x00 SSTORE STOP
    #   — has calldata (re-entrant):
    #     JUMPDEST
    #     PUSH1 0xCC PUSH1 0x00 TSTORE
    #     PUSH1 0x00 PUSH1 0x00 REVERT

    # Let me lay this out byte by byte:
    # 0x00: 36        CALLDATASIZE
    # 0x01: 6020      PUSH1 0x20 (jump to re-entrant branch)
    # 0x03: 57        JUMPI
    # — first entry —
    # 0x04: 60bb      PUSH1 0xBB
    # 0x06: 6000      PUSH1 0x00
    # 0x08: 5d        TSTORE
    # 0x09: 6000      PUSH1 0x00 (retSize)
    # 0x0b: 6000      PUSH1 0x00 (retOffset)
    # 0x0d: 6001      PUSH1 0x01 (argsSize)
    # 0x0f: 6000      PUSH1 0x00 (argsOffset)
    # 0x11: 6000      PUSH1 0x00 (value)
    # 0x13: 30        ADDRESS
    # 0x14: 5a        GAS
    # 0x15: f1        CALL
    # 0x16: 50        POP
    # 0x17: 6000      PUSH1 0x00
    # 0x19: 5c        TLOAD
    # 0x1a: 6000      PUSH1 0x00
    # 0x1c: 55        SSTORE
    # 0x1d: 00        STOP
    # — padding —
    # 0x1e: 00 00
    # — re-entrant —
    # 0x20: 5b        JUMPDEST
    # 0x21: 60cc      PUSH1 0xCC
    # 0x23: 6000      PUSH1 0x00
    # 0x25: 5d        TSTORE
    # 0x26: 6000      PUSH1 0x00
    # 0x28: 6000      PUSH1 0x00
    # 0x2a: fd        REVERT
    runtime="3660205760bb60005d60006000600160006000305af15060005c6000550000005b60cc60005d60006000fd"

    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"

    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 300000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    # Call with no data — triggers first entry path
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 300000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Outer call failed: $call_status" >&2
        return 1
    fi

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    # Should be 0xBB (187) — the reverted sub-call's 0xCC should be rolled back
    if [[ "$stored_dec" -ne 187 ]]; then
        echo "TSTORE revert not undone: expected 187 (0xBB), got $stored_dec" >&2
        if [[ "$stored_dec" -eq 204 ]]; then
            echo "Got 0xCC — sub-call REVERT did not roll back transient storage!" >&2
        fi
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-gas
@test "TSTORE gas cost is less than SSTORE for zero-to-nonzero write" {
    # TSTORE costs 100 gas (warm storage cost). SSTORE zero-to-nonzero costs 20,000+.
    # Deploy two contracts: one does TSTORE, one does SSTORE with same value.
    # Compare gas used.

    # Contract A: TSTORE(0, 1) + STOP
    # Runtime: 60 01 60 00 5d 00
    a_runtime="600160005d00"
    a_len=$(( ${#a_runtime} / 2 ))
    a_len_hex=$(printf "%02x" "$a_len")
    a_initcode="60${a_len_hex}600c60003960${a_len_hex}6000f3${a_runtime}"

    # Contract B: SSTORE(0, 1) + STOP
    # Runtime: 60 01 60 00 55 00
    b_runtime="600160005500"
    b_len=$(( ${#b_runtime} / 2 ))
    b_len_hex=$(printf "%02x" "$b_len")
    b_initcode="60${b_len_hex}600c60003960${b_len_hex}6000f3${b_runtime}"

    # Deploy both
    a_receipt=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${a_initcode}")
    a_addr=$(echo "$a_receipt" | jq -r '.contractAddress')

    b_receipt=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${b_initcode}")
    b_addr=$(echo "$b_receipt" | jq -r '.contractAddress')

    # Call A (TSTORE)
    a_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$a_addr")
    a_gas=$(echo "$a_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Call B (SSTORE)
    b_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$b_addr")
    b_gas=$(echo "$b_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "TSTORE gas: $a_gas, SSTORE gas: $b_gas" >&3

    if [[ "$a_gas" -ge "$b_gas" ]]; then
        echo "TSTORE ($a_gas) should cost less gas than SSTORE ($b_gas)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip1153,evm-opcode
@test "TSTORE in DELEGATECALL shares caller transient storage context" {
    # When contract A DELEGATECALLs contract B, B's TSTORE writes to A's
    # transient storage context. Verify by:
    #   1. Deploy B with runtime: PUSH1 0xDD PUSH1 0x00 TSTORE STOP
    #   2. Deploy A with runtime: DELEGATECALL B, then TLOAD(0), SSTORE(0, result)
    #   3. Call A — slot 0 should be 0xDD

    # Contract B: TSTORE(0, 0xDD) + STOP
    b_runtime="60dd60005d00"
    b_len=$(( ${#b_runtime} / 2 ))
    b_len_hex=$(printf "%02x" "$b_len")
    b_initcode="60${b_len_hex}600c60003960${b_len_hex}6000f3${b_runtime}"

    b_receipt=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${b_initcode}")
    b_addr=$(echo "$b_receipt" | jq -r '.contractAddress')
    b_addr_hex="${b_addr#0x}"

    # Contract A runtime:
    #   PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 PUSH1 0x00 PUSH20 <B> GAS DELEGATECALL
    #   POP  PUSH1 0x00 TLOAD  PUSH1 0x00 SSTORE  STOP
    # 60 00 60 00 60 00 60 00 73 <B:20> 5a f4 50 60 00 5c 60 00 55 00
    a_runtime="6000600060006000"
    a_runtime+="73${b_addr_hex}"
    a_runtime+="5af4"  # GAS DELEGATECALL
    a_runtime+="50"    # POP
    a_runtime+="60005c" # TLOAD(0)
    a_runtime+="60005500" # SSTORE(0) STOP

    a_len=$(( ${#a_runtime} / 2 ))
    a_len_hex=$(printf "%02x" "$a_len")
    a_initcode="60${a_len_hex}600c60003960${a_len_hex}6000f3${a_runtime}"

    a_receipt=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${a_initcode}")
    a_addr=$(echo "$a_receipt" | jq -r '.contractAddress')

    # Call A
    call_receipt=$(cast send --legacy --gas-limit 300000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$a_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "DELEGATECALL test call failed: $call_status" >&2
        return 1
    fi

    stored=$(cast storage "$a_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    if [[ "$stored_dec" -ne 221 ]]; then  # 0xDD = 221
        echo "DELEGATECALL TSTORE did not write to caller's context:" >&2
        echo "  expected 221 (0xDD), got $stored_dec" >&2
        return 1
    fi
}
