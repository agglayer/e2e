#!/bin/bash
set -euo pipefail

function mint_pol_token() {
    local bridge_addr="$1"
    echo "=== Minting POL ===" >&3
    cast send \
        --rpc-url $l1_rpc_url \
        --private-key $private_key \
        $pol_address \
        "$MINT_FN_SIG" \
        $eth_address 10000000000000000000000
    # Allow bridge to spend it
    cast send \
        --rpc-url $l1_rpc_url \
        --private-key $private_key \
        $pol_address \
        "$APPROVE_FN_SIG" \
        $bridge_addr 10000000000000000000000
}

function mint_and_approve_erc20_tokens() {
    local rpc_url="$1"            # The L1 RPC URL
    local erc20_token_addr="$2"   # The gas token contract address
    local minter_private_key="$3" # The minter private key
    local receiver_add="$4"       # The receiver address (for minted tokens)
    local tokens_amount="$5"      # The amount of tokens to transfer (e.g., "0.1ether")
    local approve_to="${6:-}"     # The address to approve the transfer (optional)

    # Query the erc20 token balance of the sender
    run query_contract "$rpc_url" "$erc20_token_addr" "$BALANCE_OF_FN_SIG" "$sender_addr"
    assert_success
    local erc20_token_balance=$(echo "$output" | tail -n 1)

    # Log the account's current gas token balance
    echo "Initial account balance: $erc20_token_balance wei" >&3

    # Convert tokens_amount to Wei for comparison
    local wei_amount=$(cast --to-unit "$tokens_amount" wei)

    # Mint the required tokens by sending a transaction
    run send_tx "$rpc_url" "$minter_private_key" "$erc20_token_addr" "$MINT_FN_SIG" "$receiver_add" "$tokens_amount"
    assert_success

    # If approve_to is provided, approve the transfer
    if [ -n "$approve_to" ]; then
        run send_tx "$rpc_url" "$minter_private_key" "$erc20_token_addr" "$APPROVE_FN_SIG" "$approve_to" "$tokens_amount"
        assert_success
    fi
}
