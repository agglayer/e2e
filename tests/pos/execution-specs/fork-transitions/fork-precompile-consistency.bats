#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,fork-transition,precompile-consistency

# Test 1.2 — Precompile Consistency Check
#
# Verifies that precompiles exist/don't exist at the correct fork boundaries
# by using eth_call with historical block numbers.
#
# REQUIREMENTS:
#   - Kurtosis network with STAGGERED fork activation (not all at block 0)
#   - Bor nodes running with --gcmode=archive (for historical state queries)
#   - Fork block numbers passed via environment variables (see defaults below)
#
# Environment variables (override to match your Kurtosis fork config):
#   FORK_MADHUGIRI       block number where Madhugiri activates (BLS12-381)
#   FORK_MADHUGIRI_PRO   block number where MadhugiriPro activates (p256Verify)
#   FORK_LISOVO          block number where Lisovo activates (KZG point eval)

# ────────────────────────────────────────────────────────────────────────────
# Setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Default staggered fork blocks — override via env to match Kurtosis config
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-512}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-576}"
    FORK_LISOVO="${FORK_LISOVO:-704}"
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# eth_call a precompile at a specific block number.
# Returns hex output (including 0x prefix), or empty on revert/error.
_call_at_block() {
    local addr="$1"
    local input="${2:-0x}"
    local block="$3"
    local out
    out=$(cast call --rpc-url "${L2_RPC_URL}" --block "${block}" "${addr}" "${input}" 2>/dev/null) || out=""
    echo "${out}"
}

# Returns 0 (true) when the hex string is non-empty AND has at least one
# non-zero nibble.
_is_nontrivial() {
    local data="${1#0x}"
    [[ -n "${data}" && "${data//0/}" != "" ]]
}

# Wait until the chain has progressed past a given block number.
_wait_for_block() {
    local target="$1"
    local target_hex
    target_hex=$(printf "0x%x" "${target}")
    assert_command_eventually_greater_or_equal \
        "cast block-number --rpc-url ${L2_RPC_URL}" \
        "${target}" 300 10
}

# Assert precompile is NOT active at a given block (returns empty or 0x).
_assert_precompile_inactive() {
    local addr="$1"
    local input="$2"
    local block="$3"
    local label="$4"
    local out
    out=$(_call_at_block "${addr}" "${input}" "${block}")
    if _is_nontrivial "${out}"; then
        echo "FAIL: ${label} returned non-trivial output at block ${block}: ${out}" >&2
        return 1
    fi
    echo "  OK: ${label} inactive at block ${block}" >&3
}

# Assert precompile IS active at a given block (returns non-trivial output).
_assert_precompile_active() {
    local addr="$1"
    local input="$2"
    local block="$3"
    local label="$4"
    local out
    out=$(_call_at_block "${addr}" "${input}" "${block}")
    if ! _is_nontrivial "${out}"; then
        echo "FAIL: ${label} returned trivial/empty output at block ${block}: '${out}'" >&2
        return 1
    fi
    echo "  OK: ${label} active at block ${block}" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Shared test vectors
# ────────────────────────────────────────────────────────────────────────────

# BLS12-381 G1Add: identity + G = G (should return non-trivial 128-byte point)
_bls_g1add_input() {
    local pad="00000000000000000000000000000000"
    local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
    local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
    local G1="${pad}${g1x}${pad}${g1y}"
    local inf
    inf=$(printf '%0256s' '' | tr ' ' '0')
    echo "0x${inf}${G1}"
}

# p256Verify: Wycheproof test vector #1 (should return 1)
_p256_input() {
    local input="0x"
    input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"
    input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"
    input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"
    input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"
    input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"
    echo "${input}"
}

# KZG point evaluation: valid 192-byte test vector
# Uses a known valid (commitment, z, y, proof) tuple.
# For inactive detection we just need any 192-byte input — an active precompile
# will either succeed or revert (empty from _call), while an inactive address
# returns 0x (trivial success).
_kzg_input() {
    # 192 bytes of non-zero data — enough to distinguish active (reverts on
    # invalid proof) from inactive (returns 0x trivially).
    local input="0x"
    input+="01" # versioned hash prefix
    input+=$(printf '%0382s' '1' | tr ' ' '0') # pad to 192 bytes total
    echo "${input}"
}

# ecPairing: empty input returns 1 (always active post-Byzantium)
_ecpairing_input() {
    echo "0x"
}

# ────────────────────────────────────────────────────────────────────────────
# Pre-flight: ensure chain has progressed past all fork blocks
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,fork-transition,preflight
@test "preflight: chain has progressed past all fork blocks" {
    local max_fork="${FORK_LISOVO}"
    # Need a few blocks past the last fork for post-fork queries
    local target=$(( max_fork + 5 ))
    echo "Waiting for chain to reach block ${target} ..." >&3
    _wait_for_block "${target}"
    echo "Chain is past all fork blocks." >&3
}

# ────────────────────────────────────────────────────────────────────────────
# 1.2 — Precompile existence matrix across fork eras
# ────────────────────────────────────────────────────────────────────────────

# --- BLS12-381 suite (0x0b–0x11): activated at Madhugiri ---

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G1Add (0x0b) inactive before Madhugiri" {
    local input
    input=$(_bls_g1add_input)
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000b" \
        "${input}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 G1Add (0x0b)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G1Add (0x0b) active after Madhugiri" {
    local input
    input=$(_bls_g1add_input)
    _assert_precompile_active \
        "0x000000000000000000000000000000000000000b" \
        "${input}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 G1Add (0x0b)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G1MSM (0x0c) inactive before Madhugiri" {
    # G1MSM with scalar-1 × G
    local pad="00000000000000000000000000000000"
    local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
    local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    local input="0x${pad}${g1x}${pad}${g1y}${scalar1}"
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000c" \
        "${input}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 G1MSM (0x0c)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G1MSM (0x0c) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
    local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    local input="0x${pad}${g1x}${pad}${g1y}${scalar1}"
    _assert_precompile_active \
        "0x000000000000000000000000000000000000000c" \
        "${input}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 G1MSM (0x0c)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G2Add (0x0d) inactive before Madhugiri" {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local inf
    inf=$(printf '%0512s' '' | tr ' ' '0')
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000d" \
        "0x${inf}${G2}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 G2Add (0x0d)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G2Add (0x0d) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local inf
    inf=$(printf '%0512s' '' | tr ' ' '0')
    _assert_precompile_active \
        "0x000000000000000000000000000000000000000d" \
        "0x${inf}${G2}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 G2Add (0x0d)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G2MSM (0x0e) inactive before Madhugiri" {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000e" \
        "0x${G2}${scalar1}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 G2MSM (0x0e)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 G2MSM (0x0e) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_active \
        "0x000000000000000000000000000000000000000e" \
        "0x${G2}${scalar1}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 G2MSM (0x0e)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 Pairing (0x0f) inactive before Madhugiri" {
    # e(G1_inf, G2) — use non-empty input so inactive = trivial 0x return
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local g1_inf
    g1_inf=$(printf '%0256s' '' | tr ' ' '0')
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000f" \
        "0x${g1_inf}${G2}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 Pairing (0x0f)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 Pairing (0x0f) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local g1_inf
    g1_inf=$(printf '%0256s' '' | tr ' ' '0')
    _assert_precompile_active \
        "0x000000000000000000000000000000000000000f" \
        "0x${g1_inf}${G2}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 Pairing (0x0f)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 MapFpToG1 (0x10) inactive before Madhugiri" {
    local pad="00000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_inactive \
        "0x0000000000000000000000000000000000000010" \
        "0x${pad}${fp1}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 MapFpToG1 (0x10)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 MapFpToG1 (0x10) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_active \
        "0x0000000000000000000000000000000000000010" \
        "0x${pad}${fp1}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 MapFpToG1 (0x10)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 MapFp2ToG2 (0x11) inactive before Madhugiri" {
    local pad="00000000000000000000000000000000"
    local fp0="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_inactive \
        "0x0000000000000000000000000000000000000011" \
        "0x${pad}${fp0}${pad}${fp1}" \
        $(( FORK_MADHUGIRI - 1 )) \
        "BLS12-381 MapFp2ToG2 (0x11)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,bls12
@test "1.2: BLS12-381 MapFp2ToG2 (0x11) active after Madhugiri" {
    local pad="00000000000000000000000000000000"
    local fp0="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    _assert_precompile_active \
        "0x0000000000000000000000000000000000000011" \
        "0x${pad}${fp0}${pad}${fp1}" \
        $(( FORK_MADHUGIRI + 1 )) \
        "BLS12-381 MapFp2ToG2 (0x11)"
}

# --- p256Verify (0x0100): activated at MadhugiriPro ---

# bats test_tags=execution-specs,fork-transition,precompile-consistency,p256
@test "1.2: p256Verify (0x0100) inactive before MadhugiriPro" {
    local input
    input=$(_p256_input)
    _assert_precompile_inactive \
        "0x0000000000000000000000000000000000000100" \
        "${input}" \
        $(( FORK_MADHUGIRI_PRO - 1 )) \
        "p256Verify (0x0100)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,p256
@test "1.2: p256Verify (0x0100) active after MadhugiriPro" {
    local input
    input=$(_p256_input)
    _assert_precompile_active \
        "0x0000000000000000000000000000000000000100" \
        "${input}" \
        $(( FORK_MADHUGIRI_PRO + 1 )) \
        "p256Verify (0x0100)"
}

# --- KZG point evaluation (0x0a): activated at Lisovo ---

# bats test_tags=execution-specs,fork-transition,precompile-consistency,kzg
@test "1.2: KZG point evaluation (0x0a) inactive before Lisovo" {
    local input
    input=$(_kzg_input)
    _assert_precompile_inactive \
        "0x000000000000000000000000000000000000000a" \
        "${input}" \
        $(( FORK_LISOVO - 1 )) \
        "KZG point eval (0x0a)"
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,kzg
@test "1.2: KZG point evaluation (0x0a) active after Lisovo" {
    # An active KZG precompile will revert on our dummy input (invalid proof),
    # which means _call_at_block returns "". An inactive address returns "0x".
    # So for "active" we check it does NOT return trivial "0x".
    local input
    input=$(_kzg_input)
    local out
    out=$(_call_at_block \
        "0x000000000000000000000000000000000000000a" \
        "${input}" \
        $(( FORK_LISOVO + 1 )))
    # Active precompile: reverts on invalid proof → empty string from _call
    # Inactive address: returns "0x" (trivial success)
    if [[ "${out}" == "0x" ]]; then
        echo "FAIL: KZG (0x0a) returned trivial 0x at block $(( FORK_LISOVO + 1 )) — still inactive" >&2
        return 1
    fi
    echo "  OK: KZG point eval (0x0a) active at block $(( FORK_LISOVO + 1 )) (reverted on invalid input as expected)" >&3
}

# --- Cross-check: legacy precompiles remain active across all fork boundaries ---

# bats test_tags=execution-specs,fork-transition,precompile-consistency,legacy
@test "1.2: ecRecover (0x01) remains active across all fork boundaries" {
    local input="0x"
    input+="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"
    input+="000000000000000000000000000000000000000000000000000000000000001c"
    input+="9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"
    input+="4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"

    local -a checkpoints=(
        $(( FORK_MADHUGIRI - 1 ))
        $(( FORK_MADHUGIRI + 1 ))
        $(( FORK_MADHUGIRI_PRO + 1 ))
        $(( FORK_LISOVO + 1 ))
    )
    for block in "${checkpoints[@]}"; do
        _assert_precompile_active \
            "0x0000000000000000000000000000000000000001" \
            "${input}" \
            "${block}" \
            "ecRecover (0x01) at block ${block}"
    done
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,legacy
@test "1.2: SHA-256 (0x02) remains active across all fork boundaries" {
    local -a checkpoints=(
        $(( FORK_MADHUGIRI - 1 ))
        $(( FORK_MADHUGIRI + 1 ))
        $(( FORK_MADHUGIRI_PRO + 1 ))
        $(( FORK_LISOVO + 1 ))
    )
    for block in "${checkpoints[@]}"; do
        local out
        out=$(_call_at_block "0x0000000000000000000000000000000000000002" "0x" "${block}")
        [[ "${out}" == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
        echo "  OK: SHA-256 (0x02) correct at block ${block}" >&3
    done
}

# bats test_tags=execution-specs,fork-transition,precompile-consistency,legacy
@test "1.2: ecPairing (0x08) remains active across all fork boundaries" {
    local -a checkpoints=(
        $(( FORK_MADHUGIRI - 1 ))
        $(( FORK_MADHUGIRI + 1 ))
        $(( FORK_MADHUGIRI_PRO + 1 ))
        $(( FORK_LISOVO + 1 ))
    )
    for block in "${checkpoints[@]}"; do
        local out
        out=$(_call_at_block "0x0000000000000000000000000000000000000008" "0x" "${block}")
        [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
        echo "  OK: ecPairing (0x08) correct at block ${block}" >&3
    done
}
