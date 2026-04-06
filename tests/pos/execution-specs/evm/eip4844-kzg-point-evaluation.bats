#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,eip4844,lisovo

# EIP-4844: KZG Point Evaluation Precompile (0x0a)
#
# Verifies a KZG proof that a polynomial (represented by a blob commitment)
# evaluates to a given value at a given point.
#
# Precompile address: 0x000000000000000000000000000000000000000a
# Input (192 bytes):  versioned_hash(32) || z(32) || y(32) || commitment(48) || proof(48)
# Output (64 bytes):  FIELD_ELEMENTS_PER_BLOB(32) || BLS_MODULUS(32)
# Gas cost:           50,000
#
# The precompile returns a fixed 64-byte value on success:
#   0x0000...1000  (FIELD_ELEMENTS_PER_BLOB = 4096)
#   73eda753...01  (BLS_MODULUS)
#
# Activated with the Cancun hardfork (Lisovo on Polygon PoS).
#
# Test vectors sourced from:
#   - Bor: core/vm/testdata/precompiles/pointEvaluation.json
#   - ethereum/c-kzg-4844: tests/verify_kzg_proof/kzg-mainnet/

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Fork schedule — needed to pin calls within the KZG-active window.
    _setup_fork_env

    # KZG precompile address
    KZG_ADDR="0x000000000000000000000000000000000000000a"

    # Fixed return value on success: FIELD_ELEMENTS_PER_BLOB || BLS_MODULUS
    KZG_SUCCESS="0x000000000000000000000000000000000000000000000000000000000000100073eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"

    # Block at which KZG is known to be active (midpoint of Lisovo→LisovoPro).
    # When LisovoPro has already passed, querying "latest" would see KZG as
    # removed, so all tests pin to this block instead.
    if [[ "${FORK_LISOVO:-999999999}" -lt 999999999 && "${FORK_LISOVO_PRO:-999999999}" -lt 999999999 && "${FORK_LISOVO_PRO}" -gt "${FORK_LISOVO}" ]]; then
        KZG_ACTIVE_BLOCK=$(( (FORK_LISOVO + FORK_LISOVO_PRO) / 2 ))
    elif [[ "${FORK_LISOVO:-999999999}" -lt 999999999 ]]; then
        KZG_ACTIVE_BLOCK="${FORK_LISOVO}"
    else
        KZG_ACTIVE_BLOCK=""
    fi
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Call KZG precompile via eth_call, return output (empty string on revert).
# Pins to KZG_ACTIVE_BLOCK when available so the call lands within the
# Lisovo→LisovoPro window where KZG is active (it is removed at LisovoPro).
_kzg_call() {
    local input="${1:-0x}"
    local block_flag=()
    if [[ -n "${KZG_ACTIVE_BLOCK:-}" ]]; then
        block_flag=(--block "${KZG_ACTIVE_BLOCK}")
    fi
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" "${block_flag[@]}" "${KZG_ADDR}" "${input}" 2>/dev/null) || out=""
    echo "${out}"
}

# Compute versioned hash from a 48-byte KZG commitment (hex, no 0x prefix).
# versioned_hash = 0x01 || SHA256(commitment)[1:]
_versioned_hash() {
    local commitment_hex="$1"
    local hash
    hash=$(printf '%s' "$commitment_hex" | xxd -r -p | openssl dgst -sha256 -binary | xxd -p | tr -d '\n')
    echo "01${hash:2}"
}

# Build the 192-byte precompile input from individual components.
# Args: commitment(96 hex) z(64 hex) y(64 hex) proof(96 hex) — all without 0x prefix
_build_kzg_input() {
    local commitment="$1"
    local z="$2"
    local y="$3"
    local proof="$4"
    local vh
    vh=$(_versioned_hash "$commitment")
    echo "0x${vh}${z}${y}${commitment}${proof}"
}

# Skip if KZG precompile is not active on this chain.
# Waits for the KZG-active block before probing so the chain has reached it.
_require_kzg_active() {
    if [[ -z "${KZG_ACTIVE_BLOCK:-}" ]]; then
        skip "Lisovo fork not active (KZG precompile never enabled)"
    fi
    _wait_for_block_on "${KZG_ACTIVE_BLOCK}" "$L2_RPC_URL" "L2_RPC"
    local out
    out=$(_kzg_call "$BOR_VECTOR_INPUT")
    if [[ "${out}" != "${KZG_SUCCESS}" ]]; then
        skip "KZG precompile not active at ${KZG_ADDR} block ${KZG_ACTIVE_BLOCK} (pre-Cancun/Lisovo chain)"
    fi
}

# ─── Test vectors ────────────────────────────────────────────────────────────
#
# Pre-built input from Bor's pointEvaluation.json (already includes versioned hash).
BOR_VECTOR_INPUT="0x01e798154708fe7789429634053cbf9f99b619f9f084048927333fce637f549b564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d3630624d25032e67a7e6a4910df5834b8fe70e6bcfeeac0352434196bdf4b2485d5a18f59a8d2a1a625a17f3fea0fe5eb8c896db3764f3185481bc22f91b4aaffcca25f26936857bc3a7c2539ea8ec3a952b7873033e038326e87ed3e1276fd140253fa08e9fc25fb2d9a98527fc22a2c9612fbeafdad446cbc7bcdbdcd780af2c16a"

# ─── Feature probe ───────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG point evaluation precompile is active at 0x0a" {
    if [[ -z "${KZG_ACTIVE_BLOCK:-}" ]]; then
        skip "Lisovo fork not active (KZG precompile never enabled)"
    fi
    _wait_for_block_on "${KZG_ACTIVE_BLOCK}" "$L2_RPC_URL" "L2_RPC"

    local out
    out=$(_kzg_call "$BOR_VECTOR_INPUT")
    echo "KZG output (block ${KZG_ACTIVE_BLOCK}): ${out}" >&3

    if [[ -z "${out}" || "${out}" == "0x" ]]; then
        skip "KZG precompile not active at ${KZG_ADDR}"
    fi

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# ─── Bor test vector ────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG Bor vector: valid proof returns FIELD_ELEMENTS_PER_BLOB || BLS_MODULUS" {
    _require_kzg_active

    local out
    out=$(_kzg_call "$BOR_VECTOR_INPUT")

    if [[ "${out}" != "${KZG_SUCCESS}" ]]; then
        echo "Expected KZG success value, got: '${out}'" >&2
        return 1
    fi
}

# ─── c-kzg-4844 consensus spec test vectors (valid proofs) ──────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector correct_proof_0_0: zero polynomial at origin" {
    _require_kzg_active

    # Commitment to the zero polynomial (G1 point at infinity).
    # f(0) = 0, proof = point at infinity.
    local input
    input=$(_build_kzg_input \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

    local out
    out=$(_kzg_call "$input")
    echo "correct_proof_0_0 output: ${out}" >&3

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector correct_proof_1_0: constant polynomial (twos) at origin" {
    _require_kzg_active

    # Commitment to polynomial p(x)=2 for all x.
    # f(0) = 2, proof = point at infinity (constant poly has zero quotient).
    local input
    input=$(_build_kzg_input \
        "a572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000002" \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

    local out
    out=$(_kzg_call "$input")
    echo "correct_proof_1_0 output: ${out}" >&3

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector correct_proof_2_0: non-trivial polynomial at origin" {
    _require_kzg_active

    local input
    input=$(_build_kzg_input \
        "a421e229565952cfff4ef3517100a97da1d4fe57956fa50a442f92af03b1bf37adacc8ad4ed209b31287ea5bb94d9d06" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "50625ad853cc21ba40594f79591e5d35c445ecf9453014da6524c0cf6367c359" \
        "b72d80393dc39beea3857cb3719277138876b2b207f1d5e54dd62a14e3242d123b5a6db066181ff01a51c26c9d2f400b")

    local out
    out=$(_kzg_call "$input")
    echo "correct_proof_2_0 output: ${out}" >&3

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector correct_proof_3_0: non-trivial polynomial at origin (alt)" {
    _require_kzg_active

    local input
    input=$(_build_kzg_input \
        "b49d88afcd7f6c61a8ea69eff5f609d2432b47e7e4cd50b02cdddb4e0c1460517e8df02e4e64dc55e3d8ca192d57193a" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "1ed7d14d1b3fb1a1890d67b81715531553ad798df2009b4311d9fe2bea6cb964" \
        "a71f21ca51b443ad35bb8a26d274223a690d88d9629927dc80b0856093e08a372820248df5b8a43b6d98fd52a62fa376")

    local out
    out=$(_kzg_call "$input")
    echo "correct_proof_3_0 output: ${out}" >&3

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector correct_proof_4_0: Bor's commitment polynomial at origin" {
    _require_kzg_active

    # Uses the same commitment as the Bor test vector but evaluated at z=0.
    local input
    input=$(_build_kzg_input \
        "8f59a8d2a1a625a17f3fea0fe5eb8c896db3764f3185481bc22f91b4aaffcca25f26936857bc3a7c2539ea8ec3a952b7" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "61157104410181bdc6eac224aa9436ac268bdcfeecb6badf71d228adda820af3" \
        "809adfa8b078b0921cdb8696ca017a0cc2d5337109016f36a766886eade28d32f205311ff5def247c3ddba91896fae97")

    local out
    out=$(_kzg_call "$input")
    echo "correct_proof_4_0 output: ${out}" >&3

    [[ "${out}" == "${KZG_SUCCESS}" ]]
}

# ─── Invalid input: wrong length ─────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects empty input (0 bytes)" {
    _require_kzg_active

    local out
    out=$(_kzg_call "0x")
    echo "Empty input output: '${out}'" >&3

    # Active precompile must revert on invalid-length input
    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects truncated input (32 bytes — only versioned hash)" {
    _require_kzg_active

    # Send just the versioned hash (32 bytes), missing z, y, commitment, proof
    local out
    out=$(_kzg_call "0x01e798154708fe7789429634053cbf9f99b619f9f084048927333fce637f549b")
    echo "32-byte input output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects truncated input (96 bytes — missing commitment and proof)" {
    _require_kzg_active

    # versioned_hash(32) + z(32) + y(32) = 96 bytes, but 192 required
    local partial="0x"
    partial+="01e798154708fe7789429634053cbf9f99b619f9f084048927333fce637f549b"  # versioned_hash
    partial+="564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306"  # z
    partial+="24d25032e67a7e6a4910df5834b8fe70e6bcfeeac0352434196bdf4b2485d5a1"  # y

    local out
    out=$(_kzg_call "$partial")
    echo "96-byte input output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects oversized input (193 bytes — one extra byte)" {
    _require_kzg_active

    # Append one extra byte to the valid input
    local oversized="${BOR_VECTOR_INPUT}00"

    local out
    out=$(_kzg_call "$oversized")
    echo "193-byte input output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects undersized input (191 bytes — one byte short)" {
    _require_kzg_active

    # Remove the last byte (2 hex chars) from the valid input
    local undersized="${BOR_VECTOR_INPUT:0:$(( ${#BOR_VECTOR_INPUT} - 2 ))}"

    local out
    out=$(_kzg_call "$undersized")
    echo "191-byte input output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# ─── Invalid input: wrong versioned hash ─────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects mismatched versioned hash (corrupted first byte)" {
    _require_kzg_active

    # Change the version byte from 0x01 to 0x02
    local bad_input="0x02${BOR_VECTOR_INPUT:4}"

    local out
    out=$(_kzg_call "$bad_input")
    echo "Bad version byte output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects mismatched versioned hash (all zeros)" {
    _require_kzg_active

    # Replace versioned_hash with 32 zero bytes, keep z, y, commitment, proof from Bor vector
    local bad_input="0x"
    bad_input+="0000000000000000000000000000000000000000000000000000000000000000"  # zeroed versioned_hash
    bad_input+="${BOR_VECTOR_INPUT:66}"  # z + y + commitment + proof

    local out
    out=$(_kzg_call "$bad_input")
    echo "Zero versioned hash output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects versioned hash from different commitment" {
    _require_kzg_active

    # Use the versioned hash from the zero-polynomial commitment (correct_proof_0_0)
    # but pair it with the Bor vector's z, y, commitment, proof.
    local wrong_vh
    wrong_vh=$(_versioned_hash "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

    local bad_input="0x"
    bad_input+="${wrong_vh}"
    bad_input+="${BOR_VECTOR_INPUT:66}"  # z + y + commitment + proof from Bor vector

    local out
    out=$(_kzg_call "$bad_input")
    echo "Wrong commitment versioned hash output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# ─── Invalid input: incorrect proof ──────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG c-kzg vector incorrect_proof_0_0: wrong proof for zero polynomial" {
    _require_kzg_active

    # Correct commitment/z/y for zero polynomial, but proof = G1 generator (wrong).
    # From c-kzg-4844: verify_kzg_proof_case_incorrect_proof_0_0 → output: false
    local input
    input=$(_build_kzg_input \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb")

    local out
    out=$(_kzg_call "$input")
    echo "incorrect_proof_0_0 output: '${out}'" >&3

    # Incorrect proof must cause the precompile to revert
    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects corrupted proof (bit-flip in Bor vector proof)" {
    _require_kzg_active

    # Take the Bor vector but flip a byte in the proof field.
    # Proof starts at byte offset 128 (hex offset 256 + 2 for "0x" prefix = char 258).
    # Original proof starts with 87..., change to 97...
    local input_hex="${BOR_VECTOR_INPUT}"
    # proof starts at position: 2(0x) + 64(vh) + 64(z) + 64(y) + 96(commitment) = 290
    local before="${input_hex:0:290}"
    local after="${input_hex:292}"
    local bad_byte="97"  # original is "87"
    local bad_input="${before}${bad_byte}${after}"

    local out
    out=$(_kzg_call "$bad_input")
    echo "Corrupted proof output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# ─── Invalid input: wrong claim value ────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects wrong y value (claim mismatch)" {
    _require_kzg_active

    # Use the Bor vector but change y (the claimed evaluation result).
    # y is at bytes 64-95 → hex chars 130-193 (after "0x" prefix).
    # Original y starts with 24d250..., replace with zeros.
    local bad_input="0x"
    bad_input+="${BOR_VECTOR_INPUT:2:128}"   # versioned_hash + z (64 bytes = 128 hex)
    bad_input+="0000000000000000000000000000000000000000000000000000000000000000"  # y = 0
    bad_input+="${BOR_VECTOR_INPUT:194}"     # commitment + proof

    local out
    out=$(_kzg_call "$bad_input")
    echo "Wrong y value output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects wrong z value (evaluation point mismatch)" {
    _require_kzg_active

    # Use the Bor vector but change z (evaluation point).
    # z is at bytes 32-63 → hex chars 66-129 (after "0x" prefix).
    local bad_input="0x"
    bad_input+="${BOR_VECTOR_INPUT:2:64}"    # versioned_hash (32 bytes = 64 hex)
    bad_input+="0000000000000000000000000000000000000000000000000000000000000001"  # z = 1 (was different)
    bad_input+="${BOR_VECTOR_INPUT:130}"     # y + commitment + proof

    local out
    out=$(_kzg_call "$bad_input")
    echo "Wrong z value output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# ─── All zeros input ─────────────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG rejects 192 bytes of all zeros" {
    _require_kzg_active

    # 192 bytes of zeros — version byte is 0x00 (invalid, must be 0x01)
    local zeros="0x"
    for ((i = 0; i < 6; i++)); do
        zeros+="0000000000000000000000000000000000000000000000000000000000000000"
    done

    local out
    out=$(_kzg_call "$zeros")
    echo "All-zero input output: '${out}'" >&3

    [[ -z "${out}" ]]
}

# ─── Gas cost verification ───────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile,evm-gas
@test "KZG precompile gas cost is 50000 (EIP-4844)" {
    _require_kzg_active

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local ephemeral_pk
    ephemeral_pk=$(echo "$wallet_json" | jq -r '.private_key')
    local ephemeral_addr
    ephemeral_addr=$(echo "$wallet_json" | jq -r '.address')

    local _ferr
    if ! _ferr=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value 1ether "$ephemeral_addr" 2>&1 >/dev/null); then
        case "$_ferr" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                skip "Chain stalled — cannot fund ephemeral wallet";;
            *) echo "Fund failed: $_ferr" >&2; return 1;;
        esac
    fi

    local gas_estimate
    gas_estimate=$(cast estimate --rpc-url "$L2_RPC_URL" \
        --block "${KZG_ACTIVE_BLOCK}" \
        --from "$ephemeral_addr" \
        "$KZG_ADDR" "$BOR_VECTOR_INPUT" 2>/dev/null) || true

    if [[ -z "$gas_estimate" ]]; then
        skip "eth_estimateGas not available for precompile calls"
    fi

    local gas_dec
    gas_dec=$(printf "%d" "$gas_estimate" 2>/dev/null) || gas_dec="$gas_estimate"
    echo "KZG eth_estimateGas: $gas_dec" >&3

    # Expected: 21000 (intrinsic) + 50000 (precompile) + calldata cost.
    # 192 bytes of calldata: mix of zero and nonzero bytes.
    # Approx calldata cost: ~2500 gas (varies by content).
    # Total expected: ~73500
    # If the precompile cost were drastically wrong, estimate would be very different.
    # We check that gas > 70000 (proves precompile charges significant gas).
    if [[ "$gas_dec" -lt 70000 ]]; then
        echo "Gas estimate ($gas_dec) unexpectedly low — precompile may not be charging 50000" >&2
        return 1
    fi

    # Upper bound sanity check (should not exceed 80000 for a simple precompile call).
    if [[ "$gas_dec" -gt 80000 ]]; then
        echo "Gas estimate ($gas_dec) unexpectedly high" >&2
        return 1
    fi

    echo "Gas estimate ($gas_dec) consistent with 50000 precompile cost" >&3
}

# ─── Contract integration ───────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG precompile callable from a deployed contract via STATICCALL" {
    _require_kzg_active

    # This test sends real transactions; they execute at the current tip.
    # If LisovoPro has already passed, KZG is removed at latest and the
    # STATICCALL inside the contract will fail. Skip in that case.
    if [[ -n "${KZG_ACTIVE_BLOCK:-}" && "${FORK_LISOVO_PRO:-999999999}" -lt 999999999 ]]; then
        local current_block
        current_block=$(_block_number_on "$L2_RPC_URL" 2>/dev/null) || current_block=0
        if [[ "$current_block" -ge "${FORK_LISOVO_PRO}" ]]; then
            skip "KZG removed at LisovoPro (block ${FORK_LISOVO_PRO}) — cannot test via live transaction at tip ${current_block}"
        fi
    fi

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local ephemeral_pk
    ephemeral_pk=$(echo "$wallet_json" | jq -r '.private_key')
    local ephemeral_addr
    ephemeral_addr=$(echo "$wallet_json" | jq -r '.address')

    local _ferr2
    if ! _ferr2=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value 1ether "$ephemeral_addr" 2>&1 >/dev/null); then
        case "$_ferr2" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                skip "Chain stalled — cannot fund ephemeral wallet";;
            *) echo "Fund failed: $_ferr2" >&2; return 1;;
        esac
    fi

    # Deploy a contract that:
    #   1. Copies the 192-byte input to memory via PUSH32+MSTORE (6 x 32-byte chunks)
    #   2. STATICCALLs the KZG precompile at 0x0a
    #   3. Stores the STATICCALL success flag at storage slot 0
    #   4. Loads the first 32 bytes of return data and stores at slot 1
    local input_no_prefix="${BOR_VECTOR_INPUT#0x}"
    local runtime=""

    # Store 192 bytes of input in memory (6 x 32-byte chunks)
    for ((chunk = 0; chunk < 6; chunk++)); do
        local chunk_hex="${input_no_prefix:$(( chunk * 64 )):64}"
        local offset_hex
        offset_hex=$(printf "%02x" $(( chunk * 32 )))
        runtime+="7f${chunk_hex}60${offset_hex}52"  # PUSH32 <chunk> PUSH1 <offset> MSTORE
    done

    # STATICCALL(gas, 0x0a, 0, 192, 192, 64)
    # retLen=64 (0x40), retOff=192 (0xc0), argsLen=192 (0xc0), argsOff=0
    runtime+="604060c060c06000"                                     # retLen, retOff, argsLen, argsOff
    runtime+="73000000000000000000000000000000000000000a"            # PUSH20 KZG addr
    runtime+="5a"                                                   # GAS
    runtime+="fa"                                                   # STATICCALL
    runtime+="60005500"                                             # SSTORE(0, success_flag) — slot 0
    # Load first 32 bytes of return data from memory offset 0xc0
    runtime+="60c051"                                               # MLOAD(0xc0)
    runtime+="60015500"                                             # SSTORE(1, return_word_0) — slot 1

    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%04x" "$runtime_len")
    local initcode="61${runtime_len_hex}61000f60003961${runtime_len_hex}6000f3${runtime}"

    local deploy_receipt
    deploy_receipt=$(cast send --legacy --gas-limit 1000000 \
        --private-key "$ephemeral_pk" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local contract_addr
    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    if [[ "$contract_addr" == "null" || -z "$contract_addr" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    local call_receipt
    call_receipt=$(cast send --legacy --gas-limit 1000000 \
        --private-key "$ephemeral_pk" --rpc-url "$L2_RPC_URL" --json \
        "$contract_addr")

    local call_status
    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Contract call failed: $call_status" >&2
        return 1
    fi

    # Slot 0: STATICCALL success flag (should be 1)
    local success_flag
    success_flag=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    if [[ "$success_flag" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "STATICCALL to KZG precompile failed (success=$success_flag)" >&2
        return 1
    fi

    # Slot 1: first 32 bytes of return data (FIELD_ELEMENTS_PER_BLOB = 4096 = 0x1000)
    local return_word
    return_word=$(cast storage "$contract_addr" 1 --rpc-url "$L2_RPC_URL")
    if [[ "$return_word" != "0x0000000000000000000000000000000000000000000000000000000000001000" ]]; then
        echo "KZG return word 0 = $return_word (expected 0x...1000)" >&2
        return 1
    fi

    echo "KZG precompile correctly callable from contract via STATICCALL" >&3
}

# ─── Return value consistency ────────────────────────────────────────────────

# bats test_tags=execution-specs,eip4844,lisovo,precompile
@test "KZG return value is identical across different valid proofs" {
    _require_kzg_active

    # All valid KZG proofs must return the same fixed 64-byte value.
    # Compare the Bor vector result with the zero-polynomial vector result.
    local out_bor
    out_bor=$(_kzg_call "$BOR_VECTOR_INPUT")

    local input_zero
    input_zero=$(_build_kzg_input \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
    local out_zero
    out_zero=$(_kzg_call "$input_zero")

    echo "Bor vector output:  ${out_bor}" >&3
    echo "Zero poly output:   ${out_zero}" >&3

    if [[ "${out_bor}" != "${out_zero}" ]]; then
        echo "Return values differ: bor='${out_bor}' vs zero='${out_zero}'" >&2
        return 1
    fi

    [[ "${out_bor}" == "${KZG_SUCCESS}" ]]
}
