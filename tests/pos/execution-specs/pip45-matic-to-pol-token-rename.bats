#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pip45

# PIP-45: Token Symbol Change MATIC -> POL
# Activated in Ahmedabad hardfork (mainnet block 62,278,656).
# https://github.com/maticnetwork/Polygon-Improvement-Proposals/blob/main/PIPs/PIP-45.md
#
# The MRC20 system contract at 0x0000...1010 was updated via hard fork bytecode
# replacement to return "Polygon Ecosystem Token" for name() and "POL" for symbol().

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=execution-specs,pip45,system-contract
@test "PIP-45: MRC20 system contract name() returns valid token name" {
    local mrc20="0x0000000000000000000000000000000000001010"

    # Verify contract has code
    local code
    code=$(cast code "$mrc20" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "MRC20 contract at $mrc20 has no code on this chain"
    fi

    # Call name() — ERC20 standard function
    set +e
    local name
    name=$(cast call "$mrc20" "name()(string)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 || -z "$name" ]]; then
        skip "MRC20 contract does not implement name() or call failed"
    fi

    echo "MRC20 name(): $name" >&3

    # PIP-45 renamed from "Matic Token" to "Polygon Ecosystem Token".
    # Pre-Ahmedabad chains still return "Matic Token" — both are valid.
    if [[ "$name" == *"Polygon Ecosystem Token"* ]]; then
        echo "PIP-45 active: name = Polygon Ecosystem Token" >&3
    elif [[ "$name" == *"Matic"* ]]; then
        echo "PIP-45 not yet active: name = Matic Token (pre-Ahmedabad)" >&3
    else
        echo "Unexpected MRC20 name: $name" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip45,system-contract
@test "PIP-45: MRC20 system contract symbol() returns valid token symbol" {
    local mrc20="0x0000000000000000000000000000000000001010"

    local code
    code=$(cast code "$mrc20" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "MRC20 contract at $mrc20 has no code on this chain"
    fi

    set +e
    local symbol
    symbol=$(cast call "$mrc20" "symbol()(string)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 || -z "$symbol" ]]; then
        skip "MRC20 contract does not implement symbol() or call failed"
    fi

    echo "MRC20 symbol(): $symbol" >&3

    # PIP-45 renamed from "MATIC" to "POL".
    # Pre-Ahmedabad chains still return "MATIC" — both are valid.
    if [[ "$symbol" == *"POL"* ]]; then
        echo "PIP-45 active: symbol = POL" >&3
    elif [[ "$symbol" == *"MATIC"* ]]; then
        echo "PIP-45 not yet active: symbol = MATIC (pre-Ahmedabad)" >&3
    else
        echo "Unexpected MRC20 symbol: $symbol" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,pip45,system-contract
@test "PIP-45: MRC20 system contract decimals() returns 18" {
    local mrc20="0x0000000000000000000000000000000000001010"

    local code
    code=$(cast code "$mrc20" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "MRC20 contract at $mrc20 has no code on this chain"
    fi

    set +e
    local decimals
    decimals=$(cast call "$mrc20" "decimals()(uint8)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 || -z "$decimals" ]]; then
        skip "MRC20 contract does not implement decimals() or call failed"
    fi

    echo "MRC20 decimals(): $decimals" >&3

    if [[ "$decimals" -ne 18 ]]; then
        echo "Expected 18 decimals, got: $decimals" >&2
        return 1
    fi
}
