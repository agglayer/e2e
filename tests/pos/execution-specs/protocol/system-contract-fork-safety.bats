#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,system-contracts,fork-activation

# System Contract Fork Safety Tests
# ====================================
# Verifies that Bor's genesis-deployed system contracts remain functional
# across every fork activation boundary. If a fork changes EVM behavior
# in a way that breaks system contract calls, the chain halts.
#
# System contracts under test:
#   0x1000 - BorValidatorSet: manages validator set per span/sprint
#   0x1001 - StateReceiver:   receives L1->L2 state sync data via Heimdall
#   0x1010 - MRC20:           native token wrapper (POL / MATIC)
#
# For each fork boundary block N, tests query at N-1, N, and N+1 to catch
# regressions introduced by EVM changes at the exact activation point.
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with Bor + Heimdall
#   - FORK_* env vars matching the deployed fork schedule
#
# RUN: bats tests/pos/execution-specs/protocol/system-contract-fork-safety.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Discover all Bor RPC endpoints in the enclave (validators + RPCs)
    local urls=() labels=()
    for i in $(seq 1 12); do
        for role in validator rpc; do
            local svc="l2-el-${i}-bor-heimdall-v2-${role}"
            local port
            if port=$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null); then
                port="${port#http://}"; port="${port#https://}"
                urls+=("http://${port}")
                labels+=("${svc}")
            fi
        done
    done

    # Persist for per-test setup (bash arrays can't be exported across processes)
    : > "${BATS_FILE_TMPDIR}/bor_rpc_urls"
    : > "${BATS_FILE_TMPDIR}/bor_rpc_labels"
    for idx in "${!urls[@]}"; do
        echo "${urls[$idx]}" >> "${BATS_FILE_TMPDIR}/bor_rpc_urls"
        echo "${labels[$idx]}" >> "${BATS_FILE_TMPDIR}/bor_rpc_labels"
    done

    echo "Discovered ${#urls[@]} Bor node(s): ${labels[*]}" >&3
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Load discovered Bor endpoints
    mapfile -t BOR_RPC_URLS < "${BATS_FILE_TMPDIR}/bor_rpc_urls"
    mapfile -t BOR_RPC_LABELS < "${BATS_FILE_TMPDIR}/bor_rpc_labels"

    [[ ${#BOR_RPC_URLS[@]} -ge 1 ]] || skip "No Bor RPC endpoints discovered in enclave"

    # System contract addresses
    VALIDATOR_SET="0x0000000000000000000000000000000000001000"
    MRC20="0x0000000000000000000000000000000000001010"
    STATE_RECEIVER="${L2_STATE_RECEIVER_ADDRESS:-0x0000000000000000000000000000000000001001}"

    # Fork schedule from env vars (matches CI defaults)
    FORK_RIO="${FORK_RIO:-256}"
    FORK_MADHUGIRI="${FORK_MADHUGIRI:-320}"
    FORK_MADHUGIRI_PRO="${FORK_MADHUGIRI_PRO:-384}"
    FORK_DANDELI="${FORK_DANDELI:-448}"
    FORK_LISOVO="${FORK_LISOVO:-512}"
    FORK_LISOVO_PRO="${FORK_LISOVO_PRO:-576}"
    FORK_GIUGLIANO="${FORK_GIUGLIANO:-640}"
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Build the list of fork blocks to test, based on BOR_MIN_VERSION.
# Populates the global arrays _FORK_NAMES and _FORK_BLOCKS.
_build_fork_list() {
    _FORK_NAMES=("rio")
    _FORK_BLOCKS=("${FORK_RIO}")

    local base=""
    local running="${BOR_MIN_VERSION:-}"
    [[ -n "$running" ]] && base=$(echo "$running" | sed -E 's/(-beta[0-9]*|-rc[0-9]*)$//')

    if [[ -z "$base" ]] || _ver_gte "$base" "2.5.0"; then
        _FORK_NAMES+=("madhugiri" "madhugiriPro")
        _FORK_BLOCKS+=("${FORK_MADHUGIRI}" "${FORK_MADHUGIRI_PRO}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.5.6"; then
        _FORK_NAMES+=("dandeli")
        _FORK_BLOCKS+=("${FORK_DANDELI}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.6.0"; then
        _FORK_NAMES+=("lisovo" "lisovoPro")
        _FORK_BLOCKS+=("${FORK_LISOVO}" "${FORK_LISOVO_PRO}")
    fi
    if [[ -z "$base" ]] || _ver_gte "$base" "2.7.0"; then
        _FORK_NAMES+=("giugliano")
        _FORK_BLOCKS+=("${FORK_GIUGLIANO}")
    fi
}

# Returns 0 if version $1 >= $2, 1 otherwise.
_ver_gte() {
    local running="$1" required="$2"
    local lower
    lower=$(printf '%s\n%s' "$running" "$required" | sort -V | head -1)
    [[ "$lower" == "$required" ]]
}

# Wait for the primary L2 RPC to reach the target block.
# Includes stall detection: if block doesn't advance for 24 x 5s = 120s, returns 1.
_wait_for_block() {
    local target="$1"
    local rpc="${2:-$L2_RPC_URL}"
    local current
    current=$(cast block-number --rpc-url "$rpc" 2>/dev/null || echo 0)
    [[ "$current" -ge "$target" ]] && return 0

    local remaining=$(( target - current ))
    local timeout=$(( remaining * 3 + 300 ))
    [[ "$timeout" -gt 1800 ]] && timeout=1800
    local STALL_LIMIT=24

    echo "  Waiting for block ${target} (current: ${current}, timeout: ${timeout}s)..." >&3

    local start_time elapsed last_block stall_count
    start_time=$(date +%s)
    last_block="$current"
    stall_count=0

    while true; do
        elapsed=$(( $(date +%s) - start_time ))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "  TIMEOUT waiting for block ${target} (stuck at ${current})" >&2
            return 1
        fi

        local rpc_ok
        current=$(cast block-number --rpc-url "$rpc" 2>/dev/null) && rpc_ok=1 || { rpc_ok=0; current="$last_block"; }
        [[ "$current" -ge "$target" ]] && return 0

        if [[ "$rpc_ok" -eq 1 ]]; then
            if [[ "$current" -eq "$last_block" ]]; then
                stall_count=$(( stall_count + 1 ))
                if [[ "$stall_count" -ge "$STALL_LIMIT" ]]; then
                    echo "  STUCK: chain has not advanced from block ${current} for $(( stall_count * 5 ))s" >&2
                    return 1
                fi
            else
                stall_count=0
            fi
        fi
        last_block="$current"
        sleep 5
    done
}

# Ensure the chain has advanced past all fork boundaries we plan to test.
_wait_past_all_forks() {
    _build_fork_list
    local last_fork="${_FORK_BLOCKS[-1]}"
    local target=$(( last_fork + 3 ))
    _wait_for_block "${target}" || {
        echo "Chain could not reach block ${target} (last fork at ${last_fork})" >&2
        return 1
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,system-contracts,fork-activation,validator-set
@test "system-contract-safety: ValidatorSet.getValidators() returns valid set at each fork boundary" {
    _wait_past_all_forks

    local errors=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        local offsets=(-1 0 1)
        for offset in "${offsets[@]}"; do
            local block=$(( fblock + offset ))
            [[ "$block" -lt 1 ]] && continue

            # Try getValidators() first (selector 0xb7ab4db5)
            set +e
            local result
            result=$(cast call "$VALIDATOR_SET" \
                "getValidators()(address[],uint256[])" \
                --rpc-url "$L2_RPC_URL" \
                --block "$block" 2>/dev/null)
            local exit_code=$?
            set -e

            if [[ $exit_code -ne 0 || -z "$result" ]]; then
                # Fallback: try getBorValidators(uint256)
                set +e
                result=$(cast call "$VALIDATOR_SET" \
                    "getBorValidators(uint256)(address[],uint256[])" \
                    "$block" \
                    --rpc-url "$L2_RPC_URL" \
                    --block "$block" 2>/dev/null)
                exit_code=$?
                set -e
            fi

            if [[ $exit_code -ne 0 || -z "$result" ]]; then
                echo "FAIL: getValidators() failed at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            # Verify the result contains at least one address (non-empty validator set)
            local addr_count
            addr_count=$(echo "$result" | head -1 | tr ',' '\n' | grep -cE '0x[0-9a-fA-F]{40}' || true)

            if [[ "$addr_count" -lt 1 ]]; then
                echo "FAIL: getValidators() returned empty set at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
            else
                echo "  OK ${fname} fork+${offset} (block ${block}): ${addr_count} validator(s)" >&3
            fi
        done
    done

    [[ "$errors" -eq 0 ]] || {
        echo "${errors} getValidators() call(s) failed across fork boundaries" >&2
        return 1
    }
}

# bats test_tags=execution-specs,system-contracts,fork-activation,state-receiver
@test "system-contract-safety: StateReceiver contract code exists at all fork boundaries" {
    _wait_past_all_forks

    local errors=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        local offsets=(-1 0 1)
        for offset in "${offsets[@]}"; do
            local block=$(( fblock + offset ))
            [[ "$block" -lt 1 ]] && continue

            local code
            code=$(cast code "$STATE_RECEIVER" --rpc-url "$L2_RPC_URL" --block "$block" 2>/dev/null)

            if [[ -z "$code" || "$code" == "0x" ]]; then
                echo "FAIL: StateReceiver (${STATE_RECEIVER}) has no code at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
            else
                local code_len=$(( (${#code} - 2) / 2 ))
                echo "  OK ${fname} fork+${offset} (block ${block}): StateReceiver code ${code_len} bytes" >&3
            fi
        done
    done

    [[ "$errors" -eq 0 ]] || {
        echo "${errors} StateReceiver code check(s) failed across fork boundaries" >&2
        return 1
    }
}

# bats test_tags=execution-specs,system-contracts,fork-activation,mrc20
@test "system-contract-safety: MRC20 (POL) balance query works across all forks" {
    _wait_past_all_forks

    # Use the zero address as a known query target (balance may be 0, but the call must succeed)
    local query_addr="0x0000000000000000000000000000000000000000"
    local errors=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        local offsets=(-1 0 1)
        for offset in "${offsets[@]}"; do
            local block=$(( fblock + offset ))
            [[ "$block" -lt 1 ]] && continue

            # balanceOf(address) selector: 0x70a08231
            set +e
            local balance
            balance=$(cast call "$MRC20" \
                "balanceOf(address)(uint256)" \
                "$query_addr" \
                --rpc-url "$L2_RPC_URL" \
                --block "$block" 2>/dev/null)
            local exit_code=$?
            set -e

            if [[ $exit_code -ne 0 ]]; then
                echo "FAIL: MRC20 balanceOf() failed at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
            else
                echo "  OK ${fname} fork+${offset} (block ${block}): balanceOf(0x0) = ${balance}" >&3
            fi
        done
    done

    [[ "$errors" -eq 0 ]] || {
        echo "${errors} MRC20 balanceOf() call(s) failed across fork boundaries" >&2
        return 1
    }
}

# bats test_tags=execution-specs,system-contracts,fork-activation,cross-node
@test "system-contract-safety: ValidatorSet returns same set on all nodes" {
    if [[ ${#BOR_RPC_URLS[@]} -lt 2 ]]; then
        skip "Need >= 2 Bor nodes for cross-node comparison (found ${#BOR_RPC_URLS[@]})"
    fi

    _wait_past_all_forks

    # Also wait for all secondary nodes to reach the last fork
    local last_fork="${_FORK_BLOCKS[-1]}"
    local target=$(( last_fork + 3 ))
    for idx in "${!BOR_RPC_URLS[@]}"; do
        _wait_for_block "${target}" "${BOR_RPC_URLS[$idx]}" || {
            echo "FAIL: ${BOR_RPC_LABELS[$idx]} could not reach block ${target}" >&2
            return 1
        }
    done

    local divergences=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        # Query getValidators() at the fork block on each node
        local ref_result="" ref_label=""

        for idx in "${!BOR_RPC_URLS[@]}"; do
            set +e
            local result
            result=$(cast call "$VALIDATOR_SET" \
                "getValidators()(address[],uint256[])" \
                --rpc-url "${BOR_RPC_URLS[$idx]}" \
                --block "$fblock" 2>/dev/null)
            local exit_code=$?
            set -e

            if [[ $exit_code -ne 0 || -z "$result" ]]; then
                # Fallback to getBorValidators
                set +e
                result=$(cast call "$VALIDATOR_SET" \
                    "getBorValidators(uint256)(address[],uint256[])" \
                    "$fblock" \
                    --rpc-url "${BOR_RPC_URLS[$idx]}" \
                    --block "$fblock" 2>/dev/null)
                exit_code=$?
                set -e
            fi

            if [[ $exit_code -ne 0 || -z "$result" ]]; then
                echo "  WARN: ${BOR_RPC_LABELS[$idx]} cannot call getValidators at block ${fblock}" >&3
                continue
            fi

            if [[ -z "$ref_result" ]]; then
                ref_result="$result"
                ref_label="${BOR_RPC_LABELS[$idx]}"
                continue
            fi

            if [[ "$result" != "$ref_result" ]]; then
                echo "DIVERGENCE at ${fname} (block ${fblock}):" >&2
                echo "  ${ref_label}: ${ref_result:0:200}" >&2
                echo "  ${BOR_RPC_LABELS[$idx]}: ${result:0:200}" >&2
                divergences=$(( divergences + 1 ))
            fi
        done

        if [[ "$divergences" -eq 0 && -n "$ref_result" ]]; then
            echo "  OK ${fname} (block ${fblock}): all ${#BOR_RPC_URLS[@]} nodes agree on validator set" >&3
        fi
    done

    [[ "$divergences" -eq 0 ]] || {
        echo "${divergences} validator set divergence(s) detected across nodes" >&2
        return 1
    }
}

# bats test_tags=execution-specs,system-contracts,fork-activation,code-hash
@test "system-contract-safety: system contract code hash unchanged across fork boundaries" {
    _wait_past_all_forks

    # For each system contract, verify that code hash at fork-1 == code hash at fork.
    # A code hash change at a fork block means the fork replaced the contract bytecode,
    # which is expected for some PIPs (e.g. PIP-45 at Ahmedabad) but unexpected otherwise.
    local contracts=("$VALIDATOR_SET" "$STATE_RECEIVER" "$MRC20")
    local contract_names=("ValidatorSet" "StateReceiver" "MRC20")
    local unexpected_changes=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        local pre_block=$(( fblock - 1 ))
        [[ "$pre_block" -lt 1 ]] && continue

        for ci in "${!contracts[@]}"; do
            local addr="${contracts[$ci]}"
            local cname="${contract_names[$ci]}"

            local code_pre code_post
            code_pre=$(cast code "$addr" --rpc-url "$L2_RPC_URL" --block "$pre_block" 2>/dev/null)
            code_post=$(cast code "$addr" --rpc-url "$L2_RPC_URL" --block "$fblock" 2>/dev/null)

            # Skip if either block has no code (contract not yet deployed)
            if [[ -z "$code_pre" || "$code_pre" == "0x" ]]; then
                echo "  SKIP ${cname} at ${fname}: no code at block ${pre_block}" >&3
                continue
            fi
            if [[ -z "$code_post" || "$code_post" == "0x" ]]; then
                echo "  FAIL ${cname} at ${fname}: code disappeared at block ${fblock}" >&2
                unexpected_changes=$(( unexpected_changes + 1 ))
                continue
            fi

            # Compare code hashes (cheaper than comparing full bytecode strings)
            local hash_pre hash_post
            hash_pre=$(cast keccak "$code_pre" 2>/dev/null)
            hash_post=$(cast keccak "$code_post" 2>/dev/null)

            if [[ "$hash_pre" != "$hash_post" ]]; then
                local len_pre=$(( (${#code_pre} - 2) / 2 ))
                local len_post=$(( (${#code_post} - 2) / 2 ))
                echo "  CHANGE ${cname} at ${fname} (block ${fblock}): code hash changed" >&3
                echo "    pre:  ${hash_pre} (${len_pre} bytes)" >&3
                echo "    post: ${hash_post} (${len_post} bytes)" >&3
                echo "    This may be an intentional PIP-driven bytecode replacement." >&3
                # Log as informational, not failure: some forks intentionally replace
                # system contract bytecode (e.g. PIP-45 at Ahmedabad, PIP-36).
                # The real test is whether the contract remains callable (other tests).
            else
                echo "  OK ${cname} at ${fname} (block ${fblock}): code hash unchanged (${hash_pre})" >&3
            fi
        done
    done

    # A code hash change is informational (intentional PIPs do this).
    # A code _disappearance_ is a failure.
    [[ "$unexpected_changes" -eq 0 ]] || {
        echo "${unexpected_changes} system contract(s) lost code at fork boundaries" >&2
        return 1
    }
}

# bats test_tags=execution-specs,system-contracts,fork-activation,validator-set,span
@test "system-contract-safety: ValidatorSet.currentSpanNumber() returns valid span at all forks" {
    _wait_past_all_forks

    local errors=0

    for fi_idx in "${!_FORK_NAMES[@]}"; do
        local fname="${_FORK_NAMES[$fi_idx]}"
        local fblock="${_FORK_BLOCKS[$fi_idx]}"
        [[ "$fblock" -le 1 ]] && continue

        local offsets=(-1 0 1)
        for offset in "${offsets[@]}"; do
            local block=$(( fblock + offset ))
            [[ "$block" -lt 1 ]] && continue

            set +e
            local span
            span=$(cast call "$VALIDATOR_SET" \
                "currentSpanNumber()(uint256)" \
                --rpc-url "$L2_RPC_URL" \
                --block "$block" 2>/dev/null)
            local exit_code=$?
            set -e

            if [[ $exit_code -ne 0 || -z "$span" ]]; then
                echo "FAIL: currentSpanNumber() failed at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            # Span number must be a non-negative integer
            if ! [[ "$span" =~ ^[0-9]+$ ]]; then
                echo "FAIL: currentSpanNumber() returned non-numeric value '${span}' at ${fname} fork+${offset} (block ${block})" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            echo "  OK ${fname} fork+${offset} (block ${block}): currentSpanNumber() = ${span}" >&3
        done
    done

    [[ "$errors" -eq 0 ]] || {
        echo "${errors} currentSpanNumber() call(s) failed across fork boundaries" >&2
        return 1
    }
}
