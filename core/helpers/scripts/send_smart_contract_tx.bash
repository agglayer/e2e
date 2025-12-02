#!/usr/bin/env bash
# shellcheck disable=SC2154

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/extract_tx_hash.bash"

function send_smart_contract_transaction() {
    local private_key="$1"
    local receiver_addr="$2"
    local function_sig="$3"
    shift 3
    local params=("$@")

    echo "Sending smart contract transaction to $receiver_addr with function signature: '$function_sig' and params: ${params[*]}" >&3

    # Send the smart contract interaction using cast
    local cast_output tx_hash
    cast_output=$(cast send "$receiver_addr" --rpc-url "$rpc_url" --private-key "$private_key" "$function_sig" "${params[@]}" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to send transaction. Output:"
        echo "$cast_output"
        return 1
    fi

    tx_hash=$(extract_tx_hash "$cast_output")
    [[ -z "$tx_hash" ]] && {
        echo "Error: Failed to extract transaction hash."
        return 1
    }

    echo "Transaction successful (transaction hash: $tx_hash)"
}
