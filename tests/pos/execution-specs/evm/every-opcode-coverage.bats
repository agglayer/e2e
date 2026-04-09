#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,evm-every-opcode
# shellcheck disable=SC2154  # variables exported from setup_file

# Every-Opcode EVM Coverage Tests
# =================================
# Deploys and executes a contract that exercises every EVM opcode and every
# precompile in a single constructor transaction.  Validates:
#   - Successful deployment (all code paths completed without OOG)
#   - Deterministic accumulator written to storage
#   - LOG0-LOG4 emission with correct topic/data structure
#   - Opcode-level trace coverage across all EVM instruction categories
#   - Chain liveness after a gas-heavy deployment
#
# The contract source is at core/contracts/every-opcode.evm and must be
# pre-compiled to core/contracts/bin/every-opcode.bin using the wjmelements/evm
# assembler (https://github.com/wjmelements/evm).
#
# Compile:  ./scripts/compile-evm-asm.sh
#
# RUN: bats tests/pos/execution-specs/evm/every-opcode-coverage.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup — deploy the contract once, share state across all tests
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    local project_root="${BATS_TEST_DIRNAME}/../../../.."
    local bytecode_file="${project_root}/core/contracts/bin/every-opcode.bin"

    if [[ ! -f "$bytecode_file" ]]; then
        echo "ERROR: Compiled bytecode not found at $bytecode_file" >&2
        echo "The pre-compiled binary must be committed to the repository." >&2
        echo "To regenerate: ./scripts/compile-evm-asm.sh" >&2
        return 1
    fi

    local bytecode
    bytecode=$(cat "$bytecode_file" | tr -d '[:space:]')

    if [[ -z "$bytecode" ]]; then
        echo "ERROR: every-opcode.bin is empty" >&2
        return 1
    fi

    # Ensure 0x prefix
    [[ "$bytecode" == 0x* ]] || bytecode="0x${bytecode}"

    echo "Bytecode size: $(( (${#bytecode} - 2) / 2 )) bytes" >&3

    # ── Fund ephemeral deployment wallet ──────────────────────────────────
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    export DEPLOY_PRIVATE_KEY
    DEPLOY_PRIVATE_KEY=$(echo "$wallet_json" | jq -r '.private_key')
    local deploy_address
    deploy_address=$(echo "$wallet_json" | jq -r '.address')
    echo "Deployment wallet: $deploy_address" >&3

    local _err
    if ! _err=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value 10ether "$deploy_address" 2>&1 >/dev/null); then
        case "$_err" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                export _SKIP_ALL="Chain stalled — cannot fund deployment wallet"
                return 0
                ;;
            *)
                echo "Fund failed: $_err" >&2
                return 1
                ;;
        esac
    fi

    # ── Deploy the every-opcode contract ──────────────────────────────────
    # The entire .evm file compiles to constructor bytecode.  The constructor
    # exercises every opcode, stores the accumulator in slot 0, and RETURNs
    # 32 bytes (the accumulator value) as the runtime code.
    local receipt
    if ! receipt=$(cast send \
            --legacy \
            --gas-limit 25000000 \
            --private-key "$DEPLOY_PRIVATE_KEY" \
            --rpc-url "$L2_RPC_URL" \
            --json \
            --create "$bytecode" 2>&1); then
        case "$receipt" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                export _SKIP_ALL="Chain stalled — deployment tx failed"
                return 0
                ;;
            *)
                echo "Deployment failed: $receipt" >&2
                return 1
                ;;
        esac
    fi

    # Persist receipt for tests to read.
    export RECEIPT_FILE
    RECEIPT_FILE=$(mktemp)
    echo "$receipt" > "$RECEIPT_FILE"

    export EVERY_OPCODE_TX_HASH
    EVERY_OPCODE_TX_HASH=$(echo "$receipt" | jq -r '.transactionHash')
    export EVERY_OPCODE_CONTRACT
    EVERY_OPCODE_CONTRACT=$(echo "$receipt" | jq -r '.contractAddress')
    export EVERY_OPCODE_STATUS
    EVERY_OPCODE_STATUS=$(echo "$receipt" | jq -r '.status')
    export EVERY_OPCODE_GAS_USED
    EVERY_OPCODE_GAS_USED=$(echo "$receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
    export DEPLOY_BLOCK
    DEPLOY_BLOCK=$(echo "$receipt" | jq -r '.blockNumber' | xargs printf "%d\n")

    echo "Deployed at $EVERY_OPCODE_CONTRACT (tx: $EVERY_OPCODE_TX_HASH, gas: $EVERY_OPCODE_GAS_USED, block: $DEPLOY_BLOCK)" >&3

    # ── Pre-fetch opcode trace for trace tests ────────────────────────────
    # Done here so the result is shared across all tests (each @test runs in
    # a subshell, so caching inside _ensure_trace would not persist).
    export TRACE_FILE
    TRACE_FILE=$(mktemp)

    local js_tracer='{"tracer": "{data:{},fault:function(){},step:function(l){var o=l.op.toString();this.data[o]=(this.data[o]||0)+1;},result:function(){return this.data;}}"}'
    local trace_result

    if trace_result=$(cast rpc debug_traceTransaction "$EVERY_OPCODE_TX_HASH" \
            "$js_tracer" --rpc-url "$L2_RPC_URL" 2>/dev/null); then
        echo "$trace_result" > "$TRACE_FILE"
        echo "Opcode trace fetched (JS tracer)" >&3
    elif trace_result=$(cast rpc debug_traceTransaction "$EVERY_OPCODE_TX_HASH" \
            '{}' --rpc-url "$L2_RPC_URL" 2>/dev/null); then
        echo "$trace_result" | jq '
            [.structLogs[].op] | group_by(.) | map({(.[0]): length}) | add
        ' > "$TRACE_FILE"
        echo "Opcode trace fetched (structLogs fallback)" >&3
    else
        echo '{}' > "$TRACE_FILE"
        echo "WARNING: debug_traceTransaction not available — trace tests will skip" >&3
    fi
}

teardown_file() {
    if [[ -f "${RECEIPT_FILE:-}" ]]; then rm -f "$RECEIPT_FILE"; fi
    if [[ -f "${TRACE_FILE:-}" ]]; then rm -f "$TRACE_FILE"; fi
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Chain stalls are infra issues — skip rather than fail.
    if [[ -n "${_SKIP_ALL:-}" ]]; then
        skip "$_SKIP_ALL"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Check that the trace file was populated in setup_file.
# Skips the test if tracing was not available.
_require_trace() {
    if [[ ! -f "${TRACE_FILE:-}" ]]; then
        skip "Trace file not available"
    fi
    local content
    content=$(cat "$TRACE_FILE")
    if [[ "$content" == "{}" || -z "$content" ]]; then
        skip "debug_traceTransaction not available on this node"
    fi
}

# Check whether an opcode appears in the trace.  Returns 0 if present.
_trace_has_opcode() {
    local opcode="$1"
    jq -e --arg op "$opcode" 'has($op)' "$TRACE_FILE" >/dev/null 2>&1
}

# Assert a list of opcodes are all present in the trace.
# Prints missing opcodes and returns 1 if any are absent.
_assert_opcodes_present() {
    local -a missing=()
    for op in "$@"; do
        if ! _trace_has_opcode "$op"; then
            missing+=("$op")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing opcodes (${#missing[@]}): ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Tests
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=execution-specs,evm-every-opcode,deployment
@test "every-opcode contract deploys successfully" {
    [[ "$EVERY_OPCODE_STATUS" == "0x1" ]]

    # Contract address must be non-null.
    [[ -n "$EVERY_OPCODE_CONTRACT" && "$EVERY_OPCODE_CONTRACT" != "null" ]]

    echo "Contract: $EVERY_OPCODE_CONTRACT" >&3
    echo "Gas used: $EVERY_OPCODE_GAS_USED" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,accumulator
@test "accumulator stored in slot 0 is non-zero" {
    local slot0
    slot0=$(cast storage "$EVERY_OPCODE_CONTRACT" 0 --rpc-url "$L2_RPC_URL")

    local zero="0x0000000000000000000000000000000000000000000000000000000000000000"
    if [[ "$slot0" == "$zero" ]]; then
        echo "Accumulator in slot 0 is zero — opcode chain did not execute correctly" >&2
        return 1
    fi

    echo "Accumulator (slot 0): $slot0" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,accumulator
@test "intermediate accumulator written to slot 0x11235813" {
    # Section 18 of the contract stores the accumulator at slot 0x11235813
    # before the final sections (sub-contract deployments, system calls).
    local slot_intermediate
    slot_intermediate=$(cast storage "$EVERY_OPCODE_CONTRACT" 0x11235813 --rpc-url "$L2_RPC_URL")

    local zero="0x0000000000000000000000000000000000000000000000000000000000000000"
    if [[ "$slot_intermediate" == "$zero" ]]; then
        echo "Intermediate accumulator at slot 0x11235813 is zero — SSTORE in section 18 failed" >&2
        return 1
    fi

    echo "Intermediate accumulator (slot 0x11235813): $slot_intermediate" >&3

    # The final accumulator (slot 0) should differ from the intermediate one
    # because sections 19-21 modify the accumulator further.
    local slot0
    slot0=$(cast storage "$EVERY_OPCODE_CONTRACT" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$slot0" == "$slot_intermediate" ]]; then
        echo "WARNING: final accumulator equals intermediate — sections 19-21 may not have modified it" >&3
    else
        echo "Final accumulator differs from intermediate (sections 19-21 contributed)" >&3
    fi
}

# bats test_tags=execution-specs,evm-every-opcode,accumulator
@test "runtime code is 32 bytes and matches accumulator in slot 0" {
    # The constructor RETURNs the 32-byte accumulator as runtime code.
    local code
    code=$(cast code "$EVERY_OPCODE_CONTRACT" --rpc-url "$L2_RPC_URL")

    local code_len=$(( (${#code} - 2) / 2 ))  # subtract 0x prefix, hex chars / 2
    if [[ "$code_len" -ne 32 ]]; then
        echo "Expected 32-byte runtime code, got $code_len bytes" >&2
        echo "Code: $code" >&2
        return 1
    fi

    # Runtime code should match slot 0 (both are the accumulator value).
    local slot0
    slot0=$(cast storage "$EVERY_OPCODE_CONTRACT" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$code" != "$slot0" ]]; then
        echo "Runtime code does not match slot 0:" >&2
        echo "  code  = $code" >&2
        echo "  slot0 = $slot0" >&2
        return 1
    fi

    echo "Runtime code (32 bytes) matches slot 0: $code" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,logs
@test "receipt contains 5 log entries from LOG0 through LOG4" {
    # The contract emits: LOG0 (0 topics), LOG1 (1), LOG2 (2), LOG3 (3), LOG4 (4).
    local receipt
    receipt=$(cat "$RECEIPT_FILE")

    local log_count
    log_count=$(echo "$receipt" | jq '.logs | length')
    if [[ "$log_count" -ne 5 ]]; then
        echo "Expected 5 log entries (LOG0-LOG4), got $log_count" >&2
        return 1
    fi

    # Verify each log has the expected number of topics (0 through 4).
    local expected_topics=(0 1 2 3 4)
    for i in "${!expected_topics[@]}"; do
        local actual_topics
        actual_topics=$(echo "$receipt" | jq ".logs[$i].topics | length")
        if [[ "$actual_topics" -ne "${expected_topics[$i]}" ]]; then
            echo "Log[$i]: expected ${expected_topics[$i]} topics, got $actual_topics" >&2
            return 1
        fi
    done

    echo "All 5 log entries have correct topic counts (0,1,2,3,4)" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,logs
@test "log data contains 'John was here' payload" {
    # All 5 LOG events share the same data: "John was here\n" (14 bytes).
    # Hex: 4a6f686e2077617320686572650a
    local receipt
    receipt=$(cat "$RECEIPT_FILE")

    local expected_data="0x4a6f686e2077617320686572650a"

    for i in $(seq 0 4); do
        local data
        data=$(echo "$receipt" | jq -r ".logs[$i].data")
        if [[ "$data" != "$expected_data" ]]; then
            echo "Log[$i] data mismatch:" >&2
            echo "  expected: $expected_data" >&2
            echo "  actual:   $data" >&2
            return 1
        fi
    done

    echo "All 5 logs contain 'John was here' data" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers arithmetic, comparison, and bitwise opcodes" {
    _require_trace

    _assert_opcodes_present \
        ADD MUL SUB DIV SDIV MOD SMOD ADDMOD MULMOD EXP SIGNEXTEND \
        LT GT SLT SGT EQ ISZERO \
        AND OR XOR NOT BYTE SHL SHR SAR

    echo "All arithmetic, comparison, and bitwise opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers environment and block info opcodes" {
    _require_trace

    _assert_opcodes_present \
        ADDRESS BALANCE ORIGIN CALLER CALLVALUE CALLDATALOAD CALLDATASIZE \
        CALLDATACOPY CODESIZE CODECOPY GASPRICE EXTCODESIZE EXTCODECOPY \
        EXTCODEHASH BLOCKHASH COINBASE TIMESTAMP NUMBER PREVRANDAO \
        GASLIMIT CHAINID SELFBALANCE BASEFEE GAS

    echo "All environment and block info opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers memory, storage, and flow control opcodes" {
    _require_trace

    _assert_opcodes_present \
        MLOAD MSTORE MSTORE8 MSIZE MCOPY \
        SLOAD SSTORE \
        SHA3 \
        JUMP JUMPI JUMPDEST PC \
        POP RETURN RETURNDATASIZE RETURNDATACOPY

    echo "All memory, storage, and flow control opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers PUSH0 through PUSH32" {
    _require_trace

    _assert_opcodes_present \
        PUSH0 \
        PUSH1 PUSH2 PUSH3 PUSH4 PUSH5 PUSH6 PUSH7 PUSH8 \
        PUSH9 PUSH10 PUSH11 PUSH12 PUSH13 PUSH14 PUSH15 PUSH16 \
        PUSH17 PUSH18 PUSH19 PUSH20 PUSH21 PUSH22 PUSH23 PUSH24 \
        PUSH25 PUSH26 PUSH27 PUSH28 PUSH29 PUSH30 PUSH31 PUSH32

    echo "All 33 PUSH opcodes (PUSH0-PUSH32) present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers DUP1-DUP16 and SWAP1-SWAP16" {
    _require_trace

    _assert_opcodes_present \
        DUP1 DUP2 DUP3 DUP4 DUP5 DUP6 DUP7 DUP8 \
        DUP9 DUP10 DUP11 DUP12 DUP13 DUP14 DUP15 DUP16 \
        SWAP1 SWAP2 SWAP3 SWAP4 SWAP5 SWAP6 SWAP7 SWAP8 \
        SWAP9 SWAP10 SWAP11 SWAP12 SWAP13 SWAP14 SWAP15 SWAP16

    echo "All 32 DUP/SWAP opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers LOG0-LOG4" {
    _require_trace

    _assert_opcodes_present LOG0 LOG1 LOG2 LOG3 LOG4

    echo "All LOG opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers CALL, CALLCODE, DELEGATECALL, STATICCALL" {
    _require_trace

    _assert_opcodes_present CALL CALLCODE DELEGATECALL STATICCALL

    echo "All call-family opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers CREATE and CREATE2" {
    _require_trace

    _assert_opcodes_present CREATE CREATE2

    echo "CREATE and CREATE2 present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers transient storage (TSTORE, TLOAD)" {
    _require_trace

    _assert_opcodes_present TSTORE TLOAD

    echo "Transient storage opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers sub-contract terminal opcodes (STOP, REVERT, INVALID, SELFDESTRUCT)" {
    _require_trace

    # These opcodes run inside sub-contracts deployed via CREATE.
    # STOP: runtime = 00
    # REVERT: runtime = 600080FD
    # INVALID: runtime = FE
    # SELFDESTRUCT: runtime = 6000FF
    _assert_opcodes_present STOP REVERT INVALID SELFDESTRUCT

    echo "All terminal opcodes exercised via sub-contracts" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,trace
@test "trace covers blob opcodes (BLOBHASH, BLOBBASEFEE)" {
    _require_trace

    # BLOBHASH and BLOBBASEFEE run inside sub-contracts.  On non-blob txs
    # they return 0 but the opcodes should still be present in the trace.
    _assert_opcodes_present BLOBHASH BLOBBASEFEE

    echo "Blob opcodes present in trace" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,precompile
@test "legacy precompiles (ecrecover, sha256, ripemd160, identity) produced results" {
    # The contract calls precompiles and XORs their output into the accumulator.
    # If the accumulator is non-zero and the contract succeeded, the precompiles
    # returned results.  We can verify more specifically by checking that the
    # contract's storage was written (already done) and that the receipt shows
    # enough gas was consumed for precompile calls.
    #
    # A more direct check: call the precompiles standalone with the same inputs
    # and verify they return non-trivial data.

    # ecrecover (0x01) — should return an address
    local ecrecover_input="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3000000000000000000000000000000000000000000000000000000000000001c9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac80388256084f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"
    local ecrecover_out
    if ! ecrecover_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000001" "0x${ecrecover_input}" 2>&1); then
        echo "ecrecover call failed: $ecrecover_out" >&2
        return 1
    fi
    if [[ -z "$ecrecover_out" || "$ecrecover_out" == "0x" ]]; then
        echo "ecrecover returned empty" >&2
        return 1
    fi
    echo "ecrecover output: $ecrecover_out" >&3

    # sha256 (0x02) — hash 32 bytes
    local sha256_out
    if ! sha256_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000002" \
        "$ecrecover_out" 2>&1); then
        echo "sha256 call failed: $sha256_out" >&2
        return 1
    fi
    if [[ -z "$sha256_out" || "$sha256_out" == "0x" ]]; then
        echo "sha256 returned empty" >&2
        return 1
    fi
    echo "sha256 output: $sha256_out" >&3

    # ripemd160 (0x03)
    local ripemd_out
    if ! ripemd_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000003" \
        "$sha256_out" 2>&1); then
        echo "ripemd160 call failed: $ripemd_out" >&2
        return 1
    fi
    if [[ -z "$ripemd_out" || "$ripemd_out" == "0x" ]]; then
        echo "ripemd160 returned empty" >&2
        return 1
    fi
    echo "ripemd160 output: $ripemd_out" >&3

    # identity (0x04) — should return input unchanged
    local identity_out
    if ! identity_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000004" \
        "$sha256_out" 2>&1); then
        echo "identity call failed: $identity_out" >&2
        return 1
    fi
    if [[ "$identity_out" != "$sha256_out" ]]; then
        echo "identity precompile did not return input unchanged:" >&2
        echo "  input:  $sha256_out" >&2
        echo "  output: $identity_out" >&2
        return 1
    fi
    echo "identity precompile verified (returned input unchanged)" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,precompile
@test "modexp precompile (0x05) returns expected result" {
    # 2^10 mod 1000 = 1024 mod 1000 = 24
    local input="0x"
    input+="0000000000000000000000000000000000000000000000000000000000000020"  # baseLen=32
    input+="0000000000000000000000000000000000000000000000000000000000000020"  # expLen=32
    input+="0000000000000000000000000000000000000000000000000000000000000020"  # modLen=32
    input+="0000000000000000000000000000000000000000000000000000000000000002"  # base=2
    input+="000000000000000000000000000000000000000000000000000000000000000a"  # exp=10
    input+="00000000000000000000000000000000000000000000000000000000000003e8"  # mod=1000

    local out
    if ! out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000005" "$input" 2>&1); then
        echo "modexp call failed: $out" >&2
        return 1
    fi

    local expected="0x0000000000000000000000000000000000000000000000000000000000000018"
    if [[ "$out" != "$expected" ]]; then
        echo "modexp(2, 10, 1000) expected 24 (0x18), got: $out" >&2
        return 1
    fi
    echo "modexp(2^10 mod 1000) = 24 (correct)" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,precompile
@test "bn256 precompiles (ecAdd 0x06, ecMul 0x07) return valid curve points" {
    # ecAdd: G + known_point → should return a valid 64-byte point
    local ecadd_input="0x"
    ecadd_input+="0000000000000000000000000000000000000000000000000000000000000001"
    ecadd_input+="0000000000000000000000000000000000000000000000000000000000000002"
    ecadd_input+="1c76476f4def4bb94541d57ebba1193381ffa7aa76ada664dd31c16024c43f59"
    ecadd_input+="3034dd2920f673e204fee2811c678745fc819b55d3e9d294e45c9b03a76aef41"

    local ecadd_out
    if ! ecadd_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000006" "$ecadd_input" 2>&1); then
        echo "ecAdd call failed: $ecadd_out" >&2
        return 1
    fi

    if [[ -z "$ecadd_out" || "$ecadd_out" == "0x" || ${#ecadd_out} -lt 130 ]]; then
        echo "ecAdd returned invalid output: $ecadd_out" >&2
        return 1
    fi
    echo "ecAdd returned 64-byte point: ${ecadd_out:0:42}..." >&3

    # ecMul: G * 2 → should return 2G
    local ecmul_input="0x"
    ecmul_input+="0000000000000000000000000000000000000000000000000000000000000001"
    ecmul_input+="0000000000000000000000000000000000000000000000000000000000000002"
    ecmul_input+="0000000000000000000000000000000000000000000000000000000000000002"

    local ecmul_out
    if ! ecmul_out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000007" "$ecmul_input" 2>&1); then
        echo "ecMul call failed: $ecmul_out" >&2
        return 1
    fi

    if [[ -z "$ecmul_out" || "$ecmul_out" == "0x" || ${#ecmul_out} -lt 130 ]]; then
        echo "ecMul returned invalid output: $ecmul_out" >&2
        return 1
    fi
    echo "ecMul(G, 2) returned 64-byte point: ${ecmul_out:0:42}..." >&3
}

# bats test_tags=execution-specs,evm-every-opcode,precompile
@test "blake2f precompile (0x09) returns non-trivial output" {
    # BLAKE2F with 1 round — EIP-152 requires exactly 213 bytes:
    #   rounds(4) + h(64) + m(128) + t(16) + f(1) = 213
    local input="0x"
    input+="00000001"  # rounds = 1 (4 bytes)
    input+="48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5"  # h[0..3] (32 bytes)
    input+="d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b"  # h[4..7] (32 bytes)
    input+="6162630000000000000000000000000000000000000000000000000000000000"  # m[0..3]  (32 bytes)
    input+="0000000000000000000000000000000000000000000000000000000000000000"  # m[4..7]  (32 bytes)
    input+="0000000000000000000000000000000000000000000000000000000000000000"  # m[8..11] (32 bytes)
    input+="0000000000000000000000000000000000000000000000000000000000000000"  # m[12..15](32 bytes)
    input+="0300000000000000"  # t[0] (8 bytes, little-endian)
    input+="0000000000000000"  # t[1] (8 bytes)
    input+="01"  # f = true (1 byte)

    local out
    if ! out=$(cast call --rpc-url "$L2_RPC_URL" \
        "0x0000000000000000000000000000000000000009" "$input" 2>&1); then
        echo "blake2f call failed: $out" >&2
        return 1
    fi

    local zero_64="0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    if [[ -z "$out" || "$out" == "0x" || "$out" == "$zero_64" ]]; then
        echo "blake2f returned empty or zero: $out" >&2
        return 1
    fi
    echo "blake2f output: ${out:0:42}..." >&3
}

# bats test_tags=execution-specs,evm-every-opcode,system-contracts
@test "Bor system contracts (ValidatorContract 0x1000, StateReceiver 0x1001) are callable" {
    # The contract CALLs these system contracts. Verify they have code.
    local validator="0x0000000000000000000000000000000000001000"
    local state_receiver="0x0000000000000000000000000000000000001001"

    local v_code
    v_code=$(cast code "$validator" --rpc-url "$L2_RPC_URL")
    if [[ "$v_code" == "0x" ]]; then
        echo "ValidatorContract at $validator has no code" >&2
        return 1
    fi
    echo "ValidatorContract code: $(( (${#v_code} - 2) / 2 )) bytes" >&3

    local sr_code
    sr_code=$(cast code "$state_receiver" --rpc-url "$L2_RPC_URL")
    if [[ "$sr_code" == "0x" ]]; then
        echo "StateReceiver at $state_receiver has no code" >&2
        return 1
    fi
    echo "StateReceiver code: $(( (${#sr_code} - 2) / 2 )) bytes" >&3
}

# bats test_tags=execution-specs,evm-every-opcode,liveness
@test "chain continues producing blocks after heavy all-opcode deployment" {
    local post_block
    local wait_secs=0
    local max_wait=60
    local target=$(( DEPLOY_BLOCK + 5 ))

    while true; do
        post_block=$(cast block-number --rpc-url "$L2_RPC_URL" 2>/dev/null) || post_block=0
        if [[ "$post_block" -ge "$target" ]]; then
            break
        fi
        if [[ "$wait_secs" -ge "$max_wait" ]]; then
            echo "Chain stalled after every-opcode deployment: stuck at block $post_block (need $target)" >&2
            return 1
        fi
        sleep 2
        wait_secs=$(( wait_secs + 2 ))
    done

    echo "Chain liveness confirmed: block $post_block (deployed at $DEPLOY_BLOCK)" >&3
}
