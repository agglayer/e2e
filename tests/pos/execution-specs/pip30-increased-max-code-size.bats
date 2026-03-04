#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip30

# PIP-30: Increase Max Code Size from 24KB (EIP-170) to 32KB
# Activated in Ahmedabad hardfork (mainnet block 62,278,656).
# https://github.com/maticnetwork/Polygon-Improvement-Proposals/blob/main/PIPs/PIP-30.md
#
# Standard Ethereum enforces MAX_CODE_SIZE = 24,576 bytes (EIP-170).
# PIP-30 raises this to 32,768 bytes on Polygon PoS.
# Tests detect the active limit and verify boundary behavior.

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    # Fund with 2 ETH: deploying 32KB contracts costs ~6.5M gas in code-deposit
    # (200 gas/byte * 32768 = 6,553,600) plus overhead. At 25 Gwei ~ 0.17 ETH/deploy.
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 2ether "$ephemeral_address" >/dev/null
}

# Helper: attempt to deploy a contract that RETURNs `size` bytes of zeroed memory.
# Initcode: PUSH3 <size> PUSH1 0x00 RETURN
# Outputs receipt JSON on success, empty string on failure.
_deploy_runtime_size() {
    local size=$1
    local size_hex
    size_hex=$(printf '%06x' "$size")
    # Gas: code-deposit (200/byte) + memory expansion + overhead
    local gas_limit=$(( 200 * size + 500000 ))

    set +e
    local receipt
    receipt=$(cast send \
        --legacy \
        --gas-limit "$gas_limit" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x62${size_hex}6000f3" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 && -n "$receipt" ]]; then
        echo "$receipt"
    fi
}

# bats test_tags=execution-specs,pip30,code-size
@test "PIP-30 probe: deploy 24577-byte runtime to detect active MAX_CODE_SIZE" {
    # 24577 bytes exceeds EIP-170 (24576) but is within PIP-30 (32768).
    # If PIP-30 is active: deployment succeeds. If standard EIP-170: fails.
    local receipt
    receipt=$(_deploy_runtime_size 24577)

    if [[ -n "$receipt" ]]; then
        local tx_status
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            local contract_addr
            contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
            local deployed_code
            deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
            local deployed_len=$(( (${#deployed_code} - 2) / 2 ))
            echo "PIP-30 ACTIVE: 24577-byte runtime deployed ($deployed_len bytes at $contract_addr)" >&3
            [[ "$deployed_len" -eq 24577 ]]
            return 0
        fi
    fi

    echo "PIP-30 NOT ACTIVE: 24577-byte runtime rejected (standard EIP-170 limit)" >&3
    echo "Chain enforces MAX_CODE_SIZE = 24576 bytes (Ethereum standard)" >&3
    # Pass either way — this test documents the active limit
}

# bats test_tags=execution-specs,pip30,code-size
@test "PIP-30: deploy exactly 32768-byte runtime succeeds at PIP-30 boundary" {
    # First probe whether PIP-30 is active
    local probe
    probe=$(_deploy_runtime_size 24577)
    if [[ -z "$probe" ]] || [[ $(echo "$probe" | jq -r '.status // "0x0"') != "0x1" ]]; then
        skip "PIP-30 not active on this chain (EIP-170 24KB limit in effect)"
    fi

    # Deploy exactly 32768 bytes — the PIP-30 maximum
    local receipt
    receipt=$(_deploy_runtime_size 32768)

    if [[ -z "$receipt" ]]; then
        echo "32768-byte deploy rejected at RPC level" >&2
        return 1
    fi

    local tx_status
    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "32768-byte runtime deploy failed (status=$tx_status)" >&2
        return 1
    fi

    local contract_addr
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    local deployed_code
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    local deployed_len=$(( (${#deployed_code} - 2) / 2 ))

    if [[ "$deployed_len" -ne 32768 ]]; then
        echo "Expected 32768-byte runtime, got $deployed_len bytes" >&2
        return 1
    fi
    echo "PIP-30 boundary confirmed: 32768-byte runtime at $contract_addr" >&3
}

# bats test_tags=execution-specs,pip30,code-size
@test "PIP-30: deploy 32769-byte runtime is rejected (exceeds PIP-30 limit)" {
    # 32769 bytes exceeds both EIP-170 (24576) and PIP-30 (32768).
    # Must be rejected regardless of which limit is active.
    local receipt
    receipt=$(_deploy_runtime_size 32769)

    if [[ -n "$receipt" ]]; then
        local tx_status
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 32769-byte runtime (over both limits), but tx succeeded" >&2
            return 1
        fi
    fi
    # Rejected — correct behavior regardless of PIP-30 status
}

# bats test_tags=execution-specs,pip30,code-size
@test "PIP-30: deploy 28000-byte runtime succeeds (between EIP-170 and PIP-30 limits)" {
    # 28000 bytes is between EIP-170 (24576) and PIP-30 (32768).
    # Succeeds only if PIP-30 is active.
    local probe
    probe=$(_deploy_runtime_size 24577)
    if [[ -z "$probe" ]] || [[ $(echo "$probe" | jq -r '.status // "0x0"') != "0x1" ]]; then
        skip "PIP-30 not active on this chain (EIP-170 24KB limit in effect)"
    fi

    local receipt
    receipt=$(_deploy_runtime_size 28000)

    if [[ -z "$receipt" ]]; then
        echo "28000-byte deploy rejected at RPC level" >&2
        return 1
    fi

    local tx_status
    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "28000-byte runtime deploy failed (status=$tx_status)" >&2
        return 1
    fi

    local contract_addr
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    local deployed_code
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    local deployed_len=$(( (${#deployed_code} - 2) / 2 ))

    if [[ "$deployed_len" -ne 28000 ]]; then
        echo "Expected 28000-byte runtime, got $deployed_len bytes" >&2
        return 1
    fi
    echo "28000-byte runtime deployed at $contract_addr" >&3
}
