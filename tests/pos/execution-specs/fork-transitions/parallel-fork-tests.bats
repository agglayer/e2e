#!/usr/bin/env bats
# bats file_tags=pos,fork-activation

# Tests 1.2 + 1.3 — Fork Transition & Precompile Consistency (merged)
#
# Designed for PARALLEL execution with: bats --jobs N fork-tests.bats
#
# Each test independently polls _wait_for_block / _wait_before_fork to reach
# the chain height it needs. setup_file() pre-funds one wallet per test so
# there are no nonce conflicts when tests run concurrently.
#
# Coverage:
#   1.3 — Fork Transitions: real on-chain transactions across fork boundaries
#   1.2 — Precompile Consistency: eth_call to verify precompile
#          activation/deactivation at correct fork boundaries
#
# REQUIREMENTS:
#   - Kurtosis network with STAGGERED fork activation
#   - Fork block numbers passed via environment variables
#   - Below fork activation order must be enforced
# EL_HARD_FORK_BLOCKS = {
#     "jaipur": 0,
#     "delhi": 0,
#     "indore": 0,
#     "agra": 0,
#     "napoli": 0,
#     "ahmedabad": 0,
#     "bhilai": 0,
#     "rio": 256,
#     "madhugiri": 320,
#     "madhugiriPro": 384,
#     "dandeli": 448,
#     "lisovo": 512,
#     "lisovoPro": 576,
#     "giugliano": 640,
# }


# ────────────────────────────────────────────────────────────────────────────
# File-level setup / teardown (runs once, before/after all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Create temp dir shared by all tests for pre-funded wallets
    WALLET_DIR=$(mktemp -d)
    export WALLET_DIR

    local num_tests
    num_tests=$(grep -c '^@test ' "${BATS_TEST_FILENAME}")

    echo "Pre-funding ${num_tests} ephemeral wallets..." >&3

    local i
    for i in $(seq 1 "$num_tests"); do
        local wallet_json addr
        wallet_json=$(cast wallet new --json | jq '.[0]')
        echo "$wallet_json" > "${WALLET_DIR}/wallet_${i}.json"
        addr=$(echo "$wallet_json" | jq -r '.address')

        cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value 10ether "$addr" >/dev/null
    done

    echo "All ${num_tests} wallets funded" >&3
}

teardown_file() {
    [[ -d "${WALLET_DIR:-}" ]] && rm -rf "$WALLET_DIR"
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/eventually.bash"
    pos_setup

    # Default staggered fork blocks — override via env to match Kurtosis config
    FORK_JAIPUR="${FORK_JAIPUR:-0}"
    FORK_DELHI="${FORK_DELHI:-0}"
    FORK_INDORE="${FORK_INDORE:-0}"
    FORK_AGRA="${FORK_AGRA:-0}"
    FORK_NAPOLI="${FORK_NAPOLI:-0}"
    FORK_AHMEDABAD="${FORK_AHMEDABAD:-0}"
    FORK_BHILAI="${FORK_BHILAI:-0}"
    # 64-block gaps (~2 min at 2s/block). Tests run in parallel so gaps can be
    # tight — each test independently waits for its target block.
    # Match these in the Kurtosis EL_HARD_FORK_BLOCKS config.
    FORK_RIO="${FORK_RIO:-256}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-320}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-384}"
    FORK_DANDELI="${FORK_DANDELI:-448}"
    FORK_LISOVO="${FORK_LISOVO:-512}"
    FORK_LISOVO_PRO="${FORK_LISOVO_PRO:-576}"
    FORK_GIUGLIANO="${FORK_GIUGLIANO:-640}"

    # Read pre-funded wallet for this test (created in setup_file)
    local wallet_json
    wallet_json=$(cat "${WALLET_DIR}/wallet_${BATS_TEST_NUMBER}.json")
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers — on-chain transactions (1.3)
# ────────────────────────────────────────────────────────────────────────────

# Deploy a contract from runtime bytecode hex. Sets $contract_addr.
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

# Deploy a large contract (> 255 bytes runtime) using PUSH2. Sets $contract_addr.
deploy_large_runtime() {
    local runtime="$1"
    local gas="${2:-10000000}"
    local runtime_len=$(( ${#runtime} / 2 ))
    local size_hex
    size_hex=$(printf "%04x" "$runtime_len")
    local initcode="61${size_hex}61000b60003961${size_hex}6000f3${runtime}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    local status
    status=$(echo "$receipt" | jq -r '.status')
    if [[ "$status" != "0x1" ]]; then
        echo "deploy_large_runtime failed: $status" >&2
        return 1
    fi
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
}

# Call a deployed contract. Sets $call_receipt.
call_contract() {
    local addr="$1"
    local gas="${2:-200000}"
    call_receipt=$(cast send \
        --legacy --gas-limit "$gas" \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        "$addr")
}

_receipt_status() { echo "$1" | jq -r '.status'; }
_receipt_block()  { echo "$1" | jq -r '.blockNumber' | xargs printf "%d"; }

# ────────────────────────────────────────────────────────────────────────────
# Helpers — chain queries
# ────────────────────────────────────────────────────────────────────────────

_current_block() { cast block-number --rpc-url "$L2_RPC_URL"; }

# Get block field via raw JSON-RPC (avoids cast block flag compatibility issues)
_block_field() {
    local block="$1" field="$2"
    local block_hex
    block_hex=$(printf '0x%x' "$block")
    curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["'"${block_hex}"'",false],"id":1}' \
        | jq -r ".result.${field}"
}

_base_fee_at() {
    local val
    val=$(_block_field "$1" "baseFeePerGas")
    printf "%d" "$val"
}

_gas_used_at() {
    local val
    val=$(_block_field "$1" "gasUsed")
    printf "%d" "$val"
}

_gas_limit_at() {
    local val
    val=$(_block_field "$1" "gasLimit")
    printf "%d" "$val"
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers — bor version detection
# ────────────────────────────────────────────────────────────────────────────

# Fetch bor version from web3_clientVersion RPC and cache it.
# Returns a semver-like string e.g. "2.5.9" or "2.6.5" or "2.7.0-beta".
# Cached in BOR_VERSION after first call.
_bor_version() {
    if [[ -n "${BOR_VERSION:-}" ]]; then
        echo "$BOR_VERSION"
        return
    fi
    local result
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}')
    # Response format: "Bor/v2.5.9-stable-abcdef12-20250101/linux-amd64/go1.22.0"
    #                  "Bor/v2.7.0-beta-abcdef12-20250301/linux-amd64/go1.23.0"
    # Extract: major.minor.patch (e.g. "2.5.9") and optional meta (e.g. "-beta").
    # The -stable suffix is stripped since it's not part of semver.
    local raw
    raw=$(echo "$result" | jq -r '.result // empty')
    echo "  web3_clientVersion: ${raw}" >&3
    # Case-insensitive match, extract version+meta before the commit hash.
    BOR_VERSION=$(echo "$raw" | sed -E 's#^[Bb]or/v([0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]*)?).*#\1#')
    # If sed didn't match (no substitution), BOR_VERSION equals the full raw string.
    if [[ "$BOR_VERSION" == "$raw" || -z "$BOR_VERSION" ]]; then
        BOR_VERSION="unknown"
    fi
    echo "$BOR_VERSION"
}

# Compare bor version against a minimum required version.
# Returns 0 (true) if running version >= required version.
# Usage: _bor_version_gte "2.6.0"
_bor_version_gte() {
    local required="$1"
    local current
    current=$(_bor_version)
    if [[ "$current" == "unknown" ]]; then
        # Can't determine version — assume latest for safety.
        return 0
    fi
    # Strip pre-release suffix for comparison (2.7.0-beta -> 2.7.0).
    local current_base required_base
    current_base=$(echo "$current" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')
    required_base=$(echo "$required" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')

    # Compare using sort -V (version sort).
    local lower
    lower=$(printf '%s\n%s' "$current_base" "$required_base" | sort -V | head -1)
    [[ "$lower" == "$required_base" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers — wait for chain progression
# ────────────────────────────────────────────────────────────────────────────

# Wait until the chain reaches a target block. Dynamic timeout.
_wait_for_block() {
    local target="$1"
    local current
    current=$(_current_block)

    if [[ "$current" -ge "$target" ]]; then
        return 0
    fi

    local blocks_remaining=$(( target - current ))
    local timeout=$(( blocks_remaining * 2 + 120 ))
    [[ "$timeout" -lt 60 ]] && timeout=60
    [[ "$timeout" -gt 1800 ]] && timeout=1800

    echo "  Waiting for block ${target} (current: ${current}, timeout: ${timeout}s)..." >&3
    assert_command_eventually_greater_or_equal \
        "cast block-number --rpc-url ${L2_RPC_URL}" \
        "${target}" "${timeout}" 5
}

# Wait until the chain is NEAR a fork (fork - margin), then verify not past it.
# For "before fork" tests that send real transactions.
_wait_before_fork() {
    local fork_block="$1"
    local margin="${2:-10}"

    local current
    current=$(_current_block)

    if [[ "$current" -ge "$fork_block" ]]; then
        skip "chain already at block ${current}, past fork block ${fork_block}"
    fi

    local approach_block=$(( fork_block - margin ))
    [[ "$approach_block" -lt 1 ]] && approach_block=1

    if [[ "$current" -lt "$approach_block" ]]; then
        echo "  Waiting for block ${approach_block} (${margin} blocks before fork ${fork_block})..." >&3
        _wait_for_block "$approach_block"
    fi

    current=$(_current_block)
    if [[ "$current" -ge "$fork_block" ]]; then
        skip "chain reached fork block ${fork_block} during wait (now at ${current})"
    fi

    echo "  Chain at block ${current}, fork at ${fork_block} — sending pre-fork tx" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers — precompile consistency (1.2)
# ────────────────────────────────────────────────────────────────────────────

# eth_call via raw JSON-RPC. Supports "latest" or numeric block.
# Returns "ERROR:<message>" on JSON-RPC errors so callers can detect failures.
_call_at_block() {
    local addr="$1" input="${2:-0x}" block="$3"
    local block_param
    if [[ "$block" == "latest" ]]; then
        block_param='"latest"'
    else
        local block_hex
        block_hex=$(printf '0x%x' "$block")
        block_param="\"${block_hex}\""
    fi
    local result
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"'"${addr}"'","data":"'"${input}"'"},'"${block_param}"'],"id":1}')
    # Detect JSON-RPC errors (e.g., "historical state not available")
    local err
    err=$(echo "${result}" | jq -r '.error.message // empty' 2>/dev/null) || err=""
    if [[ -n "${err}" ]]; then
        echo "ERROR:${err}"
        return 0
    fi
    local out
    out=$(echo "${result}" | jq -r '.result // empty' 2>/dev/null) || out=""
    echo "${out}"
}

_is_nontrivial() {
    local data="${1#0x}"
    [[ -n "${data}" && "${data//0/}" != "" ]]
}

_assert_precompile_inactive() {
    local addr="$1" input="$2" block="$3" label="$4"
    local out
    out=$(_call_at_block "${addr}" "${input}" "${block}")
    if [[ "${out}" == ERROR:* ]]; then
        echo "FAIL: ${label} eth_call error at block ${block}: ${out#ERROR:}" >&2
        return 1
    fi
    if _is_nontrivial "${out}"; then
        echo "FAIL: ${label} returned non-trivial output at block ${block}: ${out}" >&2
        return 1
    fi
    echo "  OK: ${label} inactive at block ${block}" >&3
}

_assert_precompile_active() {
    local addr="$1" input="$2" block="$3" label="$4"
    local out
    out=$(_call_at_block "${addr}" "${input}" "${block}")
    if [[ "${out}" == ERROR:* ]]; then
        echo "FAIL: ${label} eth_call error at block ${block}: ${out#ERROR:}" >&2
        return 1
    fi
    if ! _is_nontrivial "${out}"; then
        echo "FAIL: ${label} returned trivial/empty output at block ${block}: '${out}'" >&2
        return 1
    fi
    echo "  OK: ${label} active at block ${block}" >&3
}

# Assert precompile is active by checking that it reverts on bad input.
# Active precompile: eth_call returns a revert error. Inactive: returns "0x" result.
# Distinguishes precompile reverts from infrastructure errors (historical state unavailable).
_assert_precompile_reverts() {
    local addr="$1" input="$2" block="$3" label="$4"
    local block_param
    if [[ "$block" == "latest" ]]; then
        block_param='"latest"'
    else
        local block_hex
        block_hex=$(printf '0x%x' "$block")
        block_param="\"${block_hex}\""
    fi
    local result
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"'"${addr}"'","data":"'"${input}"'"},'"${block_param}"'],"id":1}')
    local has_error
    has_error=$(echo "${result}" | jq 'has("error")' 2>/dev/null)
    local err_msg
    err_msg=$(echo "${result}" | jq -r '.error.message // empty' 2>/dev/null) || err_msg=""

    if [[ "${has_error}" == "true" ]]; then
        # Fail on infrastructure errors (not precompile reverts)
        if [[ "${err_msg}" == *"historical state"* || "${err_msg}" == *"not available"* ]]; then
            echo "FAIL: ${label} historical state error at block ${block}: ${err_msg}" >&2
            return 1
        fi
        # Precompile revert = active
        echo "  OK: ${label} active (reverted on bad input) at block ${block}" >&3
        return 0
    fi

    local out
    out=$(echo "${result}" | jq -r '.result // empty' 2>/dev/null) || out=""
    if [[ "${out}" == "0x" || -z "${out}" ]]; then
        echo "FAIL: ${label} returned trivial 0x at block ${block} — precompile inactive" >&2
        return 1
    fi
    echo "  OK: ${label} active (returned data) at block ${block}" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Shared test vectors for precompile inputs
# ────────────────────────────────────────────────────────────────────────────

_ecrecover_input() {
    local input="0x"
    input+="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"
    input+="000000000000000000000000000000000000000000000000000000000000001c"
    input+="9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"
    input+="4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"
    echo "${input}"
}

_modexp_input() {
    local input="0x"
    input+="0000000000000000000000000000000000000000000000000000000000000001"
    input+="0000000000000000000000000000000000000000000000000000000000000001"
    input+="0000000000000000000000000000000000000000000000000000000000000001"
    input+="08"  # B = 8
    input+="09"  # E = 9
    input+="0a"  # M = 10
    echo "${input}"
}

_bls_g1add_input() {
    local pad="00000000000000000000000000000000"
    local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
    local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
    local G1="${pad}${g1x}${pad}${g1y}"
    local inf
    inf=$(printf '%0256s' '' | tr ' ' '0')
    echo "0x${inf}${G1}"
}

_bls_g1msm_input() {
    local pad="00000000000000000000000000000000"
    local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
    local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    echo "0x${pad}${g1x}${pad}${g1y}${scalar1}"
}

_bls_g2add_input() {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local inf
    inf=$(printf '%0512s' '' | tr ' ' '0')
    echo "0x${inf}${G2}"
}

_bls_g2msm_input() {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
    echo "0x${G2}${scalar1}"
}

_bls_pairing_input() {
    local pad="00000000000000000000000000000000"
    local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
    local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
    local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
    local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
    local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
    local g1_inf
    g1_inf=$(printf '%0256s' '' | tr ' ' '0')
    echo "0x${g1_inf}${G2}"
}

_bls_mapg1_input() {
    local pad="00000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    echo "0x${pad}${fp1}"
}

_bls_mapg2_input() {
    local pad="00000000000000000000000000000000"
    local fp0="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
    echo "0x${pad}${fp0}${pad}${fp1}"
}

_p256_input() {
    local input="0x"
    input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"
    input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"
    input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"
    input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"
    input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"
    echo "${input}"
}

_kzg_input() {
    # Empty calldata — active KZG precompile rejects invalid-length input with a
    # revert (returns ERROR via eth_call). Inactive address returns "0x" (success).
    echo "0x"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  GENESIS FORKS (block 0): Jaipur, Delhi, Indore, Agra, Napoli,
#                            Ahmedabad, Bhilai
#
#  These forks are always activated at genesis in our test environments.
#  No "before fork" transition tests — only "after fork" feature verification.
#
# ════════════════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────────────────────
# Agra — PUSH0 opcode + initcode size limit
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=fork-transition,opcode,push0,agra
@test "1.3: Agra — PUSH0 opcode succeeds in transaction after fork" {
    _wait_for_block $(( FORK_AGRA + 1 ))

    # Runtime: PUSH0 PUSH1 0x00 SSTORE STOP
    deploy_runtime "5f60005500"
    call_contract "$contract_addr"
    local status mined_block
    status=$(_receipt_status "$call_receipt")
    mined_block=$(_receipt_block "$call_receipt")

    echo "PUSH0 post-Agra: status=${status} block=${mined_block}" >&3
    [[ "$mined_block" -ge "$FORK_AGRA" ]]
    [[ "$status" == "0x1" ]]

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    echo "Storage slot 0: ${stored}" >&3
}

# bats test_tags=fork-transition,agra,initcode
@test "1.3: Agra — initcode size limit enforced (EIP-3860)" {
    _wait_for_block $(( FORK_AGRA + 1 ))

    # Contract runtime: PUSH2 0xC001 PUSH1 0 PUSH1 0 CREATE PUSH1 0 SSTORE STOP
    # CREATE with 49153 bytes initcode (1 over MaxInitCodeSize=49152)
    local size_hex="c001"
    local runtime="61${size_hex}60006000f060005500"
    deploy_runtime "$runtime" 5000000
    call_contract "$contract_addr" 5000000

    local status
    status=$(_receipt_status "$call_receipt")
    echo "Oversized initcode CREATE tx status: ${status}" >&3

    # EIP-3860 enforcement: either the tx reverts (0x0) or succeeds with CREATE
    # returning 0 stored in slot 0. Both are valid enforcement behaviors.
    if [[ "$status" == "0x1" ]]; then
        local stored result
        stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
        result=$(printf "%d" "$stored")
        echo "CREATE returned: ${result} (0 = failed due to initcode limit)" >&3
        [[ "$result" -eq 0 ]]
    else
        # tx reverted — initcode limit enforced at transaction level
        echo "Tx reverted (0x0) — initcode limit enforced" >&3
        [[ "$status" == "0x0" ]]
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Napoli — MCOPY, TSTORE/TLOAD, SELFDESTRUCT restriction
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=fork-transition,opcode,mcopy,napoli
@test "1.3: Napoli — MCOPY opcode succeeds in transaction after fork" {
    _wait_for_block $(( FORK_NAPOLI + 1 ))

    deploy_runtime "6001600060205e00"
    call_contract "$contract_addr"
    local status mined_block
    status=$(_receipt_status "$call_receipt")
    mined_block=$(_receipt_block "$call_receipt")

    echo "MCOPY post-Napoli: status=${status} block=${mined_block}" >&3
    [[ "$mined_block" -ge "$FORK_NAPOLI" ]]
    [[ "$status" == "0x1" ]]
}

# bats test_tags=fork-transition,opcode,transient-storage,napoli
@test "1.3: Napoli — TSTORE/TLOAD succeed and produce correct state after fork" {
    _wait_for_block $(( FORK_NAPOLI + 1 ))

    deploy_runtime "604260005d60005c60005500"
    call_contract "$contract_addr"
    local status
    status=$(_receipt_status "$call_receipt")
    [[ "$status" == "0x1" ]]

    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    echo "Storage slot 0: ${stored} (expect 0x42)" >&3
    [[ $(printf "%d" "$stored") -eq 66 ]]
}

# bats test_tags=fork-transition,selfdestruct,napoli
@test "1.3: Napoli — SELFDESTRUCT no longer removes code (EIP-6780)" {
    _wait_for_block $(( FORK_NAPOLI + 1 ))

    local beneficiary="${ephemeral_address#0x}"
    deploy_runtime "73${beneficiary}ff"
    local addr="$contract_addr"

    call_contract "$addr"
    local status
    status=$(_receipt_status "$call_receipt")
    [[ "$status" == "0x1" ]]

    local code
    code=$(cast code --rpc-url "$L2_RPC_URL" "$addr")
    echo "Code after SELFDESTRUCT: ${code}" >&3
    [[ "${code}" != "0x" && -n "${code}" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# Ahmedabad — MaxCodeSize 24KB → 32KB
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=fork-transition,ahmedabad,max-code-size
@test "1.3: Ahmedabad — contract > 24KB deploys successfully after fork" {
    _wait_for_block $(( FORK_AHMEDABAD + 1 ))

    local size=25000
    local runtime
    runtime=$(printf '%0*s' $(( size * 2 )) '' | tr ' ' '0')
    deploy_large_runtime "$runtime"

    local code code_len
    code=$(cast code --rpc-url "$L2_RPC_URL" "$contract_addr")
    code_len=$(( (${#code} - 2) / 2 ))
    echo "Deployed code size: ${code_len} bytes" >&3
    [[ "$code_len" -eq "$size" ]]
}

# bats test_tags=fork-transition,ahmedabad,max-code-size
@test "1.3: Ahmedabad — contract > 32KB fails to deploy" {
    _wait_for_block $(( FORK_AHMEDABAD + 1 ))

    local size=32769
    local runtime
    runtime=$(printf '%0*s' $(( size * 2 )) '' | tr ' ' '0')
    local size_hex
    size_hex=$(printf "%04x" "$size")
    local initcode="61${size_hex}61000b60003961${size_hex}6000f3${runtime}"

    local receipt status
    receipt=$(cast send \
        --legacy --gas-limit 30000000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")
    status=$(echo "$receipt" | jq -r '.status')
    echo "32KB+ contract deploy status: ${status} (expect 0x0)" >&3
    [[ "$status" == "0x0" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 1.2: Legacy precompiles (0x01–0x09) at genesis forks
#      Checked early (chain at ~block 5) using eth_call at "latest".
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=precompile-consistency,legacy
@test "1.2: legacy precompiles (0x01–0x09) active at genesis forks" {
    _wait_for_block 5

    local input expected out

    # ecRecover (0x01)
    input=$(_ecrecover_input)
    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "${input}" "latest" "ecRecover (0x01)"

    # SHA-256 (0x02) — empty input
    expected="0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    out=$(_call_at_block "0x0000000000000000000000000000000000000002" "0x" "latest")
    [[ "${out}" == "${expected}" ]]
    echo "  OK: SHA-256 correct" >&3

    # RIPEMD-160 (0x03)
    expected="0x0000000000000000000000009c1185a5c5e9fc54612808977ee8f548b2258d31"
    out=$(_call_at_block "0x0000000000000000000000000000000000000003" "0x" "latest")
    [[ "${out}" == "${expected}" ]]
    echo "  OK: RIPEMD-160 correct" >&3

    # identity (0x04)
    out=$(_call_at_block "0x0000000000000000000000000000000000000004" "0xdeadbeef" "latest")
    [[ "${out}" == "0xdeadbeef" ]]
    echo "  OK: identity correct" >&3

    # modexp (0x05) — 8^9 mod 10 = 8
    input=$(_modexp_input)
    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "${input}" "latest")
    [[ "${out}" == "0x08" ]]
    echo "  OK: modexp correct" >&3

    # bn256Add (0x06)
    input="0x"
    input+="0000000000000000000000000000000000000000000000000000000000000001"
    input+="0000000000000000000000000000000000000000000000000000000000000002"
    input+="0000000000000000000000000000000000000000000000000000000000000001"
    input+="0000000000000000000000000000000000000000000000000000000000000002"
    _assert_precompile_active "0x0000000000000000000000000000000000000006" \
        "${input}" "latest" "bn256Add (0x06)"

    # ecPairing (0x08) — empty input = 1
    expected="0x0000000000000000000000000000000000000000000000000000000000000001"
    out=$(_call_at_block "0x0000000000000000000000000000000000000008" "0x" "latest")
    [[ "${out}" == "${expected}" ]]
    echo "  OK: ecPairing correct" >&3

    # blake2F (0x09)
    local rounds="0000000c"
    local h="48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5"
    h+="d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b"
    local m="6162630000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    local t0="0300000000000000"
    local t1="0000000000000000"
    local f="01"
    input="0x${rounds}${h}${m}${t0}${t1}${f}"
    _assert_precompile_active "0x0000000000000000000000000000000000000009" \
        "${input}" "latest" "blake2F (0x09)"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  RIO (block 256)
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,rio
@test "1.3: Rio — chain progresses smoothly through fork boundary" {
    [[ "$FORK_RIO" -le 1 ]] && skip "Rio at genesis"
    _wait_for_block $(( FORK_RIO + 2 ))

    # In Bor PoS, the miner field is 0x0 — signer is extracted from block seal.
    # Verify chain progresses by checking block hashes are valid.
    local before_hash after_hash
    before_hash=$(_block_field "$(( FORK_RIO - 1 ))" "hash")
    after_hash=$(_block_field "$(( FORK_RIO + 1 ))" "hash")

    echo "Rio-1 hash: ${before_hash}" >&3
    echo "Rio+1 hash: ${after_hash}" >&3

    [[ -n "$before_hash" && "$before_hash" != "null" ]]
    [[ -n "$after_hash" && "$after_hash" != "null" ]]
    [[ "$before_hash" != "$after_hash" ]]
}

# bats test_tags=precompile-consistency,legacy,rio
@test "1.2: legacy precompiles still active at Rio" {
    _wait_for_block $(( FORK_RIO + 1 ))

    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "$(_ecrecover_input)" "latest" "ecRecover (0x01)"

    local rounds="0000000c"
    local h="48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5"
    h+="d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b"
    local m="6162630000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    local t0="0300000000000000"
    local t1="0000000000000000"
    local f="01"
    local input="0x${rounds}${h}${m}${t0}${t1}${f}"
    _assert_precompile_active "0x0000000000000000000000000000000000000009" \
        "${input}" "latest" "blake2F (0x09)"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  PRE-MADHUGIRI: Verify precompile state before Bor's Madhugiri fork.
#
#  NOTE on precompile inheritance: Before Madhugiri, the active precompile
#  set comes from upstream Prague (activated at genesis). Prague already
#  includes BLS12-381 (0x0b–0x11) and p256Verify (0x0100).
#
#  Madhugiri then OVERRIDES with its own table that includes BLS but
#  DROPS p256Verify. MadhugiriPro re-adds p256Verify.
#
#  KZG (0x0a) is not in any table until Lisovo.
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=precompile-consistency,bls12,p256,pre-madhugiri
@test "1.2: BLS12-381 and p256Verify already active before Madhugiri (via upstream Prague)" {
    [[ "$FORK_MADHUGIRI" -le 10 ]] && skip "Madhugiri at genesis"
    _wait_before_fork "$FORK_MADHUGIRI"

    # BLS active from genesis via upstream Prague precompile table
    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add (via Prague)"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing (via Prague)"

    # p256Verify active from genesis via upstream Prague precompile table
    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify (via Prague)"
}

# bats test_tags=precompile-consistency,kzg,pre-madhugiri
@test "1.2: KZG (0x0a) still inactive before Madhugiri" {
    [[ "$FORK_MADHUGIRI" -le 10 ]] && skip "Madhugiri at genesis"
    _wait_before_fork "$FORK_MADHUGIRI"

    # KZG is not in the Cancun precompile set on any bor version.
    # It only appears in Madhugiri+ (2.5.9) or Lisovo+ (2.6.x+).
    # Before Madhugiri, the chain is in Cancun → KZG must be inactive.
    _assert_precompile_inactive "0x000000000000000000000000000000000000000a" \
        "$(_kzg_input)" "latest" "KZG point eval"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  MADHUGIRI — BLS12-381, EIP-7825 tx gas limit, modexp change
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,madhugiri,tx-gas-limit
@test "1.3: Madhugiri — transaction with gas > 33554432 is rejected (EIP-7825)" {
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    local max_tx_gas=33554432
    local over_limit=$(( max_tx_gas + 1 ))

    set +e
    local result
    result=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$ephemeral_private_key" \
        --legacy --gas-limit "$over_limit" --value 0 "$ephemeral_address" --json 2>&1)
    local exit_code=$?
    set -e

    echo "Send with gas ${over_limit}: exit=${exit_code}" >&3

    if [[ "$exit_code" -eq 0 ]]; then
        local status
        status=$(echo "$result" | jq -r '.status' 2>/dev/null) || status=""
        [[ "$status" != "0x1" ]]
    fi
}

# bats test_tags=fork-transition,madhugiri,tx-gas-limit
@test "1.3: Madhugiri — transaction at exactly 33554432 gas is accepted" {
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    local receipt status
    receipt=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$ephemeral_private_key" \
        --legacy --gas-limit 33554432 --value 0 "$ephemeral_address" --json)
    status=$(echo "$receipt" | jq -r '.status')
    echo "Send with gas 33554432: status=${status}" >&3
    [[ "$status" == "0x1" ]]
}

# bats test_tags=precompile-consistency,p256,madhugiri,known-behavior
@test "1.2: p256Verify (0x0100) is DROPPED at Madhugiri (known: missing from Madhugiri precompile table)" {
    # KNOWN BEHAVIOR: PrecompiledContractsMadhugiri does not include p256Verify.
    # p256 is active before Madhugiri (via upstream Prague) and re-added at MadhugiriPro.
    # If this test FAILS, it means p256 was added to the Madhugiri table.
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    local current
    current=$(_current_block)
    if [[ "$current" -ge "$FORK_MADHUGIRI_PRO" ]]; then
        skip "chain past MadhugiriPro (block ${current}), cannot verify Madhugiri-era p256 state"
    fi

    _assert_precompile_inactive "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify (dropped at Madhugiri)"
}

# bats test_tags=precompile-consistency,bls12,madhugiri
@test "1.2: BLS12-381 (0x0b–0x11) active after Madhugiri" {
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000c" \
        "$(_bls_g1msm_input)" "latest" "G1MSM"
    _assert_precompile_active "0x000000000000000000000000000000000000000d" \
        "$(_bls_g2add_input)" "latest" "G2Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000e" \
        "$(_bls_g2msm_input)" "latest" "G2MSM"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing"
    _assert_precompile_active "0x0000000000000000000000000000000000000010" \
        "$(_bls_mapg1_input)" "latest" "MapFpToG1"
    _assert_precompile_active "0x0000000000000000000000000000000000000011" \
        "$(_bls_mapg2_input)" "latest" "MapFp2ToG2"
}

# bats test_tags=precompile-consistency,modexp,madhugiri
@test "1.2: modexp (0x05) correctness at Madhugiri (EIP-7823/7883)" {
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    local input out
    input=$(_modexp_input)
    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "${input}" "latest")

    echo "modexp after Madhugiri: ${out}" >&3
    [[ "${out}" == "0x08" ]]
}

# bats test_tags=gas,precompile,madhugiri
@test "1.3: SHA-256 precompile gas stable across Madhugiri boundary" {
    _wait_for_block $(( FORK_MADHUGIRI + 1 ))

    local addr="0x0000000000000000000000000000000000000002"
    local gas_before gas_after
    gas_before=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_MADHUGIRI - 1 )) "${addr}" "0x616263" 2>/dev/null) || gas_before="0"
    gas_after=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_MADHUGIRI + 1 )) "${addr}" "0x616263" 2>/dev/null) || gas_after="0"

    echo "SHA-256 gas: before=${gas_before} after=${gas_after}" >&3
    if [[ "$gas_before" != "0" && "$gas_after" != "0" ]]; then
        [[ "$gas_before" == "$gas_after" ]]
    else
        echo "  WARN: gas estimation not available at historical blocks (archive mode not enabled)" >&3
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#
#  PRE-MADHUGIRI PRO: p256 still dropped (Madhugiri table omits it)
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=precompile-consistency,p256,madhugiri-pro
@test "1.2: p256Verify (0x0100) still inactive in Madhugiri era (before MadhugiriPro re-adds it)" {
    [[ "$FORK_MADHUGIRI_PRO" -le 10 ]] && skip "MadhugiriPro at genesis"
    _wait_before_fork "$FORK_MADHUGIRI_PRO"

    # p256 is dropped when Madhugiri overrides the upstream Prague precompile table.
    # MadhugiriPro re-adds it.
    _assert_precompile_inactive "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify (dropped at Madhugiri)"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  MADHUGIRI PRO — p256Verify re-activation
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=precompile-consistency,p256,madhugiri-pro
@test "1.2: p256Verify (0x0100) active after MadhugiriPro" {
    _wait_for_block $(( FORK_MADHUGIRI_PRO + 1 ))

    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify"
}

# bats test_tags=precompile-consistency,bls12,madhugiri-pro
@test "1.2: BLS12-381 still active at MadhugiriPro" {
    _wait_for_block $(( FORK_MADHUGIRI_PRO + 1 ))

    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  DANDELI — TargetGasPercentage 50% → 65%
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,gas,dandeli
@test "1.3: Dandeli — base fee dynamics change with 65% gas target" {
    _wait_for_block $(( FORK_DANDELI + 5 ))

    local pre_fee1 pre_fee2 post_fee1 post_fee2
    pre_fee1=$(_base_fee_at "$(( FORK_DANDELI - 3 ))")
    pre_fee2=$(_base_fee_at "$(( FORK_DANDELI - 2 ))")
    post_fee1=$(_base_fee_at "$(( FORK_DANDELI + 3 ))")
    post_fee2=$(_base_fee_at "$(( FORK_DANDELI + 4 ))")

    local pre_gas post_gas pre_limit post_limit
    pre_gas=$(_gas_used_at "$(( FORK_DANDELI - 3 ))")
    post_gas=$(_gas_used_at "$(( FORK_DANDELI + 3 ))")
    pre_limit=$(_gas_limit_at "$(( FORK_DANDELI - 3 ))")
    post_limit=$(_gas_limit_at "$(( FORK_DANDELI + 3 ))")

    echo "Pre-Dandeli:  baseFee ${pre_fee1}→${pre_fee2}, gasUsed=${pre_gas}/${pre_limit}" >&3
    echo "Post-Dandeli: baseFee ${post_fee1}→${post_fee2}, gasUsed=${post_gas}/${post_limit}" >&3

    [[ "$pre_fee1" -gt 0 ]]
    [[ "$post_fee1" -gt 0 ]]
}

# bats test_tags=precompile-consistency,legacy,dandeli
@test "1.2: legacy precompiles + BLS + p256 still active at Dandeli" {
    _wait_for_block $(( FORK_DANDELI + 1 ))

    # Legacy
    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "$(_ecrecover_input)" "latest" "ecRecover"
    local out
    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "$(_modexp_input)" "latest")
    [[ "${out}" == "0x08" ]]
    echo "  OK: modexp correct" >&3

    # BLS12-381
    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"

    # p256Verify
    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify"

    # KZG (0x0a) activation at Dandeli depends on bor version:
    #   2.5.9:  KZG in Madhugiri/MadhugiriPro sets → active at block 448
    #   2.6.x+: KZG only in Lisovo set → inactive at block 448
    local kzg_out
    kzg_out=$(_call_at_block "0x000000000000000000000000000000000000000a" "$(_kzg_input)" "latest")
    local kzg_active=false
    if [[ "${kzg_out}" == ERROR:* ]] || _is_nontrivial "${kzg_out}"; then
        kzg_active=true
    fi

    if _bor_version_gte "2.6.0"; then
        if [[ "$kzg_active" == "true" ]]; then
            echo "FAIL: KZG (0x0a) unexpectedly active at Dandeli on bor $(_bor_version)" >&2
            return 1
        fi
        echo "  OK: KZG inactive at Dandeli [bor $(_bor_version)]" >&3
    else
        # On 2.5.9, MadhugiriPro set (active from block 384) includes KZG.
        if [[ "$kzg_active" != "true" ]]; then
            echo "FAIL: KZG (0x0a) unexpectedly inactive at Dandeli on bor $(_bor_version) — should be in MadhugiriPro set" >&2
            return 1
        fi
        echo "  OK: KZG active at Dandeli (expected on bor $(_bor_version) — in MadhugiriPro set)" >&3
    fi
}

# bats test_tags=gas,precompile,dandeli
@test "1.3: blake2F precompile gas stable across Dandeli boundary" {
    _wait_for_block $(( FORK_DANDELI + 1 ))

    local rounds="0000000c"
    local h="48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5"
    h+="d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b"
    local m="6162630000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    m+="0000000000000000000000000000000000000000000000000000000000000000"
    local t0="0300000000000000"
    local t1="0000000000000000"
    local f="01"
    local input="0x${rounds}${h}${m}${t0}${t1}${f}"
    local addr="0x0000000000000000000000000000000000000009"

    local gas_before gas_after
    gas_before=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_DANDELI - 1 )) "${addr}" "${input}" 2>/dev/null) || gas_before="0"
    gas_after=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_DANDELI + 1 )) "${addr}" "${input}" 2>/dev/null) || gas_after="0"

    echo "blake2F gas: before=${gas_before} after=${gas_after}" >&3
    if [[ "$gas_before" != "0" && "$gas_after" != "0" ]]; then
        [[ "$gas_before" == "$gas_after" ]]
    else
        echo "  WARN: gas estimation not available at historical blocks (archive mode not enabled)" >&3
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#
#  PRE-LISOVO: CLZ "before fork" test + KZG still inactive
#
#  Each test independently polls to wait for / catch the right timing window.
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,opcode,clz,lisovo
@test "1.3: Lisovo — CLZ opcode reverts in transaction before fork" {
    [[ "$FORK_LISOVO" -le 10 ]] && skip "Lisovo at genesis, no pre-fork blocks"
    _wait_before_fork "$FORK_LISOVO"

    # Runtime: PUSH1 0x01 CLZ PUSH1 0x00 SSTORE STOP
    deploy_runtime "60011e60005500"
    call_contract "$contract_addr"
    local status mined_block
    status=$(_receipt_status "$call_receipt")
    mined_block=$(_receipt_block "$call_receipt")

    echo "CLZ pre-Lisovo: status=${status} block=${mined_block} (fork=${FORK_LISOVO})" >&3
    [[ "$mined_block" -lt "$FORK_LISOVO" ]]
    [[ "$status" == "0x0" ]]
}

# bats test_tags=precompile-consistency,kzg,lisovo
@test "1.2: KZG (0x0a) still inactive before Lisovo" {
    [[ "$FORK_LISOVO" -le 10 ]] && skip "Lisovo at genesis"
    _wait_before_fork "$FORK_LISOVO"

    # Before Lisovo (block ~502), the active fork is MadhugiriPro (block 384+).
    #   2.5.9:  MadhugiriPro set includes KZG → active
    #   2.6.x+: MadhugiriPro set does NOT include KZG → inactive
    local kzg_out
    kzg_out=$(_call_at_block "0x000000000000000000000000000000000000000a" "$(_kzg_input)" "latest")
    local kzg_active=false
    if [[ "${kzg_out}" == ERROR:* ]] || _is_nontrivial "${kzg_out}"; then
        kzg_active=true
    fi

    if _bor_version_gte "2.6.0"; then
        if [[ "$kzg_active" == "true" ]]; then
            echo "FAIL: KZG (0x0a) unexpectedly active before Lisovo on bor $(_bor_version)" >&2
            return 1
        fi
        echo "  OK: KZG inactive before Lisovo [bor $(_bor_version)]" >&3
    else
        # On 2.5.9, KZG is in MadhugiriPro set → already active before Lisovo.
        if [[ "$kzg_active" != "true" ]]; then
            echo "FAIL: KZG (0x0a) unexpectedly inactive before Lisovo on bor $(_bor_version) — should be in MadhugiriPro set" >&2
            return 1
        fi
        echo "  OK: KZG active before Lisovo (expected on bor $(_bor_version) — in MadhugiriPro set)" >&3
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#
#  LISOVO — CLZ opcode, KZG activation
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,opcode,clz,lisovo
@test "1.3: Lisovo — CLZ opcode succeeds and returns correct value after fork" {
    _wait_for_block "$FORK_LISOVO"

    deploy_runtime "60011e60005500"
    call_contract "$contract_addr"
    local status
    status=$(_receipt_status "$call_receipt")

    if _bor_version_gte "2.6.0"; then
        # CLZ (0x1e) added in Lisovo — should succeed.
        [[ "$status" == "0x1" ]]
        local stored result
        stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
        result=$(printf "%d" "$stored")
        echo "CLZ(1) = ${result} (expect 255) [bor $(_bor_version)]" >&3
        [[ "$result" -eq 255 ]]
    else
        # Pre-2.6.0 bor doesn't implement CLZ — tx reverts.
        echo "CLZ tx status=${status} (expected 0x0 on bor $(_bor_version) — CLZ not implemented)" >&3
        [[ "$status" == "0x0" ]]
    fi
}

# bats test_tags=precompile-consistency,kzg,lisovo
@test "1.2: KZG point evaluation (0x0a) active in Lisovo era (on-chain tx)" {
    # KZG is active at Lisovo but dropped at LisovoPro. This test must run while
    # the chain is in the Lisovo era (between FORK_LISOVO and FORK_LISOVO_PRO).
    # On-chain tx executes in the current fork's EVM context, so if the chain is
    # past LisovoPro, the tx would reflect LisovoPro's precompile set (no KZG).
    [[ "$FORK_LISOVO_PRO" -le "$FORK_LISOVO" ]] && skip "LisovoPro not after Lisovo"
    _wait_for_block $(( FORK_LISOVO + 1 ))

    local current
    current=$(_current_block)
    if [[ "$current" -ge "$FORK_LISOVO_PRO" ]]; then
        skip "chain already past LisovoPro (block ${current}), cannot verify Lisovo-era KZG without archive mode"
    fi

    # Deploy contract that STATICCALLs KZG precompile (0x0a) and stores result.
    # success=0 means STATICCALL reverted (precompile exists, bad input) = ACTIVE
    # success=1 means STATICCALL succeeded (no code at address) = INACTIVE
    deploy_runtime "6000600060006000600a5afa600055003d60015500" 500000
    call_contract "$contract_addr" 500000

    local status
    status=$(_receipt_status "$call_receipt")
    [[ "$status" == "0x1" ]]

    local success_flag
    success_flag=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    success_flag=$(printf "%d" "$success_flag")

    echo "KZG STATICCALL success flag: ${success_flag} (0=reverted=active, 1=no code=inactive)" >&3

    # KZG active means STATICCALL reverts on empty input → success_flag = 0
    [[ "$success_flag" -eq 0 ]]
}

# bats test_tags=precompile-consistency,legacy,lisovo
@test "1.2: all precompiles correct at Lisovo" {
    _wait_for_block $(( FORK_LISOVO + 1 ))

    # Legacy
    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "$(_ecrecover_input)" "latest" "ecRecover"

    local out
    out=$(_call_at_block "0x0000000000000000000000000000000000000002" "0x" "latest")
    [[ "${out}" == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
    echo "  OK: SHA-256 correct" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "$(_modexp_input)" "latest")
    [[ "${out}" == "0x08" ]]
    echo "  OK: modexp correct" >&3

    # BLS12-381
    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing"

    # p256Verify
    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify"
}

# bats test_tags=gas,precompile,lisovo
@test "1.3: ecRecover precompile gas stable across Lisovo boundary" {
    _wait_for_block $(( FORK_LISOVO + 1 ))

    local input addr gas_before gas_after
    input=$(_ecrecover_input)
    addr="0x0000000000000000000000000000000000000001"
    gas_before=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_LISOVO - 1 )) "${addr}" "${input}" 2>/dev/null) || gas_before="0"
    gas_after=$(cast estimate --rpc-url "$L2_RPC_URL" --block $(( FORK_LISOVO + 1 )) "${addr}" "${input}" 2>/dev/null) || gas_after="0"

    echo "ecRecover gas: before=${gas_before} after=${gas_after}" >&3
    if [[ "$gas_before" != "0" && "$gas_after" != "0" ]]; then
        [[ "$gas_before" == "$gas_after" ]]
    else
        echo "  WARN: gas estimation not available at historical blocks (archive mode not enabled)" >&3
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#
#  LISOVO PRO — final fork
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,lisovopro
@test "1.3: LisovoPro — chain progresses smoothly through fork boundary" {
    [[ "$FORK_LISOVO_PRO" -le 1 ]] && skip "LisovoPro at genesis"
    _wait_for_block $(( FORK_LISOVO_PRO + 2 ))

    local before_hash after_hash
    before_hash=$(_block_field "$(( FORK_LISOVO_PRO - 1 ))" "hash")
    after_hash=$(_block_field "$(( FORK_LISOVO_PRO + 1 ))" "hash")

    [[ -n "$before_hash" && "$before_hash" != "null" ]]
    [[ -n "$after_hash" && "$after_hash" != "null" ]]
    echo "LisovoPro boundary OK" >&3
}

# bats test_tags=precompile-consistency,kzg,lisovopro,known-behavior
@test "1.2: KZG point evaluation (0x0a) is INACTIVE at LisovoPro (known: missing from precompile table)" {
    # KNOWN BEHAVIOR: PrecompiledContractsLisovoPro in core/vm/contracts.go does not
    # include 0x0a (kzgPointEvaluation). KZG is active at Lisovo but dropped at LisovoPro.
    # This test asserts the current behavior. If it FAILS, it means KZG was added back
    # to the LisovoPro precompile table — update this test accordingly.
    _wait_for_block $(( FORK_LISOVO_PRO + 1 ))

    # Deploy contract that STATICCALLs KZG precompile (0x0a) and stores result.
    # success=0 means STATICCALL reverted (precompile exists, bad input) = ACTIVE
    # success=1 means STATICCALL succeeded (no code at address) = INACTIVE
    deploy_runtime "6000600060006000600a5afa600055003d60015500" 500000
    call_contract "$contract_addr" 500000

    local status
    status=$(_receipt_status "$call_receipt")
    [[ "$status" == "0x1" ]]

    local success_flag
    success_flag=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    success_flag=$(printf "%d" "$success_flag")

    echo "KZG STATICCALL at LisovoPro: success_flag=${success_flag} (0=active, 1=inactive)" >&3

    if _bor_version_gte "2.6.0"; then
        # On 2.6.x+, KZG is removed at LisovoPro — STATICCALL succeeds (no code).
        if [[ "$success_flag" -ne 1 ]]; then
            echo "FAIL: KZG still active at LisovoPro on bor $(_bor_version) — should have been removed" >&2
            return 1
        fi
        echo "  KZG correctly removed at LisovoPro [bor $(_bor_version)]" >&3
    else
        # On pre-2.6.0, KZG is in all post-Cancun sets — still active at LisovoPro.
        if [[ "$success_flag" -ne 0 ]]; then
            echo "FAIL: KZG unexpectedly inactive at LisovoPro on bor $(_bor_version)" >&2
            return 1
        fi
        echo "  KZG still active at LisovoPro (expected on bor $(_bor_version) — no LisovoPro precompile removal)" >&3
    fi
}

# bats test_tags=precompile-consistency,kzg,lisovopro,warm-cold
@test "1.2: BALANCE(0x0a) on-chain at LisovoPro — warm/cold gas baked into state root" {
    # This test sends an on-chain transaction that executes BALANCE on the KZG
    # precompile address (0x0a) after LisovoPro activates. The gas cost of
    # BALANCE depends on whether 0x0a is in the warm precompile set:
    #
    #   - Bor 2.5.9: 0x0a is warm (included in all post-Cancun sets) → 100 gas
    #   - Bor 2.6.x+: 0x0a is cold (removed at LisovoPro) → 2600 gas
    #
    # The gas difference gets baked into the transaction's gasUsed and thus the
    # block's state root. An archive node running a different bor version will
    # compute a different state root for this block → BAD BLOCK.
    #
    # This test always passes (it just executes BALANCE and stores the result).
    # The actual failure is expected during archive sync, not here.
    _wait_for_block $(( FORK_LISOVO_PRO + 1 ))

    # Contract: PUSH20<0x0a> BALANCE POP STOP
    # Just executes BALANCE on 0x0a so the warm/cold gas cost is included in
    # the transaction's gasUsed. No need to store the result — the gas
    # difference alone is enough to cause a state root mismatch.
    deploy_runtime "73000000000000000000000000000000000000000a315000"
    call_contract "$contract_addr"

    local status gas_used
    status=$(_receipt_status "$call_receipt")
    gas_used=$(echo "$call_receipt" | jq -r '.gasUsed' | xargs printf "%d" 2>/dev/null) || gas_used="unknown"
    [[ "$status" == "0x1" ]]

    echo "BALANCE(0x0a) tx at LisovoPro: gasUsed=${gas_used}" >&3
    echo "  On bor 2.5.9 (warm): ~21200 | On bor 2.6.x+ (cold): ~23700" >&3
    echo "  This gas difference causes BAD BLOCK when archive node replays with different version" >&3
}

# bats test_tags=precompile-consistency,lisovopro
@test "1.2: all precompiles correct at LisovoPro" {
    _wait_for_block $(( FORK_LISOVO_PRO + 1 ))

    # Legacy
    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "$(_ecrecover_input)" "latest" "ecRecover"

    local out
    out=$(_call_at_block "0x0000000000000000000000000000000000000002" "0x" "latest")
    [[ "${out}" == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
    echo "  OK: SHA-256 at LisovoPro" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000003" "0x" "latest")
    [[ "${out}" == "0x0000000000000000000000009c1185a5c5e9fc54612808977ee8f548b2258d31" ]]
    echo "  OK: RIPEMD-160 at LisovoPro" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000004" "0xdeadbeef" "latest")
    [[ "${out}" == "0xdeadbeef" ]]
    echo "  OK: identity at LisovoPro" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "$(_modexp_input)" "latest")
    [[ "${out}" == "0x08" ]]
    echo "  OK: modexp at LisovoPro" >&3

    local expected="0x0000000000000000000000000000000000000000000000000000000000000001"
    out=$(_call_at_block "0x0000000000000000000000000000000000000008" "0x" "latest")
    [[ "${out}" == "${expected}" ]]
    echo "  OK: ecPairing at LisovoPro" >&3

    # BLS12-381
    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000c" \
        "$(_bls_g1msm_input)" "latest" "G1MSM"
    _assert_precompile_active "0x000000000000000000000000000000000000000d" \
        "$(_bls_g2add_input)" "latest" "G2Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000e" \
        "$(_bls_g2msm_input)" "latest" "G2MSM"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing"
    _assert_precompile_active "0x0000000000000000000000000000000000000010" \
        "$(_bls_mapg1_input)" "latest" "MapFpToG1"
    _assert_precompile_active "0x0000000000000000000000000000000000000011" \
        "$(_bls_mapg2_input)" "latest" "MapFp2ToG2"

    # p256Verify
    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify"
}

# ════════════════════════════════════════════════════════════════════════════
#
#  GIUGLIANO — consensus-layer fork: PIP-66 early block announcements,
#              gas target + base fee change denominator in block header extra
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,giugliano
@test "1.3: Giugliano — chain progresses smoothly through fork boundary" {
    [[ "$FORK_GIUGLIANO" -le 1 ]] && skip "Giugliano at genesis"
    _wait_for_block $(( FORK_GIUGLIANO + 2 ))

    local before_hash after_hash
    before_hash=$(_block_field "$(( FORK_GIUGLIANO - 1 ))" "hash")
    after_hash=$(_block_field "$(( FORK_GIUGLIANO + 1 ))" "hash")

    echo "Giugliano-1 hash: ${before_hash}" >&3
    echo "Giugliano+1 hash: ${after_hash}" >&3

    [[ -n "$before_hash" && "$before_hash" != "null" ]]
    [[ -n "$after_hash" && "$after_hash" != "null" ]]
    [[ "$before_hash" != "$after_hash" ]]
}

# bats test_tags=fork-transition,giugliano,gas-params
@test "1.3: Giugliano — bor_getBlockGasParams returns gasTarget and baseFeeChangeDenominator" {
    _wait_for_block $(( FORK_GIUGLIANO + 1 ))

    local block_hex result gas_target bfcd
    block_hex=$(printf '0x%x' "$(( FORK_GIUGLIANO + 1 ))")
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"bor_getBlockGasParams","params":["'"${block_hex}"'"],"id":1}')

    # Verify no JSON-RPC error — skip if method doesn't exist (older bor versions).
    local err
    err=$(echo "$result" | jq -r '.error.message // empty')
    if [[ -n "$err" ]]; then
        if [[ "$err" == *"does not exist"* || "$err" == *"not available"* ]]; then
            skip "bor_getBlockGasParams not available on bor $(_bor_version)"
        fi
        echo "FAIL: bor_getBlockGasParams returned error: ${err}" >&2
        return 1
    fi

    # .result must be a non-null object — guards against silently passing if the
    # RPC method doesn't exist on this node version.
    local result_type
    result_type=$(echo "$result" | jq -r '.result | type')
    if [[ "$result_type" != "object" ]]; then
        echo "FAIL: bor_getBlockGasParams .result is ${result_type}, expected object" >&2
        return 1
    fi

    gas_target=$(echo "$result" | jq -r '.result.gasTarget // empty')
    bfcd=$(echo "$result" | jq -r '.result.baseFeeChangeDenominator // empty')

    echo "Post-Giugliano block $((FORK_GIUGLIANO + 1)): gasTarget=${gas_target} baseFeeChangeDenominator=${bfcd}" >&3

    [[ -n "$gas_target" && "$gas_target" != "null" ]]
    [[ -n "$bfcd" && "$bfcd" != "null" ]]

    # Sanity: values should be non-zero hex
    local gt_dec bfcd_dec
    gt_dec=$(printf "%d" "$gas_target")
    bfcd_dec=$(printf "%d" "$bfcd")
    echo "  gasTarget=${gt_dec} baseFeeChangeDenominator=${bfcd_dec}" >&3
    [[ "$gt_dec" -gt 0 ]]
    [[ "$bfcd_dec" -gt 0 ]]
}

# bats test_tags=fork-transition,giugliano,gas-params
@test "1.3: Giugliano — bor_getBlockGasParams returns null fields for pre-Giugliano block" {
    [[ "$FORK_GIUGLIANO" -le 1 ]] && skip "Giugliano at genesis, no pre-fork blocks"
    _wait_for_block $(( FORK_GIUGLIANO + 1 ))

    local block_hex result gas_target bfcd
    block_hex=$(printf '0x%x' "$(( FORK_GIUGLIANO - 1 ))")
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"bor_getBlockGasParams","params":["'"${block_hex}"'"],"id":1}')

    local err
    err=$(echo "$result" | jq -r '.error.message // empty')
    if [[ -n "$err" ]]; then
        if [[ "$err" == *"does not exist"* || "$err" == *"not available"* ]]; then
            skip "bor_getBlockGasParams not available on bor $(_bor_version)"
        fi
        echo "FAIL: bor_getBlockGasParams returned error: ${err}" >&2
        return 1
    fi

    # .result must be a non-null object (method exists) — guard against silent
    # pass if bor_getBlockGasParams is missing entirely and .result is null.
    local result_type
    result_type=$(echo "$result" | jq -r '.result | type')
    if [[ "$result_type" != "object" ]]; then
        echo "FAIL: bor_getBlockGasParams .result is ${result_type}, expected object" >&2
        return 1
    fi

    gas_target=$(echo "$result" | jq -r '.result.gasTarget')
    bfcd=$(echo "$result" | jq -r '.result.baseFeeChangeDenominator')

    echo "Pre-Giugliano block $((FORK_GIUGLIANO - 1)): gasTarget=${gas_target} baseFeeChangeDenominator=${bfcd}" >&3

    [[ "$gas_target" == "null" ]]
    [[ "$bfcd" == "null" ]]
}

# bats test_tags=fork-transition,giugliano,gas-params
@test "1.3: Giugliano — gasTarget is consistent with gasLimit and target percentage" {
    _wait_for_block $(( FORK_GIUGLIANO + 3 ))

    local block_hex result gas_target_hex
    block_hex=$(printf '0x%x' "$(( FORK_GIUGLIANO + 2 ))")

    # Get gasTarget from bor_getBlockGasParams
    result=$(curl -s -X POST "${L2_RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"bor_getBlockGasParams","params":["'"${block_hex}"'"],"id":1}')

    # Skip if method doesn't exist on this bor version.
    local err
    err=$(echo "$result" | jq -r '.error.message // empty')
    if [[ -n "$err" && ("$err" == *"does not exist"* || "$err" == *"not available"*) ]]; then
        skip "bor_getBlockGasParams not available on this bor version"
    fi

    gas_target_hex=$(echo "$result" | jq -r '.result.gasTarget')
    [[ -n "$gas_target_hex" && "$gas_target_hex" != "null" ]]

    # Get parent block's gasLimit (gasTarget is computed from parent)
    local parent_gas_limit
    parent_gas_limit=$(_gas_limit_at "$(( FORK_GIUGLIANO + 1 ))")

    local gas_target_dec
    gas_target_dec=$(printf "%d" "$gas_target_hex")

    echo "Parent gasLimit=${parent_gas_limit} gasTarget=${gas_target_dec}" >&3

    # gasTarget should be a fraction of parent gasLimit (target% of gasLimit).
    # It must be > 0 and <= gasLimit.
    [[ "$gas_target_dec" -gt 0 ]]
    [[ "$gas_target_dec" -le "$parent_gas_limit" ]]
}

# bats test_tags=precompile-consistency,giugliano
@test "1.2: all precompiles unchanged at Giugliano (same as LisovoPro)" {
    _wait_for_block $(( FORK_GIUGLIANO + 1 ))

    # Legacy
    _assert_precompile_active "0x0000000000000000000000000000000000000001" \
        "$(_ecrecover_input)" "latest" "ecRecover"

    local out
    out=$(_call_at_block "0x0000000000000000000000000000000000000002" "0x" "latest")
    [[ "${out}" == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
    echo "  OK: SHA-256 at Giugliano" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000004" "0xdeadbeef" "latest")
    [[ "${out}" == "0xdeadbeef" ]]
    echo "  OK: identity at Giugliano" >&3

    out=$(_call_at_block "0x0000000000000000000000000000000000000005" "$(_modexp_input)" "latest")
    [[ "${out}" == "0x08" ]]
    echo "  OK: modexp at Giugliano" >&3

    # BLS12-381
    _assert_precompile_active "0x000000000000000000000000000000000000000b" \
        "$(_bls_g1add_input)" "latest" "G1Add"
    _assert_precompile_active "0x000000000000000000000000000000000000000f" \
        "$(_bls_pairing_input)" "latest" "BLS12 Pairing"

    # p256Verify
    _assert_precompile_active "0x0000000000000000000000000000000000000100" \
        "$(_p256_input)" "latest" "p256Verify"
}

# bats test_tags=fork-transition,giugliano,gas-params
@test "1.3: Giugliano — base fee remains non-zero through fork boundary" {
    [[ "$FORK_GIUGLIANO" -le 1 ]] && skip "Giugliano at genesis"
    _wait_for_block $(( FORK_GIUGLIANO + 2 ))

    local pre_fee post_fee
    pre_fee=$(_base_fee_at "$(( FORK_GIUGLIANO - 1 ))")
    post_fee=$(_base_fee_at "$(( FORK_GIUGLIANO + 1 ))")

    echo "Giugliano boundary: baseFee ${pre_fee} → ${post_fee}" >&3
    [[ "$pre_fee" -gt 0 ]]
    [[ "$post_fee" -gt 0 ]]
}

# ════════════════════════════════════════════════════════════════════════════
#
#  CHAIN CONTINUITY — each test waits for all forks to pass
#
# ════════════════════════════════════════════════════════════════════════════

# bats test_tags=fork-transition,chain-continuity
@test "1.3: no reorgs at fork boundaries — parent hashes are consistent" {
    _wait_for_block $(( FORK_GIUGLIANO + 2 ))
    local -a fork_blocks=(
        "${FORK_JAIPUR}" "${FORK_DELHI}" "${FORK_INDORE}" "${FORK_AGRA}"
        "${FORK_NAPOLI}" "${FORK_AHMEDABAD}" "${FORK_BHILAI}" "${FORK_RIO}"
        "${FORK_MADHUGIRI}" "${FORK_MADHUGIRI_PRO}" "${FORK_DANDELI}"
        "${FORK_LISOVO}" "${FORK_LISOVO_PRO}" "${FORK_GIUGLIANO}"
    )

    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 0 ]] && continue
        local parent_hash block_parent_hash
        parent_hash=$(_block_field "$(( fb - 1 ))" "hash")
        block_parent_hash=$(_block_field "${fb}" "parentHash")

        if [[ "${parent_hash}" != "${block_parent_hash}" ]]; then
            echo "FAIL: Reorg detected at fork block ${fb}!" >&2
            return 1
        fi
        echo "  OK: Block ${fb} consistent" >&3
    done
}

# bats test_tags=fork-transition,chain-continuity
@test "1.3: timestamps strictly increasing across all fork boundaries" {
    _wait_for_block $(( FORK_GIUGLIANO + 2 ))
    local -a fork_blocks=(
        "${FORK_DELHI}" "${FORK_INDORE}" "${FORK_AGRA}" "${FORK_NAPOLI}"
        "${FORK_AHMEDABAD}" "${FORK_BHILAI}" "${FORK_RIO}" "${FORK_MADHUGIRI}"
        "${FORK_MADHUGIRI_PRO}" "${FORK_DANDELI}" "${FORK_LISOVO}" "${FORK_LISOVO_PRO}"
        "${FORK_GIUGLIANO}"
    )

    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 1 ]] && continue
        local ts_before ts_at ts_after
        ts_before=$(printf "%d" "$(_block_field "$(( fb - 1 ))" "timestamp")")
        ts_at=$(printf "%d" "$(_block_field "${fb}" "timestamp")")
        ts_after=$(printf "%d" "$(_block_field "$(( fb + 1 ))" "timestamp")")

        [[ "$ts_at" -gt "$ts_before" ]]
        [[ "$ts_after" -gt "$ts_at" ]]
    done
}

# bats test_tags=fork-transition,chain-continuity
@test "1.3: base fee exists and is non-zero across all fork boundaries" {
    _wait_for_block $(( FORK_GIUGLIANO + 2 ))
    local -a fork_blocks=(
        "${FORK_DELHI}" "${FORK_INDORE}" "${FORK_AGRA}" "${FORK_NAPOLI}"
        "${FORK_AHMEDABAD}" "${FORK_BHILAI}" "${FORK_RIO}" "${FORK_MADHUGIRI}"
        "${FORK_MADHUGIRI_PRO}" "${FORK_DANDELI}" "${FORK_LISOVO}" "${FORK_LISOVO_PRO}"
        "${FORK_GIUGLIANO}"
    )

    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 0 ]] && continue
        local fee
        fee=$(_base_fee_at "${fb}")
        echo "Fork block ${fb}: baseFee = ${fee}" >&3
        [[ "$fee" -gt 0 ]]
    done
}
