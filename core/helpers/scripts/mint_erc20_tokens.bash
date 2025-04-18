#!/usr/bin/env bash

function mint_erc20_tokens() {
    local rpc_url="$1"            # The L1 RPC URL
    local erc20_token_addr="$2"   # The gas token contract address
    local minter_private_key="$3" # The minter private key
    local receiver="$4"           # The receiver address (for minted tokens)
    local tokens_amount="$5"      # The amount of tokens to transfer (e.g., "0.1ether")

    # Query the erc20 token balance of the sender
    run query_contract "$rpc_url" "$erc20_token_addr" "$balance_of_fn_sig" "$sender_addr"
    assert_success
    local erc20_token_balance=$(echo "$output" | tail -n 1)

    # Log the account's current gas token balance
    echo "Initial account balance: $erc20_token_balance wei" >&3

    # Convert tokens_amount to Wei for comparison
    local wei_amount=$(cast --to-unit "$tokens_amount" wei)

    # Mint the required tokens by sending a transaction
    run send_tx "$rpc_url" "$minter_private_key" "$erc20_token_addr" "$mint_fn_sig" "$receiver" "$tokens_amount"
    assert_success
}