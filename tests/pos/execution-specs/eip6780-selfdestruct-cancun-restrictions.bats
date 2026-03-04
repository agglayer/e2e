#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,eip6780

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

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "SELFDESTRUCT in same tx as creation destroys contract code" {
    # Deploy a contract whose constructor:
    #   1. Stores 0x42 at slot 0
    #   2. SELFDESTRUCTs to the zero address
    # Post-Cancun (EIP-6780): SELFDESTRUCT in the same tx as creation STILL
    # destroys the contract (code removed, balance sent).
    #
    # Constructor bytecode:
    #   PUSH1 0x42  PUSH1 0x00  SSTORE     60 42 60 00 55
    #   PUSH20 0x00..00  SELFDESTRUCT       73 00..00 ff
    # No RETURN — constructor selfdestructs, so no runtime deployed.
    beneficiary="0000000000000000000000000000000000000000"
    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --value 1000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x604260005573${beneficiary}ff")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Deployment+selfdestruct tx failed: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")

    if [[ "$deployed_code" != "0x" ]]; then
        echo "Expected empty code after same-tx SELFDESTRUCT, got: $deployed_code" >&2
        return 1
    fi

    balance=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$balance" -ne 0 ]]; then
        echo "Expected zero balance after same-tx SELFDESTRUCT, got: $balance" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "SELFDESTRUCT on pre-existing contract: code persists post-Cancun" {
    # Deploy a contract with a SELFDESTRUCT function, then call it in a later tx.
    # Post-Cancun: code must persist, only balance is sent to beneficiary.
    #
    # Runtime bytecode:
    #   PUSH20 0x00..00  SELFDESTRUCT   (73 00..00 ff)
    # That's 22 bytes of runtime.
    beneficiary="0000000000000000000000000000000000000000"
    runtime="73${beneficiary}ff"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"  # 12 bytes initcode prefix

    # Initcode: CODECOPY pattern + RETURN
    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    # Step 1: Deploy the contract
    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --value 10000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed: $deploy_status" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    code_before=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$code_before" == "0x" ]]; then
        echo "Contract has no code after deployment" >&2
        return 1
    fi

    # Step 2: Call the contract (triggers SELFDESTRUCT) in a separate tx
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "SELFDESTRUCT call failed: $call_status" >&2
        return 1
    fi

    # Step 3: Verify code PERSISTS (Cancun EIP-6780 behavior)
    code_after=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$code_after" == "0x" ]]; then
        echo "Code was destroyed — pre-Cancun behavior detected. EIP-6780 not active." >&2
        return 1
    fi

    echo "Code persists after SELFDESTRUCT on pre-existing contract (EIP-6780 confirmed)" >&3
}

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "SELFDESTRUCT to self: balance preserved post-Cancun" {
    # Deploy a contract that SELFDESTRUCTs to its own address.
    # Post-Cancun on pre-existing contracts: balance should remain at the address.
    #
    # Runtime: ADDRESS SELFDESTRUCT (30 ff) — 2 bytes
    runtime="30ff"
    runtime_len="02"
    offset_hex="0c"

    initcode="60${runtime_len}60${offset_hex}60003960${runtime_len}6000f3${runtime}"

    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --value 50000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed: $deploy_status" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    balance_before=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")

    # Call to trigger SELFDESTRUCT-to-self
    cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$contract_addr" >/dev/null

    balance_after=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")

    echo "Balance before SELFDESTRUCT-to-self: $balance_before" >&3
    echo "Balance after SELFDESTRUCT-to-self: $balance_after" >&3

    # Post-Cancun: balance stays (SELFDESTRUCT on pre-existing only sends balance,
    # but when beneficiary == self, balance remains).
    if [[ "$balance_after" -ne "$balance_before" ]]; then
        echo "Balance changed after SELFDESTRUCT-to-self:" >&2
        echo "  before=$balance_before after=$balance_after" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "SELFDESTRUCT sends balance to beneficiary" {
    # Deploy contract with value, then SELFDESTRUCT to a fresh beneficiary.
    # Verify the beneficiary receives the exact balance.
    beneficiary_wallet=$(cast wallet new --json | jq -r '.[0].address')
    beneficiary_hex="${beneficiary_wallet#0x}"

    # Runtime: PUSH20 <beneficiary> SELFDESTRUCT (73 <20B> ff)
    runtime="73${beneficiary_hex}ff"
    runtime_len=$(( ${#runtime} / 2 ))
    runtime_len_hex=$(printf "%02x" "$runtime_len")
    offset_hex="0c"

    initcode="60${runtime_len_hex}60${offset_hex}60003960${runtime_len_hex}6000f3${runtime}"

    # Deploy with 100000 wei
    deposit_amount=100000
    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --value "$deposit_amount" \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')
    contract_balance=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")

    beneficiary_before=$(cast balance "$beneficiary_wallet" --rpc-url "$L2_RPC_URL")

    # Trigger SELFDESTRUCT
    cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        "$contract_addr" >/dev/null

    beneficiary_after=$(cast balance "$beneficiary_wallet" --rpc-url "$L2_RPC_URL")
    increase=$(( beneficiary_after - beneficiary_before ))

    echo "Contract had $contract_balance wei, beneficiary received $increase wei" >&3

    if [[ "$increase" -ne "$contract_balance" ]]; then
        echo "Beneficiary did not receive exact contract balance:" >&2
        echo "  contract_balance=$contract_balance increase=$increase" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "SELFDESTRUCT inside STATICCALL reverts" {
    # SELFDESTRUCT is a state-modifying operation and must fail inside STATICCALL.
    # Deploy two contracts:
    #   A (caller): does STATICCALL to B
    #   B (target): does SELFDESTRUCT
    # A stores the STATICCALL return value (0 = failure) at slot 0.

    # Contract B runtime: PUSH20 0x00..00 SELFDESTRUCT
    b_beneficiary="0000000000000000000000000000000000000000"
    b_runtime="73${b_beneficiary}ff"
    b_runtime_len=$(( ${#b_runtime} / 2 ))
    b_runtime_len_hex=$(printf "%02x" "$b_runtime_len")
    b_offset_hex="0c"
    b_initcode="60${b_runtime_len_hex}60${b_offset_hex}60003960${b_runtime_len_hex}6000f3${b_runtime}"

    # Deploy B
    b_receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${b_initcode}")

    b_status=$(echo "$b_receipt" | jq -r '.status')
    if [[ "$b_status" != "0x1" ]]; then
        echo "Contract B deployment failed" >&2
        return 1
    fi

    b_addr=$(echo "$b_receipt" | jq -r '.contractAddress')
    b_addr_hex="${b_addr#0x}"

    # Contract A runtime: STATICCALL(gas, B, 0, 0, 0, 0) then SSTORE result at slot 0
    # PUSH1 0x00 (retSize) PUSH1 0x00 (retOffset) PUSH1 0x00 (argsSize)
    # PUSH1 0x00 (argsOffset) PUSH20 <B> GAS STATICCALL
    # PUSH1 0x00 SSTORE STOP
    a_runtime="600060006000600073${b_addr_hex}5afa60005500"
    a_runtime_len=$(( ${#a_runtime} / 2 ))
    a_runtime_len_hex=$(printf "%02x" "$a_runtime_len")
    a_offset_hex="0c"
    a_initcode="60${a_runtime_len_hex}60${a_offset_hex}60003960${a_runtime_len_hex}6000f3${a_runtime}"

    # Deploy A
    a_receipt=$(cast send \
        --legacy \
        --gas-limit 300000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${a_initcode}")

    a_status=$(echo "$a_receipt" | jq -r '.status')
    if [[ "$a_status" != "0x1" ]]; then
        echo "Contract A deployment failed" >&2
        return 1
    fi

    a_addr=$(echo "$a_receipt" | jq -r '.contractAddress')

    # Call A — it will STATICCALL B which tries to SELFDESTRUCT
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 300000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$a_addr")

    call_status=$(echo "$call_receipt" | jq -r '.status')
    if [[ "$call_status" != "0x1" ]]; then
        echo "Outer call failed (expected it to succeed with inner STATICCALL failure)" >&2
        return 1
    fi

    # STATICCALL returns 0 on failure, 1 on success
    result=$(cast storage "$a_addr" 0 --rpc-url "$L2_RPC_URL")
    result_dec=$(printf "%d" "$result")

    if [[ "$result_dec" -ne 0 ]]; then
        echo "STATICCALL with SELFDESTRUCT should return 0 (failure), got: $result_dec" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,eip6780,evm-opcode
@test "CREATE2 redeploy after SELFDESTRUCT in creation tx succeeds" {
    # EIP-6780: SELFDESTRUCT in the same tx as creation fully destroys the account.
    # After the tx completes, the address should be clean (nonce=0, no code),
    # allowing a second CREATE2 with the same salt to succeed.
    #
    # We split the two CREATE2 operations into separate transactions because
    # SELFDESTRUCT cleanup is deferred to end-of-transaction in the EVM.
    #
    # Factory runtime (one CREATE2 per call):
    #   PUSH2 0x33ff  PUSH1 0x00  MSTORE     — child initcode (CALLER SELFDESTRUCT) in memory
    #   PUSH1 0x42  PUSH1 0x02  PUSH1 0x1e  PUSH1 0x00  CREATE2  — deploy child
    #   CALLVALUE  SSTORE  STOP              — store result at slot = msg.value
    #
    # Call 1 (value=0): CREATE2 → child selfdestructs → address stored at slot 0
    # Call 2 (value=1): CREATE2 same salt → redeploy → address stored at slot 1
    factory_runtime="6133ff"    # PUSH2 0x33ff
    factory_runtime+="6000"     # PUSH1 0x00
    factory_runtime+="52"       # MSTORE  → mem[30..31] = 0x33ff
    factory_runtime+="6042"     # PUSH1 0x42 (salt)
    factory_runtime+="6002"     # PUSH1 0x02 (size)
    factory_runtime+="601e"     # PUSH1 0x1e (offset=30)
    factory_runtime+="6000"     # PUSH1 0x00 (value)
    factory_runtime+="f5"       # CREATE2
    factory_runtime+="34"       # CALLVALUE
    factory_runtime+="55"       # SSTORE
    factory_runtime+="00"       # STOP

    factory_runtime_len=$(( ${#factory_runtime} / 2 ))
    factory_runtime_len_hex=$(printf "%02x" "$factory_runtime_len")
    factory_offset_hex="0c"

    factory_initcode="60${factory_runtime_len_hex}60${factory_offset_hex}60003960${factory_runtime_len_hex}6000f3${factory_runtime}"

    # Deploy factory
    deploy_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${factory_initcode}")

    deploy_status=$(echo "$deploy_receipt" | jq -r '.status')
    if [[ "$deploy_status" != "0x1" ]]; then
        echo "Factory deployment failed: $deploy_status" >&2
        return 1
    fi

    factory_addr=$(echo "$deploy_receipt" | jq -r '.contractAddress')

    # TX 1: CREATE2 deploys child (33ff = CALLER SELFDESTRUCT), child selfdestructs
    call1_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --value 0 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$factory_addr")

    call1_status=$(echo "$call1_receipt" | jq -r '.status')
    if [[ "$call1_status" != "0x1" ]]; then
        echo "Factory call 1 failed: $call1_status" >&2
        return 1
    fi

    first_child_raw=$(cast storage "$factory_addr" 0 --rpc-url "$L2_RPC_URL")
    first_child="0x${first_child_raw: -40}"

    if [[ "$first_child" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "First CREATE2 returned zero address" >&2
        return 1
    fi
    echo "First CREATE2 child address: $first_child" >&3

    # TX 2 (separate tx): CREATE2 redeploys child at same address
    # EIP-6780 cleanup has occurred between transactions, so the address is clean.
    call2_receipt=$(cast send \
        --legacy \
        --gas-limit 500000 \
        --value 1 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$factory_addr")

    call2_status=$(echo "$call2_receipt" | jq -r '.status')
    if [[ "$call2_status" != "0x1" ]]; then
        echo "Factory call 2 failed: $call2_status" >&2
        return 1
    fi

    second_child_raw=$(cast storage "$factory_addr" 1 --rpc-url "$L2_RPC_URL")
    second_child="0x${second_child_raw: -40}"

    if [[ "$second_child" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "Second CREATE2 returned zero address — redeploy after SELFDESTRUCT failed" >&2
        return 1
    fi

    # Both addresses should match (deterministic from same salt + initcode)
    first_lower=$(echo "$first_child" | tr '[:upper:]' '[:lower:]')
    second_lower=$(echo "$second_child" | tr '[:upper:]' '[:lower:]')
    if [[ "$first_lower" != "$second_lower" ]]; then
        echo "CREATE2 addresses differ: first=$first_child second=$second_child" >&2
        return 1
    fi

    echo "CREATE2 redeploy succeeded at same address: $second_child" >&3
}
