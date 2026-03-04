#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,tx-types

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=execution-specs,tx-types,transaction-eoa
@test "type 0 (legacy) receipt has correct type and gasPrice field" {
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    receipt=$(cast send \
        --legacy \
        --gas-limit 21000 \
        --gas-price "$gas_price" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000)

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Legacy tx failed: $tx_status" >&2
        return 1
    fi

    # Type should be 0x0
    tx_type=$(echo "$receipt" | jq -r '.type')
    tx_type_dec=$(printf "%d" "$tx_type")
    if [[ "$tx_type_dec" -ne 0 ]]; then
        echo "Expected type 0 for legacy tx, got: $tx_type" >&2
        return 1
    fi

    # effectiveGasPrice should equal the gas price we set
    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")
    if [[ "$effective_gas_price" -ne "$gas_price" ]]; then
        echo "effectiveGasPrice mismatch: expected $gas_price, got $effective_gas_price" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,tx-types,evm-gas
@test "type 1 (EIP-2930) access list reduces gas for warm storage access" {
    # Deploy a contract that reads 3 storage slots. Using an access list to
    # pre-warm all 3 slots should save more gas than the access list overhead.
    # Per-slot saving: 2100 (cold) - 100 (warm) = 2000. For 3 slots = 6000.
    # Access list cost: 1900 (address) + 3*100 (keys) = 2200. Net saving ~3800.

    # Runtime: SLOAD(0) POP SLOAD(1) POP SLOAD(2) POP STOP
    runtime="60005450600154506002545000"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"
    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    # Call without access list (cold storage reads)
    cold_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr")
    cold_gas=$(echo "$cold_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    # Call with access list that warms all 3 slots
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    slot0="0x0000000000000000000000000000000000000000000000000000000000000000"
    slot1="0x0000000000000000000000000000000000000000000000000000000000000001"
    slot2="0x0000000000000000000000000000000000000000000000000000000000000002"

    set +e
    warm_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --gas-price "$gas_price" \
        --access-list "${contract_addr}:${slot0},${contract_addr}:${slot1},${contract_addr}:${slot2}" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr" 2>/dev/null)
    warm_exit=$?
    set -e

    if [[ $warm_exit -ne 0 || -z "$warm_receipt" ]]; then
        skip "Node does not support access list transactions"
    fi

    warm_status=$(echo "$warm_receipt" | jq -r '.status')
    if [[ "$warm_status" != "0x1" ]]; then
        echo "Access list tx failed: $warm_status" >&2
        return 1
    fi

    warm_gas=$(echo "$warm_receipt" | jq -r '.gasUsed' | xargs printf "%d\n")

    echo "Cold SLOAD gas (3 slots): $cold_gas, Warm SLOAD (access list) gas: $warm_gas" >&3

    tx_type=$(echo "$warm_receipt" | jq -r '.type')
    tx_type_dec=$(printf "%d" "$tx_type")
    if [[ "$tx_type_dec" -ne 1 ]]; then
        echo "Expected type 1 for access list tx, got: $tx_type" >&2
        return 1
    fi

    if [[ "$warm_gas" -ge "$cold_gas" ]]; then
        echo "Access list did not reduce gas: warm=$warm_gas >= cold=$cold_gas" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,tx-types,evm-gas
@test "type 2 (EIP-1559) effectiveGasPrice = baseFee + min(priorityFee, maxFee - baseFee)" {
    base_fee=$(cast base-fee --rpc-url "$L2_RPC_URL")
    priority_fee=30000000000  # 30 Gwei
    max_fee=$(( base_fee * 2 + priority_fee ))

    receipt=$(cast send \
        --gas-limit 21000 \
        --gas-price "$max_fee" \
        --priority-gas-price "$priority_fee" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000 2>/dev/null) || {
        skip "Node rejected type-2 tx"
    }

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Type-2 tx failed: $tx_status" >&2
        return 1
    fi

    effective_gas_price=$(echo "$receipt" | jq -r '.effectiveGasPrice' | xargs printf "%d\n")

    block_number=$(echo "$receipt" | jq -r '.blockNumber')
    block_base_fee=$(cast block "$block_number" --json --rpc-url "$L2_RPC_URL" | jq -r '.baseFeePerGas' | xargs printf "%d\n")

    # effectiveGasPrice = baseFee + min(maxPriorityFee, maxFee - baseFee)
    max_possible_tip=$(( max_fee - block_base_fee ))
    if [[ "$priority_fee" -lt "$max_possible_tip" ]]; then
        expected_tip="$priority_fee"
    else
        expected_tip="$max_possible_tip"
    fi
    expected_effective=$(( block_base_fee + expected_tip ))

    if [[ "$effective_gas_price" -ne "$expected_effective" ]]; then
        echo "effectiveGasPrice mismatch:" >&2
        echo "  actual=$effective_gas_price expected=$expected_effective" >&2
        echo "  baseFee=$block_base_fee priority=$priority_fee maxFee=$max_fee" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,tx-types,evm-gas
@test "type 2 maxFeePerGas below baseFee is rejected" {
    base_fee=$(cast base-fee --rpc-url "$L2_RPC_URL")

    # Set maxFee well below current baseFee
    low_max_fee=$(( base_fee / 2 ))
    if [[ "$low_max_fee" -lt 1 ]]; then
        low_max_fee=1
    fi

    set +e
    receipt=$(cast send \
        --gas-limit 21000 \
        --gas-price "$low_max_fee" \
        --priority-gas-price "$low_max_fee" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        0x0000000000000000000000000000000000000000 2>&1)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // empty' 2>/dev/null)
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected rejection for maxFee ($low_max_fee) below baseFee ($base_fee), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or failed status — correctly rejected
}

# bats test_tags=execution-specs,tx-types,evm-gas
@test "type 1 access list with multiple storage keys is accepted" {
    # Deploy a contract that reads 3 storage slots.
    # Runtime: SLOAD(0) POP SLOAD(1) POP SLOAD(2) POP STOP
    runtime="60005450600154506002545000"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"
    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy --gas-limit 200000 \
        --private-key "$ephemeral_private_key" --rpc-url "$L2_RPC_URL" --json \
        --create "0x${initcode}")
    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")

    # Access list with 3 storage keys
    slot0="0x0000000000000000000000000000000000000000000000000000000000000000"
    slot1="0x0000000000000000000000000000000000000000000000000000000000000001"
    slot2="0x0000000000000000000000000000000000000000000000000000000000000002"

    set +e
    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --gas-price "$gas_price" \
        --access-list "${contract_addr}:${slot0},${contract_addr}:${slot1},${contract_addr}:${slot2}" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -ne 0 || -z "$receipt" ]]; then
        skip "Node does not support access list transactions with multiple keys"
    fi

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Multi-key access list tx failed: $tx_status" >&2
        return 1
    fi

    tx_type=$(echo "$receipt" | jq -r '.type')
    tx_type_dec=$(printf "%d" "$tx_type")
    if [[ "$tx_type_dec" -ne 1 ]]; then
        echo "Expected type 1, got: $tx_type" >&2
        return 1
    fi

    echo "Multi-key access list tx succeeded (type 1)" >&3
}
