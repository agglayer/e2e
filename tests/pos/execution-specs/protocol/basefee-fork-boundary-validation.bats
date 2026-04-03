#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,basefee,fork-activation

# Base Fee Fork Boundary Validation
# ===================================
# Validates that Bor's base fee calculation changes are correctly applied
# across fork boundaries in the kurtosis devnet.
#
# Critical base fee parameter changes across forks:
#   - BaseFeeChangeDenominator: 8 (default) -> 16 (Delhi) -> 64 (Bhilai) -> configurable (Lisovo)
#   - Target gas percentage: 50% (default) -> 65% (Dandeli)
#   - Base fee validation: strict match (pre-Lisovo) -> bounded within 5% (post-Lisovo)
#   - Minimum base fee: 7 wei (enforced by bor)
#
# These tests query specific block numbers at fork boundaries to verify
# correct base fee transitions and catch S0 risks from misconfigured forks.

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests — Erigon discovery)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    export L2_ERIGON_RPC_URL
    _discover_erigon_rpc || {
        echo "WARNING: No Erigon RPC node found — cross-client test will be skipped." >&3
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # Fork block defaults for the kurtosis devnet.
    _setup_fork_env

    # Minimum base fee enforced by bor (wei).
    MIN_BASE_FEE=7
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Get base fee (decimal) for a given block number.
_get_base_fee() {
    local block_num="$1"
    local rpc="${2:-$L2_RPC_URL}"
    local base_fee_hex
    base_fee_hex=$(cast block "$block_num" --json --rpc-url "$rpc" | jq -r '.baseFeePerGas // empty')
    if [[ -z "$base_fee_hex" ]]; then
        echo ""
        return 1
    fi
    printf "%d" "$base_fee_hex"
}

# Get block data fields (baseFeePerGas, gasUsed, gasLimit) as decimal values.
# Sets variables: _bf, _gu, _gl
_get_block_data() {
    local block_num="$1"
    local rpc="${2:-$L2_RPC_URL}"
    local block_json
    block_json=$(cast block "$block_num" --json --rpc-url "$rpc")

    _bf=$(printf "%d" "$(echo "$block_json" | jq -r '.baseFeePerGas // "0x0"')")
    _gu=$(printf "%d" "$(echo "$block_json" | jq -r '.gasUsed // "0x0"')")
    _gl=$(printf "%d" "$(echo "$block_json" | jq -r '.gasLimit // "0x0"')")
}

# ────────────────────────────────────────────────────────────────────────────
# Test 1: Base fee is non-zero at all fork boundaries
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation
@test "basefee-fork: base fee is non-zero at all fork boundaries" {
    # Collect all fork blocks that are above genesis and not disabled (999999999).
    local -a fork_blocks=()
    [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 ]] && fork_blocks+=("${FORK_RIO}")
    [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 ]] && fork_blocks+=("${FORK_DANDELI}")
    [[ "${FORK_LISOVO}" -gt 0 && "${FORK_LISOVO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO}")
    [[ "${FORK_LISOVO_PRO}" -gt 0 && "${FORK_LISOVO_PRO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO_PRO}")
    [[ "${FORK_GIUGLIANO}" -gt 0 && "${FORK_GIUGLIANO}" -lt 999999999 ]] && fork_blocks+=("${FORK_GIUGLIANO}")

    if [[ "${#fork_blocks[@]}" -eq 0 ]]; then
        skip "All forks are at genesis or disabled -- no boundaries to check"
    fi

    # Wait for chain to reach the last fork block.
    local max_fork=0
    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -gt "$max_fork" ]] && max_fork="$fb"
    done
    _wait_for_block_on "$max_fork" "$L2_RPC_URL" "L2_RPC"

    local failures=0
    for fb in "${fork_blocks[@]}"; do
        local base_fee
        base_fee=$(_get_base_fee "$fb")

        if [[ -z "$base_fee" ]]; then
            echo "FAIL: Block $fb (fork boundary) has no baseFeePerGas field" >&2
            failures=$((failures + 1))
            continue
        fi

        if [[ "$base_fee" -le 0 ]]; then
            echo "FAIL: Block $fb (fork boundary) has baseFee=$base_fee (must be > 0)" >&2
            failures=$((failures + 1))
        else
            echo "OK: Block $fb baseFee=$base_fee" >&3
        fi
    done

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures fork boundary block(s) have zero or missing baseFee" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 2: Base fee is at least 7 wei (minimum) across all blocks
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation
@test "basefee-fork: base fee is at least 7 wei (minimum) across all blocks" {
    # Spot-check base fee at fork boundaries, mid-fork blocks, and recent blocks.
    local -a check_blocks=()

    # Fork boundary blocks (exclude disabled forks at 999999999)
    [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 ]] && check_blocks+=("${FORK_RIO}")
    [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 ]] && check_blocks+=("${FORK_DANDELI}")
    [[ "${FORK_LISOVO}" -gt 0 && "${FORK_LISOVO}" -lt 999999999 ]] && check_blocks+=("${FORK_LISOVO}")
    [[ "${FORK_LISOVO_PRO}" -gt 0 && "${FORK_LISOVO_PRO}" -lt 999999999 ]] && check_blocks+=("${FORK_LISOVO_PRO}")
    [[ "${FORK_GIUGLIANO}" -gt 0 && "${FORK_GIUGLIANO}" -lt 999999999 ]] && check_blocks+=("${FORK_GIUGLIANO}")

    # Mid-fork sample blocks (between fork boundaries)
    if [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 && "${FORK_DANDELI}" -gt "${FORK_RIO}" && "${FORK_DANDELI}" -lt 999999999 ]]; then
        check_blocks+=("$(( (FORK_RIO + FORK_DANDELI) / 2 ))")
    fi
    if [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 && "${FORK_LISOVO}" -gt "${FORK_DANDELI}" && "${FORK_LISOVO}" -lt 999999999 ]]; then
        check_blocks+=("$(( (FORK_DANDELI + FORK_LISOVO) / 2 ))")
    fi

    # Recent blocks
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")
    check_blocks+=("$latest" "$((latest > 1 ? latest - 1 : 1))")

    # Wait for the latest needed block
    local max_block=0
    for b in "${check_blocks[@]}"; do
        [[ "$b" -gt "$max_block" ]] && max_block="$b"
    done
    _wait_for_block_on "$max_block" "$L2_RPC_URL" "L2_RPC"

    local failures=0
    for b in "${check_blocks[@]}"; do
        [[ "$b" -le 0 ]] && continue
        local base_fee
        base_fee=$(_get_base_fee "$b") || continue

        if [[ -z "$base_fee" ]]; then
            continue
        fi

        if [[ "$base_fee" -lt "$MIN_BASE_FEE" ]]; then
            echo "FAIL: Block $b has baseFee=$base_fee (must be >= $MIN_BASE_FEE wei)" >&2
            failures=$((failures + 1))
        else
            echo "OK: Block $b baseFee=$base_fee >= $MIN_BASE_FEE wei" >&3
        fi
    done

    echo "Checked ${#check_blocks[@]} blocks, $failures below minimum" >&3

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures block(s) have baseFee below minimum of $MIN_BASE_FEE wei" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 3: Consecutive blocks have valid base fee transition pre-Lisovo
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation,eip1559
@test "basefee-fork: consecutive blocks have valid base fee transition pre-Lisovo" {
    # Pre-Lisovo, baseFee[N] must be exactly calculable from block[N-1]:
    #   target = gasLimit / 2  (50% pre-Dandeli, 65% post-Dandeli via target calc below)
    #   baseFee[N] = baseFee[N-1] + baseFee[N-1] * (gasUsed[N-1] - target) / (target * denominator)
    #
    # Post-Bhilai the denominator is 64. In the kurtosis devnet, Delhi and Bhilai
    # are at genesis, so the entire pre-Lisovo range uses denominator 64.

    if [[ "${FORK_LISOVO}" -le 0 ]]; then
        skip "Lisovo at genesis -- no pre-Lisovo range to check"
    fi

    # Pick a window of 10 consecutive blocks well before Lisovo but after
    # all denominator-changing forks are active.
    local window_start
    if [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 && "${FORK_DANDELI}" -lt "${FORK_LISOVO}" ]]; then
        # Use blocks right after Dandeli but before Lisovo
        window_start=$(( FORK_DANDELI + 2 ))
    elif [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 ]]; then
        window_start=$(( FORK_RIO + 2 ))
    else
        window_start=2
    fi

    local window_end=$(( window_start + 9 ))
    if [[ "$window_end" -ge "${FORK_LISOVO}" ]]; then
        window_end=$(( FORK_LISOVO - 1 ))
    fi
    if [[ "$window_end" -le "$window_start" ]]; then
        skip "Not enough blocks between last denominator fork and Lisovo"
    fi

    _wait_for_block_on "$window_end" "$L2_RPC_URL" "L2_RPC"

    local denominator=64
    local violations=0
    local checks=0

    # Determine if we are post-Dandeli (target = 65%) or pre-Dandeli (target = 50%)
    local use_dandeli_target=false
    if [[ "${FORK_DANDELI}" -gt 0 && "$window_start" -ge "${FORK_DANDELI}" ]]; then
        use_dandeli_target=true
    fi

    for ((bn = window_start + 1; bn <= window_end; bn++)); do
        _get_block_data "$((bn - 1))"
        local parent_bf=$_bf parent_gu=$_gu parent_gl=$_gl

        _get_block_data "$bn"
        local child_bf=$_bf

        [[ "$parent_bf" -lt 1 || "$parent_gl" -lt 1 ]] && continue
        checks=$((checks + 1))

        # Calculate target gas
        local target_gas
        if [[ "$use_dandeli_target" == "true" ]]; then
            # 65% target: target = gasLimit * 65 / 100
            target_gas=$(( parent_gl * 65 / 100 ))
        else
            # 50% target (standard EIP-1559)
            target_gas=$(( parent_gl / 2 ))
        fi
        [[ "$target_gas" -lt 1 ]] && continue

        # Compute expected base fee
        local expected_bf
        if [[ "$parent_gu" -eq "$target_gas" ]]; then
            expected_bf="$parent_bf"
        elif [[ "$parent_gu" -gt "$target_gas" ]]; then
            local delta=$(( parent_gu - target_gas ))
            local increment=$(( parent_bf * delta / target_gas / denominator ))
            [[ "$increment" -lt 1 ]] && increment=1
            expected_bf=$(( parent_bf + increment ))
        else
            local delta=$(( target_gas - parent_gu ))
            local decrement=$(( parent_bf * delta / target_gas / denominator ))
            expected_bf=$(( parent_bf - decrement ))
            [[ "$expected_bf" -lt 1 ]] && expected_bf=1
        fi

        # Enforce minimum
        [[ "$expected_bf" -lt "$MIN_BASE_FEE" ]] && expected_bf="$MIN_BASE_FEE"

        if [[ "$child_bf" -ne "$expected_bf" ]]; then
            echo "Block $bn: baseFee=$child_bf expected=$expected_bf (parent bf=$parent_bf gu=$parent_gu gl=$parent_gl target=$target_gas)" >&2
            violations=$((violations + 1))
        fi
    done

    echo "Checked $checks block pairs (blocks $window_start..$window_end), violations: $violations" >&3

    if [[ "$violations" -gt 0 ]]; then
        echo "$violations / $checks blocks have incorrect deterministic baseFee (pre-Lisovo)" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 4: Base fee is within 5% boundary post-Lisovo
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation,pip79
@test "basefee-fork: base fee is within 5% boundary post-Lisovo" {
    # After Lisovo, PIP-79 replaces strict deterministic validation with
    # bounded validation: baseFee changes are bounded within +/-5% per block.
    #   lowerBound = parentBaseFee * 95 / 100
    #   upperBound = parentBaseFee * 105 / 100

    if [[ "${FORK_LISOVO}" -le 0 || "${FORK_LISOVO}" -ge 999999999 ]]; then
        skip "Lisovo at genesis or disabled -- no post-Lisovo range to check"
    fi

    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Check 20 blocks starting from Lisovo activation
    local check_start=$(( FORK_LISOVO + 1 ))
    local check_end=$(( FORK_LISOVO + 20 ))
    if [[ "$check_end" -gt "$latest" ]]; then
        check_end="$latest"
    fi
    if [[ "$check_start" -ge "$check_end" ]]; then
        skip "Not enough post-Lisovo blocks to validate (need chain past block $check_end)"
    fi

    _wait_for_block_on "$check_end" "$L2_RPC_URL" "L2_RPC"

    local violations=0
    local checks=0

    for ((bn = check_start; bn <= check_end; bn++)); do
        local parent_bf child_bf
        parent_bf=$(_get_base_fee "$((bn - 1))")
        child_bf=$(_get_base_fee "$bn")

        [[ -z "$parent_bf" || -z "$child_bf" ]] && continue
        [[ "$parent_bf" -lt 1 ]] && continue
        checks=$((checks + 1))

        local lower_bound=$(( parent_bf * 95 / 100 ))
        local upper_bound=$(( parent_bf * 105 / 100 ))
        [[ "$lower_bound" -lt 1 ]] && lower_bound=1

        if [[ "$child_bf" -lt "$lower_bound" || "$child_bf" -gt "$upper_bound" ]]; then
            echo "Block $bn: baseFee=$child_bf outside +/-5% of parent=$parent_bf (range: [$lower_bound, $upper_bound])" >&2
            violations=$((violations + 1))
        fi
    done

    echo "Checked $checks post-Lisovo block pairs, violations: $violations" >&3

    if [[ "$violations" -gt 0 ]]; then
        echo "$violations / $checks blocks violate PIP-79 +/-5% bound post-Lisovo" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 5: Target gas percentage changes at Dandeli
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation,dandeli
@test "basefee-fork: target gas percentage changes at Dandeli" {
    # At Dandeli, the EIP-1559 target gas usage shifts from 50% to 65%.
    # This means blocks using 65% of the gas limit should result in stable
    # base fee (no change). Below 65% usage, base fee should decrease.
    #
    # We verify this by checking that the base fee calculation at blocks
    # right after Dandeli is consistent with a 65% target, not 50%.

    _require_min_bor "2.5.6"

    if [[ "${FORK_DANDELI}" -le 0 || "${FORK_DANDELI}" -ge 999999999 ]]; then
        skip "Dandeli at genesis or disabled"
    fi
    if [[ "${FORK_LISOVO}" -le 0 || "${FORK_LISOVO}" -ge 999999999 || "${FORK_LISOVO}" -le "$(( FORK_DANDELI + 5 ))" ]]; then
        skip "Not enough blocks between Dandeli and Lisovo to verify target change"
    fi

    _wait_for_block_on "$(( FORK_DANDELI + 5 ))" "$L2_RPC_URL" "L2_RPC"

    # Check blocks right after Dandeli activation.
    # The base fee formula with 65% target should produce different results
    # than with 50% target when gasUsed is between 50-65% of gasLimit.
    local denominator=64
    local target_match_65=0
    local target_match_50=0
    local checks=0

    for ((bn = FORK_DANDELI + 1; bn <= FORK_DANDELI + 5 && bn < FORK_LISOVO; bn++)); do
        _get_block_data "$((bn - 1))"
        local parent_bf=$_bf parent_gu=$_gu parent_gl=$_gl

        _get_block_data "$bn"
        local child_bf=$_bf

        [[ "$parent_bf" -lt 1 || "$parent_gl" -lt 1 ]] && continue
        checks=$((checks + 1))

        # Compute expected base fee with 65% target
        local target_65=$(( parent_gl * 65 / 100 ))
        local expected_65
        if [[ "$parent_gu" -eq "$target_65" ]]; then
            expected_65="$parent_bf"
        elif [[ "$parent_gu" -gt "$target_65" ]]; then
            local d=$(( parent_gu - target_65 ))
            local inc=$(( parent_bf * d / target_65 / denominator ))
            [[ "$inc" -lt 1 ]] && inc=1
            expected_65=$(( parent_bf + inc ))
        else
            local d=$(( target_65 - parent_gu ))
            local dec=$(( parent_bf * d / target_65 / denominator ))
            expected_65=$(( parent_bf - dec ))
            [[ "$expected_65" -lt 1 ]] && expected_65=1
        fi
        [[ "$expected_65" -lt "$MIN_BASE_FEE" ]] && expected_65="$MIN_BASE_FEE"

        # Compute expected base fee with 50% target
        local target_50=$(( parent_gl / 2 ))
        local expected_50
        if [[ "$parent_gu" -eq "$target_50" ]]; then
            expected_50="$parent_bf"
        elif [[ "$parent_gu" -gt "$target_50" ]]; then
            local d=$(( parent_gu - target_50 ))
            local inc=$(( parent_bf * d / target_50 / denominator ))
            [[ "$inc" -lt 1 ]] && inc=1
            expected_50=$(( parent_bf + inc ))
        else
            local d=$(( target_50 - parent_gu ))
            local dec=$(( parent_bf * d / target_50 / denominator ))
            expected_50=$(( parent_bf - dec ))
            [[ "$expected_50" -lt 1 ]] && expected_50=1
        fi
        [[ "$expected_50" -lt "$MIN_BASE_FEE" ]] && expected_50="$MIN_BASE_FEE"

        echo "Block $bn: actual=$child_bf expected_65=$expected_65 expected_50=$expected_50" >&3

        if [[ "$child_bf" -eq "$expected_65" ]]; then
            target_match_65=$((target_match_65 + 1))
        fi
        if [[ "$child_bf" -eq "$expected_50" ]]; then
            target_match_50=$((target_match_50 + 1))
        fi
    done

    if [[ "$checks" -eq 0 ]]; then
        skip "No usable block pairs found after Dandeli"
    fi

    echo "Post-Dandeli: $target_match_65/$checks match 65% target, $target_match_50/$checks match 50% target" >&3

    # The 65% target should match more blocks than the 50% target.
    # If both match (e.g. gasUsed=0 produces same result with both targets),
    # that's acceptable -- the key assertion is that 50% doesn't exclusively match.
    if [[ "$target_match_50" -gt 0 && "$target_match_65" -eq 0 ]]; then
        echo "FAIL: Post-Dandeli blocks match 50% target but not 65% -- Dandeli target change not applied" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 6: Cross-client base fee agreement at fork boundaries
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation,cross-client
@test "basefee-fork: cross-client base fee agreement at fork boundaries" {
    # Bor and Erigon must report the same baseFeePerGas at every fork boundary.
    # A disagreement indicates a fork activation mismatch between clients.

    if [[ -z "${L2_ERIGON_RPC_URL:-}" ]]; then
        skip "No Erigon RPC URL available (no Erigon node in enclave)"
    fi

    local -a fork_blocks=()
    [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 ]] && fork_blocks+=("${FORK_RIO}")
    [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 ]] && fork_blocks+=("${FORK_DANDELI}")
    [[ "${FORK_LISOVO}" -gt 0 && "${FORK_LISOVO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO}")
    [[ "${FORK_LISOVO_PRO}" -gt 0 && "${FORK_LISOVO_PRO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO_PRO}")
    [[ "${FORK_GIUGLIANO}" -gt 0 && "${FORK_GIUGLIANO}" -lt 999999999 ]] && fork_blocks+=("${FORK_GIUGLIANO}")

    if [[ "${#fork_blocks[@]}" -eq 0 ]]; then
        skip "All forks at genesis or disabled -- no boundaries to compare"
    fi

    # Wait for both clients to reach past the last fork block.
    local max_fork=0
    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -gt "$max_fork" ]] && max_fork="$fb"
    done
    local target=$(( max_fork + 2 ))
    _wait_for_block_on "$target" "$L2_RPC_URL" "L2_RPC"
    _wait_for_block_on "$target" "$L2_ERIGON_RPC_URL" "Erigon"

    local failures=0
    for fb in "${fork_blocks[@]}"; do
        local bor_bf erigon_bf
        bor_bf=$(_get_base_fee "$fb" "$L2_RPC_URL") || true
        erigon_bf=$(_get_base_fee "$fb" "$L2_ERIGON_RPC_URL") || true

        if [[ -z "$bor_bf" ]]; then
            echo "WARN: Bor has no baseFee at block $fb -- skipping" >&3
            continue
        fi
        if [[ -z "$erigon_bf" ]]; then
            echo "FAIL: Erigon has no baseFee at block $fb (Bor reports $bor_bf)" >&2
            failures=$((failures + 1))
            continue
        fi

        if [[ "$bor_bf" -ne "$erigon_bf" ]]; then
            echo "DIVERGENCE at fork block $fb: Bor baseFee=$bor_bf, Erigon baseFee=$erigon_bf" >&2
            failures=$((failures + 1))
        else
            echo "OK: Block $fb baseFee=$bor_bf (Bor == Erigon)" >&3
        fi
    done

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures fork boundary block(s) have baseFee disagreement between Bor and Erigon" >&2
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 7: Base fee transitions smoothly across all fork boundaries
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,basefee,fork-activation,continuity
@test "basefee-fork: base fee transitions smoothly across all fork boundaries" {
    # At fork activation blocks, the base fee should not show discontinuous
    # jumps. The maximum allowed change between consecutive blocks is bounded
    # by the applicable denominator rule (pre-Lisovo: 1/64 max, post-Lisovo: 5%).
    # A sudden spike or crash at a fork block indicates misconfigured activation.

    local -a fork_blocks=()
    [[ "${FORK_RIO}" -gt 0 && "${FORK_RIO}" -lt 999999999 ]] && fork_blocks+=("${FORK_RIO}")
    [[ "${FORK_DANDELI}" -gt 0 && "${FORK_DANDELI}" -lt 999999999 ]] && fork_blocks+=("${FORK_DANDELI}")
    [[ "${FORK_LISOVO}" -gt 0 && "${FORK_LISOVO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO}")
    [[ "${FORK_LISOVO_PRO}" -gt 0 && "${FORK_LISOVO_PRO}" -lt 999999999 ]] && fork_blocks+=("${FORK_LISOVO_PRO}")
    [[ "${FORK_GIUGLIANO}" -gt 0 && "${FORK_GIUGLIANO}" -lt 999999999 ]] && fork_blocks+=("${FORK_GIUGLIANO}")

    if [[ "${#fork_blocks[@]}" -eq 0 ]]; then
        skip "All forks at genesis or disabled -- no boundaries to check"
    fi

    local max_fork=0
    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -gt "$max_fork" ]] && max_fork="$fb"
    done
    _wait_for_block_on "$(( max_fork + 2 ))" "$L2_RPC_URL" "L2_RPC"

    local failures=0

    for fb in "${fork_blocks[@]}"; do
        [[ "$fb" -le 1 ]] && continue

        # Get base fee at fork-1, fork, fork+1
        local bf_before bf_at bf_after
        bf_before=$(_get_base_fee "$((fb - 1))") || continue
        bf_at=$(_get_base_fee "$fb") || continue
        bf_after=$(_get_base_fee "$((fb + 1))") || continue

        [[ -z "$bf_before" || -z "$bf_at" || -z "$bf_after" ]] && continue

        echo "Fork $fb: baseFee before=$bf_before at=$bf_at after=$bf_after" >&3

        # Check transition into the fork block (fork-1 -> fork).
        # Use a generous 12.5% bound (1/8, the loosest Ethereum default)
        # since the exact denominator may change at this block.
        if [[ "$bf_before" -gt 0 ]]; then
            local change=$(( bf_at - bf_before ))
            [[ "$change" -lt 0 ]] && change=$(( -change ))
            # Max allowed: 12.5% of parent = parent / 8 + 1 (rounding)
            local max_allowed=$(( bf_before / 8 + 1 ))

            if [[ "$change" -gt "$max_allowed" ]]; then
                echo "DISCONTINUITY entering fork $fb: |$bf_at - $bf_before| = $change > max $max_allowed (12.5%)" >&2
                failures=$((failures + 1))
            fi
        fi

        # Check transition out of the fork block (fork -> fork+1).
        if [[ "$bf_at" -gt 0 ]]; then
            local change=$(( bf_after - bf_at ))
            [[ "$change" -lt 0 ]] && change=$(( -change ))

            # Post-Lisovo uses 5% bound, pre-Lisovo uses 1/64 (~1.56%)
            local max_allowed
            if [[ "$fb" -ge "${FORK_LISOVO}" ]]; then
                max_allowed=$(( bf_at * 5 / 100 + 1 ))
            else
                max_allowed=$(( bf_at / 64 + 1 ))
            fi

            if [[ "$change" -gt "$max_allowed" ]]; then
                echo "DISCONTINUITY leaving fork $fb: |$bf_after - $bf_at| = $change > max $max_allowed" >&2
                failures=$((failures + 1))
            fi
        fi
    done

    echo "Checked ${#fork_blocks[@]} fork boundaries, discontinuities: $failures" >&3

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures discontinuous baseFee transition(s) detected at fork boundaries" >&2
        return 1
    fi
}
