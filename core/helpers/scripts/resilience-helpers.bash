#!/usr/bin/env bash

# Shared helpers for resilience test suite.
# Load from test files with: load "../../../../core/helpers/scripts/resilience-helpers.bash"

# Return the current block number from the given RPC URL.
# Usage: _read_block_number <rpc_url>
_read_block_number() {
    local rpc_url="$1"
    local current

    current=$(cast block-number --rpc-url "$rpc_url" 2>/dev/null) || {
        echo "RPC block query failed for ${rpc_url}" >&2
        return 1
    }
    if [[ ! "$current" =~ ^[0-9]+$ ]]; then
        echo "Non-numeric block response from ${rpc_url}: ${current}" >&2
        return 1
    fi

    echo "$current"
}

# Wait for the chain to advance at least $min_advance blocks past $start_block
# on the given RPC URL. Returns the final block number on success.
# Usage: _wait_for_block_advance <start_block> [min_advance=10] [timeout=120] [rpc_url=$L2_RPC_URL]
_wait_for_block_advance() {
    local start_block="$1"
    local min_advance="${2:-10}"
    local timeout="${3:-120}"
    local rpc_url="${4:-$L2_RPC_URL}"
    local target=$(( start_block + min_advance ))
    local elapsed=0

    while true; do
        local current
        current=$(_read_block_number "$rpc_url" 2>/dev/null || true)
        if [[ -n "$current" && "$current" -ge "$target" ]]; then
            echo "$current"
            return 0
        fi
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "Timeout: chain stuck at block ${current:-unreachable}, expected >= $target" >&2
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

    for _attempt in $(seq 1 "$attempts"); do
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

    # Compiled with solc 0.8.24: Counter { uint256 count; increment(); get(); }
    local bytecode="0x608060405234801561000f575f80fd5b506101778061001d5f395ff3fe608060405234801561000f575f80fd5b506004361061003f575f3560e01c806306661abd146100435780636d4ce63c14610061578063d09de08a1461007f575b5f80fd5b61004b610089565b60405161005891906100c8565b60405180910390f35b61006961008e565b60405161007691906100c8565b60405180910390f35b610087610096565b005b5f5481565b5f8054905090565b60015f808282546100a7919061010e565b92505081905550565b5f819050919050565b6100c2816100b0565b82525050565b5f6020820190506100db5f8301846100b9565b92915050565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52601160045260245ffd5b5f610118826100b0565b9150610123836100b0565b925082820190508082111561013b5761013a6100e1565b5b9291505056fea264697066735822122098de8aa3dfbbd6a49c98a433cd4110648ab1b5ee398e692aa7e732715cf5488264736f6c63430008180033"

    local gas_price
    gas_price=$(cast gas-price --rpc-url "$rpc_url")
    local comp_gas_price
    comp_gas_price=$(echo "$gas_price * 25 / 10" | bc)

    local output
    output=$(cast send --rpc-url "$rpc_url" --private-key "$private_key" \
        --gas-price "$comp_gas_price" --gas-limit 500000 --legacy --create "$bytecode" --json 2>&1)

    echo "$output" | jq -r '.contractAddress // empty'
}

# Assert we are targeting a Kurtosis devnet (safety guard).
# Skips the test if ENCLAVE_NAME is not set.
_require_devnet() {
    if [[ -z "${ENCLAVE_NAME:-}" && -z "${RESILIENCE_ALLOW_NON_DEVNET:-}" ]]; then
        skip "Resilience tests require a Kurtosis devnet (set ENCLAVE_NAME or RESILIENCE_ALLOW_NON_DEVNET=1)"
    fi
}
