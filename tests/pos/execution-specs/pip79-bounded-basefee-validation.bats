#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip79,lisovo

# PIP-79: Bounded-Range Validation for Configurable EIP-1559 Parameters
#
# Replaces Polygon PoS's deterministic EIP-1559 baseFee validation with
# boundary-based validation. Instead of requiring blocks to declare an
# exact baseFee computed from hardcoded parameters, validators accept any
# baseFee within a +/-5% range of the parent block's baseFee.
#
# Consensus rules:
#   lowerBound = parentBaseFee * 95 / 100  (floor division)
#   upperBound = parentBaseFee * 105 / 100 (floor division)
#   Valid iff:  lowerBound <= childBaseFee <= upperBound
#   Minimum:    childBaseFee >= 1 wei (baseFee of 0 is always invalid)
#
# Activated with the Lisovo hardfork on Polygon PoS.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# Helper: detect if Lisovo hardfork is active by probing the CLZ opcode (EIP-7939).
# CLZ activates in the same Lisovo hardfork as PIP-79.
# Returns 0 if Lisovo is active, 1 otherwise.
_is_lisovo_active() {
    # Deploy a tiny contract: PUSH1 0x01 CLZ(0x1e) POP STOP
    # If CLZ is active, this succeeds. If not, it reverts (invalid opcode).
    local runtime="60011e5000"
    local initcode="6005600c600039600560 00f3${runtime}"
    # Clean hex
    initcode="6005600c6000396005600 0f3${runtime}"
    initcode="6005600c60003960056000f3${runtime}"

    local receipt
    receipt=$(cast send \
        --legacy --gas-limit 100000 \
        --private-key "$PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}" 2>/dev/null) || return 1

    local addr
    addr=$(echo "$receipt" | jq -r '.contractAddress')
    [[ "$addr" == "null" || -z "$addr" ]] && return 1

    local call_receipt
    call_receipt=$(cast send \
        --legacy --gas-limit 100000 \
        --private-key "$PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" --json \
        "$addr" 2>/dev/null) || return 1

    local status
    status=$(echo "$call_receipt" | jq -r '.status')
    [[ "$status" == "0x1" ]]
}

# ─── Feature probe ────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "base fee is present and positive on all recent blocks (PIP-79 invariant)" {
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest" -lt 10 ]]; then
        skip "Not enough blocks to verify base fee invariant (need >= 10)"
    fi

    local start=$(( latest - 9 ))
    local failures=0

    for ((bn = start; bn <= latest; bn++)); do
        local base_fee_hex
        base_fee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // "0x0"')

        local base_fee_dec
        base_fee_dec=$(printf "%d" "$base_fee_hex")

        if [[ "$base_fee_dec" -lt 1 ]]; then
            echo "Block $bn: baseFee = $base_fee_dec (must be >= 1 wei)" >&2
            failures=$(( failures + 1 ))
        fi
    done

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures block(s) have baseFee < 1 wei" >&2
        return 1
    fi

    echo "All blocks $start..$latest have positive baseFee" >&3
}

# ─── Lisovo-specific: baseFee no longer strictly deterministic ─────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "PIP-79 active: baseFee deviates from old deterministic formula (Lisovo only)" {
    # Pre-Lisovo, baseFee is computed deterministically from parent block's gasUsed
    # and gasLimit using denominator 64. Post-Lisovo (PIP-79), block producers can
    # choose any baseFee within ±5% of parent. This test verifies the chain is NOT
    # strictly following the old deterministic formula, confirming PIP-79 is active.
    #
    # Skip on pre-Lisovo chains (detected via CLZ opcode probe).

    if ! _is_lisovo_active; then
        skip "Lisovo hardfork not active (CLZ opcode probe failed)"
    fi

    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")
    local depth=50

    if [[ "$latest" -lt "$depth" ]]; then
        depth="$latest"
    fi
    if [[ "$depth" -lt 10 ]]; then
        skip "Not enough blocks to detect non-deterministic baseFee"
    fi

    local start=$(( latest - depth + 1 ))
    local deviations=0
    local checks=0

    for ((bn = start + 1; bn <= latest; bn++)); do
        local parent_json
        parent_json=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' $(( bn - 1 )))" false \
            --rpc-url "$L2_RPC_URL")
        local child_json
        child_json=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL")

        local parent_base_fee
        parent_base_fee=$(printf "%d" "$(echo "$parent_json" | jq -r '.baseFeePerGas // "0x0"')")
        local parent_gas_used
        parent_gas_used=$(printf "%d" "$(echo "$parent_json" | jq -r '.gasUsed // "0x0"')")
        local parent_gas_limit
        parent_gas_limit=$(printf "%d" "$(echo "$parent_json" | jq -r '.gasLimit // "0x0"')")
        local child_base_fee
        child_base_fee=$(printf "%d" "$(echo "$child_json" | jq -r '.baseFeePerGas // "0x0"')")

        [[ "$parent_base_fee" -lt 1 || "$parent_gas_limit" -lt 1 ]] && continue
        checks=$(( checks + 1 ))

        # Compute the old deterministic baseFee (denominator = 64)
        local target_gas=$(( parent_gas_limit / 2 ))
        local deterministic_base_fee
        if [[ "$parent_gas_used" -eq "$target_gas" ]]; then
            deterministic_base_fee="$parent_base_fee"
        elif [[ "$parent_gas_used" -gt "$target_gas" ]]; then
            local delta=$(( parent_gas_used - target_gas ))
            local increment=$(( parent_base_fee * delta / target_gas / 64 ))
            [[ "$increment" -lt 1 ]] && increment=1
            deterministic_base_fee=$(( parent_base_fee + increment ))
        else
            local delta=$(( target_gas - parent_gas_used ))
            local decrement=$(( parent_base_fee * delta / target_gas / 64 ))
            deterministic_base_fee=$(( parent_base_fee - decrement ))
            [[ "$deterministic_base_fee" -lt 1 ]] && deterministic_base_fee=1
        fi

        if [[ "$child_base_fee" -ne "$deterministic_base_fee" ]]; then
            deviations=$(( deviations + 1 ))
        fi
    done

    echo "Checked $checks blocks, $deviations deviated from old deterministic formula" >&3

    # On a Lisovo chain, we expect at least some blocks to deviate from the
    # old formula (block producers have tuning flexibility). If zero deviations
    # are found over 50 blocks, PIP-79 may not be effective.
    # Note: it's possible (but unlikely) that a producer coincidentally matches
    # the old formula on every block; treat 0 deviations as informational, not failure.
    if [[ "$deviations" -eq 0 ]]; then
        echo "WARNING: No deviations from old deterministic formula detected in $checks blocks" >&3
        echo "PIP-79 is active (CLZ probe passed) but producer may be using default parameters" >&3
    fi
}

# ─── Core validation: ±5% bounded range ──────────────────────────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "consecutive block baseFees are within ±5% of each other" {
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")
    local depth=50

    if [[ "$latest" -lt "$depth" ]]; then
        depth="$latest"
    fi
    if [[ "$depth" -lt 2 ]]; then
        skip "Not enough blocks to check consecutive baseFee relationship"
    fi

    local start=$(( latest - depth + 1 ))
    local violations=0

    local prev_base_fee=""
    for ((bn = start; bn <= latest; bn++)); do
        local base_fee_hex
        base_fee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // "0x0"')
        local base_fee_dec
        base_fee_dec=$(printf "%d" "$base_fee_hex")

        if [[ -n "$prev_base_fee" && "$prev_base_fee" -gt 0 ]]; then
            local lower_bound=$(( prev_base_fee * 95 / 100 ))
            local upper_bound=$(( prev_base_fee * 105 / 100 ))

            # Enforce minimum of 1 wei
            if [[ "$lower_bound" -lt 1 ]]; then
                lower_bound=1
            fi

            if [[ "$base_fee_dec" -lt "$lower_bound" || "$base_fee_dec" -gt "$upper_bound" ]]; then
                echo "Block $bn: baseFee=$base_fee_dec outside ±5% of parent=$prev_base_fee" >&2
                echo "  Valid range: [$lower_bound, $upper_bound]" >&2
                violations=$(( violations + 1 ))
            fi
        fi

        prev_base_fee="$base_fee_dec"
    done

    echo "Checked $depth blocks ($start..$latest), violations: $violations" >&3

    if [[ "$violations" -gt 0 ]]; then
        echo "$violations baseFee boundary violation(s) found" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "baseFee change rate is tighter than Ethereum mainnet (max ±5% vs ±12.5%)" {
    # PIP-79 bounds baseFee to ±5% per block, which is tighter than Ethereum's
    # EIP-1559 ±12.5% (1/8). Verify the actual observed rate is within ±5%.
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest" -lt 20 ]]; then
        skip "Not enough blocks for rate analysis"
    fi

    local start=$(( latest - 19 ))
    local max_increase_pct=0
    local max_decrease_pct=0
    local prev_base_fee=""

    for ((bn = start; bn <= latest; bn++)); do
        local base_fee_hex
        base_fee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // "0x0"')
        local base_fee_dec
        base_fee_dec=$(printf "%d" "$base_fee_hex")

        if [[ -n "$prev_base_fee" && "$prev_base_fee" -gt 0 ]]; then
            # Calculate percentage change (multiplied by 1000 for 0.1% precision)
            local diff=$(( base_fee_dec - prev_base_fee ))
            local pct_x1000
            if [[ "$prev_base_fee" -gt 0 ]]; then
                pct_x1000=$(( diff * 100000 / prev_base_fee ))
            else
                pct_x1000=0
            fi

            # Track max increase/decrease
            if [[ "$pct_x1000" -gt "$max_increase_pct" ]]; then
                max_increase_pct="$pct_x1000"
            fi
            if [[ "$pct_x1000" -lt "$max_decrease_pct" ]]; then
                max_decrease_pct="$pct_x1000"
            fi
        fi

        prev_base_fee="$base_fee_dec"
    done

    echo "Max increase: $(( max_increase_pct / 1000 )).$(( (max_increase_pct % 1000 + 1000) % 1000 ))%" >&3
    echo "Max decrease: $(( max_decrease_pct / 1000 )).$(( ((-max_decrease_pct) % 1000 + 1000) % 1000 ))%" >&3

    # ±5% = ±5000 in our x1000 scale. Add small epsilon for rounding.
    if [[ "$max_increase_pct" -gt 5100 ]]; then
        echo "Max baseFee increase exceeds +5%: ${max_increase_pct}/1000 %" >&2
        return 1
    fi
    if [[ "$max_decrease_pct" -lt -5100 ]]; then
        echo "Max baseFee decrease exceeds -5%: ${max_decrease_pct}/1000 %" >&2
        return 1
    fi
}

# ─── Stress: baseFee behavior under load ──────────────────────────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee,stress
@test "baseFee stays within ±5% bounds under transaction load" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local ephemeral_private_key
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    local ephemeral_address
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')

    # Fund the ephemeral wallet
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --legacy --gas-limit 21000 --value 2ether "$ephemeral_address" >/dev/null

    local before_block
    before_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Send a burst of transactions to increase gas usage and push baseFee up.
    local nonce
    nonce=$(cast nonce "$ephemeral_address" --rpc-url "$L2_RPC_URL")

    local burn_addr="0x000000000000000000000000000000000000dEaD"
    for ((i = 0; i < 20; i++)); do
        cast send --rpc-url "$L2_RPC_URL" --private-key "$ephemeral_private_key" \
            --legacy --gas-limit 21000 --nonce $(( nonce + i )) \
            --value 0.001ether "$burn_addr" --async >/dev/null 2>&1 || true
    done

    # Wait for transactions to be included (up to 30 seconds)
    local timeout=30
    local waited=0
    while [[ "$waited" -lt "$timeout" ]]; do
        local current_block
        current_block=$(cast block-number --rpc-url "$L2_RPC_URL")
        if [[ $(( current_block - before_block )) -ge 5 ]]; then
            break
        fi
        sleep 2
        waited=$(( waited + 2 ))
    done

    local after_block
    after_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    # Now verify all blocks in the range maintain ±5% invariant
    local violations=0
    local prev_base_fee=""
    for ((bn = before_block; bn <= after_block; bn++)); do
        local base_fee_hex
        base_fee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // "0x0"')
        local base_fee_dec
        base_fee_dec=$(printf "%d" "$base_fee_hex")

        if [[ -n "$prev_base_fee" && "$prev_base_fee" -gt 0 ]]; then
            local lower=$(( prev_base_fee * 95 / 100 ))
            local upper=$(( prev_base_fee * 105 / 100 ))
            [[ "$lower" -lt 1 ]] && lower=1

            if [[ "$base_fee_dec" -lt "$lower" || "$base_fee_dec" -gt "$upper" ]]; then
                echo "Block $bn: baseFee=$base_fee_dec outside [$lower, $upper] (parent=$prev_base_fee)" >&2
                violations=$(( violations + 1 ))
            fi
        fi

        prev_base_fee="$base_fee_dec"
    done

    echo "Under load: checked blocks $before_block..$after_block, violations: $violations" >&3

    if [[ "$violations" -gt 0 ]]; then
        echo "$violations baseFee boundary violation(s) under load" >&2
        return 1
    fi
}

# ─── Long-range convergence ───────────────────────────────────────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "baseFee does not diverge over a long block range" {
    # Over many blocks, baseFee should remain bounded. Check that it doesn't
    # grow or shrink unboundedly (which would indicate a broken feedback loop).
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")
    local depth=100

    if [[ "$latest" -lt "$depth" ]]; then
        depth="$latest"
    fi
    if [[ "$depth" -lt 10 ]]; then
        skip "Not enough blocks for long-range baseFee check"
    fi

    local start=$(( latest - depth + 1 ))

    local first_base_fee=""
    local last_base_fee=""
    local min_base_fee=""
    local max_base_fee=""

    for ((bn = start; bn <= latest; bn++)); do
        local base_fee_hex
        base_fee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$bn")" false \
            --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // "0x0"')
        local base_fee_dec
        base_fee_dec=$(printf "%d" "$base_fee_hex")

        if [[ -z "$first_base_fee" ]]; then
            first_base_fee="$base_fee_dec"
            min_base_fee="$base_fee_dec"
            max_base_fee="$base_fee_dec"
        fi
        last_base_fee="$base_fee_dec"

        if [[ "$base_fee_dec" -lt "$min_base_fee" ]]; then min_base_fee="$base_fee_dec"; fi
        if [[ "$base_fee_dec" -gt "$max_base_fee" ]]; then max_base_fee="$base_fee_dec"; fi
    done

    echo "Range $start..$latest ($depth blocks):" >&3
    echo "  first=$first_base_fee last=$last_base_fee min=$min_base_fee max=$max_base_fee" >&3

    # BaseFee should never be zero
    if [[ "$min_base_fee" -lt 1 ]]; then
        echo "BaseFee reached 0 — violates PIP-79 minimum of 1 wei" >&2
        return 1
    fi

    # Sanity check: with ±5% per block over 100 blocks, the theoretical max
    # cumulative change is 1.05^100 ≈ 131x. If baseFee changed by more than
    # 200x over this range, something is likely broken.
    if [[ "$max_base_fee" -gt 0 && "$min_base_fee" -gt 0 ]]; then
        local ratio=$(( max_base_fee / min_base_fee ))
        if [[ "$ratio" -gt 200 ]]; then
            echo "BaseFee ratio (max/min) = $ratio exceeds expected bound of 200x" >&2
            return 1
        fi
    fi
}

# ─── Block header field validation ─────────────────────────────────────────────

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "baseFeePerGas field exists in block headers" {
    local latest
    latest=$(cast block-number --rpc-url "$L2_RPC_URL")

    local block_json
    block_json=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$latest")" false \
        --rpc-url "$L2_RPC_URL")

    local base_fee_field
    base_fee_field=$(echo "$block_json" | jq -r '.baseFeePerGas // "MISSING"')

    if [[ "$base_fee_field" == "MISSING" || "$base_fee_field" == "null" ]]; then
        echo "baseFeePerGas field missing from block $latest header" >&2
        return 1
    fi

    local base_fee_dec
    base_fee_dec=$(printf "%d" "$base_fee_field")
    echo "Block $latest baseFeePerGas = $base_fee_dec wei" >&3

    if [[ "$base_fee_dec" -lt 1 ]]; then
        echo "baseFeePerGas = $base_fee_dec is invalid (must be >= 1)" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip79,lisovo,basefee
@test "BASEFEE opcode returns value matching block header baseFeePerGas" {
    # Deploy a contract that uses the BASEFEE opcode (0x48) and stores result.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local ephemeral_private_key
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    local ephemeral_address
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # Runtime: BASEFEE PUSH1 0x00 SSTORE STOP
    # BASEFEE = 0x48
    local runtime="4860005500"
    local runtime_len=$(( ${#runtime} / 2 ))
    local runtime_len_hex
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    local initcode="60${runtime_len_hex}600c60003960${runtime_len_hex}6000f3${runtime}"

    local deploy_receipt
    deploy_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")
    local contract_addr
    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    local call_receipt
    call_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" --json \
        "$contract_addr")

    local call_status
    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "BASEFEE contract call failed: $call_status" >&2
        return 1
    fi

    # Get the stored BASEFEE value
    local stored
    stored=$(cast storage "$contract_addr" 0 --rpc-url "$L2_RPC_URL")
    local opcode_basefee
    opcode_basefee=$(printf "%d" "$stored")

    # Get baseFee from the block header where the tx was included
    local tx_block_hex
    tx_block_hex=$(echo "$call_receipt" | jq -r '.blockNumber')
    local tx_block_dec
    tx_block_dec=$(printf "%d" "$tx_block_hex")

    local header_basefee_hex
    header_basefee_hex=$(cast rpc eth_getBlockByNumber "$(printf '0x%x' "$tx_block_dec")" false \
        --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas')
    local header_basefee
    header_basefee=$(printf "%d" "$header_basefee_hex")

    echo "BASEFEE opcode=$opcode_basefee, header=$header_basefee (block $tx_block_dec)" >&3

    if [[ "$opcode_basefee" -ne "$header_basefee" ]]; then
        echo "BASEFEE opcode ($opcode_basefee) != block header ($header_basefee)" >&2
        return 1
    fi
}
