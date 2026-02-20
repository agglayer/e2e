#!/usr/bin/env bats
# bats file_tags=pos

setup() {
    load "../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=evm-stress
@test "fuzz node with edge-case contract creation bytecodes and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # 15 edge-case bytecodes, each sent 7 times = 105 txs
    bytecodes=(
        "fe"
        "00"
        "5b600056"
        "60ff60005260206000f3"
        "60006000fd"
        "60006000f0"
        "3d"
        "7f$(python3 -c "print('00'*32, end='')")56"
        "f4"
        "58"
        "60016001f5"
        "3660006000f0"
        "6000356000f3"
        "60206000f3"
        "60ff"
    )

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    tx_hashes=()

    for bytecode in "${bytecodes[@]}"; do
        # shellcheck disable=SC2034
        for repeat in $(seq 1 7); do
            set +e
            tx_hash=$(cast send \
                --create "0x${bytecode}" \
                --nonce "$nonce" \
                --gas-limit 1000000 \
                --gas-price "$gas_price" \
                --legacy \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" 2>/dev/null)
            set -e
            if [[ -n "$tx_hash" ]]; then
                tx_hashes+=("$tx_hash")
            fi
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted ${#tx_hashes[@]} contract creation txs, waiting for settlement..." >&3

    # Wait for the last few txs to settle by watching block progress
    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    deadline=$(( start_block + 30 ))
    while true; do
        current=$(cast block-number --rpc-url "$L2_RPC_URL")
        if [[ "$current" -ge "$deadline" ]]; then
            break
        fi
        sleep 2
    done

    # Liveness check
    live_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    if [[ -z "$live_block" || "$live_block" -eq 0 ]]; then
        echo "Liveness check failed: node did not return a valid block number after fuzz" >&2
        return 1
    fi
    echo "Liveness check passed at block $live_block" >&3
}

# bats test_tags=evm-stress
@test "fuzz node with variable-size calldata transactions and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    # Calldata sizes (bytes): 0,1,4,16,64,256,1024,2048,4096,8192,16384,32768
    # Each sent 9 times = 108 txs
    sizes=(0 1 4 16 64 256 1024 2048 4096 8192 16384 32768)

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    for size in "${sizes[@]}"; do
        if [[ "$size" -eq 0 ]]; then
            calldata="0x"
        else
            calldata="0x$(python3 -c "print('00'*${size}, end='')")"
        fi

        # shellcheck disable=SC2034
        for repeat in $(seq 1 9); do
            # gas: 21000 + 4*size (zero bytes cost 4 gas each)
            gas_limit=$(( 21000 + 4 * size + 10000 ))
            set +e
            cast send \
                --nonce "$nonce" \
                --gas-limit "$gas_limit" \
                --gas-price "$gas_price" \
                --legacy \
                --data "$calldata" \
                --async \
                --private-key "$ephemeral_private_key" \
                --rpc-url "$L2_RPC_URL" \
                0x0000000000000000000000000000000000000000 &>/dev/null
            set -e
            nonce=$(( nonce + 1 ))
        done
    done

    echo "Submitted 108 variable-calldata txs, waiting for settlement..." >&3

    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    deadline=$(( start_block + 30 ))
    while true; do
        current=$(cast block-number --rpc-url "$L2_RPC_URL")
        if [[ "$current" -ge "$deadline" ]]; then
            break
        fi
        sleep 2
    done

    live_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    if [[ -z "$live_block" || "$live_block" -eq 0 ]]; then
        echo "Liveness check failed after calldata fuzz" >&2
        return 1
    fi
    echo "Liveness check passed at block $live_block" >&3
}

# bats test_tags=evm-stress
@test "fuzz node with edge-case gas limits and verify liveness" {
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 0.1ether "$ephemeral_address" >/dev/null

    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$ephemeral_address")
    null_addr="0x0000000000000000000000000000000000000000"
    dead_addr="0x000000000000000000000000000000000000dead"

    send_tx() {
        local extra_args=("$@")
        set +e
        cast send \
            --nonce "$nonce" \
            --gas-price "$gas_price" \
            --legacy \
            --async \
            --private-key "$ephemeral_private_key" \
            --rpc-url "$L2_RPC_URL" \
            "${extra_args[@]}" &>/dev/null
        set -e
        nonce=$(( nonce + 1 ))
    }

    # 10 variations x 10 repetitions = 100 txs
    # shellcheck disable=SC2034
    for i in $(seq 1 10); do
        send_tx --gas-limit 21000 "$null_addr"
        send_tx --gas-limit 21001 "$null_addr"
        send_tx --gas-limit 100000 "$null_addr"
        send_tx --gas-limit 1000000 "$null_addr"
        send_tx --gas-limit 10000000 "$null_addr"
        send_tx --gas-limit 30000000 "$null_addr"
        send_tx --gas-limit 21000 --value 1 "$null_addr"
        send_tx --gas-limit 21000 --legacy "$null_addr"
        send_tx --gas-limit 50000 --data "0xdeadbeef" "$null_addr"
        send_tx --gas-limit 21000 "$dead_addr"
    done

    echo "Submitted 100 edge-case gas-limit txs, waiting for settlement..." >&3

    start_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    deadline=$(( start_block + 30 ))
    while true; do
        current=$(cast block-number --rpc-url "$L2_RPC_URL")
        if [[ "$current" -ge "$deadline" ]]; then
            break
        fi
        sleep 2
    done

    live_block=$(cast block-number --rpc-url "$L2_RPC_URL")
    if [[ -z "$live_block" || "$live_block" -eq 0 ]]; then
        echo "Liveness check failed after gas-limit fuzz" >&2
        return 1
    fi
    echo "Liveness check passed at block $live_block" >&3
}
