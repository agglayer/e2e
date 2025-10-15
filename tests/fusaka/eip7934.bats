#!/usr/bin/env bats
# bats file_tags=fusaka,eip-7934

# This file implements tests for EIP-7934
# https://eips.ethereum.org/EIPS/eip-7934

setup() {
    sender=$(cast wallet new --json | jq .[0])
    sender_address=$(echo "$sender" | jq -r .address)
    sender_private_key=$(echo "$sender" | jq -r .private_key)

    source "$BATS_TEST_DIRNAME/../../core/helpers/scripts/fund.bash"
    fund_up_to $l1_private_key $sender_address $(cast to-wei 100) $l1_rpc_url

    export sender_private_key
    export sender_address
}


setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../../core/helpers/common.bash"
    _setup_vars
}

gen_zero_bytecode(){
  local bytes=${1:-256}
  printf '0x'; awk -v n="$bytes" 'BEGIN{for(i=0;i<n;i++) printf "00"}'
  echo
}


# THIS TEST TRIES TO FILL BLOCKS IN TIME, SO THE HIGUER L1 SLOT TIME THE BETTER
# WITH DEFAULT KURTOSIS SLOF OF 2 SECONDS WE'RE UNABLE TO FILL BLOCKS

@test "RLP Execution block size limit 10M " {
    # bytecode=$(gen_zero_bytecode 49152)
    bytecode=$(gen_zero_bytecode 49152)

    txs_to_submit=500

    starting_block=$(cast bn --rpc-url "$l1_rpc_url")
    nonce=$(cast nonce --rpc-url "$l1_rpc_url" "$sender_address")

    for i in $(seq 1 $txs_to_submit); do
        cast send --gas-limit 16_000_000 --rpc-url "$l1_rpc_url" --private-key "$sender_private_key" --async --nonce "$nonce" --create $bytecode
        nonce=$((nonce + 1))
    done

    echo "✅ Successfully submitted $txs_to_submit transactions to L1" >&3

    sleep 24 # wait for the blocks to be mined
    ending_block=$(cast bn --rpc-url "$l1_rpc_url")

    for block in $(seq $starting_block $ending_block); do
        hex_block=$(cast to-hex "$block")
        run cast rpc debug_getRawBlock "$hex_block" --rpc-url "$l1_rpc_url"
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to get block $block, output: $output" >&3
            exit 1
        fi

        rawhex=$(echo "$output" | tr -d '\n' | sed 's/^"//; s/"$//')
        hexstr=${rawhex#0x}
        bytes=$(( ${#hexstr} / 2 ))
        echo "RLP encoded block size for block $block (bytes): $bytes" >&3

    done
}