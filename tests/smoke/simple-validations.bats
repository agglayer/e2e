#!/usr/bin/env bats

setup() {
    rpc_url=${L2_RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    # bridge_service_url=${BRIDGE_SERVICE_URL:-"$(kurtosis port print cdk zkevm-bridge-service-001 rpc)"}
    private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    eth_address=$(cast wallet address --private-key "$private_key")
    export ETH_RPC_URL="$rpc_url"
}
# bats test_tags=smoke
@test "send zero priced transactions and confirm rejection" {
    if cast send --legacy --gas-price 0 --value "1" --private-key "$private_key" 0x0000000000000000000000000000000000000000 ; then
        echo "A zero priced legacy transaction was mined"
        exit 1
    fi
    if cast send --gas-price 0 --value "1" --private-key "$private_key" 0x0000000000000000000000000000000000000000 ; then
        echo "A zero priced eip-1559 transaction was mined"
        exit 1
    fi

    hex_nonce=$(printf "0x%x" "$(cast nonce --rpc-url "$rpc_url" "$eth_address")")
    tx_fields='["'"$hex_nonce"'","0x","0x5208","0x0000000000000000000000000000000000000000","0x","0x"]'
    rlp_data=$(cast to-rlp "$tx_fields")
    signing_data=$(cast keccak "$rlp_data")
    signature=$(cast wallet sign --no-hash --private-key "$private_key" "$signing_data")
    signature_r=$(echo "$signature" | cut -c 3-66)
    signature_s=$(echo "$signature" | cut -c 67-130)
    signature_v=$(echo "$signature" | cut -c 131-132)
    signed_tx_fields='["'"$hex_nonce"'","0x","0x5208","0x0000000000000000000000000000000000000000","0x","0x","'"$signature_v"'","'"$signature_r"'","'"$signature_s"'"]'
    signed_data=$(cast to-rlp "$signed_tx_fields")

    if cast publish "$signed_data" ; then
        echo "A zero priced pre eip-155 transaction was mined"
        exit 1
    fi
}

# bats test_tags=smoke
@test "send ETH and verify pending nonce updates" {
    # shellcheck disable=SC2034
    for i in {1..20}; do
        nonce=$(cast nonce --block pending "$eth_address")
        tmp_file=$(mktemp)
        cast send \
             --gas-limit 21000 \
             --nonce "$nonce" \
             --async \
             --value "1" \
             --private-key "$private_key" 0x0000000000000000000000000000000000000000 > "$tmp_file"

        pending_nonce=$(cast nonce --block pending "$eth_address")
        tx_hash="$(cat "$tmp_file")"
        # block until mined
        cast receipt "$tx_hash" &> /dev/null
        final_pending_nonce=$(cast nonce --block pending "$eth_address")

        if [[ $nonce -eq $pending_nonce ]]; then
            echo "the pending nonce returned by the rpc is not updated after accepting a transaction into the pool"
            printf "tx hash: %s\n" "$tx_hash"
            printf "initial nonce: %s\n" "$nonce"
            printf "pending nonce: %s\n" "$pending_nonce"
            printf "final nonce: %s\n" "$final_pending_nonce"
            exit 1
        fi
        sleep 2
    done
}

# bats test_tags=smoke
@test "query finalized, safe, latest, and pending blocks return expected order" {
    prev_finalized_block=0
    prev_safe_block=0
    prev_latest_block=0
    prev_pending_block=0

    # shellcheck disable=SC2034
    for i in {1..20}; do
        finalized_block=$(cast block-number finalized)
        safe_block=$(cast block-number safe)
        latest_block=$(cast block-number latest)
        pending_block=$(cast block-number pending)
        earliest_block=$(cast block-number earliest)

        if [[ $finalized_block -eq 0 || $safe_block -eq 0 || $latest_block -eq 0 || $pending_block -eq 0 ]]; then
            echo "Safe, finalized, latest, and pending blocks are not all non-zero"
            exit 1
        fi

        if [[ $earliest_block -ne 0 ]]; then
            echo "the earliest block is not equal to 0"
            exit 1
        fi

        if [[ $pending_block -lt $latest_block ]]; then
            echo "The pending block is less than the latest block. This should never happen"
            exit 1
        fi

        if [[ $latest_block -lt $safe_block ]]; then
            echo "The latest block is less than the safe block. This should never happen"
            exit 1
        fi

        if [[ $safe_block -lt $finalized_block ]]; then
            echo "The safe block is less than the finalized block. This should never happen"
            exit 1
        fi

        if [[ $prev_pending_block -gt $pending_block ]]; then
            echo "The pending block number seems to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_pending_block" "$pending_block"
            exit 1
        fi

        if [[ $prev_latest_block -gt $latest_block ]]; then
            echo "The latest block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_latest_block" "$latest_block"
            exit 1
        fi

        if [[ $prev_safe_block -gt $safe_block ]]; then
            echo "The safe block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_safe_block" "$safe_block"
            exit 1
        fi

        if [[ $prev_finalized_block -gt $finalized_block ]]; then
            echo "The safe block number seemed to have gone backward"
            printf "Prev %d, Current %d\n" "$prev_finalized_block" "$finalized_block"
            exit 1
        fi

        prev_finalized_block="$finalized_block"
        prev_safe_block="$safe_block"
        prev_latest_block="$latest_block"
        prev_pending_block="$pending_block"

        sleep 2
    done
}

# bats test_tags=smoke
@test "send multiple transactions with same nonce and verify rejection" {
    nonce=$(cast nonce "$eth_address")
    gas_price=$(cast gas-price)

    # shellcheck disable=SC2034
    for i in {1..5}; do

        for j in {1..5}; do
            cantor=$(bc <<< "((($i+$j)*($i+$j+1))/2)+$j")

            set +e
            cast send \
                 --gas-limit 21000 \
                 --nonce "$nonce" \
                 --async \
                 --gas-price "$gas_price" \
                 --value "$cantor" \
                 --private-key "$private_key" 0x0000000000000000000000000000000000000000
            exit_code=$?
            set -e
            if [[ $j -ne 1 && $exit_code -eq 0 ]]; then
                echo "it seems like the a later transaction was accepted into the pool. Race condition?"
                exit 1
            fi
        done

        nonce=$((nonce + 1))
        sleep 2
    done
}

