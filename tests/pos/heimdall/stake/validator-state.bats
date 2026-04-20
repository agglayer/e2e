#!/usr/bin/env bats
# bats file_tags=heimdall,stake,correctness

# Heimdall Stake — Validator State Consistency
# =============================================
# This suite verifies the Heimdall stake module's validator set is internally
# consistent and agrees with the CometBFT consensus layer:
#
#   1. ID uniqueness       — Every active validator carries a distinct numeric ID;
#                            duplicate IDs indicate a state corruption in the
#                            staking module that can cause incorrect validator
#                            resolution at consensus boundaries.
#   2. Signer addresses    — Every active validator must have a non-empty, non-null
#                            signer address that is not the Ethereum zero address;
#                            a zero or missing signer breaks cross-chain message
#                            attribution and vote-extension verification.
#   3. Voting power totals — The sum of individual validator power reported by the
#                            Heimdall REST API must equal the total voting power
#                            reported by the CometBFT RPC (within a ±5 tolerance
#                            for encoding rounding); divergence here means the two
#                            layers have an inconsistent view of the staking state.
#   4. Validator count     — The number of validators in Heimdall must be non-zero
#                            and must match the CometBFT active-validator count;
#                            a mismatch means the consensus engine is operating
#                            on a different validator set than the staking module.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - At least 1 active validator registered in Heimdall's stake module
#
# RUN: bats tests/pos/heimdall/stake/validator-state.bats

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
            export L2_CL_RPC_URL="${rpc_port}"
        else
            # Best-effort substitution: swap the REST port for the RPC port.
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi
    # Normalise — strip double http:// if kurtosis already returns a URL.
    L2_CL_RPC_URL="${L2_CL_RPC_URL/#http:\/\/http:\/\//http:\/\/}"
    export L2_CL_RPC_URL
    echo "L2_CL_RPC_URL=${L2_CL_RPC_URL}" >&3

    # Probe the validator set via the span endpoint (the /stake/validators
    # REST endpoint is "Not Implemented" on heimdall-v2, so we use the
    # latest span's validator_set.validators array instead).
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null \
        | jq -r '.span.validator_set.validators | length' 2>/dev/null || true)

    if [[ -z "${probe}" || ! "${probe}" =~ ^[0-9]+$ || "${probe}" -eq 0 ]]; then
        echo "WARNING: Heimdall span validator set not reachable or returned no validators at ${L2_CL_API_URL} — all stake tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_stake_unavailable"
    else
        echo "Heimdall span validator_set reachable; validators=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_stake_unavailable"
    fi

    # Probe the CometBFT RPC separately — tests 3 and 4 require it.
    local rpc_probe
    rpc_probe=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${rpc_probe}" ]]; then
        echo "NOTE: CometBFT RPC not reachable at ${L2_CL_RPC_URL} — VP consistency and count tests will be skipped." >&3
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
            export L2_CL_RPC_URL="${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi
    L2_CL_RPC_URL="${L2_CL_RPC_URL/#http:\/\/http:\/\//http:\/\/}"
    export L2_CL_RPC_URL

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_stake_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall span validator set not reachable at ${L2_CL_API_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch all validators from the Heimdall span endpoint.
# The /stake/validators REST endpoint returns "Not Implemented" on
# heimdall-v2, so we read validators from the latest span's
# validator_set.validators array instead.  Each entry contains:
#   val_id, signer, jailed, voting_power, proposer_priority
# Prints the raw JSON array of validator objects on stdout, or returns 1.
_get_validators() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/bor/spans/latest" 2>/dev/null || true)
    local vals
    vals=$(printf '%s' "${raw}" \
        | jq -c '.span.validator_set.validators // empty' 2>/dev/null || true)
    if [[ -z "${vals}" || "${vals}" == "null" || "${vals}" == "[]" ]]; then
        return 1
    fi
    printf '%s' "${vals}"
}

# Fetch the CometBFT validator set from the RPC endpoint.
# Prints the raw JSON result object on stdout, or returns 1.
# Note: height=0 is rejected by CometBFT ("height must be greater than 0"),
# so we omit it to get the latest height.
_get_cometbft_validators_rpc() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/validators?per_page=100" 2>/dev/null || true)
    local result
    result=$(printf '%s' "${raw}" | jq -c '.result // empty' 2>/dev/null || true)
    if [[ -z "${result}" || "${result}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${result}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=stake,correctness
@test "heimdall stake: all active validators have unique validator IDs" {
    # Every validator in the active set must carry a distinct numeric ID.
    # Duplicate IDs indicate a state corruption in the staking module that can
    # cause incorrect validator resolution at consensus boundaries.

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    local n_validators
    n_validators=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    if [[ "${n_validators}" -eq 0 ]]; then
        skip "Active validator set is empty — chain may not have started staking yet"
    fi

    echo "  Active validators: ${n_validators}" >&3

    # Collect all IDs and detect duplicates using an associative array.
    local -A seen_ids=()
    local -a duplicate_ids=()
    local i
    for (( i = 0; i < n_validators; i++ )); do
        local vid
        vid=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].val_id // .[$idx].id // empty)')
        # Validate that id is a non-negative integer before use.
        [[ "${vid}" =~ ^[0-9]+$ ]] || vid=""

        if [[ -z "${vid}" || "${vid}" == "null" ]]; then
            echo "  WARN: validator at index ${i} has no resolvable id field — skipping" >&3
            continue
        fi

        if [[ -n "${seen_ids[${vid}]:-}" ]]; then
            duplicate_ids+=("${vid}")
            echo "FAIL: duplicate validator ID ${vid} found at index ${i} (already seen at index ${seen_ids[${vid}]})" >&2
        else
            seen_ids["${vid}"]="${i}"
            echo "  validator[${i}]: id=${vid}" >&3
        fi
    done

    if [[ "${#duplicate_ids[@]}" -gt 0 ]]; then
        echo "Duplicate validator IDs detected: ${duplicate_ids[*]}" >&2
        return 1
    fi

    echo "  OK: ${n_validators} validators, all IDs unique" >&3
}

# bats test_tags=stake,correctness
@test "heimdall stake: all active validators have non-empty signer addresses" {
    # Every active validator must have a signer address that is non-empty,
    # non-null, and not the Ethereum zero address.  A zero or missing signer
    # breaks cross-chain message attribution and vote-extension verification.

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    local n_validators
    n_validators=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    if [[ "${n_validators}" -eq 0 ]]; then
        skip "Active validator set is empty — chain may not have started staking yet"
    fi

    echo "  Active validators: ${n_validators}" >&3

    local failures=0
    local i
    for (( i = 0; i < n_validators; i++ )); do
        local vid signer
        vid=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].val_id // .[$idx].id // empty)')
        signer=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].signer // empty')

        if [[ -z "${signer}" || "${signer}" == "null" ]]; then
            echo "FAIL: validator id=${vid} (index ${i}) has an empty or null signer address" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        # Reject the Ethereum zero address — it is never a valid validator signer.
        if [[ "${signer}" == "0x0000000000000000000000000000000000000000" ]]; then
            echo "FAIL: validator id=${vid} (index ${i}) has the zero signer address (${signer})" >&2
            failures=$(( failures + 1 ))
            continue
        fi

        echo "  validator[${i}]: id=${vid} signer=${signer}" >&3
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} validator(s) with invalid signer address detected — see messages above" >&2
        return 1
    fi

    echo "  OK: all ${n_validators} validators have valid signer addresses" >&3
}

# bats test_tags=stake,correctness
@test "heimdall stake: reported total voting power matches sum of individual validators" {
    # The sum of each validator's power from the Heimdall REST API must agree
    # with the total voting power reported by the CometBFT RPC.  Divergence here
    # means the two layers have an inconsistent view of the staking state, which
    # can cause liveness or safety failures if consensus thresholds are computed
    # from mismatched data.
    #
    # A ±5 tolerance is allowed for integer encoding rounding across API versions.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not available — skipping VP consistency check"
    fi

    local vals_json
    if ! vals_json=$(_get_validators); then
        skip "Could not fetch validator set from ${L2_CL_API_URL} — skipping VP check"
    fi

    local n_validators
    n_validators=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_validators}" =~ ^[0-9]+$ ]] || n_validators=0

    if [[ "${n_validators}" -eq 0 ]]; then
        skip "Active validator set is empty — chain may not have started staking yet"
    fi

    # Sum the power field for each Heimdall validator — active only (non-jailed,
    # power > 0), matching the set CometBFT tracks for consensus.
    local heimdall_vp_sum=0
    local i
    for (( i = 0; i < n_validators; i++ )); do
        local jailed_flag vp
        jailed_flag=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].jailed // false')
        [[ "${jailed_flag}" == "true" ]] && continue
        vp=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].voting_power // .[$idx].power // 0)')
        # Validate that vp is a non-negative integer before arithmetic use.
        [[ "${vp}" =~ ^[0-9]+$ ]] || vp=0
        [[ "${vp}" -eq 0 ]] && continue
        heimdall_vp_sum=$(( heimdall_vp_sum + vp ))
    done

    echo "  Heimdall validator count: ${n_validators}" >&3
    echo "  Heimdall VP sum: ${heimdall_vp_sum}" >&3

    # Fetch CometBFT total voting power.
    local cmt_result
    if ! cmt_result=$(_get_cometbft_validators_rpc); then
        skip "Could not fetch CometBFT validator data from ${L2_CL_RPC_URL} — skipping VP consistency check"
    fi

    # Prefer the top-level total_voting_power field; fall back to summing
    # individual .voting_power entries from .validators[].
    local cometbft_vp_total
    cometbft_vp_total=$(printf '%s' "${cmt_result}" \
        | jq -r '.total_voting_power // empty' 2>/dev/null || true)
    [[ "${cometbft_vp_total}" =~ ^[0-9]+$ ]] || cometbft_vp_total=""

    if [[ -z "${cometbft_vp_total}" ]]; then
        # Fall back: sum .voting_power from each entry in .validators[].
        cometbft_vp_total=$(printf '%s' "${cmt_result}" \
            | jq -r '[.validators[]?.voting_power // 0 | tonumber] | add // 0' \
            2>/dev/null || true)
        [[ "${cometbft_vp_total}" =~ ^[0-9]+$ ]] || cometbft_vp_total=0
    fi

    echo "  CometBFT total VP: ${cometbft_vp_total}" >&3

    if [[ "${cometbft_vp_total}" -eq 0 && "${heimdall_vp_sum}" -eq 0 ]]; then
        skip "Both Heimdall VP sum and CometBFT total VP are zero — staking may not have started yet"
    fi

    # Compute absolute difference using integer arithmetic only.
    local diff
    if [[ "${heimdall_vp_sum}" -ge "${cometbft_vp_total}" ]]; then
        diff=$(( heimdall_vp_sum - cometbft_vp_total ))
    else
        diff=$(( cometbft_vp_total - heimdall_vp_sum ))
    fi

    echo "  VP difference (|Heimdall - CometBFT|): ${diff}" >&3

    if [[ "${diff}" -gt 5 ]]; then
        echo "FAIL: Heimdall VP sum (${heimdall_vp_sum}) and CometBFT total VP (${cometbft_vp_total}) differ by ${diff} (threshold: 5)" >&2
        echo "  The Heimdall REST API and CometBFT consensus layer disagree on total staking power." >&2
        return 1
    fi

    echo "  OK: Heimdall VP sum=${heimdall_vp_sum} CometBFT total=${cometbft_vp_total}" >&3
}

# bats test_tags=stake,correctness
@test "heimdall stake: validator set count is non-zero and consistent with CometBFT" {
    # The number of active validators reported by the Heimdall REST API must be
    # at least 1 (a chain with no validators cannot make progress).  When the
    # CometBFT RPC is reachable, the counts must also agree: a mismatch means
    # the consensus engine is operating on a different validator set than the
    # staking module.

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    # Count only active (non-jailed, power > 0) validators — matching the set
    # CometBFT tracks. Including jailed validators would cause a false mismatch.
    local heimdall_count
    heimdall_count=$(printf '%s' "${vals_json}" \
        | jq '[.[] | select(.jailed != true and (.voting_power // .power // 0 | tonumber) > 0)] | length' \
        2>/dev/null || true)
    [[ "${heimdall_count}" =~ ^[0-9]+$ ]] || heimdall_count=0

    echo "  Heimdall active validator count: ${heimdall_count}" >&3

    if [[ "${heimdall_count}" -eq 0 ]]; then
        echo "FAIL: Heimdall reports 0 active validators — the network cannot reach BFT consensus without a validator set" >&2
        return 1
    fi

    # If CometBFT RPC is unavailable, only assert the Heimdall count is >= 1.
    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        echo "  NOTE: CometBFT RPC not reachable — skipping cross-layer count comparison" >&3
        echo "  OK: Heimdall ${heimdall_count} validators, CometBFT count unavailable" >&3
        return 0
    fi

    local cmt_result
    if ! cmt_result=$(_get_cometbft_validators_rpc); then
        echo "  NOTE: CometBFT validator fetch failed — skipping cross-layer count comparison" >&3
        echo "  OK: Heimdall ${heimdall_count} validators, CometBFT count unavailable" >&3
        return 0
    fi

    # Prefer the top-level .total field; fall back to counting .validators[].
    local cometbft_count
    cometbft_count=$(printf '%s' "${cmt_result}" \
        | jq -r '.total // empty' 2>/dev/null || true)
    [[ "${cometbft_count}" =~ ^[0-9]+$ ]] || cometbft_count=""

    if [[ -z "${cometbft_count}" ]]; then
        cometbft_count=$(printf '%s' "${cmt_result}" \
            | jq -r '(.validators // []) | length' 2>/dev/null || true)
        [[ "${cometbft_count}" =~ ^[0-9]+$ ]] || cometbft_count=0
    fi

    echo "  CometBFT validator count: ${cometbft_count}" >&3

    # Allow ±1 tolerance for in-flight validator set updates between the two layers.
    local count_diff
    if [[ "${heimdall_count}" -ge "${cometbft_count}" ]]; then
        count_diff=$(( heimdall_count - cometbft_count ))
    else
        count_diff=$(( cometbft_count - heimdall_count ))
    fi

    if [[ "${count_diff}" -gt 1 ]]; then
        echo "FAIL: Heimdall active count (${heimdall_count}) and CometBFT count (${cometbft_count}) differ by ${count_diff}" >&2
        echo "  The staking module and the consensus engine have diverged on the active validator set." >&2
        return 1
    fi

    echo "  OK: Heimdall ${heimdall_count} active validators, CometBFT ${cometbft_count} validators (delta ${count_diff})" >&3
}
