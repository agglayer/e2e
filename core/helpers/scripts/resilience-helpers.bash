#!/usr/bin/env bash

# Shared helpers for resilience test suite.
# Load from test files with: load "../../../../core/helpers/scripts/resilience-helpers.bash"

# Wait for the chain to advance at least $min_advance blocks past $start_block.
# Returns the final block number on success.
# Usage: _wait_for_block_advance <start_block> [min_advance=10] [timeout=120]
_wait_for_block_advance() {
    local start_block="$1"
    local min_advance="${2:-10}"
    local timeout="${3:-120}"
    local target=$(( start_block + min_advance ))
    local elapsed=0

    while true; do
        local current
        current=$(cast block-number --rpc-url "$L2_RPC_URL" 2>/dev/null) || current=0
        if [[ "$current" -ge "$target" ]]; then
            echo "$current"
            return 0
        fi
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "Timeout: chain stuck at block $current, expected >= $target" >&2
            return 1
        fi
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done
}

# Fund a fresh ephemeral wallet and echo "private_key:address".
# DEVNET ONLY — keys are visible in command arguments.
# Usage: wallet=$(_fund_ephemeral_wallet [amount])
_fund_ephemeral_wallet() {
    local amount="${1:-0.5ether}"
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local pk addr
    pk=$(echo "$wallet_json" | jq -r '.private_key')
    addr=$(echo "$wallet_json" | jq -r '.address')

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
        --legacy --gas-limit 21000 --value "$amount" "$addr" >/dev/null

    echo "${pk}:${addr}"
}

# Assert the RPC endpoint is responsive (retries up to $attempts times).
# Usage: _assert_rpc_alive [rpc_url] [label]
_assert_rpc_alive() {
    local rpc_url="${1:-$L2_RPC_URL}"
    local label="${2:-}"
    local attempts=3

    for i in $(seq 1 "$attempts"); do
        local result
        result=$(cast block-number --rpc-url "$rpc_url" 2>/dev/null)
        if [[ -n "$result" && "$result" =~ ^[0-9]+$ && "$result" -gt 0 ]]; then
            return 0
        fi
        sleep 2
    done

    echo "RPC unresponsive after $attempts attempts${label:+ ($label)}" >&2
    return 1
}

# Deploy a minimal counter contract (increment/get on storage slot 0).
# Returns the deployed contract address.
# Usage: addr=$(_deploy_counter_contract <rpc_url> <private_key>)
_deploy_counter_contract() {
    local rpc_url="$1"
    local private_key="$2"

    # Bytecode for a minimal counter contract
    # increment(): SLOAD 0, ADD 1, SSTORE 0
    # get(): SLOAD 0, MSTORE, RETURN
    local bytecode="0x608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b506004361061003a5760003560e01c80636d4ce63c1461003f578063d09de08a1461005d575b600080fd5b610047610067565b6040518082815260200191505060405180910390f35b610065610070565b005b60008054905090565b600160005401600081905550565b"

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$rpc_url")
    local comp_gas_price
    comp_gas_price=$(echo "$gas_price * 25 / 10" | bc)

    local output
    output=$(cast send --rpc-url "$rpc_url" --private-key "$private_key" \
        --gas-price "$comp_gas_price" --legacy --create "$bytecode" --json 2>&1)

    echo "$output" | jq -r '.contractAddress // empty'
}

# Assert we are targeting a Kurtosis devnet (safety guard).
# Skips the test if ENCLAVE_NAME is not set.
_require_devnet() {
    if [[ -z "${ENCLAVE_NAME:-}" && -z "${RESILIENCE_ALLOW_NON_DEVNET:-}" ]]; then
        skip "Resilience tests require a Kurtosis devnet (set ENCLAVE_NAME or RESILIENCE_ALLOW_NON_DEVNET=1)"
    fi
}
