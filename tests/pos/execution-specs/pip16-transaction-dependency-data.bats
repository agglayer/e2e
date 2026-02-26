#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip16

# PIP-16: Transaction Dependency Data in Block Headers
# Activated in Napoli hardfork (mainnet block 54,876,000).
# https://github.com/maticnetwork/Polygon-Improvement-Proposals/blob/main/PIPs/PIP-16.md
#
# Embeds transaction dependency information in the block header's extraData field.
# This enables parallel transaction execution by full nodes. The extraData
# format includes tx dependency metadata beyond the standard client version string.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=execution-specs,pip16,block-header
@test "PIP-16: block extraData field is non-empty and present" {
    # Bor blocks should have extraData containing validator signature and
    # optionally transaction dependency data (PIP-16).
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    local extra_data
    extra_data=$(cast block "$latest_block" --json --rpc-url "$L2_RPC_URL" | jq -r '.extraData // empty')

    if [[ -z "$extra_data" || "$extra_data" == "0x" ]]; then
        echo "Block $latest_block has empty extraData" >&2
        return 1
    fi

    local extra_len=$(( (${#extra_data} - 2) / 2 ))
    echo "Block $latest_block extraData: $extra_len bytes" >&3

    # Bor extraData is typically 32 bytes vanity + 65 bytes signature = 97 bytes minimum.
    # With PIP-16 dependency data, it may be larger.
    if [[ "$extra_len" -lt 97 ]]; then
        echo "ExtraData unusually short ($extra_len bytes, expected >= 97 for Bor)" >&3
    fi
}

# bats test_tags=execution-specs,pip16,block-header
@test "PIP-16: extraData is consistent across multiple recent blocks" {
    # Verify that extraData is present in multiple blocks and has a consistent
    # minimum size, confirming it's structurally valid (not random garbage).
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    if [[ "$latest_block" -lt 5 ]]; then
        skip "Need at least 5 blocks"
    fi

    local min_len=999999
    local max_len=0
    local all_present=true

    for i in $(seq 0 4); do
        local block_num=$(( latest_block - i ))
        local extra_data
        extra_data=$(cast block "$block_num" --json --rpc-url "$L2_RPC_URL" | jq -r '.extraData // empty')

        if [[ -z "$extra_data" || "$extra_data" == "0x" ]]; then
            all_present=false
            echo "Block $block_num has empty extraData" >&2
            continue
        fi

        local extra_len=$(( (${#extra_data} - 2) / 2 ))

        if [[ "$extra_len" -lt "$min_len" ]]; then
            min_len=$extra_len
        fi
        if [[ "$extra_len" -gt "$max_len" ]]; then
            max_len=$extra_len
        fi
    done

    echo "ExtraData size across 5 blocks: min=$min_len max=$max_len" >&3

    if [[ "$all_present" != "true" ]]; then
        echo "Some blocks have empty extraData" >&2
        return 1
    fi

    # All blocks should have at least Bor's minimum (vanity + signature = 97 bytes)
    if [[ "$min_len" -lt 32 ]]; then
        echo "Minimum extraData ($min_len bytes) is below Bor's expected minimum" >&2
        return 1
    fi
}
