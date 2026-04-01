#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,finality,resilience

# Finality & Reorg Resistance Tests
# ====================================
# Verifies that Bor's finality guarantees (backed by Heimdall milestones)
# are enforced correctly: finalized blocks must not be reorged, all nodes
# must agree on finalized state, and milestone hashes must match Bor.
#
# Risk areas covered (S1):
#   - Finalized block tag returns non-zero and advances over time
#   - safe <= finalized <= latest ordering invariant
#   - Cross-node finalized block hash agreement
#   - Heimdall milestone hash matches Bor finalized range
#   - Immutability of finalized block hashes (no silent reorgs)
#   - Finality depth stays within a reasonable bound
#
# REQUIREMENTS:
#   - Kurtosis PoS enclave with Bor + Heimdall
#   - Multiple Bor nodes for cross-node checks
#   - Heimdall REST API access for milestone verification
#
# RUN: bats tests/pos/execution-specs/resilience/finality-and-reorg-resistance.bats

# ────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    pos_setup

    # ── Discover all Bor RPC endpoints in the enclave ──
    _discover_bor_nodes "${BATS_FILE_TMPDIR}/bor_rpc_urls" "${BATS_FILE_TMPDIR}/bor_rpc_labels"

    local node_count
    node_count=$(wc -l < "${BATS_FILE_TMPDIR}/bor_rpc_urls" 2>/dev/null || echo 0)
    if [[ "${node_count}" -lt 2 ]]; then
        echo "WARNING: Need >=2 Bor nodes for cross-node finality checks" >&3
    fi

    # ── Probe Heimdall milestone API ──
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/latest" 2>/dev/null \
        | jq -r '.milestone.end_block // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        probe=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/latest" 2>/dev/null \
            | jq -r '.milestone.end_block // empty' 2>/dev/null || true)
    fi

    if [[ -z "${probe}" ]]; then
        echo "WARNING: Heimdall milestone API not reachable at ${L2_CL_API_URL}" >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    else
        echo "Heimdall milestone API reachable; latest milestone end_block=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/pos-fork-helpers.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet

    # Load discovered Bor endpoints
    mapfile -t BOR_RPC_URLS < "${BATS_FILE_TMPDIR}/bor_rpc_urls"
    mapfile -t BOR_RPC_LABELS < "${BATS_FILE_TMPDIR}/bor_rpc_labels"
}

teardown() {
    jobs -p | xargs -r kill 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

# Query a block by tag (finalized, safe, latest) from a given RPC endpoint.
# Returns the full JSON block object on stdout, or empty string on failure.
_get_block_by_tag() {
    local tag="$1" rpc="${2:-$L2_RPC_URL}"
    curl -s -m 30 --connect-timeout 5 -X POST "${rpc}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${tag}\",false],\"id\":1}" \
        | jq -r '.result // empty' 2>/dev/null || true
}

# Extract block number (decimal) from a block JSON object on stdin.
_block_number_from_json() {
    local num_hex
    num_hex=$(jq -r '.number // empty' 2>/dev/null)
    if [[ -n "${num_hex}" && "${num_hex}" != "null" ]]; then
        printf '%d' "${num_hex}"
    fi
}

# Extract block hash from a block JSON object on stdin.
_block_hash_from_json() {
    jq -r '.hash // empty' 2>/dev/null
}

# Fetch the latest milestone object from Heimdall.
# Tries standard path first, then gRPC-gateway /v1beta1/ prefix.
_get_latest_milestone() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/milestones/latest" 2>/dev/null || true)
    local ms
    ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        raw=$(curl -s -m 30 --connect-timeout 5 \
            "${L2_CL_API_URL}/v1beta1/milestones/latest" 2>/dev/null || true)
        ms=$(printf '%s' "${raw}" | jq -r 'if .milestone then .milestone else empty end' 2>/dev/null || true)
    fi
    if [[ -z "${ms}" || "${ms}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${ms}"
}

# Decode a base64 or hex hash into lowercase 0x-prefixed hex.
# Heimdall may encode the hash as base64 bytes (proto JSON) or 0x-prefixed hex.
_decode_hash() {
    local raw="$1"
    if [[ -z "${raw}" || "${raw}" == "null" ]]; then
        return 1
    fi
    # If it looks like 0x-prefixed hex, return as-is (lowercased).
    if [[ "${raw}" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    # Try base64 decode -> hex.
    local hex_decoded
    hex_decoded=$(printf '%s' "${raw}" | base64 -d 2>/dev/null \
        | od -A n -t x1 2>/dev/null | tr -d ' \n' || true)
    if [[ -n "${hex_decoded}" ]]; then
        printf '0x%s' "${hex_decoded}"
        return 0
    fi
    # Return raw value unchanged if we cannot decode it.
    printf '%s' "${raw}"
}

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=resilience,finality,s1,advancing
@test "finality: finalized block number is non-zero and advancing" {
    # Targets: finality/milestone — deterministic finality must progress.
    # If the finalized block is stuck at zero or not advancing, the
    # finality mechanism is broken and no blocks are being finalized.

    local block_json_1
    block_json_1=$(_get_block_by_tag "finalized")

    if [[ -z "${block_json_1}" ]]; then
        # Fallback to safe tag if finalized is not supported
        block_json_1=$(_get_block_by_tag "safe")
        if [[ -z "${block_json_1}" ]]; then
            skip "Neither finalized nor safe block tag available on this node"
        fi
        echo "Using 'safe' tag as fallback (finalized not available)" >&3
    fi

    local num1
    num1=$(printf '%s' "${block_json_1}" | _block_number_from_json)

    if [[ -z "${num1}" ]]; then
        echo "CRITICAL: Finalized block returned but has no block number" >&2
        return 1
    fi

    if [[ "${num1}" -eq 0 ]]; then
        echo "CRITICAL: Finalized block number is zero — finality has not advanced" >&2
        return 1
    fi

    echo "First query: finalized block = ${num1}" >&3

    # Wait for finality to advance
    sleep 15

    local block_json_2
    block_json_2=$(_get_block_by_tag "finalized")
    if [[ -z "${block_json_2}" ]]; then
        block_json_2=$(_get_block_by_tag "safe")
    fi

    local num2
    num2=$(printf '%s' "${block_json_2}" | _block_number_from_json)

    if [[ -z "${num2}" ]]; then
        echo "CRITICAL: Second finalized block query returned no block number" >&2
        return 1
    fi

    echo "Second query: finalized block = ${num2}" >&3

    if [[ "${num2}" -le "${num1}" ]]; then
        echo "CRITICAL: Finalized block did not advance: ${num1} -> ${num2}" >&2
        echo "  Finality mechanism may be stalled (no new milestones being committed)" >&2
        return 1
    fi

    echo "Finalized block advanced from ${num1} to ${num2} (delta=$(( num2 - num1 )))" >&3
}

# bats test_tags=resilience,finality,s1,ordering
@test "finality: safe <= finalized <= latest block ordering" {
    # Targets: block tag semantics — safety invariant.
    # The block tags must follow a strict ordering: safe <= finalized <= latest.
    # If this invariant is broken, the finality model is inconsistent.

    local safe_json finalized_json latest_json
    safe_json=$(_get_block_by_tag "safe")
    finalized_json=$(_get_block_by_tag "finalized")
    latest_json=$(_get_block_by_tag "latest")

    if [[ -z "${latest_json}" ]]; then
        echo "CRITICAL: Cannot query latest block — RPC may be down" >&2
        return 1
    fi

    local latest_num
    latest_num=$(printf '%s' "${latest_json}" | _block_number_from_json)

    if [[ -z "${latest_num}" ]]; then
        echo "CRITICAL: Latest block has no block number" >&2
        return 1
    fi

    echo "latest block = ${latest_num}" >&3

    # Check finalized <= latest
    if [[ -n "${finalized_json}" ]]; then
        local finalized_num
        finalized_num=$(printf '%s' "${finalized_json}" | _block_number_from_json)

        if [[ -n "${finalized_num}" ]]; then
            echo "finalized block = ${finalized_num}" >&3

            if [[ "${finalized_num}" -gt "${latest_num}" ]]; then
                echo "CRITICAL: finalized (${finalized_num}) > latest (${latest_num}) — ordering violation" >&2
                return 1
            fi
        fi
    fi

    # Check safe <= finalized (or safe <= latest if finalized unavailable)
    if [[ -n "${safe_json}" ]]; then
        local safe_num
        safe_num=$(printf '%s' "${safe_json}" | _block_number_from_json)

        if [[ -n "${safe_num}" ]]; then
            echo "safe block = ${safe_num}" >&3

            if [[ -n "${finalized_num:-}" ]]; then
                # Bor maps both safe and finalized to the milestone boundary,
                # so they may be equal. The invariant is safe <= finalized.
                if [[ "${safe_num}" -gt "${finalized_num}" ]]; then
                    echo "CRITICAL: safe (${safe_num}) > finalized (${finalized_num}) — ordering violation" >&2
                    return 1
                fi
                echo "Ordering confirmed: safe(${safe_num}) <= finalized(${finalized_num}) <= latest(${latest_num})" >&3
            else
                if [[ "${safe_num}" -gt "${latest_num}" ]]; then
                    echo "CRITICAL: safe (${safe_num}) > latest (${latest_num}) — ordering violation" >&2
                    return 1
                fi
                echo "Ordering confirmed: safe(${safe_num}) <= latest(${latest_num}) (finalized unavailable)" >&3
            fi
        fi
    fi

    if [[ -z "${safe_json}" && -z "${finalized_json}" ]]; then
        skip "Neither safe nor finalized block tags are available"
    fi
}

# bats test_tags=resilience,finality,s1,cross-node
@test "finality: all nodes agree on finalized block hash" {
    # Targets: cross-node finality — consensus agreement.
    # All Bor nodes must agree on which block is finalized at a given height.
    # A disagreement means the finality layer has split.

    if [[ "${#BOR_RPC_URLS[@]}" -lt 2 ]]; then
        skip "Need at least 2 Bor nodes for cross-node finality comparison"
    fi

    # Collect finalized block numbers from all nodes
    local -a fin_nums=() fin_hashes=() fin_rpcs=()
    local block_tag="finalized"

    for idx in "${!BOR_RPC_URLS[@]}"; do
        local rpc="${BOR_RPC_URLS[$idx]}"
        local label="${BOR_RPC_LABELS[$idx]}"

        local block_json
        block_json=$(_get_block_by_tag "${block_tag}" "${rpc}")

        if [[ -z "${block_json}" ]]; then
            # Try safe tag as fallback
            block_json=$(_get_block_by_tag "safe" "${rpc}")
            if [[ -z "${block_json}" ]]; then
                echo "  WARN: ${label} does not support finalized or safe block tag" >&3
                continue
            fi
            block_tag="safe"
        fi

        local num hash
        num=$(printf '%s' "${block_json}" | _block_number_from_json)
        hash=$(printf '%s' "${block_json}" | _block_hash_from_json)

        if [[ -n "${num}" && -n "${hash}" ]]; then
            fin_nums+=("${num}")
            fin_hashes+=("${hash}")
            fin_rpcs+=("${idx}")
            echo "  ${label}: ${block_tag} block=${num}, hash=${hash}" >&3
        fi
    done

    if [[ "${#fin_rpcs[@]}" -lt 2 ]]; then
        skip "Fewer than 2 nodes returned a finalized/safe block"
    fi

    # Compare at the lowest finalized height to avoid TOCTOU race
    local min_num="${fin_nums[0]}"
    for n in "${fin_nums[@]}"; do
        if [[ "${n}" -lt "${min_num}" ]]; then
            min_num="${n}"
        fi
    done

    echo "Comparing block hashes at height ${min_num} across ${#fin_rpcs[@]} nodes" >&3

    local ref_hash="" ref_label="" diverged=0
    for i in "${!fin_rpcs[@]}"; do
        local idx="${fin_rpcs[$i]}"
        local rpc="${BOR_RPC_URLS[$idx]}"
        local label="${BOR_RPC_LABELS[$idx]}"

        local hash
        hash=$(cast block "${min_num}" --json --rpc-url "${rpc}" 2>/dev/null | jq -r '.hash // empty')

        if [[ -z "${hash}" ]]; then
            echo "  WARN: ${label} has no block at height ${min_num}" >&3
            continue
        fi

        if [[ -z "${ref_hash}" ]]; then
            ref_hash="${hash}"
            ref_label="${label}"
            continue
        fi

        if [[ "${hash}" != "${ref_hash}" ]]; then
            echo "CRITICAL: Finalized block hash mismatch at height ${min_num}:" >&2
            echo "  ${ref_label}: ${ref_hash}" >&2
            echo "  ${label}: ${hash}" >&2
            diverged=1
        fi
    done

    if [[ "${diverged}" -ne 0 ]]; then
        echo "Finality consensus split detected — nodes disagree on finalized chain" >&2
        return 1
    fi

    echo "All ${#fin_rpcs[@]} nodes agree on block hash at finalized height ${min_num}" >&3
}

# bats test_tags=resilience,finality,s1,milestone-match
@test "finality: milestone block hash matches bor finalized range" {
    # Targets: Heimdall milestone <-> Bor finalized block consistency.
    # The milestone end_block hash recorded by Heimdall must match the
    # block hash that Bor has at that height. A mismatch means the
    # finality layer is finalizing the wrong chain.

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_milestone_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "Heimdall milestone API not reachable at ${L2_CL_API_URL}"
    fi

    local ms
    if ! ms=$(_get_latest_milestone); then
        skip "Could not fetch latest milestone from Heimdall"
    fi

    local end_block ms_hash_raw
    end_block=$(printf '%s' "${ms}" | jq -r '.end_block // empty')
    ms_hash_raw=$(printf '%s' "${ms}" | jq -r '.hash // empty')

    if [[ -z "${end_block}" || "${end_block}" == "null" ]]; then
        skip "Latest milestone has no end_block"
    fi
    if [[ -z "${ms_hash_raw}" || "${ms_hash_raw}" == "null" ]]; then
        skip "Latest milestone has no hash"
    fi

    local ms_hash
    ms_hash=$(_decode_hash "${ms_hash_raw}")
    echo "Milestone end_block=${end_block}, milestone hash=${ms_hash}" >&3

    # Fetch the block hash from Bor at the milestone end_block
    local bor_block_json
    bor_block_json=$(cast block "${end_block}" --json --rpc-url "${L2_RPC_URL}" 2>/dev/null)

    if [[ -z "${bor_block_json}" ]]; then
        echo "CRITICAL: Bor does not have block ${end_block} referenced by milestone" >&2
        return 1
    fi

    local bor_hash
    bor_hash=$(printf '%s' "${bor_block_json}" | jq -r '.hash // empty')

    if [[ -z "${bor_hash}" || "${bor_hash}" == "null" ]]; then
        echo "CRITICAL: Bor block ${end_block} has no hash" >&2
        return 1
    fi

    echo "Bor block hash for ${end_block}: ${bor_hash}" >&3

    # Normalise both to lowercase for comparison
    local ms_hash_lower bor_hash_lower
    ms_hash_lower=$(printf '%s' "${ms_hash}" | tr '[:upper:]' '[:lower:]')
    bor_hash_lower=$(printf '%s' "${bor_hash}" | tr '[:upper:]' '[:lower:]')

    if [[ "${ms_hash_lower}" != "${bor_hash_lower}" ]]; then
        echo "CRITICAL: Milestone hash DOES NOT match Bor block hash at end_block ${end_block}:" >&2
        echo "  Heimdall milestone hash: ${ms_hash_lower}" >&2
        echo "  Bor block hash:          ${bor_hash_lower}" >&2
        echo "" >&2
        echo "  Heimdall is finalizing a different chain tip than what Bor produced." >&2
        echo "  Nodes accepting this milestone will diverge from the canonical chain." >&2
        return 1
    fi

    # Additionally verify the finalized block on Bor is at or past the milestone
    local finalized_json
    finalized_json=$(_get_block_by_tag "finalized")

    if [[ -n "${finalized_json}" ]]; then
        local finalized_num
        finalized_num=$(printf '%s' "${finalized_json}" | _block_number_from_json)

        if [[ -n "${finalized_num}" ]]; then
            echo "Bor finalized block=${finalized_num}, milestone end_block=${end_block}" >&3
            if [[ "${finalized_num}" -lt "${end_block}" ]]; then
                echo "WARNING: Bor finalized block (${finalized_num}) is behind milestone end_block (${end_block})" >&3
                echo "  This may indicate finality lag, but is not necessarily a failure" >&3
            fi
        fi
    fi

    echo "OK: Milestone hash matches Bor block hash at end_block ${end_block}: ${bor_hash_lower}" >&3
}

# bats test_tags=resilience,finality,s1,immutability
@test "finality: finalized blocks have immutable hashes" {
    # Targets: finality immutability — no silent reorgs.
    # Once a block is finalized, its hash must never change. If querying
    # the same finalized block number twice yields different hashes, a
    # reorg has occurred past the finality boundary — a critical failure.

    local finalized_json_1
    finalized_json_1=$(_get_block_by_tag "finalized")

    if [[ -z "${finalized_json_1}" ]]; then
        finalized_json_1=$(_get_block_by_tag "safe")
        if [[ -z "${finalized_json_1}" ]]; then
            skip "Neither finalized nor safe block tag available"
        fi
    fi

    local num1 hash1
    num1=$(printf '%s' "${finalized_json_1}" | _block_number_from_json)
    hash1=$(printf '%s' "${finalized_json_1}" | _block_hash_from_json)

    if [[ -z "${num1}" || -z "${hash1}" ]]; then
        skip "Finalized block missing number or hash"
    fi

    echo "Recorded finalized block ${num1}: hash=${hash1}" >&3

    # Wait to allow any potential reorg activity
    sleep 10

    # Query the SAME block number again by its number (not by tag)
    local block_json_2
    block_json_2=$(cast block "${num1}" --json --rpc-url "${L2_RPC_URL}" 2>/dev/null)

    if [[ -z "${block_json_2}" ]]; then
        echo "CRITICAL: Block ${num1} no longer exists after being finalized — reorg past finality!" >&2
        return 1
    fi

    local hash2
    hash2=$(printf '%s' "${block_json_2}" | jq -r '.hash // empty')

    if [[ -z "${hash2}" ]]; then
        echo "CRITICAL: Block ${num1} has no hash on second query" >&2
        return 1
    fi

    echo "Re-queried block ${num1} after delay: hash=${hash2}" >&3

    if [[ "${hash1}" != "${hash2}" ]]; then
        echo "CRITICAL: Finalized block ${num1} hash changed!" >&2
        echo "  Before: ${hash1}" >&2
        echo "  After:  ${hash2}" >&2
        echo "" >&2
        echo "  A reorg occurred past the finality boundary." >&2
        echo "  This breaks the security model: finalized blocks must be immutable." >&2
        return 1
    fi

    echo "OK: Finalized block ${num1} hash is immutable: ${hash1}" >&3
}

# bats test_tags=resilience,finality,s1,depth
@test "finality: finality depth is reasonable" {
    # Targets: finality lag — depth bound check.
    # The gap between the latest block and the finalized block should stay
    # within a reasonable bound. An excessively large gap means finality
    # is falling behind, which increases reorg risk.

    local latest_json finalized_json
    latest_json=$(_get_block_by_tag "latest")
    finalized_json=$(_get_block_by_tag "finalized")

    if [[ -z "${latest_json}" ]]; then
        echo "CRITICAL: Cannot query latest block" >&2
        return 1
    fi

    if [[ -z "${finalized_json}" ]]; then
        finalized_json=$(_get_block_by_tag "safe")
        if [[ -z "${finalized_json}" ]]; then
            skip "Neither finalized nor safe block tag available"
        fi
        echo "Using 'safe' tag as fallback (finalized not available)" >&3
    fi

    local latest_num finalized_num
    latest_num=$(printf '%s' "${latest_json}" | _block_number_from_json)
    finalized_num=$(printf '%s' "${finalized_json}" | _block_number_from_json)

    if [[ -z "${latest_num}" || -z "${finalized_num}" ]]; then
        skip "Could not parse block numbers from latest/finalized responses"
    fi

    local depth=$(( latest_num - finalized_num ))
    local max_depth="${FINALITY_MAX_DEPTH:-256}"

    echo "latest=${latest_num}, finalized=${finalized_num}, depth=${depth}, max_allowed=${max_depth}" >&3

    if [[ "${finalized_num}" -eq 0 ]]; then
        echo "CRITICAL: Finalized block is at zero — finality has not started" >&2
        return 1
    fi

    if [[ "${depth}" -gt "${max_depth}" ]]; then
        echo "CRITICAL: Finality depth (${depth}) exceeds maximum allowed (${max_depth})" >&2
        echo "  latest=${latest_num}, finalized=${finalized_num}" >&2
        echo "" >&2
        echo "  Finality is falling too far behind block production." >&2
        echo "  This could indicate milestone voting is stalled or Heimdall is lagging." >&2
        return 1
    fi

    if [[ "${depth}" -lt 0 ]]; then
        echo "CRITICAL: Negative finality depth (${depth}) — finalized ahead of latest!" >&2
        return 1
    fi

    echo "Finality depth ${depth} is within acceptable range (<= ${max_depth})" >&3
}
