#!/usr/bin/env bats
# bats file_tags=heimdall,stake,correctness,safety

# Validator Set Safety
# ====================
# Verifies that Heimdall's validator set remains in a safe state that
# allows consensus to proceed without panicking or halting.
#
# An empty active validator set causes PrepareProposal to error, which
# halts the chain. Excessive jailing risks dropping below quorum.
# Integer overflow in voting power or proposer priority causes panics in
# the validator set logic, which also halt the chain.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - Heimdall REST API reachable at L2_CL_API_URL
#   - At least 1 active validator registered in Heimdall's stake module
#
# RUN: bats tests/heimdall/stake/validator-set-safety.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../core/helpers/pos-setup.bash"
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
        echo "WARNING: Heimdall span validator set not reachable or returned no validators at ${L2_CL_API_URL} — all safety tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_stake_unavailable"
    else
        echo "Heimdall span validator_set reachable; validators=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_stake_unavailable"
    fi

    # Probe the CometBFT RPC separately — tests 4 and 5 require it.
    local rpc_probe
    rpc_probe=$(curl -s -m 15 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${rpc_probe}" ]]; then
        echo "NOTE: CometBFT RPC not reachable at ${L2_CL_RPC_URL} — tests requiring RPC will be skipped." >&3
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
    load "../../../core/helpers/pos-setup.bash"
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

# bats test_tags=stake,correctness,safety,s0
@test "heimdall stake: active validator set is never empty" {
    # An empty active validator set causes filterVoteExtensions (called from
    # PrepareProposal) to return the error "no validators in filterVoteExtensions"
    # after the Phuket hardfork activates.  PrepareProposal propagates that error
    # back to CometBFT, which means the proposer cannot construct a valid block —
    # the chain halts.
    #
    # A validator is "active" when it is not jailed AND has power > 0.
    # The IsCurrentValidator check in the Go code is:
    #   !v.Jailed && v.StartEpoch <= currentEpoch && (v.EndEpoch == 0 || v.EndEpoch > currentEpoch) && v.VotingPower > 0
    # The REST API reflects this: jailed validators are returned with jailed=true
    # and typically power=0.

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    local n_total
    n_total=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_total}" =~ ^[0-9]+$ ]] || n_total=0

    echo "  Total validators returned by API: ${n_total}" >&3

    # Count active (non-jailed, power > 0) validators.
    local active_count=0
    local i
    for (( i = 0; i < n_total; i++ )); do
        local jailed power
        jailed=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].jailed // false')
        power=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].voting_power // .[$idx].power // 0)')
        [[ "${power}" =~ ^[0-9]+$ ]] || power=0

        if [[ "${jailed}" != "true" && "${power}" -gt 0 ]]; then
            active_count=$(( active_count + 1 ))
        fi
    done

    echo "  Active (non-jailed, power>0) validators: ${active_count}" >&3

    if [[ "${active_count}" -eq 0 ]]; then
        echo "FAIL: active validator set is empty — PrepareProposal will error and chain will halt" >&2
        echo "  filterVoteExtensions returns 'no validators in filterVoteExtensions' when validatorsCount == 0," >&2
        echo "  which propagates as an error from PrepareProposal, preventing any block from being proposed." >&2
        return 1
    fi

    echo "  OK: ${active_count} active (non-jailed, power>0) validators" >&3
}

# bats test_tags=stake,correctness,safety,s0
@test "heimdall stake: no more than N validators jailed simultaneously" {
    # BFT consensus requires 2/3 of voting power to commit a block.  If more
    # than 1/3 of validators are jailed (and therefore excluded from signing),
    # the remaining active set may fall below the 2/3 quorum threshold,
    # stalling or halting the chain.
    #
    # This test uses integer arithmetic to avoid floating-point imprecision:
    #   (jailed_count * 3) > total_count  ⟺  jailed_count / total_count > 1/3

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    local total_count
    total_count=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${total_count}" =~ ^[0-9]+$ ]] || total_count=0

    if [[ "${total_count}" -eq 0 ]]; then
        skip "No validators found — chain may not have started staking yet"
    fi

    echo "  Total validators: ${total_count}" >&3

    local jailed_count=0
    local i
    for (( i = 0; i < total_count; i++ )); do
        local jailed
        jailed=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].jailed // false')
        if [[ "${jailed}" == "true" ]]; then
            jailed_count=$(( jailed_count + 1 ))
        fi
    done

    echo "  Jailed validators: ${jailed_count}" >&3

    # Integer check: jailed > 1/3 of total ⟺ jailed * 3 > total
    local jailed_times_3
    jailed_times_3=$(( jailed_count * 3 ))

    echo "  jailed_count * 3 = ${jailed_times_3}, total = ${total_count}" >&3

    if [[ "${jailed_times_3}" -gt "${total_count}" ]]; then
        echo "FAIL: more than 1/3 of validators are jailed — BFT quorum is at risk" >&2
        echo "  Jailed: ${jailed_count} out of ${total_count} total (jailed*3=${jailed_times_3} > total=${total_count})" >&2
        echo "  BFT consensus requires 2/3 of validators to sign; excessive jailing can push the active" >&2
        echo "  set below quorum, causing the chain to stall waiting for a commit that can never arrive." >&2
        return 1
    fi

    echo "  OK: ${jailed_count} jailed out of ${total_count} total (jailed_count * 3 = ${jailed_times_3} <= total = ${total_count})" >&3
}

# bats test_tags=stake,correctness,safety
@test "heimdall stake: validator voting power is within safe integer bounds" {
    # The ValidatorSet arithmetic in validator_set.go uses int64 throughout.
    # The BFT quorum check computes:
    #   committed_vp * 3 > total_vp * 2
    # If total_vp >= 2^62, then total_vp * 2 overflows int64 (max ~9.2*10^18),
    # causing undefined behaviour or a panic in the priority/quorum logic.
    #
    # MaxTotalVotingPower in the Go code is math.MaxInt64/8 = 2^60 - 1, but
    # we test against 2^62 - 1 as a conservative upper bound for the quorum
    # multiplication (total_vp * 3 must not overflow int64).
    #
    # Individual VP is also checked against 2^53 (JS-safe integer) to guard
    # against silent precision loss in JSON parsers that deserialize uint64
    # into IEEE-754 doubles (which have 53-bit mantissas).

    # 2^53 = 9007199254740992
    local MAX_SAFE_INDIVIDUAL_VP=9007199254740992
    # 2^62 - 1 = 4611686018427387903
    local MAX_SAFE_VP=4611686018427387903

    local vals_json
    if ! vals_json=$(_get_validators); then
        fail "Could not fetch validator set from ${L2_CL_API_URL} — API may be down or no validators registered"
    fi

    local n_total
    n_total=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_total}" =~ ^[0-9]+$ ]] || n_total=0

    if [[ "${n_total}" -eq 0 ]]; then
        skip "No validators found — chain may not have started staking yet"
    fi

    echo "  Total validators: ${n_total}" >&3

    local failures=0
    local total_vp=0
    local i
    for (( i = 0; i < n_total; i++ )); do
        local vid power
        vid=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].val_id // .[$idx].id // empty)')
        power=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].voting_power // .[$idx].power // 0)')
        [[ "${power}" =~ ^[0-9]+$ ]] || power=0

        echo "  validator id=${vid}: power=${power}" >&3

        # Check individual VP against 2^53 (JS-safe integer boundary).
        if [[ "${power}" -gt "${MAX_SAFE_INDIVIDUAL_VP}" ]]; then
            echo "FAIL: validator id=${vid} (index ${i}) has power=${power} exceeding JS-safe integer bound (2^53=${MAX_SAFE_INDIVIDUAL_VP})" >&2
            echo "  JSON parsers that use IEEE-754 double for uint64 will silently lose precision on this value." >&2
            failures=$(( failures + 1 ))
        fi

        total_vp=$(( total_vp + power ))
    done

    echo "  Total VP sum: ${total_vp}" >&3

    # Check total VP against 2^62 - 1.
    # We check total_vp rather than total_vp * 3 to avoid overflow in bash arithmetic.
    if [[ "${total_vp}" -gt "${MAX_SAFE_VP}" ]]; then
        echo "FAIL: total voting power ${total_vp} exceeds safe bound (2^62-1=${MAX_SAFE_VP})" >&2
        echo "  BFT quorum check computes total_vp*3; if total_vp > 2^62, the multiplication" >&2
        echo "  overflows int64, producing a panic in the validator set priority logic." >&2
        failures=$(( failures + 1 ))
    fi

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} voting power violation(s) detected — see messages above" >&2
        return 1
    fi

    echo "  OK: total VP = ${total_vp} (well within int64 overflow bound of 2^62)" >&3
}

# bats test_tags=stake,correctness,safety
@test "heimdall stake: validator proposer priority values are within safe range" {
    # IncrementProposerPriority in validator_set.go accumulates ProposerPriority
    # across rounds using int64 arithmetic (safeAddClip / safeSubClip clip to
    # MinInt64/MaxInt64 on overflow).  However, computeAvgProposerPriority uses
    # big.Int for the sum but then panics if the average cannot be represented
    # as int64.
    #
    # A priority that has escaped the [-MaxTotalVotingPower*2, MaxTotalVotingPower*2]
    # window indicates that the priority normalisation logic is no longer keeping
    # values bounded, which can produce proposer-selection instability or panics.
    #
    # We use [-2^53, 2^53] as the safe range for this test — values outside that
    # range are still technically representable as int64 but would signal a severe
    # divergence from expected priority magnitudes and may cause overflow in
    # intermediate arithmetic on systems that decode them via JSON floats.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not available — skipping proposer priority check"
    fi

    # 2^53 = 9007199254740992
    local MAX_SAFE_PRIORITY=9007199254740992
    # Negative bound: -2^53 = -9007199254740992
    local MIN_SAFE_PRIORITY=-9007199254740992

    local cmt_result
    if ! cmt_result=$(_get_cometbft_validators_rpc); then
        skip "Could not fetch CometBFT validator data from ${L2_CL_RPC_URL} — skipping priority check"
    fi

    local n_cmt
    n_cmt=$(printf '%s' "${cmt_result}" \
        | jq -r '(.validators // []) | length' 2>/dev/null || true)
    [[ "${n_cmt}" =~ ^[0-9]+$ ]] || n_cmt=0

    if [[ "${n_cmt}" -eq 0 ]]; then
        skip "CometBFT returned no validators — skipping priority check"
    fi

    echo "  CometBFT validators with priority data: ${n_cmt}" >&3

    local failures=0
    local i
    for (( i = 0; i < n_cmt; i++ )); do
        local addr priority
        addr=$(printf '%s' "${cmt_result}" \
            | jq -r --argjson idx "${i}" '.validators[$idx].address // empty')
        priority=$(printf '%s' "${cmt_result}" \
            | jq -r --argjson idx "${i}" '.validators[$idx].proposer_priority // 0')

        # proposer_priority is a signed int64; validate it looks numeric (may be negative).
        if [[ ! "${priority}" =~ ^-?[0-9]+$ ]]; then
            echo "  WARN: validator at index ${i} (addr=${addr}) has non-numeric proposer_priority='${priority}' — skipping" >&3
            continue
        fi

        echo "  validator[${i}] addr=${addr}: proposer_priority=${priority}" >&3

        # Check against [-2^53, 2^53].
        # Bash arithmetic handles signed 64-bit integers natively.
        if [[ "${priority}" -gt "${MAX_SAFE_PRIORITY}" || "${priority}" -lt "${MIN_SAFE_PRIORITY}" ]]; then
            echo "FAIL: validator addr=${addr} (index ${i}) has proposer_priority=${priority} outside safe range [${MIN_SAFE_PRIORITY}, ${MAX_SAFE_PRIORITY}]" >&2
            echo "  Proposer priority values this large indicate the normalisation loop is not bounding" >&2
            echo "  priorities correctly; this can cause panics in computeAvgProposerPriority." >&2
            failures=$(( failures + 1 ))
        fi
    done

    if [[ "${failures}" -gt 0 ]]; then
        echo "${failures} proposer priority violation(s) detected — see messages above" >&2
        return 1
    fi

    echo "  OK: all ${n_cmt} validators have safe proposer priority values" >&3
}

# bats test_tags=stake,correctness,safety
@test "heimdall stake: CometBFT validator set matches Heimdall active validator set" {
    # PrepareProposal calls getValidatorSetForHeight, which fetches the stored
    # ValidatorSet from the Heimdall stake module.  filterVoteExtensions then
    # uses that set to verify vote extensions from CometBFT validators.
    #
    # If the two layers have diverged on validator count, vote-extension
    # verification will either reject valid extensions (causing repeated
    # PrepareProposal failures) or accept extensions from unknown validators
    # (a safety hazard).  A count mismatch of more than ±1 therefore signals
    # a dangerous divergence.  (±1 is allowed because a validator update
    # delivered in EndBlock takes one additional block to be reflected in
    # the CometBFT active set.)

    if [[ "$(cat "${BATS_FILE_TMPDIR}/cometbft_rpc_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC not available — skipping cross-layer validator set comparison"
    fi

    local vals_json
    if ! vals_json=$(_get_validators); then
        skip "Could not fetch Heimdall validator set from ${L2_CL_API_URL} — skipping comparison"
    fi

    local n_total
    n_total=$(printf '%s' "${vals_json}" | jq 'length')
    [[ "${n_total}" =~ ^[0-9]+$ ]] || n_total=0

    # Count active Heimdall validators (non-jailed, power > 0).
    local heimdall_active=0
    local -A heimdall_signers=()
    local i
    for (( i = 0; i < n_total; i++ )); do
        local jailed power signer
        jailed=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '.[$idx].jailed // false')
        power=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].voting_power // .[$idx].power // 0)')
        signer=$(printf '%s' "${vals_json}" \
            | jq -r --argjson idx "${i}" '(.[$idx].signer // "") | ascii_downcase')
        [[ "${power}" =~ ^[0-9]+$ ]] || power=0

        if [[ "${jailed}" != "true" && "${power}" -gt 0 ]]; then
            heimdall_active=$(( heimdall_active + 1 ))
            if [[ -n "${signer}" && "${signer}" != "null" ]]; then
                heimdall_signers["${signer}"]=1
            fi
        fi
    done

    echo "  Heimdall active (non-jailed, power>0) validators: ${heimdall_active}" >&3

    if [[ "${heimdall_active}" -eq 0 ]]; then
        skip "Heimdall reports no active validators — skipping cross-layer comparison"
    fi

    # Fetch CometBFT validator count.
    local cmt_result
    if ! cmt_result=$(_get_cometbft_validators_rpc); then
        skip "Could not fetch CometBFT validator data from ${L2_CL_RPC_URL} — skipping comparison"
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

    if [[ "${cometbft_count}" -eq 0 ]]; then
        skip "CometBFT returned 0 validators — skipping cross-layer comparison"
    fi

    # Compute the absolute difference.
    local diff
    if [[ "${heimdall_active}" -ge "${cometbft_count}" ]]; then
        diff=$(( heimdall_active - cometbft_count ))
    else
        diff=$(( cometbft_count - heimdall_active ))
    fi

    echo "  Count difference |Heimdall - CometBFT| = ${diff}" >&3

    # Allow ±1 for in-flight EndBlock validator updates (one-block propagation lag).
    if [[ "${diff}" -gt 1 ]]; then
        echo "FAIL: Heimdall active validator count (${heimdall_active}) and CometBFT validator count (${cometbft_count}) differ by ${diff} (threshold: 1)" >&2
        echo "  The staking module and consensus engine have diverged on the active validator set." >&2
        echo "  filterVoteExtensions in PrepareProposal uses the Heimdall set to verify CometBFT VEs;" >&2
        echo "  a count mismatch this large means extensions from unknown validators will be accepted" >&2
        echo "  or valid extensions from known validators will be wrongly rejected." >&2
        return 1
    fi

    echo "  OK: Heimdall ${heimdall_active} active validators, CometBFT ${cometbft_count} validators (count match)" >&3
}
