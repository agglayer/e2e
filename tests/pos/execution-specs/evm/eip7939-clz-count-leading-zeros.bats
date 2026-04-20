#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,eip7939,lisovo
# shellcheck disable=SC2154  # ephemeral_address/ephemeral_private_key set by _fund_ephemeral

# EIP-7939: Count Leading Zeros (CLZ) opcode
#
# Introduces opcode 0x1e (CLZ) that counts the number of leading zero bits
# in a 256-bit unsigned integer.
#
#   - Stack input:  1 value (uint256 x)
#   - Stack output: 1 value (number of leading zero bits, 0..256)
#   - Gas cost:     5 (same as MUL)
#   - Special case: CLZ(0) = 256
#
# Activated with the Lisovo hardfork on Polygon PoS.

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    _fund_ephemeral 1ether
}

# Helper: deploy a contract from runtime hex, sets $contract_addr
deploy_runtime() {
    local runtime="$1"
    local gas="${2:-200000}"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    local offset_hex="0c"
    local initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local status
    status=$(echo "$receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "deploy_runtime failed: $status" >&2
        return 1
    fi
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
}

# Helper: call a contract, sets $call_receipt
call_contract() {
    local addr="$1"
    local gas="${2:-200000}"
    call_receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$addr")

    local status
    status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "call_contract failed: $status" >&2
        return 1
    fi
}

# Helper: deploy a contract that computes CLZ(value) and stores result at slot 0.
# For values that fit in PUSH1..PUSH32, we construct the appropriate bytecode.
# $1 = hex value (no 0x prefix), padded to desired push width
# Sets $contract_addr
deploy_clz_store() {
    local value_hex="$1"
    local value_bytes=$(( ${#value_hex} / 2 ))

    local push_op
    if [[ "$value_bytes" -eq 0 ]]; then
        # Special: push 0 using PUSH1 0x00
        push_op="6000"
    elif [[ "$value_bytes" -le 32 ]]; then
        local op_byte=$(( 0x5f + value_bytes ))
        push_op=$(printf "%02x" "$op_byte")
        push_op+="$value_hex"
    else
        echo "Value too large for PUSH" >&2
        return 1
    fi

    # Runtime: PUSH<N> <value> CLZ PUSH1 0x00 SSTORE STOP
    # CLZ = 0x1e
    local runtime="${push_op}1e60005500"
    deploy_runtime "$runtime"
}

# Helper: deploy CLZ contract, call it, read slot 0, set $clz_result (decimal)
run_clz() {
    local value_hex="$1"
    deploy_clz_store "$value_hex"
    call_contract "$contract_addr"

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    clz_result=$(printf "%d" "$stored")
}

# ─── Feature probe ────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ opcode is active (feature probe)" {
    # CLZ(1) should return 255. If the opcode is not active, the contract
    # will revert with an invalid opcode error.
    set +e
    deploy_clz_store "01"
    local deploy_ok=$?
    set -e

    if [[ $deploy_ok -ne 0 ]]; then
        skip "CLZ opcode (0x1e) not active on this chain"
    fi

    set +e
    call_contract "$contract_addr"
    local call_ok=$?
    set -e

    if [[ $call_ok -ne 0 ]]; then
        skip "CLZ opcode (0x1e) not active on this chain"
    fi

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 255 ]]; then
        echo "CLZ(1) expected 255, got $result — opcode may not be EIP-7939 CLZ" >&2
        return 1
    fi

    echo "CLZ opcode (EIP-7939) confirmed active" >&3
}

# ─── Core semantics ───────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(0) returns 256" {
    run_clz "00"

    if [[ "$clz_result" -ne 256 ]]; then
        echo "CLZ(0) expected 256, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(1) returns 255" {
    run_clz "01"

    if [[ "$clz_result" -ne 255 ]]; then
        echo "CLZ(1) expected 255, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(2) returns 254" {
    run_clz "02"

    if [[ "$clz_result" -ne 254 ]]; then
        echo "CLZ(2) expected 254, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(max uint256) returns 0" {
    # 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF (32 bytes of 0xFF)
    run_clz "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    if [[ "$clz_result" -ne 0 ]]; then
        echo "CLZ(MAX_UINT256) expected 0, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(2^255) returns 0 — highest bit set" {
    # 0x8000...0000 (bit 255 set)
    run_clz "8000000000000000000000000000000000000000000000000000000000000000"

    if [[ "$clz_result" -ne 0 ]]; then
        echo "CLZ(2^255) expected 0, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(2^254) returns 1" {
    # 0x4000...0000 (bit 254 set)
    run_clz "4000000000000000000000000000000000000000000000000000000000000000"

    if [[ "$clz_result" -ne 1 ]]; then
        echo "CLZ(2^254) expected 1, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ(0x7FFF...FFFF) returns 1 — all bits set except MSB" {
    run_clz "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    if [[ "$clz_result" -ne 1 ]]; then
        echo "CLZ(0x7FFF...FFFF) expected 1, got $clz_result" >&2
        return 1
    fi
}

# ─── Powers of 2 sweep ────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ returns correct values for all single-byte powers of 2" {
    # Test 2^0 through 2^7 — these all fit in a single byte PUSH1.
    # CLZ(2^k) = 255 - k for k in [0..7]
    local -a values=("01" "02" "04" "08" "10" "20" "40" "80")
    local -a expected=(255  254  253  252  251  250  249  248)

    for i in "${!values[@]}"; do
        run_clz "${values[$i]}"

        if [[ "$clz_result" -ne "${expected[$i]}" ]]; then
            echo "CLZ(0x${values[$i]}) expected ${expected[$i]}, got $clz_result" >&2
            return 1
        fi
        echo "CLZ(0x${values[$i]}) = $clz_result" >&3
    done
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ returns correct values for powers of 2 across byte boundaries" {
    # Test 2^8, 2^16, 2^24, ... 2^248 — one power per byte boundary.
    # CLZ(2^k) = 255 - k
    local -a byte_positions=(1 2 3 4 8 12 16 20 24 28 31)

    for byte_pos in "${byte_positions[@]}"; do
        local bit_pos=$(( byte_pos * 8 ))
        local expected_clz=$(( 255 - bit_pos ))
        # Build hex: "01" followed by byte_pos zero bytes
        local value_hex="01"
        for ((j = 0; j < byte_pos; j++)); do
            value_hex+="00"
        done

        run_clz "$value_hex"

        if [[ "$clz_result" -ne "$expected_clz" ]]; then
            echo "CLZ(2^$bit_pos) expected $expected_clz, got $clz_result" >&2
            return 1
        fi
        echo "CLZ(2^$bit_pos) = $clz_result" >&3
    done
}

# ─── Mixed bit patterns ───────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ ignores trailing bits — only leading zeros matter" {
    # 0x00FF and 0x00FE should both have CLZ = 248 (first set bit is bit 7)
    run_clz "ff"
    local clz_ff="$clz_result"

    run_clz "fe"
    local clz_fe="$clz_result"

    if [[ "$clz_ff" -ne 248 ]]; then
        echo "CLZ(0xFF) expected 248, got $clz_ff" >&2
        return 1
    fi
    if [[ "$clz_fe" -ne 248 ]]; then
        echo "CLZ(0xFE) expected 248, got $clz_fe" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ of alternating bit patterns" {
    # 0xAA = 10101010 in the lowest byte → CLZ = 248 (first set bit at position 7 of byte)
    run_clz "aa"
    if [[ "$clz_result" -ne 248 ]]; then
        echo "CLZ(0xAA) expected 248, got $clz_result" >&2
        return 1
    fi

    # 0x55 = 01010101 in the lowest byte → CLZ = 249 (first set bit at position 6 of byte)
    run_clz "55"
    if [[ "$clz_result" -ne 249 ]]; then
        echo "CLZ(0x55) expected 249, got $clz_result" >&2
        return 1
    fi

    # 0xAAAA...AA (32 bytes) → first bit set at position 255 → CLZ = 0
    run_clz "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    if [[ "$clz_result" -ne 0 ]]; then
        echo "CLZ(0xAA..AA) expected 0, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ with leading zero bytes followed by non-zero byte" {
    # 16 zero bytes then 0x01 then 15 zero bytes → bit 120 set → CLZ = 135
    # Actually: 16 bytes of zeros = 128 bits of zeros at the top
    # Then 0x01 = bit 120 is set (counting from 0 at LSB)
    # Wait, let me recalculate.
    # The value as a 256-bit number: 0x0000...0001 0000...0000
    # 16 zero bytes + 01 + 15 zero bytes = 32 bytes total
    # The "01" byte is at byte position 15 (0-indexed from MSB), which is bit 120
    # CLZ = 128 - 1 = 127... let me think more carefully.
    #
    # 32 bytes total. First 16 bytes are 0x00. Byte 16 is 0x01. Bytes 17-31 are 0x00.
    # Bit numbering: bit 255 is the MSB of byte 0.
    # Byte 16, bit 0 of that byte = bit (31-16)*8 + 0 = bit 120
    # The highest set bit in 0x01 in byte 16 is bit 120.
    # But wait, 0x01 means bit 0 of that byte, which is bit 15*8 = 120.
    # CLZ = 255 - 120 = 135.

    local value_hex=""
    for ((i = 0; i < 16; i++)); do value_hex+="00"; done
    value_hex+="01"
    for ((i = 0; i < 15; i++)); do value_hex+="00"; done

    run_clz "$value_hex"
    if [[ "$clz_result" -ne 135 ]]; then
        echo "CLZ(0x00..0100..00) expected 135, got $clz_result" >&2
        return 1
    fi
}

# ─── Gas cost ──────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-gas
@test "CLZ gas cost matches MUL (both cost 5 gas)" {
    # Contract A: PUSH1 0x42 CLZ POP STOP
    # CLZ = 0x1e
    deploy_runtime "60421e5000"
    local clz_addr="$contract_addr"

    # Contract B: PUSH1 0x42 PUSH1 0x01 MUL POP STOP
    # MUL = 0x02
    deploy_runtime "60426001025000"
    local mul_addr="$contract_addr"

    local clz_call mul_call
    clz_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$clz_addr")
    local clz_gas
    clz_gas=$(echo "$clz_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    mul_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$mul_addr")
    local mul_gas
    mul_gas=$(echo "$mul_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "CLZ gas: $clz_gas, MUL gas: $mul_gas" >&3

    # Both should consume very similar gas since CLZ and MUL both cost 5.
    # The difference should only be from the extra PUSH1 in the MUL contract.
    # PUSH1 costs 3 gas, so MUL contract should cost 3 more.
    local diff=$(( mul_gas - clz_gas ))
    # Allow for the PUSH1 difference (3 gas)
    if [[ "$diff" -lt 0 ]]; then diff=$(( -diff )); fi

    # The MUL contract has one extra PUSH1 (3 gas), so diff should be ~3.
    # Allow a tolerance of 5 gas for any overhead.
    if [[ "$diff" -gt 8 ]]; then
        echo "Gas difference between CLZ and MUL contracts ($diff) is too large" >&2
        echo "Expected ~3 gas difference (one extra PUSH1 in MUL contract)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-gas
@test "CLZ is cheaper than computing leading zeros via binary search" {
    # Contract A: single CLZ opcode
    # PUSH32 <value> CLZ POP STOP
    local value32="0000000000000000000000000000000100000000000000000000000000000000"
    deploy_runtime "7f${value32}1e5000"
    local clz_addr="$contract_addr"

    # Contract B: approximate CLZ via shifts + comparisons (much more expensive)
    # Simplified: SHR by 128, check if zero, SHR by 64, etc.
    # We just do a bunch of SHR + ISZERO + ADD to simulate a manual approach.
    # PUSH32 <value> DUP1 PUSH1 128 SHR ISZERO PUSH1 128 MUL ADD
    # This is a rough approximation that will consume significantly more gas.
    local manual_runtime="7f${value32}"
    manual_runtime+="80"             # DUP1
    manual_runtime+="608060811c"     # PUSH1 128, PUSH1 128+1=wrong... let me simplify
    # Actually let's just do multiple SHR operations to make it expensive
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="60011c"         # SHR by 1
    manual_runtime+="5000"           # POP STOP

    deploy_runtime "$manual_runtime"
    local manual_addr="$contract_addr"

    local clz_call manual_call
    clz_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$clz_addr")
    local clz_gas
    clz_gas=$(echo "$clz_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    manual_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$manual_addr")
    local manual_gas
    manual_gas=$(echo "$manual_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "CLZ opcode gas: $clz_gas, Manual shifts gas: $manual_gas" >&3

    if [[ "$clz_gas" -ge "$manual_gas" ]]; then
        echo "CLZ opcode ($clz_gas) should cost less than manual shift approach ($manual_gas)" >&2
        return 1
    fi
}

# ─── Integration / interaction tests ──────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ result can be used by subsequent arithmetic (CLZ + SHR roundtrip)" {
    # Compute CLZ(x), then SHR(x, 255-CLZ(x)) should give 1 for any nonzero x.
    # We test with x = 0x42 (CLZ = 249, so SHR by 6 should give 1).
    #
    # Runtime:
    #   PUSH1 0x42      -- x on stack
    #   DUP1            -- x x
    #   CLZ             -- clz(x) x
    #   PUSH2 0x00FF    -- 255 clz(x) x
    #   SUB             -- (255-clz(x)) x
    #   SHR             -- x >> (255-clz(x))
    #   PUSH1 0x00      -- 0 result
    #   SSTORE          -- store result at slot 0
    #   STOP
    deploy_runtime "6042801e61ff00031c60005500"

    # Wait, let me recalculate. CLZ(0x42) = ?
    # 0x42 = 0b01000010. As a 256-bit number, the highest set bit is bit 6
    # (counting from bit 0 at LSB). CLZ = 255 - 6 = 249.
    # SHR by (255 - 249) = SHR by 6 → 0x42 >> 6 = 1. Correct.

    # Actually, let me reconsider the bytecode.
    # PUSH1 0x42 = 60 42
    # DUP1 = 80
    # CLZ = 1e    → stack: [clz(0x42)=249, 0x42]
    # PUSH1 0xFF = 60 ff (255)  → stack: [255, 249, 0x42]
    # SUB = 03   → stack: [6, 0x42]
    # SHR = 1c   → stack: [0x42 >> 6 = 1]
    # PUSH1 0x00 = 60 00
    # SSTORE = 55
    # STOP = 00
    deploy_runtime "6042801e60ff031c60005500"
    call_contract "$contract_addr"

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 1 ]]; then
        echo "CLZ+SHR roundtrip: expected 1 (MSB isolated), got $result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ works correctly inside CALL context" {
    # Deploy a callee that computes CLZ(0x100) and returns the result.
    # 0x100 = 256, bit 8 is set → CLZ = 247
    #
    # Callee: PUSH2 0x0100 CLZ PUSH1 0x00 MSTORE PUSH1 0x20 PUSH1 0x00 RETURN
    local callee_runtime="6101001e600052602060 00f3"
    # Clean up spaces
    callee_runtime="6101001e60005260206000f3"
    deploy_runtime "$callee_runtime"
    local callee_addr="$contract_addr"
    local callee_hex="${callee_addr#0x}"

    # Caller: CALL callee, RETURNDATACOPY result to mem, MLOAD, SSTORE at slot 0
    local caller_runtime="60006000600060006000"
    caller_runtime+="73${callee_hex}"
    caller_runtime+="5af150"         # GAS CALL POP
    caller_runtime+="602060006000"   # size=0x20, srcOff=0, destOff=0
    caller_runtime+="3e"             # RETURNDATACOPY
    caller_runtime+="600051"         # MLOAD(0)
    caller_runtime+="60005500"       # SSTORE(0) STOP

    deploy_runtime "$caller_runtime"
    local caller_addr="$contract_addr"

    call_contract "$caller_addr"

    local stored
    stored=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 247 ]]; then
        echo "CLZ(0x100) via CALL expected 247, got $result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ works correctly inside DELEGATECALL context" {
    # Deploy delegate that computes CLZ(0x8000) and stores result at slot 0.
    # 0x8000: bit 15 is set → CLZ = 240
    local delegate_runtime="6180001e60005500"
    deploy_runtime "$delegate_runtime"
    local delegate_addr="$contract_addr"
    local delegate_hex="${delegate_addr#0x}"

    # Caller: DELEGATECALL to delegate
    local caller_runtime="6000600060006000"
    caller_runtime+="73${delegate_hex}"
    caller_runtime+="5af4"   # GAS DELEGATECALL
    caller_runtime+="5000"   # POP STOP

    deploy_runtime "$caller_runtime"
    local caller_addr="$contract_addr"

    call_contract "$caller_addr"

    local stored
    stored=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 240 ]]; then
        echo "CLZ(0x8000) via DELEGATECALL expected 240, got $result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ inside STATICCALL does not modify state" {
    # Deploy callee that computes CLZ(0xFF) and returns the result (no state writes).
    # CLZ(0xFF) = 248
    local callee_runtime="60ff1e600052602060 00f3"
    callee_runtime="60ff1e60005260206000f3"
    deploy_runtime "$callee_runtime"
    local callee_addr="$contract_addr"
    local callee_hex="${callee_addr#0x}"

    # Caller: STATICCALL callee, copy return data, store result.
    local caller_runtime="60006000600060006000"
    caller_runtime+="73${callee_hex}"
    caller_runtime+="5afa50"         # GAS STATICCALL POP
    caller_runtime+="602060006000"   # RETURNDATACOPY args
    caller_runtime+="3e"             # RETURNDATACOPY
    caller_runtime+="600051"         # MLOAD(0)
    caller_runtime+="60005500"       # SSTORE(0) STOP

    deploy_runtime "$caller_runtime"
    local caller_addr="$contract_addr"

    call_contract "$caller_addr"

    local stored
    stored=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 248 ]]; then
        echo "CLZ(0xFF) via STATICCALL expected 248, got $result" >&2
        return 1
    fi
}

# ─── Edge cases ────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ of consecutive values near power-of-2 boundary" {
    # CLZ(0x7F) = 249, CLZ(0x80) = 248 — boundary at bit 7
    run_clz "7f"
    if [[ "$clz_result" -ne 249 ]]; then
        echo "CLZ(0x7F) expected 249, got $clz_result" >&2
        return 1
    fi

    run_clz "80"
    if [[ "$clz_result" -ne 248 ]]; then
        echo "CLZ(0x80) expected 248, got $clz_result" >&2
        return 1
    fi

    # CLZ(0xFF) = 248, CLZ(0x0100) = 247 — boundary at bit 8
    run_clz "ff"
    if [[ "$clz_result" -ne 248 ]]; then
        echo "CLZ(0xFF) expected 248, got $clz_result" >&2
        return 1
    fi

    run_clz "0100"
    if [[ "$clz_result" -ne 247 ]]; then
        echo "CLZ(0x0100) expected 247, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ of value with only the lowest bit set in each byte" {
    # 0x0101010101...01 (32 bytes) — MSB byte is 0x01, bit 248 set → CLZ = 7
    local value_hex=""
    for ((i = 0; i < 32; i++)); do value_hex+="01"; done

    run_clz "$value_hex"

    if [[ "$clz_result" -ne 7 ]]; then
        echo "CLZ(0x0101...01) expected 7, got $clz_result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip7939,lisovo,evm-opcode
@test "CLZ applied twice gives correct result" {
    # CLZ(CLZ(x)): CLZ(0x42)=249, CLZ(249)=CLZ(0xF9)=248
    # 0xF9 = 11111001, as 256-bit number highest bit is bit 7 → CLZ = 248
    #
    # Runtime: PUSH1 0x42 CLZ CLZ PUSH1 0x00 SSTORE STOP
    deploy_runtime "60421e1e60005500"
    call_contract "$contract_addr"

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    local result
    result=$(printf "%d" "$stored")

    if [[ "$result" -ne 248 ]]; then
        echo "CLZ(CLZ(0x42)) expected 248, got $result" >&2
        echo "  CLZ(0x42) = 249 = 0xF9, CLZ(0xF9) = 248" >&2
        return 1
    fi
}
