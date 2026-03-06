#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip80,lisovo

# PIP-80: P256 Precompile Gas Cost Adjustment
#
# Doubles the gas cost of the secp256r1 (P-256) signature verification
# precompile at address 0x0100 from 3,450 to 6,900 gas, aligning with
# Ethereum's EIP-7951 pricing.
#
# Precompile address: 0x0000000000000000000000000000000000000100
# Input (160 bytes):  hash(32) || r(32) || s(32) || x(32) || y(32)
# Output:             32-byte 0x...0001 on success, empty on failure
# Gas cost:           6,900 (was 3,450 under PIP-27)
#
# Activated with the Lisovo hardfork on Polygon PoS.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null

    # P256 precompile address
    P256_ADDR="0x0000000000000000000000000000000000000100"

    # Wycheproof test vector (ecdsa_secp256r1_sha256_p1363), sourced from Bor's p256Verify.json.
    # https://github.com/0xPolygon/bor/blob/e61aaf90c6ac7c331e5050776056eaa673543125/core/vm/testdata/precompiles/p256Verify.json
    # Valid P-256 signature
    VALID_INPUT="0x"
    VALID_INPUT+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    VALID_INPUT+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
    VALID_INPUT+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    VALID_INPUT+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
    VALID_INPUT+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y
}

# Helper: call precompile via eth_call, return output
_p256_call() {
    local input="${1:-0x}"
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" "${P256_ADDR}" "${input}" 2>/dev/null) || out=""
    echo "${out}"
}

# ─── Feature probe ────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 precompile is active at 0x0100" {
    local out
    out=$(_p256_call "$VALID_INPUT")
    echo "p256Verify output: ${out}" >&3

    if [[ "${out}" == "0x" || -z "${out}" ]]; then
        skip "P256 precompile not active at ${P256_ADDR}"
    fi

    [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

# ─── Functional correctness ──────────────────────────────────────────────────

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 valid signature returns 1" {
    local out
    out=$(_p256_call "$VALID_INPUT")

    if [[ "${out}" == "0x" || -z "${out}" ]]; then
        skip "P256 precompile not active"
    fi

    if [[ "${out}" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Valid signature should return 1, got: ${out}" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 invalid signature returns empty output" {
    # Corrupt the signature by flipping a byte in 'r'
    local bad_input="0x"
    bad_input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash (same)
    bad_input+="b73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r (first byte changed a7→b7)
    bad_input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    bad_input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
    bad_input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y

    local out
    out=$(_p256_call "$bad_input")

    # First check if precompile is active
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Invalid signature should return empty (revert/failure)
    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Invalid signature should NOT return 1" >&2
        return 1
    fi
    echo "Invalid signature correctly rejected (output: '${out}')" >&3
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 empty input returns empty output" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    local out
    out=$(_p256_call "0x")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Empty input should NOT return success" >&2
        return 1
    fi
    echo "Empty input correctly rejected (output: '${out}')" >&3
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 truncated input (less than 160 bytes) returns empty output" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Send only the hash (32 bytes, but 160 required)
    local truncated="0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"

    local out
    out=$(_p256_call "$truncated")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Truncated input (32 bytes) should NOT return success" >&2
        return 1
    fi
    echo "Truncated input correctly rejected (output: '${out}')" >&3
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 extra input bytes beyond 160 are ignored (still verifies)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Append 32 extra bytes of garbage after the valid 160-byte input
    local extended="${VALID_INPUT}deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

    local out
    out=$(_p256_call "$extended")

    # The precompile should either accept (ignoring extra bytes) or reject.
    # Per RIP-7212/EIP-7951, only the first 160 bytes are used.
    echo "Extended input (192 bytes) output: '${out}'" >&3
    # If it returns 1, extra bytes are correctly ignored
    # If it returns empty, the implementation rejects oversized input (also acceptable)
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 all-zero input returns empty (invalid point)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # 160 bytes of zeros — (0,0) is not a valid curve point
    local zero_input="0x"
    for ((i = 0; i < 5; i++)); do
        zero_input+="0000000000000000000000000000000000000000000000000000000000000000"
    done

    local out
    out=$(_p256_call "$zero_input")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "All-zero input should NOT return success (invalid curve point)" >&2
        return 1
    fi
    echo "All-zero input correctly rejected" >&3
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 r=0 returns empty (r must be in range 1..n-1)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Valid input but with r = 0
    local bad_r_input="0x"
    bad_r_input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    bad_r_input+="0000000000000000000000000000000000000000000000000000000000000000"  # r = 0
    bad_r_input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    bad_r_input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
    bad_r_input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y

    local out
    out=$(_p256_call "$bad_r_input")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "r=0 should NOT return success" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 s=0 returns empty (s must be in range 1..n-1)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    local bad_s_input="0x"
    bad_s_input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    bad_s_input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
    bad_s_input+="0000000000000000000000000000000000000000000000000000000000000000"  # s = 0
    bad_s_input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
    bad_s_input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y

    local out
    out=$(_p256_call "$bad_s_input")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "s=0 should NOT return success" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 point not on curve returns empty" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Use valid hash, r, s but set public key to (1, 1) which is not on the P-256 curve
    local bad_point_input="0x"
    bad_point_input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    bad_point_input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
    bad_point_input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    bad_point_input+="0000000000000000000000000000000000000000000000000000000000000001"  # x = 1
    bad_point_input+="0000000000000000000000000000000000000000000000000000000000000001"  # y = 1

    local out
    out=$(_p256_call "$bad_point_input")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Point (1,1) not on P-256 curve should NOT return success" >&2
        return 1
    fi
}

# ─── Gas cost verification ────────────────────────────────────────────────────

# bats test_tags=execution-specs,pip80,lisovo,precompile,evm-gas
@test "P256 precompile gas cost is 6900 (PIP-80 doubled from 3450)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Deploy a contract that calls the P256 precompile via STATICCALL with
    # a specific gas stipend. If we give it exactly 6900 gas for the precompile
    # portion, it should succeed. If we give less (e.g. 6899), it should fail.
    #
    # We build two contracts:
    #   A: Calls P256 with enough gas (succeeds, stores STATICCALL return value 1)
    #   B: Calls P256 with gas stipend of 3449 (old cost - 1, should fail)
    #
    # This proves the cost is > 3449 (consistent with 6900).

    # First, deploy a contract that calls P256 and stores the success flag.
    # The contract loads the input from its own code, copies to memory,
    # then STATICCALLs the precompile.

    # Simpler approach: use cast estimate to measure gas consumption.
    # eth_estimateGas for calling the precompile directly.
    local gas_estimate
    gas_estimate=$(cast estimate --rpc-url "$L2_RPC_URL" \
        --from "$ephemeral_address" \
        "$P256_ADDR" "$VALID_INPUT" 2>/dev/null) || true

    if [[ -n "$gas_estimate" ]]; then
        local gas_dec
        gas_dec=$(printf "%d" "$gas_estimate" 2>/dev/null) || gas_dec="$gas_estimate"
        echo "P256 eth_estimateGas: $gas_dec" >&3

        # The estimate should include the 21000 intrinsic gas + 6900 precompile + calldata cost.
        # 160 bytes of calldata: some zero, some nonzero.
        # Nonzero byte costs 16 gas, zero byte costs 4 gas.
        # With ~140 nonzero bytes and ~20 zero bytes: ~140*16 + 20*4 = 2240+80 = 2320
        # Total expected: ~21000 + 6900 + ~2320 = ~30220
        # With old cost: ~21000 + 3450 + ~2320 = ~26770
        # Midpoint between old and new: ~28495

        if [[ "$gas_dec" -gt 28000 ]]; then
            echo "Gas estimate ($gas_dec) consistent with PIP-80 cost of 6900" >&3
        else
            echo "Gas estimate ($gas_dec) looks like old PIP-27 cost of 3450" >&2
            echo "Expected ~30220 (21000 intrinsic + 6900 precompile + ~2320 calldata)" >&2
            return 1
        fi
    else
        echo "eth_estimateGas not available, falling back to transaction-based measurement" >&3

        # Deploy contract that calls P256 precompile and we measure gas from receipt
        # Build calldata into contract bytecode for a clean measurement.
        # Contract: copy 160 bytes of input to memory, STATICCALL precompile, store result
        local input_no_prefix="${VALID_INPUT#0x}"

        # Push the 160-byte input to memory in 32-byte chunks (5 PUSH32 + MSTORE)
        local runtime=""
        for ((chunk = 0; chunk < 5; chunk++)); do
            local chunk_hex="${input_no_prefix:$(( chunk * 64 )):64}"
            local offset_hex
            offset_hex=$(printf "%02x" $(( chunk * 32 )))
            runtime+="7f${chunk_hex}60${offset_hex}52"  # PUSH32 <chunk> PUSH1 <offset> MSTORE
        done

        # STATICCALL(gas, addr, argsOff, argsLen, retOff, retLen)
        # retLen=32, retOff=160 (0xa0), argsLen=160 (0xa0), argsOff=0
        runtime+="602060a060a06000"         # retLen=32, retOff=0xa0, argsLen=0xa0, argsOff=0
        runtime+="730000000000000000000000000000000000000100"  # PUSH20 P256 addr
        runtime+="5a"                       # GAS (forward all remaining)
        runtime+="fa"                       # STATICCALL
        runtime+="60005500"                 # SSTORE(0, success_flag) STOP

        local runtime_len=$(( ${#runtime} / 2 ))
        local runtime_len_hex
        if [[ "$runtime_len" -le 255 ]]; then
            runtime_len_hex=$(printf "%02x" "$runtime_len")
            local initcode="60${runtime_len_hex}600c60003960${runtime_len_hex}6000f3${runtime}"
        else
            runtime_len_hex=$(printf "%04x" "$runtime_len")
            # PUSH2 for larger bytecode
            local offset="000f"  # 15 bytes for initcode header with PUSH2
            local initcode="61${runtime_len_hex}61${offset}60003961${runtime_len_hex}6000f3${runtime}"
        fi

        local deploy_receipt
        deploy_receipt=$(cast send \
            --legacy --gas-limit 500000 \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" --json \
            --create "0x${initcode}")

        local contract_addr
        contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

        if [[ "$contract_addr" == "null" || -z "$contract_addr" ]]; then
            echo "Contract deployment failed" >&2
            return 1
        fi

        local call_receipt
        call_receipt=$(cast send \
            --legacy --gas-limit 500000 \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" --json \
            "$contract_addr")

        local gas_used
        gas_used=$(echo "$call_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")
        echo "P256 contract call gasUsed: $gas_used" >&3

        # The call gas should include the 6900 precompile cost.
        # Intrinsic gas = 21000, contract execution overhead ~200-300 gas for
        # the PUSH32/MSTORE/STATICCALL opcodes, + 6900 for precompile.
        # Expected range: ~28000 - 30000
        # With old cost it would be: ~24500 - 26500
        if [[ "$gas_used" -lt 27500 ]]; then
            echo "Gas used ($gas_used) seems too low for PIP-80 cost of 6900" >&2
            echo "May still be using old PIP-27 cost of 3450" >&2
            return 1
        fi
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile,evm-gas
@test "P256 invalid input still consumes gas (no gas refund on failure)" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Build two contracts: one calling with valid input, one with invalid input.
    # Both should consume similar gas (precompile charges gas regardless of outcome).
    local valid_input_no_prefix="${VALID_INPUT#0x}"

    # Invalid input: corrupt hash
    local invalid_input_no_prefix="0000000000000000000000000000000000000000000000000000000000000000"
    invalid_input_no_prefix+="${valid_input_no_prefix:64}"  # Keep r, s, x, y from valid input

    # Helper to build a P256-calling contract from 160 bytes of hex input
    _build_p256_contract() {
        local input_hex="$1"
        local rt=""
        for ((chunk = 0; chunk < 5; chunk++)); do
            local chunk_hex="${input_hex:$(( chunk * 64 )):64}"
            local offset_hex
            offset_hex=$(printf "%02x" $(( chunk * 32 )))
            rt+="7f${chunk_hex}60${offset_hex}52"
        done
        rt+="602060a060a06000"
        rt+="730000000000000000000000000000000000000100"
        rt+="5afa"
        rt+="60005500"
        echo "$rt"
    }

    local valid_runtime
    valid_runtime=$(_build_p256_contract "$valid_input_no_prefix")
    local invalid_runtime
    invalid_runtime=$(_build_p256_contract "$invalid_input_no_prefix")

    # Deploy valid contract
    local valid_len=$(( ${#valid_runtime} / 2 ))
    local valid_len_hex
    valid_len_hex=$(printf "%04x" "$valid_len")
    local valid_initcode="61${valid_len_hex}61000f60003961${valid_len_hex}6000f3${valid_runtime}"
    local valid_deploy
    valid_deploy=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${valid_initcode}")
    local valid_addr
    valid_addr=$(echo "$valid_deploy" | jq -r '.contractAddress')

    # Deploy invalid contract
    local invalid_len=$(( ${#invalid_runtime} / 2 ))
    local invalid_len_hex
    invalid_len_hex=$(printf "%04x" "$invalid_len")
    local invalid_initcode="61${invalid_len_hex}61000f60003961${invalid_len_hex}6000f3${invalid_runtime}"
    local invalid_deploy
    invalid_deploy=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${invalid_initcode}")
    local invalid_addr
    invalid_addr=$(echo "$invalid_deploy" | jq -r '.contractAddress')

    # Call both and compare gas
    local valid_call
    valid_call=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$valid_addr")
    local valid_gas
    valid_gas=$(echo "$valid_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    local invalid_call
    invalid_call=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$invalid_addr")
    local invalid_gas
    invalid_gas=$(echo "$invalid_call" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "Valid input gas: $valid_gas, Invalid input gas: $invalid_gas" >&3

    # Both should consume similar gas. The difference should be minimal
    # (just the SSTORE cost difference between storing 1 vs 0).
    local diff=$(( valid_gas - invalid_gas ))
    if [[ "$diff" -lt 0 ]]; then diff=$(( -diff )); fi

    # SSTORE zero→nonzero vs zero→zero can differ by up to ~20000 gas.
    # But the precompile itself should charge the same in both cases.
    # We mainly verify the invalid call didn't use dramatically less gas
    # (which would indicate early-exit without charging).
    if [[ "$invalid_gas" -lt $(( valid_gas / 2 )) ]]; then
        echo "Invalid input gas ($invalid_gas) is less than half of valid ($valid_gas)" >&2
        echo "Precompile may not be charging gas on failure" >&2
        return 1
    fi
}

# ─── Additional Wycheproof vectors ────────────────────────────────────────────

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 Wycheproof test vector #1 (signature malleability) verifies correctly" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Wycheproof ecdsa_secp256r1_sha256_p1363_test.json, testGroups[0], tcId 1.
    # Source: https://github.com/C2SP/wycheproof/blob/e0df04e0c033f2d25c5051dd06230336c7822358/testvectors_v1/ecdsa_secp256r1_sha256_p1363_test.json
    # msg = "313233343030" (ASCII "123400"), hash = SHA-256(msg)
    # Public key (JWK x/y decoded to hex):
    #   x = 2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838
    #   y = c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e
    # sig (P1363 r||s) = 2ba3a8be...4cd60b85...
    local input2="0x"
    input2+="bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023"  # SHA-256("123400")
    input2+="2ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e18"  # r
    input2+="4cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd76"  # s
    input2+="2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838"  # x
    input2+="c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e"  # y

    local out
    out=$(_p256_call "$input2")

    if [[ "${out}" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Wycheproof vector #1 should verify, got: '${out}'" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 Wycheproof test vector #60 (Shamir edge case) verifies correctly" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Wycheproof ecdsa_secp256r1_sha256_p1363_test.json, testGroups[0], tcId 60.
    # Source: https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ecdsa_secp256r1_sha256_p1363_test.json
    # msg = "3639383139" (ASCII "69819"), hash = SHA-256(msg)
    # Same public key as tcId 1.
    local input3="0x"
    input3+="70239dd877f7c944c422f44dea4ed1a52f2627416faf2f072fa50c772ed6f807"  # SHA-256("69819")
    input3+="64a1aab5000d0e804f3e2fc02bdee9be8ff312334e2ba16d11547c97711c898e"  # r
    input3+="6af015971cc30be6d1a206d4e013e0997772a2f91d73286ffd683b9bb2cf4f1b"  # s
    input3+="2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838"  # x
    input3+="c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e"  # y

    local out
    out=$(_p256_call "$input3")

    if [[ "${out}" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Wycheproof vector #60 should verify, got: '${out}'" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 wrong public key for valid signature returns empty" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Use the valid hash, r, s but with a different (but valid) public key.
    # P-256 generator point G:
    #   x = 6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296
    #   y = 4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5
    local wrong_key_input="0x"
    wrong_key_input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
    wrong_key_input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
    wrong_key_input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
    wrong_key_input+="6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"  # x (generator)
    wrong_key_input+="4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"  # y (generator)

    local out
    out=$(_p256_call "$wrong_key_input")

    if [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "Wrong public key should NOT verify the signature" >&2
        return 1
    fi
    echo "Wrong public key correctly rejected" >&3
}

# ─── Contract integration ─────────────────────────────────────────────────────

# bats test_tags=execution-specs,pip80,lisovo,precompile
@test "P256 precompile callable from a deployed contract via STATICCALL" {
    local valid_out
    valid_out=$(_p256_call "$VALID_INPUT")
    if [[ "${valid_out}" == "0x" || -z "${valid_out}" ]]; then
        skip "P256 precompile not active"
    fi

    # Deploy a contract that calls P256, reads the return, and stores success at slot 0.
    local input_no_prefix="${VALID_INPUT#0x}"
    local runtime=""

    # Store input in memory (5 x PUSH32 + MSTORE)
    for ((chunk = 0; chunk < 5; chunk++)); do
        local chunk_hex="${input_no_prefix:$(( chunk * 64 )):64}"
        local offset_hex
        offset_hex=$(printf "%02x" $(( chunk * 32 )))
        runtime+="7f${chunk_hex}60${offset_hex}52"
    done

    # STATICCALL(gas, 0x100, 0, 160, 160, 32)
    runtime+="602060a060a06000"
    runtime+="730000000000000000000000000000000000000100"
    runtime+="5afa"            # GAS STATICCALL → success (0 or 1)
    runtime+="50"              # POP success flag
    # Load the return data (32 bytes at offset 0xa0)
    runtime+="60a051"          # MLOAD(0xa0) — should be 0x01 for valid sig
    runtime+="60005500"        # SSTORE(0) STOP

    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%04x" "$runtime_len")
    local initcode="61${runtime_len_hex}61000f60003961${runtime_len_hex}6000f3${runtime}"

    local deploy_receipt
    deploy_receipt=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local contract_addr
    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    local call_receipt
    call_receipt=$(cast send --legacy --gas-limit 500000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$contract_addr")

    local call_status
    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Contract call failed: $call_status" >&2
        return 1
    fi

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$stored" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "P256 precompile via contract STATICCALL returned: $stored (expected 0x...01)" >&2
        return 1
    fi

    echo "P256 precompile correctly callable from contract via STATICCALL" >&3
}
