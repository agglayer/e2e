#!/usr/bin/env bats
# bats file_tags=cdk-erigon

setup() {
    load "$PROJECT_ROOT/core/helpers/agglayer-cdk-common-setup.bash"
    _agglayer_cdk_common_setup  # Standard setup (wallet, funding, RPC, etc.)
}

# bats file_tags=regression,el:cdk-erigon
# https://github.com/0xPolygonHermez/cdk-erigon/issues/1044
@test "send 0xFB opcode to sequencer and ensure failure" {
    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 1000000 \
         --json \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" --create 5ffb > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x0" ]]; then
        echo "❌ This transaction should have failed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# https://github.com/0xPolygonHermez/cdk-erigon/issues/1046
# solc --strict-assembly - <<< "{mstore(0, create(0, 0, 0xfffffffffff)) return(0, 32)}"
@test "send CREATE with large size" {
    local bytecode="0x650fffffffffff5f80f05f5260205ff3"

    if cast call --rpc-url "$L2_RPC_URL" --create "$bytecode"; then
        echo "❌ This should have failed"
        exit 1
    fi

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29000000 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x0" ]]; then
        echo "❌ This transaction should have failed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# solc --strict-assembly - <<< "{return(0, sub(0, 1))}"
@test "send large RETURN" {
    local bytecode="0x60015f035ff3"

    if cast call --rpc-url "$L2_RPC_URL" --create "$bytecode"; then
        echo "❌ This should have failed"
        exit 1
    fi

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29000000 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x0" ]]; then
        echo "❌ This transaction should have failed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# solc --strict-assembly - <<< "{mstore(0, create2(0, 0, 0xfffffffffff, 1)) return(0, 32)}"
@test "send CREATE2 with large size" {
    local bytecode="0x6001650fffffffffff5f80f55f5260205ff3"

    if cast call --rpc-url "$L2_RPC_URL" --create "$bytecode"; then
        echo "❌ This should have failed"
        exit 1
    fi

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29000000 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x0" ]]; then
        echo "❌ This transaction should have failed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}


# https://github.com/0xPolygonHermez/cdk-erigon/issues/1073
@test "send malformed PUSH opcode" {
    local addr
    addr=$(cast wallet address --private-key "$PRIVATE_KEY")
    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    local test_address
    test_address=$(cast compute-address --rpc-url "$L2_RPC_URL" --nonce "$nonce" "$addr" | sed 's/.*: //')

    cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --create 6300000001630000001560003963000000016000F360

    if [[ "$(cast code --rpc-url "$L2_RPC_URL" "$test_address")" != "0x60" ]]; then
        cast code --rpc-url "$L2_RPC_URL" "$test_address"
        echo "❌ The test contract with a malformed push doesn't look right"
        exit 1
    fi

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29000000 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         "$test_address" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x1" ]]; then
        echo "❌ This transaction should have passed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# https://github.com/0xPolygonHermez/cdk-erigon/issues/1136
@test "send SHA256 counter" {
    local addr
    addr=$(cast wallet address --private-key "$PRIVATE_KEY")
    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    local test_address
    test_address=$(cast compute-address --rpc-url "$L2_RPC_URL" --nonce "$nonce" "$addr" | sed 's/.*: //')

    cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --create 0x601E600C600039601E6000F360016000526001611000525B600160015F355F60025AF4630000000B5600

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

    for i in {1..5}; do
        cast send --async --nonce "$nonce" --legacy --private-key "$PRIVATE_KEY" --rpc-url "$L2_RPC_URL" --gas-limit 100000 "$test_address" 0x0000000000000000000000000000000000000000000000000000000000000139 &> /dev/null
        nonce=$((nonce+1))
    done

    assert_block_production "$L2_RPC_URL" 12
}

# solc --strict-assembly - <<< "{mstore(100,100) pop(create2(0x8c,0x8c,0x6234608c608c,0x17179149))}"
@test "send CREATE2 oom issue" {
    local bytecode="0x606480526317179149656234608c608c608c80f500"

    if cast call --rpc-url "$L2_RPC_URL" --create "$bytecode"; then
        echo "❌ This should have failed"
        exit 1
    fi

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29000000 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x0" ]]; then
        echo "❌ This transaction should have failed"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}


@test "send executable PUSH operand" {
    # Manually constructed contract
    local bytecode="0x665b5f5fa05f5ff350600156fe"
    
    # Assembly breakdown:
    # 00000000: PUSH7 0x5b5f5fa05f5ff3
    # 00000008: POP
    # 00000009: PUSH1 0x01
    # 0000000b: JUMP
    # 0000000c: INVALID
    # In most EVMs, the JUMP should fail because offset 1 is inside a push.
    # However, in zkEVM, it should work and return properly, never hitting the INVALID.

    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.logs | length' "$out_file")" -ne 1 ]]; then
        echo "❌ Expected one log in executable PUSH operand"
        exit 1
    fi

    if [[ "$(jq -r '.status' "$out_file")" != "0x1" ]]; then
        echo "❌ Expected successful status from executable PUSH"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# solc --strict-assembly - <<< "{if lt(gas(), 50000) { log0(0, 0) return(0, 0) } codecopy(0, 0, codesize()) pop(create(0, 0, codesize()))}"
@test "send recursive CREATE transaction" {
    local bytecode="0x61c3505a10601157385f8039385f80f0005b5f80a05f80f3"
    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29999999 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.logs | length' "$out_file")" -ne 1 ]]; then
        echo "❌ Expected one log"
        exit 1
    fi

    if [[ "$(jq -r '.status' "$out_file")" != "0x1" ]]; then
        echo "❌ Expected successful status"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}

# solc --strict-assembly - <<< "{codecopy(0, 0, codesize()) pop(create(0, 0, codesize()))}"
@test "send exhaustive recursive CREATE transaction" {
    local bytecode="0x385f8039385f80f000"
    local out_file
    out_file=$(mktemp)

    cast send --legacy \
         --gas-limit 29999999 \
         --rpc-url "$L2_RPC_URL" \
         --private-key "$PRIVATE_KEY" \
         --json \
         --create "$bytecode" > "$out_file"

    if [[ "$(jq -r '.status' "$out_file")" != "0x1" ]]; then
        echo "❌ Expected successful status from executable PUSH"
        exit 1
    fi

    assert_block_production "$L2_RPC_URL" 12
}


@test "counter overflowing transactions do not create new batches" {
    deploy_test_contracts "$L2_RPC_URL" "$PRIVATE_KEY"

    local start_bn
    start_bn=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_batchNumber | jq -r '.' | perl -nwl -e "print hex")

    local eth_address
    eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")

    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$eth_address")

    local wallets nonce_file
    wallets=$(mktemp)
    nonce_file=$(mktemp)

    cast wallet new --number 15 --json > "$wallets"

    jq -r '.[].address' "$wallets" | while read -r tmp_address; do
        cast send --async --nonce "$nonce" --value 0.1ether --legacy --private-key "$PRIVATE_KEY" --rpc-url "$L2_RPC_URL" "$tmp_address"
        nonce=$((nonce+1))
        echo "$nonce" > "$nonce_file"
    done

    cast send --nonce "$(cat "$nonce_file")" --value 0 --legacy --private-key "$PRIVATE_KEY" --rpc-url "$L2_RPC_URL" "$(cast az)"

    jq -r '.[].private_key' "$wallets" | while read -r tmp_private_key; do
        cast send --async \
             --gas-limit 29999999 \
             --legacy \
             --private-key "$tmp_private_key" \
             --rpc-url "$L2_RPC_URL" \
             "$COUNTERS_ADDR" "$(cast abi-encode 'f(uint32)' 5)"
    done

    sleep 10

    start_bn=$((start_bn+2))
    local end_bn
    end_bn=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_batchNumber | jq -r '.' | perl -nwl -e "print hex")

    if [[ "$end_bn" -gt "$start_bn" ]]; then
        echo "❌ More than 2 batches were created while sending unmineable transactions"
        exit 1
    fi
}

@test "send IDENTITY precompile test" {
    local addr
    addr=$(cast wallet address --private-key "$PRIVATE_KEY")

    local nonce
    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")

    local test_address
    test_address=$(cast compute-address --rpc-url "$L2_RPC_URL" --nonce "$nonce" "$addr" | sed 's/.*: //')

    cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --create 6016600C60003960166000F36001600052600160003552595F595F595F60045AFA00

    if [[ "$(cast code --rpc-url "$L2_RPC_URL" "$test_address")" == "0x" ]]; then
        echo "❌ The test contract seems to be empty!"
        exit 1
    fi

    nonce=$(cast nonce --rpc-url "$L2_RPC_URL" "$addr")
    for ((i=1; i<=5; i++)); do
        cast send --async \
            --nonce "$nonce" \
            --legacy \
            --rpc-url "$L2_RPC_URL" \
            --private-key "$PRIVATE_KEY" \
            --value 1 \
            --gas-limit 29999999 \
            "$test_address" 0x00000000000000000000000000000000000000000000000000000000003BBDE0
        nonce=$((nonce+1))
    done

    assert_block_production "$L2_RPC_URL" 12
}
