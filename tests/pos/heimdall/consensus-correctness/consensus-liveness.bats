#!/usr/bin/env bats
# bats file_tags=heimdall,consensus,correctness,liveness

# Heimdall Consensus Liveness
# ============================
# Verifies that Heimdall's BFT consensus layer is live, advancing, and
# satisfying the standard safety and liveness properties of CometBFT.
#
# These properties are required for correct network operation:
#
#   1. Chain advancement   — Heimdall block height increases over time;
#                            a stalled chain means consensus has halted
#   2. Validator power     — Every active validator has strictly positive
#                            voting power; this is a fundamental invariant
#                            of the staking module
#   3. Commit completeness — Each committed block's signed header contains
#                            one entry per active validator
#   4. Consensus round     — Blocks are decided in round 0 under normal
#                            operation; consistently elevated rounds indicate
#                            the network is struggling to reach agreement,
#                            which can cascade into liveness failures
#   5. BFT quorum          — Each committed block must be backed by strictly
#                            more than 2/3 of total voting power
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - Heimdall CometBFT RPC reachable at L2_CL_RPC_URL (optional; derived
#     from kurtosis or L2_CL_API_URL port-substitution if not set)
#
# RUN: bats tests/pos/heimdall/consensus-correctness/consensus-liveness.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Resolve the CometBFT JSON-RPC URL.  It is exposed on a different port
    # from the Cosmos REST API (L2_CL_API_URL).  Try kurtosis first, then
    # fall back to replacing the REST port (1317) with the CometBFT default
    # (26657).
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            export L2_CL_RPC_URL="http://${rpc_port}"
        else
            # Best-effort substitution: swap the REST port for the RPC port.
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi
    echo "L2_CL_RPC_URL=${L2_CL_RPC_URL}" >&3

    # Probe liveness via the REST status endpoint.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/status" 2>/dev/null \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall status endpoint not reachable at ${L2_CL_API_URL} — all liveness tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_liveness_unavailable"
    else
        echo "Heimdall status reachable; latest_block_height=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_liveness_unavailable"
    fi

    # Probe the CometBFT RPC separately — some tests require it.
    local rpc_probe
    rpc_probe=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${rpc_probe}" ]]; then
        echo "NOTE: CometBFT RPC not reachable at ${L2_CL_RPC_URL} — commit-level tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable"
    else
        echo "CometBFT RPC reachable; latest_block_height=${rpc_probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Re-derive L2_CL_RPC_URL so it is available in every test subshell.
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            export L2_CL_RPC_URL="http://${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_liveness_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall status endpoint not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Return the current Heimdall block height as a decimal integer.
# Uses the CometBFT /status endpoint on the REST API host.
_heimdall_height() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/status" 2>/dev/null || true)
    local h
    h=$(printf '%s' "${raw}" \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
    if [[ -z "${h}" || "${h}" == "null" ]]; then
        return 1
    fi
    printf '%d' "${h}"
}

# Fetch the active validator set from the Heimdall REST API.
# Prints the raw JSON array of validator objects, or returns 1.
#
# Strategy:
#   1. /stake/validators-set — heimdall-v2 (returns .validator_set.validators)
#   2. /stake/validators     — heimdall-v1 (returns .validators)
#   3. /bor/spans/latest     — fallback via span validator_set
_get_validators() {
    local raw vals

    # Attempt 1: /stake/validators-set (heimdall-v2)
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/stake/validators-set" 2>/dev/null || true)
    vals=$(printf '%s' "${raw}" \
        | jq -c '.validator_set.validators // empty' 2>/dev/null || true)

    # Attempt 2: /stake/validators (heimdall-v1) or /v1beta1/ prefix
    if [[ -z "${vals}" || "${vals}" == "null" || "${vals}" == "[]" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/stake/validators" 2>/dev/null || true)
        vals=$(printf '%s' "${raw}" \
            | jq -c '.validators // empty' 2>/dev/null || true)
    fi
    if [[ -z "${vals}" || "${vals}" == "null" || "${vals}" == "[]" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/stake/validators" 2>/dev/null || true)
        vals=$(printf '%s' "${raw}" \
            | jq -c '.validators // empty' 2>/dev/null || true)
    fi

    # Attempt 3: span validator_set as a last resort
    if [[ -z "${vals}" || "${vals}" == "null" || "${vals}" == "[]" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null || true)
        vals=$(printf '%s' "${raw}" \
            | jq -c '.span.validator_set.validators // empty' 2>/dev/null || true)
    fi

    if [[ -z "${vals}" || "${vals}" == "null" || "${vals}" == "[]" ]]; then
        return 1
    fi
    printf '%s' "${vals}"
}

# Fetch the CometBFT commit object for the given height (decimal).
# Prints the raw JSON commit object, or returns 1.
_get_commit() {
    local height="$1"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/commit?height=${height}" 2>/dev/null || true)
    local commit
    commit=$(printf '%s' "${raw}" \
        | jq -r '.result.signed_header.commit // empty' 2>/dev/null || true)
    if [[ -z "${commit}" || "${commit}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${commit}"
}

# Fetch the CometBFT validator set at the given height (decimal).
# Prints the raw JSON array of validator objects, or returns 1.
_get_cometbft_validators() {
    local height="$1"
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/validators?height=${height}&per_page=100" 2>/dev/null || true)
    local vals
    vals=$(printf '%s' "${raw}" \
        | jq -r '.result.validators // empty' 2>/dev/null || true)
    if [[ -z "${vals}" || "${vals}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${vals}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=consensus,correctness,liveness
@test "heimdall consensus: chain is live and advancing" {
    # The chain must produce at least one new block within 60 seconds.
    # A permanently stalled height means BFT consensus has halted.

    local h1
    if ! h1=$(_heimdall_height); then
        fail "Could not read block height from Heimdall at ${L2_CL_API_URL}/status"
    fi

    echo "  Initial height: ${h1}" >&3
    echo "  Waiting up to 60s for chain to advance..." >&3

    local h2="${h1}"
    local deadline=$(( $(date +%s) + 60 ))
    local h_new

    while [[ "$(date +%s)" -lt "${deadline}" ]]; do
        sleep 5
        h_new=$(_heimdall_height 2>/dev/null || echo "${h2}")
        if [[ "${h_new}" -gt "${h1}" ]]; then
            h2="${h_new}"
            break
        fi
    done

    echo "  Height after poll: ${h2}" >&3

    if [[ "${h2}" -le "${h1}" ]]; then
        echo "FAIL: Heimdall height did not advance beyond ${h1} within 60 seconds" >&2
        echo "  BFT consensus has stalled — check CometBFT logs for details." >&2
        return 1
    fi

    echo "  OK: chain advanced from ${h1} to ${h2} (+$(( h2 - h1 )) block(s))" >&3
}

# bats test_tags=consensus,correctness,liveness
@test "heimdall consensus: all active validators have strictly positive voting power" {
    # Every validator in the active set must have voting_power > 0.
    # This is a fundamental invariant of the staking module.

    local vals_json
    if ! vals_json=$(_get_validators); then
        skip "Could not fetch validator set from ${L2_CL_API_URL} — skipping power check"
    fi

    local n_validators
    n_validators=$(printf '%s' "${vals_json}" | jq 'length')
    # Ensure n_validators is a safe integer before use in arithmetic.
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    if [[ "${n_validators}" -eq 0 ]]; then
        skip "Active validator set is empty — chain may not have started staking yet"
    fi

    echo "  Active validators: ${n_validators}" >&3

    local failures=0
    local i
    for (( i = 0; i < n_validators; i++ )); do
        local signer power
        signer=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].signer // empty')
        # Support both field name variants used across Heimdall API versions.
        power=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" \
                '(.[$idx].voting_power // .[$idx].power // .[$idx].VotingPower) // empty')

        # Validate that power is a safe integer before comparison.
        [[ "${power}" =~ ^-?[0-9]+$ ]] || power=""

        if [[ -z "${power}" || "${power}" == "null" ]]; then
            echo "FAIL: validator ${signer} has no resolvable voting power field" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        if [[ "${power}" -le 0 ]]; then
            echo "FAIL: validator ${signer} has non-positive voting_power=${power}" >&2
            failures=$(( failures + 1 ))
        else
            echo "  validator[${i}]: voting_power=${power}" >&3
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} validator(s) with non-positive voting power detected" >&2
        return 1
    fi

    echo "  OK: all ${n_validators} validators have positive voting power" >&3
}

# bats test_tags=consensus,correctness,liveness
@test "heimdall consensus: commit includes an entry for every validator in the active set" {
    # The CometBFT signed header commit contains one entry per validator in the
    # active set.  Each entry carries a block_id_flag indicating whether the
    # validator voted (COMMIT=2), abstained (NIL=3), or was absent (ABSENT=1).
    # This test checks that the commit is structurally complete: every address
    # in the active validator set appears in commit.signatures.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not reachable at ${L2_CL_RPC_URL} — skipping commit structure check"
    fi

    local height
    if ! height=$(_heimdall_height); then
        skip "Could not read current height from Heimdall"
    fi

    # Use height - 1 so both the commit and the validator set are finalized.
    if [[ "${height}" -lt 2 ]]; then
        skip "Chain height (${height}) too low — need at least 2 blocks for commit check"
    fi
    local check_height=$(( height - 1 ))
    echo "  Checking commit at height ${check_height}" >&3

    local commit
    if ! commit=$(_get_commit "${check_height}"); then
        skip "Could not fetch commit at height ${check_height} from ${L2_CL_RPC_URL}"
    fi

    local cmt_validators
    if ! cmt_validators=$(_get_cometbft_validators "${check_height}"); then
        skip "Could not fetch CometBFT validator set at height ${check_height}"
    fi

    local n_validators
    n_validators=$(printf '%s' "${cmt_validators}" | jq 'length')
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    if [[ "${n_validators}" -eq 0 ]]; then
        skip "CometBFT validator set at height ${check_height} is empty"
    fi

    echo "  Active validators at height ${check_height}: ${n_validators}" >&3

    # Build a set of addresses present in the commit signatures (lowercase).
    local -A commit_addrs=()
    local n_sigs
    n_sigs=$(printf '%s' "${commit}" | jq '.signatures | length')
    [[ "${n_sigs}" =~ ^[0-9]+$ ]] || n_sigs=0
    echo "  Commit signature entries: ${n_sigs}" >&3

    local j
    for (( j = 0; j < n_sigs; j++ )); do
        local addr
        addr=$(printf '%s' "${commit}" \
            | jq -r --argjson idx "${j}" '.signatures[$idx].validator_address // empty' \
            | tr '[:upper:]' '[:lower:]')
        if [[ -n "${addr}" && "${addr}" != "null" ]]; then
            commit_addrs["${addr}"]=1
        fi
    done

    # Verify that every active validator appears in the commit.
    local failures=0
    local k
    for (( k = 0; k < n_validators; k++ )); do
        local val_addr
        val_addr=$(printf '%s' "${cmt_validators}" \
            | jq -r --argjson idx "${k}" '.[$idx].address // empty' \
            | tr '[:upper:]' '[:lower:]')

        if [[ -z "${val_addr}" || "${val_addr}" == "null" ]]; then
            continue
        fi

        if [[ -z "${commit_addrs[${val_addr}]:-}" ]]; then
            echo "FAIL: validator ${val_addr} has no entry in the commit at height ${check_height}" >&2
            failures=$(( failures + 1 ))
        else
            local flag
            flag=$(printf '%s' "${commit}" \
                | jq -r --arg addr "${val_addr}" \
                    '.signatures[] | select((.validator_address // "" | ascii_downcase) == $addr) | .block_id_flag // "?"')
            echo "  validator ${val_addr}: block_id_flag=${flag}" >&3
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} validator(s) missing from commit at height ${check_height}" >&2
        return 1
    fi

    echo "  OK: all ${n_validators} active validators have an entry in the commit" >&3
}

# bats test_tags=consensus,correctness,liveness
@test "heimdall consensus: recent blocks decided at round 0" {
    # Under normal operation all validators agree in the first round (round 0).
    # Persistently elevated rounds indicate the network is struggling to reach
    # agreement, which degrades liveness and can eventually stall the chain.
    # Check the last 5 commits; allow at most 1 non-zero round as a one-off.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not reachable at ${L2_CL_RPC_URL} — skipping round check"
    fi

    local height
    if ! height=$(_heimdall_height); then
        skip "Could not read current height from Heimdall"
    fi

    local check_count=5
    if [[ "${height}" -lt "${check_count}" ]]; then
        check_count=$(( height - 1 ))
    fi
    if [[ "${check_count}" -lt 1 ]]; then
        skip "Chain height (${height}) too low — need at least 2 blocks for round check"
    fi

    local non_zero_rounds=0
    local i
    for (( i = 0; i < check_count; i++ )); do
        local h=$(( height - 1 - i ))
        local commit
        if ! commit=$(_get_commit "${h}"); then
            echo "  WARN: could not fetch commit at height ${h} — skipping" >&3
            continue
        fi

        local round
        round=$(printf '%s' "${commit}" | jq -r '.round // 0')
        # Validate round is a safe integer before comparison.
        [[ "${round}" =~ ^[0-9]+$ ]] || round=0
        echo "  height ${h}: commit round=${round}" >&3

        if [[ "${round}" -gt 0 ]]; then
            echo "  NOTE: block at height ${h} required ${round} extra round(s) to reach agreement" >&3
            non_zero_rounds=$(( non_zero_rounds + 1 ))
        fi
    done

    # Tolerate at most 1 non-zero round across the sampled window to avoid
    # flakiness from transient network conditions.
    if [[ "${non_zero_rounds}" -gt 1 ]]; then
        echo "FAIL: ${non_zero_rounds} of the last ${check_count} blocks required more than one consensus round" >&2
        echo "  This indicates the network is consistently struggling to reach agreement." >&2
        return 1
    fi

    echo "  OK: ${non_zero_rounds}/${check_count} blocks required extra rounds (threshold: 1)" >&3
}

# bats test_tags=consensus,correctness,liveness
@test "heimdall consensus: quorum of voting power committed each block" {
    # Each committed block must be backed by strictly more than 2/3 of the
    # total voting power (CometBFT BFT safety requirement).
    # Counts only COMMIT-flagged (block_id_flag=2) signatures.
    #
    # Uses the exact integer inequality: committed_vp * 3 > total_vp * 2
    # to avoid floating-point approximation errors.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not reachable at ${L2_CL_RPC_URL} — skipping quorum check"
    fi

    local height
    if ! height=$(_heimdall_height); then
        skip "Could not read current height from Heimdall"
    fi

    if [[ "${height}" -lt 2 ]]; then
        skip "Chain height (${height}) too low — need at least 2 blocks"
    fi
    local check_height=$(( height - 1 ))
    echo "  Checking quorum at height ${check_height}" >&3

    local commit
    if ! commit=$(_get_commit "${check_height}"); then
        skip "Could not fetch commit at height ${check_height}"
    fi

    local cmt_validators
    if ! cmt_validators=$(_get_cometbft_validators "${check_height}"); then
        skip "Could not fetch CometBFT validator set at height ${check_height}"
    fi

    # Build a map of address → voting_power for fast lookup.
    local n_validators
    n_validators=$(printf '%s' "${cmt_validators}" | jq 'length')
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    local -A vp_map=()
    local total_vp=0
    local k
    for (( k = 0; k < n_validators; k++ )); do
        local addr vp
        addr=$(printf '%s' "${cmt_validators}" \
            | jq -r --argjson idx "${k}" '.[$idx].address // empty' \
            | tr '[:upper:]' '[:lower:]')
        vp=$(printf '%s' "${cmt_validators}" \
            | jq -r --argjson idx "${k}" '.[$idx].voting_power // 0')
        # Validate vp is a non-negative integer before arithmetic use.
        [[ "${vp}" =~ ^[0-9]+$ ]] || vp=0
        if [[ -n "${addr}" && "${addr}" != "null" ]]; then
            vp_map["${addr}"]="${vp}"
            total_vp=$(( total_vp + vp ))
        fi
    done

    if [[ "${total_vp}" -eq 0 ]]; then
        skip "Total voting power is zero at height ${check_height} — cannot compute quorum"
    fi

    # Sum voting power of COMMIT-flagged (block_id_flag=2) signatures.
    local committed_vp=0
    local n_sigs
    n_sigs=$(printf '%s' "${commit}" | jq '.signatures | length')
    [[ "${n_sigs}" =~ ^[0-9]+$ ]] || n_sigs=0

    local j
    for (( j = 0; j < n_sigs; j++ )); do
        local flag addr
        flag=$(printf '%s' "${commit}" \
            | jq -r --argjson idx "${j}" '.signatures[$idx].block_id_flag // 1')
        addr=$(printf '%s' "${commit}" \
            | jq -r --argjson idx "${j}" '.signatures[$idx].validator_address // empty' \
            | tr '[:upper:]' '[:lower:]')
        # Validate flag is a safe integer before comparison.
        [[ "${flag}" =~ ^[0-9]+$ ]] || flag=1

        # block_id_flag 2 = COMMIT
        if [[ "${flag}" -eq 2 && -n "${addr}" ]]; then
            local vp="${vp_map[${addr}]:-0}"
            committed_vp=$(( committed_vp + vp ))
        fi
    done

    # Display an approximate percentage for diagnostics.
    local pct_x100=$(( committed_vp * 10000 / total_vp ))
    local pct_int=$(( pct_x100 / 100 ))
    local pct_frac=$(( pct_x100 % 100 ))

    echo "  Total VP:     ${total_vp}" >&3
    echo "  Committed VP: ${committed_vp}" >&3
    echo "  Quorum:       ${pct_int}.$(printf '%02d' "${pct_frac}")%" >&3

    # BFT safety check: committed_vp must be strictly more than 2/3 of total_vp.
    # Using exact integer inequality to avoid floating-point rounding issues.
    if [[ $(( committed_vp * 3 )) -le $(( total_vp * 2 )) ]]; then
        echo "FAIL: committed VP (${committed_vp}) does not exceed 2/3 of total VP (${total_vp}) at height ${check_height}" >&2
        echo "  BFT safety requires committed_vp * 3 > total_vp * 2." >&2
        return 1
    fi

    echo "  OK: quorum ${pct_int}.$(printf '%02d' "${pct_frac}")% > 66.67% at height ${check_height}" >&3
}
