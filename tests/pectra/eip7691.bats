#!/usr/bin/env bats
# bats file_tags=pectra
#
# This file implements tests for EIP-7691: Blob throughput increase
# https://eips.ethereum.org/EIPS/eip-7691
#

setup() {
    true
}

setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"pectra"}
    if [[ -n "$L2_RPC_URL" ]]; then
        export l2_rpc_url="$L2_RPC_URL"
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc 2>/dev/null); then
        export l2_rpc_url
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc 2>/dev/null); then
        export l2_rpc_url
    else
        echo "❌ Failed to determine L2 RPC URL. Please set L2_RPC_URL" >&2
        exit 1
    fi
    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_address=$(cast wallet address --private-key $l2_private_key)
    export l2_address
    #export l2_chain_id=${L2_CHAIN_ID:-"$(cast chain-id --rpc-url $l2_rpc_url)"}

    # there needs to be enough wallets to send in paralel and fill at least 1 block for the test to pass
    wallet_count=20
    wallet_private_keys=()
    fund_amount="0.01ether"

    # Let's create $wallet_count random funded wallets:
    for i in $(seq 1 $wallet_count); do
        wallet=$(cast wallet new --json)
        address=$(echo "$wallet" | jq -r '.[0].address')
        wallet_private_keys[$i]=$(echo "$wallet" | jq -r '.[0].private_key')
        run cast send --legacy --rpc-url $l2_rpc_url --json --private-key $l2_private_key --value "$fund_amount" $address
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to fund wallet $i ($address): $output"
            exit 1
        fi
    done

    export wallet_private_keys_serialized="${wallet_private_keys[*]}"
    echo "✅ Successfully funded $wallet_count wallets"

    export MAX_BLOBS_PER_BLOCK_ELECTRA=9
    export MAX_BLOB_GAS_PER_BLOCK=1179648
}

teardown() {
    rm -f blob_data.hex
}


@test "EIP-7691: Max blobs per block" {
    read -r -a wallet_private_keys <<< "$wallet_private_keys_serialized"
    echo "0x$(head -c 8192 </dev/random | xxd -p -c 8192)" > blob_data.hex

    tx_hashes=()

    # Sending blob txs as fast as possible
    for i in "${!wallet_private_keys[@]}"; do
        run cast send \
            --json \
            --rpc-url "$l2_rpc_url" \
            --private-key "${wallet_private_keys[i]}" \
            --blob \
            --async \
            --nonce 0 \
            --path blob_data.hex \
            "$(cast address-zero)"
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to send blob tx $i, output: $output"
            false
        else
            echo "✅ Successfully sent blob tx $i with pkey ${wallet_private_keys[i]}: $output"
            tx_hashes+=("$output")
        fi
    done

    blocks=()
    # lets retrieve the block for each txhash
    for tx_hash in "${tx_hashes[@]}"; do
        bn=null
        while [ "$bn" == "null" ]; do
            run cast tx $tx_hash --rpc-url "$l2_rpc_url" --json
            if [ "$status" -ne 0 ]; then
                echo "❌ Failed to retrieve tx $tx_hash, output: $output"
                false
            else
                bn=$(echo "$output" | jq -r '.blockNumber')
            fi
        done
        bn=$(echo $bn | cast to-dec)
        echo "✅ Successfully retrieved block number for tx $tx_hash: $bn"
        blocks+=("$bn")
    done

    mapfile -t unique_blocks < <(printf "%s\n" "${blocks[@]}" | sort -u)
    electra_block_found=false

    # Lets check each block
    for block in "${unique_blocks[@]}"; do
        run cast block $block --rpc-url "$l2_rpc_url" --json
        if [ "$status" -ne 0 ]; then
            echo "❌ Failed to retrieve block $block, output: $output"
            false
        else
            blob_gas_used=$(echo "$output" | jq -r '.blobGasUsed' | cast to-dec)
            blob_count=$(echo "$output" | jq -r '[.transactions[].blobVersionedHashes[]?] | length')
            echo "✅ Successfully retrieved block $block, blob_gas_used: $blob_gas_used, blob_count: $blob_count"
            # if any of these values match electra limits, we're done:
            if [ "$blob_gas_used" -eq "$MAX_BLOB_GAS_PER_BLOCK" ] || [ "$blob_count" -eq "$MAX_BLOBS_PER_BLOCK_ELECTRA" ]; then
                echo "✅ * Block $block matches EIP-7691 Electra limits"
                electra_block_found=true
            fi
        fi
    done
    if [ "$electra_block_found" = true ]; then
        echo "✅ Found block(s) matching EIP-7691 Electra limits"
    else
        echo "❌ No block found matching EIP-7691 Electra limits"
        false
    fi
}
