#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip6,pip58

# PIP-6: BaseFeeChangeDenominator 8 -> 16 (Delhi hardfork, mainnet block 38,189,056)
# PIP-58: BaseFeeChangeDenominator 16 -> 64 (Bhilai hardfork, mainnet block 73,440,256)
#
# Standard Ethereum uses denominator 8 (max 12.5% change per block).
# Polygon PoS currently uses denominator 64 (max ~1.56% change per block).
# This smooths out base fee volatility during congestion spikes.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=execution-specs,pip6,pip58,eip1559
@test "PIP-6/58: base fee changes by at most 1/64 per block (denominator = 64)" {
    # Sample 10 consecutive blocks and verify the base fee change between each
    # pair is bounded by baseFee/64 (the PIP-58 denominator).
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest_block" -lt 11 ]]; then
        skip "Need at least 11 blocks to check base fee changes over 10 pairs"
    fi

    local violations=0
    local checks=0
    local prev_base_fee=""

    for i in $(seq 0 10); do
        local block_num=$(( latest_block - 10 + i ))
        local base_fee_hex
        base_fee_hex=$(cast block "$block_num" --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // empty')

        if [[ -z "$base_fee_hex" ]]; then
            skip "Block $block_num does not have baseFeePerGas"
        fi

        local base_fee
        base_fee=$(printf "%d" "$base_fee_hex")

        if [[ -n "$prev_base_fee" && "$prev_base_fee" -gt 0 ]]; then
            local change=$(( base_fee - prev_base_fee ))
            # Absolute value
            if [[ "$change" -lt 0 ]]; then
                change=$(( -change ))
            fi

            # Max allowed change with denominator 64: baseFee / 64
            # Add 1 for rounding tolerance
            local max_change_64=$(( prev_base_fee / 64 + 1 ))

            checks=$(( checks + 1 ))

            if [[ "$change" -gt "$max_change_64" ]]; then
                echo "Block $(( block_num - 1 ))->$block_num: change=$change exceeds 1/64 max=$max_change_64 (prev=$prev_base_fee cur=$base_fee)" >&2
                violations=$(( violations + 1 ))
            fi
        fi

        prev_base_fee=$base_fee
    done

    echo "Checked $checks block pairs, $violations exceeded 1/64 bound" >&3

    if [[ "$violations" -gt 0 ]]; then
        echo "$violations / $checks block pairs exceeded the PIP-58 1/64 bound" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip6,pip58,eip1559
@test "PIP-6/58: base fee change rate is tighter than Ethereum default (1/8)" {
    # Verify the denominator is larger than Ethereum's default of 8 by checking
    # that on empty blocks (gasUsed=0), the base fee decreases by less than 1/8.
    # With denominator 64, empty-block decrease = baseFee/64 (~1.56%).
    # With denominator 8 (Ethereum), it would be baseFee/8 (12.5%).
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest_block" -lt 20 ]]; then
        skip "Need at least 20 blocks to find empty block pairs"
    fi

    local found_empty_pair=false
    local denominator_estimate=0

    for i in $(seq 1 19); do
        local block_num=$(( latest_block - 20 + i ))
        local block_json
        block_json=$(cast block "$block_num" --json --rpc-url "$L2_RPC_URL")

        local gas_used
        gas_used=$(echo "$block_json" | jq -r '.gasUsed' | xargs printf "%d\n")
        local base_fee
        base_fee=$(echo "$block_json" | jq -r '.baseFeePerGas' | xargs printf "%d\n")

        # Look for an empty block (gasUsed = 0)
        if [[ "$gas_used" -eq 0 && "$base_fee" -gt 100 ]]; then
            local next_json
            next_json=$(cast block "$(( block_num + 1 ))" --json --rpc-url "$L2_RPC_URL")
            local next_base_fee
            next_base_fee=$(echo "$next_json" | jq -r '.baseFeePerGas' | xargs printf "%d\n")

            local decrease=$(( base_fee - next_base_fee ))
            if [[ "$decrease" -gt 0 ]]; then
                found_empty_pair=true
                # Estimate denominator: baseFee / decrease
                denominator_estimate=$(( base_fee / decrease ))
                echo "Empty block $block_num: baseFee=$base_fee next=$next_base_fee decrease=$decrease" >&3
                echo "Estimated denominator: ~$denominator_estimate" >&3

                # Must be larger than Ethereum's 8
                if [[ "$denominator_estimate" -lt 9 ]]; then
                    echo "Denominator ~$denominator_estimate is not larger than Ethereum's 8" >&2
                    return 1
                fi
                break
            fi
        fi
    done

    if [[ "$found_empty_pair" != "true" ]]; then
        skip "No empty blocks with sufficient base fee found in last 20 blocks"
    fi
}

# bats test_tags=execution-specs,pip6,pip58,eip1559
@test "PIP-6/58: base fee is always positive and non-zero" {
    # Regardless of denominator, the base fee must always be positive on
    # a post-London chain. Sample 5 recent blocks.
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest_block" -lt 5 ]]; then
        skip "Need at least 5 blocks"
    fi

    for i in $(seq 0 4); do
        local block_num=$(( latest_block - i ))
        local base_fee_hex
        base_fee_hex=$(cast block "$block_num" --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas // empty')

        if [[ -z "$base_fee_hex" ]]; then
            echo "Block $block_num has no baseFeePerGas field" >&2
            return 1
        fi

        local base_fee
        base_fee=$(printf "%d" "$base_fee_hex")

        if [[ "$base_fee" -le 0 ]]; then
            echo "Block $block_num has non-positive baseFeePerGas: $base_fee" >&2
            return 1
        fi
    done

    echo "All 5 sampled blocks have positive baseFeePerGas" >&3
}
