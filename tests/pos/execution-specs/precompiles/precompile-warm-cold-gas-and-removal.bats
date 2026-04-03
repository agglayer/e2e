#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pos-precompile,evm-gas

# Precompile warm/cold gas behavior and removal tests.
#
# Two concerns:
#
#   1. Warm vs cold access gas — For all active precompiles, opcodes like
#      BALANCE and EXTCODESIZE should charge warm gas (100) after the
#      precompile has been accessed, not cold gas (2600). A mismatch here
#      can cause bad blocks if the total gas differs between clients.
#
#   2. Removed precompiles — Precompiles that were active in earlier forks
#      but removed in later ones (e.g. KZG point evaluation 0x0a removed
#      in Madhugiri on mainnet) should no longer respond as precompiles.
#      Their BALANCE/EXTCODESIZE should charge cold gas (2600) since they
#      are no longer in the warm precompile set.

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    _fund_ephemeral 1ether
}

# Helper: deploy a contract from runtime hex, return address via stdout.
_deploy() {
    local runtime="$1"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    if [[ "$runtime_len" -le 255 ]]; then
        runtime_len_hex=$(printf "%02x" "$runtime_len")
        local initcode="60${runtime_len_hex}600c60003960${runtime_len_hex}6000f3${runtime}"
    else
        runtime_len_hex=$(printf "%04x" "$runtime_len")
        local initcode="61${runtime_len_hex}61000f60003961${runtime_len_hex}6000f3${runtime}"
    fi

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")
    echo "$receipt" | jq -r '.contractAddress'
}

# Helper: build runtime bytecode that runs an opcode against a target address
# and returns the gas used via SSTORE.
#
# Strategy: GAS before, run opcode, GAS after, subtract, SSTORE to slot 0.
#   GAS PUSH20<addr> <opcode> POP GAS SWAP1 SUB PUSH1 0x00 SSTORE STOP
#
# The GAS..GAS sandwich measures the cost of the opcode + its operand handling.
_build_gas_measure_contract() {
    local addr_hex="$1"  # 20-byte hex address (no 0x prefix)
    local opcode="$2"    # 1-byte opcode hex (e.g. "31" for BALANCE)

    # GAS(5a) PUSH20(73)<addr> <opcode> POP(50) GAS(5a) SWAP1(90) SUB(03) PUSH1(60) 00 SSTORE(55) STOP(00)
    echo "5a73${addr_hex}${opcode}505a900360005500"
}

# Helper: deploy a gas-measurement contract, call it, and read the measured gas from slot 0.
_measure_opcode_gas() {
    local addr_hex="$1"
    local opcode="$2"

    local runtime
    runtime=$(_build_gas_measure_contract "$addr_hex" "$opcode")

    local contract_addr
    contract_addr=$(_deploy "$runtime")

    if [[ "$contract_addr" == "null" || -z "$contract_addr" ]]; then
        echo "0"
        return
    fi

    # Call the contract to execute the opcode.
    cast send --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" \
        "$contract_addr" >/dev/null 2>&1

    # Read the measured gas delta from storage slot 0.
    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL" 2>/dev/null)
    printf "%d" "$stored" 2>/dev/null || echo "0"
}

# ────────────────────────────────────────────────────────────────────────────
# Warm gas tests — active precompiles should be warm (100 gas for BALANCE)
#
# After EIP-2929, precompiles are in the warm access list. BALANCE on a warm
# address costs 100 gas. On a cold (non-precompile) address it costs 2600.
# ────────────────────────────────────────────────────────────────────────────

# Active precompile addresses to test warm access against.
# These are all precompiles expected to be active after all forks.
ACTIVE_PRECOMPILES=(
    "0000000000000000000000000000000000000001"  # ecRecover
    "0000000000000000000000000000000000000002"  # SHA-256
    "0000000000000000000000000000000000000003"  # RIPEMD-160
    "0000000000000000000000000000000000000004"  # identity
    "0000000000000000000000000000000000000005"  # modexp
    "0000000000000000000000000000000000000006"  # bn256Add
    "0000000000000000000000000000000000000007"  # bn256ScalarMul
    "0000000000000000000000000000000000000008"  # bn256Pairing
    "0000000000000000000000000000000000000009"  # blake2F
    "000000000000000000000000000000000000000b"  # BLS12 G1Add
    "0000000000000000000000000000000000000100"  # p256Verify
)

# bats test_tags=execution-specs,pos-precompile,evm-gas,warm-cold
@test "BALANCE on active precompile 0x01 (ecRecover) costs warm gas (~100), not cold (2600)" {
    local gas
    gas=$(_measure_opcode_gas "0000000000000000000000000000000000000001" "31")
    echo "BALANCE(0x01) gas: $gas" >&3

    # Warm access: ~100 gas. Cold access: 2600 gas.
    # Use 500 as threshold — well above warm (100) but far below cold (2600).
    if [[ "$gas" -gt 500 ]]; then
        echo "BALANCE on active precompile 0x01 cost $gas gas (expected ~100 warm, got cold-like)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,evm-gas,warm-cold
@test "EXTCODESIZE on active precompile 0x01 (ecRecover) costs warm gas (~100)" {
    local gas
    gas=$(_measure_opcode_gas "0000000000000000000000000000000000000001" "3b")
    echo "EXTCODESIZE(0x01) gas: $gas" >&3

    if [[ "$gas" -gt 500 ]]; then
        echo "EXTCODESIZE on active precompile 0x01 cost $gas gas (expected ~100 warm)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,evm-gas,warm-cold
@test "BALANCE on all active precompiles costs warm gas" {
    local failures=()

    for addr in "${ACTIVE_PRECOMPILES[@]}"; do
        local gas
        gas=$(_measure_opcode_gas "$addr" "31")
        echo "BALANCE(0x${addr: -4}) = ${gas} gas" >&3

        if [[ "$gas" -gt 500 ]]; then
            failures+=("0x${addr}: ${gas} gas (expected ~100)")
        fi
    done

    if [[ "${#failures[@]}" -gt 0 ]]; then
        echo "The following precompiles had cold-like BALANCE gas costs:" >&2
        printf '  %s\n' "${failures[@]}" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,evm-gas,warm-cold
@test "EXTCODESIZE on all active precompiles costs warm gas" {
    local failures=()

    for addr in "${ACTIVE_PRECOMPILES[@]}"; do
        local gas
        gas=$(_measure_opcode_gas "$addr" "3b")
        echo "EXTCODESIZE(0x${addr: -4}) = ${gas} gas" >&3

        if [[ "$gas" -gt 500 ]]; then
            failures+=("0x${addr}: ${gas} gas (expected ~100)")
        fi
    done

    if [[ "${#failures[@]}" -gt 0 ]]; then
        echo "The following precompiles had cold-like EXTCODESIZE gas costs:" >&2
        printf '  %s\n' "${failures[@]}" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,evm-gas,warm-cold
@test "BALANCE on a random non-precompile address costs cold gas (2600)" {
    # Address 0xdead is not a precompile and should have cold access cost.
    local gas
    gas=$(_measure_opcode_gas "000000000000000000000000000000000000dead" "31")
    echo "BALANCE(0xdead) gas: $gas" >&3

    # Should be 2600 (cold). If it's less than 500, something is wrong.
    if [[ "$gas" -lt 500 ]]; then
        echo "BALANCE on non-precompile address cost $gas gas (expected ~2600 cold)" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Removed precompile tests
#
# KZG point evaluation (0x0a) was added in Cancun/Lisovo but is expected to
# be removed in Madhugiri on mainnet (replaced by BLS12-381 suite at 0x0b-0x11).
# On devnets where Madhugiri is active, 0x0a should no longer behave as a
# precompile — it should return empty on eth_call and BALANCE should charge
# cold gas (2600) since it's no longer in the warm precompile set.
#
# NOTE: Whether 0x0a is removed depends on the bor version and fork config.
# If the chain is pre-Madhugiri, 0x0a is still active and these tests skip.
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pos-precompile,precompile-removal
@test "0x0a KZG: removed after LisovoPro — eth_call returns empty" {
    # First check if BLS12 G1Add (0x0b, added in Madhugiri) is active.
    # If 0x0b is not active, Madhugiri hasn't activated yet → skip.
    local bls_out
    bls_out=$(cast call --rpc-url "${L2_RPC_URL}" \
        "0x000000000000000000000000000000000000000b" \
        "0x$(printf '%0512s' '' | tr ' ' '0')" 2>/dev/null) || bls_out=""
    if [[ "${bls_out}" == "0x" || -z "${bls_out}" ]]; then
        skip "Madhugiri not active (0x0b BLS12 G1Add not responding) — 0x0a removal test not applicable"
    fi

    # Madhugiri is active. 0x0a should no longer respond as a precompile.
    local kzg_out
    kzg_out=$(cast call --rpc-url "${L2_RPC_URL}" \
        "0x000000000000000000000000000000000000000a" "0x" 2>/dev/null) || kzg_out=""

    echo "KZG (0x0a) eth_call output: '${kzg_out}'" >&3

    if [[ -n "${kzg_out}" && "${kzg_out}" != "0x" ]]; then
        echo "0x0a still responding as precompile after Madhugiri activation" >&2
        echo "Output: ${kzg_out}" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,precompile-removal,evm-gas
@test "0x0a KZG: removed after LisovoPro — BALANCE charges cold gas (2600)" {
    # Skip if Madhugiri not active.
    local bls_out
    bls_out=$(cast call --rpc-url "${L2_RPC_URL}" \
        "0x000000000000000000000000000000000000000b" \
        "0x$(printf '%0512s' '' | tr ' ' '0')" 2>/dev/null) || bls_out=""
    if [[ "${bls_out}" == "0x" || -z "${bls_out}" ]]; then
        skip "Madhugiri not active — 0x0a removal test not applicable"
    fi

    local gas
    gas=$(_measure_opcode_gas "000000000000000000000000000000000000000a" "31")
    echo "BALANCE(0x0a) gas after Madhugiri: $gas" >&3

    # After removal, 0x0a should be cold (2600). If it's still warm (~100),
    # the precompile set wasn't updated and this can cause bad blocks.
    if [[ "$gas" -lt 500 ]]; then
        echo "BALANCE on removed precompile 0x0a cost $gas gas (expected ~2600 cold)" >&2
        echo "The precompile warm set may not have been updated after Madhugiri" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pos-precompile,precompile-removal,evm-gas
@test "0x0a KZG: removed after LisovoPro — EXTCODESIZE charges cold gas" {
    local bls_out
    bls_out=$(cast call --rpc-url "${L2_RPC_URL}" \
        "0x000000000000000000000000000000000000000b" \
        "0x$(printf '%0512s' '' | tr ' ' '0')" 2>/dev/null) || bls_out=""
    if [[ "${bls_out}" == "0x" || -z "${bls_out}" ]]; then
        skip "Madhugiri not active — 0x0a removal test not applicable"
    fi

    local gas
    gas=$(_measure_opcode_gas "000000000000000000000000000000000000000a" "3b")
    echo "EXTCODESIZE(0x0a) gas after Madhugiri: $gas" >&3

    if [[ "$gas" -lt 500 ]]; then
        echo "EXTCODESIZE on removed precompile 0x0a cost $gas gas (expected ~2600 cold)" >&2
        return 1
    fi
}
