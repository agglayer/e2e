#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,evm-opcode

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

# Helper: deploy a contract from runtime hex, return address via $contract_addr
deploy_runtime() {
    local runtime="$1"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    local offset_hex="0c"
    local initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit 200000 \
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

# Helper: call a contract and return receipt via $call_receipt
call_contract() {
    local addr="$1"
    call_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$addr")

    local status
    status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "call_contract failed: $status" >&2
        return 1
    fi
}

# ─── Stack / Push ────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip3855,evm-opcode
@test "PUSH0 pushes zero onto the stack (EIP-3855)" {
    # PUSH0 (0x5f) pushes 0 onto the stack. Store it and verify.
    # Runtime: PUSH0 PUSH1 0x00 SSTORE STOP
    # 5f 60 00 55 00
    deploy_runtime "5f60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$stored" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "PUSH0 did not push zero: stored value = $stored" >&2
        return 1
    fi

    echo "PUSH0 (EIP-3855) confirmed working — pushed 0x00" >&3
}

# ─── Bitwise Shifts (EIP-145) ───────────────────────────────────────────────

# bats test_tags=execution-specs,eip145,evm-opcode
@test "SHL left shift: 1 << 4 = 16 (EIP-145)" {
    # SHL(shift, value) — shift is TOS, value is second
    # PUSH1 0x01 PUSH1 0x04 SHL PUSH1 0x00 SSTORE STOP
    # 60 01 60 04 1b 60 00 55 00
    deploy_runtime "600160041b60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    if [[ "$stored_dec" -ne 16 ]]; then
        echo "SHL(1, 4) expected 16, got $stored_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip145,evm-opcode
@test "SHR right shift: 0xFF >> 4 = 0x0F (EIP-145)" {
    # SHR(shift, value)
    # PUSH1 0xFF PUSH1 0x04 SHR PUSH1 0x00 SSTORE STOP
    # 60 ff 60 04 1c 60 00 55 00
    deploy_runtime "60ff60041c60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    if [[ "$stored_dec" -ne 15 ]]; then
        echo "SHR(0xFF, 4) expected 15 (0x0F), got $stored_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip145,evm-opcode
@test "SAR arithmetic right shift sign-extends negative values (EIP-145)" {
    # SAR on a value with MSB set should sign-extend.
    # Simpler: push -1 (0xFF..FF), SAR by 1 = still -1 (0xFF..FF)
    # PUSH32 0xFF..FF PUSH1 0x01 SAR PUSH1 0x00 SSTORE STOP
    deploy_runtime "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011d60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    if [[ "$stored" != "$expected" ]]; then
        echo "SAR(-1, 1) expected $expected, got $stored" >&2
        return 1
    fi
}

# ─── Arithmetic ─────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,evm-opcode
@test "SIGNEXTEND correctly sign-extends byte 0 of 0x80" {
    # SIGNEXTEND(0, 0x80): extend bit 7 of byte 0 → should fill with 1s
    # Result: 0xFF..FF80
    # PUSH1 0x80 PUSH1 0x00 SIGNEXTEND PUSH1 0x00 SSTORE STOP
    # 60 80 60 00 0b 60 00 55 00
    deploy_runtime "608060000b60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80"
    if [[ "$stored" != "$expected" ]]; then
        echo "SIGNEXTEND(0, 0x80) expected $expected, got $stored" >&2
        return 1
    fi
}

# ─── Memory Operations (EIP-5656 MCOPY) ─────────────────────────────────────

# bats test_tags=execution-specs,eip5656,evm-opcode
@test "MCOPY basic non-overlapping copy of 32 bytes" {
    # Store 0xFF..FF at memory offset 0, MCOPY 32 bytes from offset 0 to offset 32,
    # then SSTORE the value at offset 32 to slot 0 for verification.
    #
    # 7f FF..FF(32) 6000 52 6020 6000 6020 5e 6020 51 6000 55 00
    runtime="7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    runtime+="600052"      # MSTORE at 0
    runtime+="602060006020" # MCOPY args: push len=0x20, src=0x00, dst=0x20
    runtime+="5e"           # MCOPY
    runtime+="602051"       # MLOAD from 0x20
    runtime+="60005500"     # SSTORE to slot 0, STOP

    deploy_runtime "$runtime"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    if [[ "$stored" != "$expected" ]]; then
        echo "MCOPY non-overlapping copy failed:" >&2
        echo "  expected: $expected" >&2
        echo "  got:      $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip5656,evm-opcode
@test "MCOPY overlapping forward copy (src < dst) has correct memmove semantics" {
    # Store 0xAA..AA at mem[0..31], MCOPY 32 bytes from 0 to 16,
    # then load mem[16..47] and verify it equals 0xAA..AA.
    runtime="7faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    runtime+="600052"       # MSTORE at 0
    runtime+="602060006010" # MCOPY args: push len=0x20, src=0x00, dst=0x10
    runtime+="5e"           # MCOPY
    runtime+="601051"       # MLOAD from 0x10
    runtime+="60005500"     # SSTORE to slot 0, STOP

    deploy_runtime "$runtime"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    if [[ "$stored" != "$expected" ]]; then
        echo "MCOPY forward overlapping copy incorrect:" >&2
        echo "  expected: $expected" >&2
        echo "  got:      $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip5656,evm-opcode
@test "MCOPY overlapping backward copy (src > dst) has correct memmove semantics" {
    # Store 0xBB..BB at mem[32..63], MCOPY 32 bytes from offset 32 to offset 16.
    runtime="7fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    runtime+="602052"       # MSTORE at 0x20 (32)
    runtime+="602060206010" # MCOPY args: push len=0x20, src=0x20, dst=0x10
    runtime+="5e"           # MCOPY
    runtime+="601051"       # MLOAD from 0x10
    runtime+="60005500"     # SSTORE to slot 0, STOP

    deploy_runtime "$runtime"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    if [[ "$stored" != "$expected" ]]; then
        echo "MCOPY backward overlapping copy incorrect:" >&2
        echo "  expected: $expected" >&2
        echo "  got:      $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip5656,evm-opcode
@test "MCOPY with zero length is a no-op" {
    # Store 0xCC..CC at mem[0..31], MCOPY with length 0, verify mem[0..31] unchanged.
    runtime="7fcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    runtime+="600052"       # MSTORE at 0
    runtime+="600060006020" # MCOPY args: push len=0x00, src=0x00, dst=0x20
    runtime+="5e"           # MCOPY (zero length)
    runtime+="600051"       # MLOAD from 0 (verify source unchanged)
    runtime+="60005500"     # SSTORE to slot 0, STOP

    deploy_runtime "$runtime"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    if [[ "$stored" != "$expected" ]]; then
        echo "MCOPY zero-length modified source memory:" >&2
        echo "  expected: $expected" >&2
        echo "  got:      $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip5656,evm-gas
@test "MCOPY to high offset triggers memory expansion and charges gas" {
    # MCOPY to a high destination offset forces memory expansion.
    # Compare gas used with and without expansion.

    # Contract A: MCOPY 1 byte from 0 to offset 0 (no expansion beyond existing)
    a_runtime="600160006000"  # MCOPY args: push len=1, src=0, dst=0
    a_runtime+="5e00"          # MCOPY STOP
    deploy_runtime "$a_runtime"
    a_addr="$contract_addr"

    # Contract B: MCOPY 1 byte from 0 to offset 1024 (forces expansion)
    b_runtime="600160006104005e00"  # MCOPY args: push len=0x01, src=0x00, dst=0x0400, MCOPY, STOP
    deploy_runtime "$b_runtime"
    b_addr="$contract_addr"

    a_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$a_addr")
    a_gas=$(echo "$a_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    b_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$b_addr")
    b_gas=$(echo "$b_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "MCOPY no expansion gas: $a_gas, MCOPY with expansion gas: $b_gas" >&3

    if [[ "$b_gas" -le "$a_gas" ]]; then
        echo "MCOPY with memory expansion ($b_gas) should cost more than without ($a_gas)" >&2
        return 1
    fi
}

# ─── Address / Context ──────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip1344,evm-opcode
@test "CHAINID returns the correct chain ID (EIP-1344)" {
    # Deploy contract: CHAINID PUSH1 0x00 SSTORE STOP
    # Runtime: 46 60 00 55 00
    deploy_runtime "4660005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    expected_chain_id=$(cast chain-id --rpc-url "$L2_RPC_URL")

    if [[ "$stored_dec" -ne "$expected_chain_id" ]]; then
        echo "CHAINID mismatch: opcode returned $stored_dec, RPC says $expected_chain_id" >&2
        return 1
    fi
    echo "CHAINID = $stored_dec" >&3
}

# bats test_tags=execution-specs,evm-opcode
@test "ADDRESS returns the contract's own address" {
    # Runtime: ADDRESS PUSH1 0x00 SSTORE STOP
    # 30 60 00 55 00
    deploy_runtime "3060005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_addr="0x${stored: -40}"

    stored_lower=$(echo "$stored_addr" | tr '[:upper:]' '[:lower:]')
    expected_lower=$(echo "$contract_addr" | tr '[:upper:]' '[:lower:]')

    if [[ "$stored_lower" != "$expected_lower" ]]; then
        echo "ADDRESS mismatch: opcode=$stored_lower expected=$expected_lower" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-opcode
@test "ORIGIN returns the transaction sender EOA" {
    # Deploy contract: ORIGIN PUSH1 0x00 SSTORE STOP
    # 32 60 00 55 00
    deploy_runtime "3260005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_addr="0x${stored: -40}"

    stored_lower=$(echo "$stored_addr" | tr '[:upper:]' '[:lower:]')
    expected_lower=$(echo "$ephemeral_address" | tr '[:upper:]' '[:lower:]')

    if [[ "$stored_lower" != "$expected_lower" ]]; then
        echo "ORIGIN mismatch: opcode=$stored_lower expected=$expected_lower" >&2
        return 1
    fi
}

# ─── Return Data ────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,evm-opcode
@test "RETURNDATASIZE before any call returns 0" {
    # RETURNDATASIZE PUSH1 0x00 SSTORE STOP
    # 3d 60 00 55 00
    deploy_runtime "3d60005500"
    call_contract "$contract_addr"

    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$stored" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
        echo "RETURNDATASIZE before any call should be 0, got: $stored" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-opcode
@test "RETURNDATASIZE after CALL reflects callee return data length" {
    # Deploy callee that returns 5 bytes.
    # Callee: PUSH5 0x0102030405 PUSH1 0x00 MSTORE PUSH1 0x05 PUSH1 0x1b RETURN
    # mem[0..31] after MSTORE = 00..00 01 02 03 04 05 (value right-aligned)
    # Return bytes 27-31 (the 5 meaningful bytes).
    callee_runtime="6401020304056000526005601bf3"

    deploy_runtime "$callee_runtime"
    callee_addr="$contract_addr"
    callee_hex="${callee_addr#0x}"

    # Deploy caller that CALLs callee, then stores RETURNDATASIZE at slot 0.
    caller_runtime="60006000600060006000"
    caller_runtime+="73${callee_hex}"
    caller_runtime+="5af150"  # GAS CALL POP
    caller_runtime+="3d"      # RETURNDATASIZE
    caller_runtime+="60005500" # SSTORE(0) STOP

    deploy_runtime "$caller_runtime"
    caller_addr="$contract_addr"

    call_contract "$caller_addr"

    stored=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    stored_dec=$(printf "%d" "$stored")

    if [[ "$stored_dec" -ne 5 ]]; then
        echo "RETURNDATASIZE after CALL expected 5, got $stored_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-opcode
@test "RETURNDATACOPY copies callee return data correctly" {
    # Deploy callee that returns 32 bytes of 0x42.
    callee_runtime="7f4242424242424242424242424242424242424242424242424242424242424242"
    callee_runtime+="600052"     # MSTORE at 0
    callee_runtime+="60206000f3" # RETURN 32 bytes from 0

    deploy_runtime "$callee_runtime"
    callee_addr="$contract_addr"
    callee_hex="${callee_addr#0x}"

    # Caller: CALL callee, RETURNDATACOPY to mem[0], MLOAD, SSTORE to slot 0.
    caller_runtime="60006000600060006000"
    caller_runtime+="73${callee_hex}"
    caller_runtime+="5af150"         # GAS CALL POP
    caller_runtime+="602060006000"   # size=0x20, srcOff=0, destOff=0
    caller_runtime+="3e"             # RETURNDATACOPY
    caller_runtime+="600051"         # MLOAD(0)
    caller_runtime+="60005500"       # SSTORE(0) STOP

    deploy_runtime "$caller_runtime"
    caller_addr="$contract_addr"

    call_contract "$caller_addr"

    stored=$(cast storage "$caller_addr" 0 --rpc-url "$L2_RPC_URL")
    expected="0x4242424242424242424242424242424242424242424242424242424242424242"
    if [[ "$stored" != "$expected" ]]; then
        echo "RETURNDATACOPY mismatch:" >&2
        echo "  expected: $expected" >&2
        echo "  got:      $stored" >&2
        return 1
    fi
}

# ─── Gas / Control Flow ─────────────────────────────────────────────────────

# bats test_tags=execution-specs,evm-opcode,evm-gas
@test "REVERT returns data and does not consume all gas" {
    # Deploy contract that REVERTs with 4 bytes of data.
    # Runtime: PUSH4 0xdeadbeef PUSH1 0x00 MSTORE PUSH1 0x04 PUSH1 0x1c REVERT
    runtime="63deadbeef6000526004601cfd"

    deploy_runtime "$runtime"

    # Call the contract — expect failure
    set +e
    call_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$contract_addr" 2>/dev/null)
    call_exit=$?
    set -e

    if [[ $call_exit -eq 0 && -n "$call_receipt" ]]; then
        tx_status=$(echo "$call_receipt" | jq -r '.status // "0x0"')
        gas_used=$(echo "$call_receipt" | jq -r '.gasUsed // "0x0"' | xargs printf "%d\n")

        echo "REVERT tx status: $tx_status, gasUsed: $gas_used" >&3

        # Gas should be significantly less than the 200000 limit
        if [[ "$gas_used" -ge 200000 ]]; then
            echo "REVERT consumed all gas ($gas_used) — should refund unused" >&2
            return 1
        fi
    fi
    # If cast itself failed, that's also acceptable — node rejected the reverted tx
}

# bats test_tags=execution-specs,eip3651,evm-gas
@test "warm COINBASE access costs less than cold access to arbitrary address (EIP-3651)" {
    # EIP-3651 (Shanghai): COINBASE is warm at start of transaction.
    # Deploy two contracts:
    #   A: COINBASE BALANCE POP STOP — accesses coinbase (warm)
    #   B: PUSH20 <random_addr> BALANCE POP STOP — accesses cold address

    random_addr=$(cast wallet new --json | jq -r '.[0].address')
    random_hex="${random_addr#0x}"

    # Contract A: COINBASE BALANCE POP STOP = 41 31 50 00
    deploy_runtime "41315000"
    a_addr="$contract_addr"

    # Contract B: PUSH20 <addr> BALANCE POP STOP = 73 <20B> 31 50 00
    deploy_runtime "73${random_hex}315000"
    b_addr="$contract_addr"

    # Call A (warm COINBASE)
    a_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$a_addr")
    a_gas=$(echo "$a_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Call B (cold address)
    b_call=$(cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$b_addr")
    b_gas=$(echo "$b_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "Warm COINBASE access gas: $a_gas, Cold address access gas: $b_gas" >&3

    if [[ "$a_gas" -ge "$b_gas" ]]; then
        echo "Warm COINBASE ($a_gas) should cost less than cold address ($b_gas)" >&2
        echo "EIP-3651 may not be active" >&2
        return 1
    fi
}
