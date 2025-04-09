#!/bin/bash
set -euo pipefail

function mint_pol_token() {
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
