#!/usr/bin/env bats
# bats file_tags=agglayer

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars
}

# bats test_tags=agglayer-rpc,reth-l1
@test "eth_getTransactionBySenderAndNonce returns a transaction on Reth L1" {
    # Send a transaction on L1 so we have a known sender+nonce pair
    local nonce
    nonce=$(cast nonce "$l1_eth_address" --rpc-url "$l1_rpc_url")

    local tx_hash
    tx_hash=$(cast send --private-key "$l1_private_key" \
        --rpc-url "$l1_rpc_url" \
        --value 0.001ether \
        "$l1_eth_address" \
        --json | jq -r '.transactionHash')

    if [[ -z "$tx_hash" || "$tx_hash" == "null" ]]; then
        echo "Failed to send L1 transaction"
        exit 1
    fi

    # Verify the RPC method exists and doesn't return an error.
    # cast rpc will exit non-zero if the method is not found, catching
    # the case where the L1 node doesn't support this Reth-specific method.
    local result
    run cast rpc --rpc-url "$l1_rpc_url" eth_getTransactionBySenderAndNonce "$l1_eth_address" "$(printf '0x%x' "$nonce")"
    if [[ "$status" -ne 0 ]]; then
        echo "eth_getTransactionBySenderAndNonce RPC call failed (method may not be supported): $output"
        exit 1
    fi
    result="$output"

    # The method returns Option<Transaction> — null means not found.
    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "eth_getTransactionBySenderAndNonce returned null for sender=$l1_eth_address nonce=$nonce"
        exit 1
    fi

    # Verify the returned transaction hash matches what we sent
    local returned_hash
    returned_hash=$(echo "$result" | jq -r '.hash')

    if [[ "$returned_hash" != "$tx_hash" ]]; then
        echo "Transaction hash mismatch: expected=$tx_hash got=$returned_hash"
        exit 1
    fi

    # Verify key fields are present in the response
    local returned_from returned_nonce
    returned_from=$(echo "$result" | jq -r '.from')
    returned_nonce=$(echo "$result" | jq -r '.nonce')

    if [[ "${returned_from,,}" != "${l1_eth_address,,}" ]]; then
        echo "Sender mismatch: expected=$l1_eth_address got=$returned_from"
        exit 1
    fi

    local expected_nonce_hex
    expected_nonce_hex=$(printf '0x%x' "$nonce")
    if [[ "$returned_nonce" != "$expected_nonce_hex" ]]; then
        echo "Nonce mismatch: expected=$expected_nonce_hex got=$returned_nonce"
        exit 1
    fi
}

# bats test_tags=agglayer-rpc,reth-l1
@test "eth_getTransactionBySenderAndNonce returns null for unused nonce" {
    # Use a very high nonce that hasn't been used
    local high_nonce="0xffffffff"

    run cast rpc --rpc-url "$l1_rpc_url" eth_getTransactionBySenderAndNonce "$l1_eth_address" "$high_nonce"
    if [[ "$status" -ne 0 ]]; then
        echo "eth_getTransactionBySenderAndNonce RPC call failed: $output"
        exit 1
    fi

    if [[ "$output" != "null" ]]; then
        echo "Expected null for unused nonce, got: $output"
        exit 1
    fi
}
