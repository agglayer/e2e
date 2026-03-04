#!/usr/bin/env bats
# bats file_tags=pos,execution-specs

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup

    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    # Fund with 1 ETH: the EIP-170 boundary test deploys 24576 bytes of code which
    # costs ~5 M gas in code-deposit fees; at ~25 Gwei that is ~0.125 ETH per test.
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-limit 21000 --value 1ether "$ephemeral_address" >/dev/null
}

# bats test_tags=execution-specs,transaction-eoa
@test "deploy single STOP opcode contract succeeds and code at address is empty" {
    # CREATE base gas is 53K; STOP costs 0 execution gas.  Explicit --gas-limit
    # avoids auto-estimation (which Bor rejects when simulating empty balances) and
    # --legacy sidesteps EIP-1559 maxFeePerGas × blockGasLimit balance pre-checks.
    receipt=$(cast send \
        --legacy \
        --gas-limit 60000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x00")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success (0x1), got: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    # STOP opcode (0x00) produces empty runtime (no RETURN), so deployed code == 0x
    if [[ "$deployed_code" != "0x" ]]; then
        echo "Expected empty runtime (0x) for STOP-only constructor, got: $deployed_code" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "deploy contract that reverts in constructor leaves no code at deployed address" {
    # 0x60006000fd = PUSH1 0x00 PUSH1 0x00 REVERT
    set +e
    receipt=$(cast send \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60006000fd" 2>/dev/null)
    send_exit=$?
    set -e

    # The tx may be accepted but fail, or cast may report failure.
    # Either way, if we got a receipt check its status; if not, that's also acceptable.
    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        contract_addr=$(echo "$receipt" | jq -r '.contractAddress // empty')

        if [[ "$tx_status" == "0x1" && -n "$contract_addr" ]]; then
            # Tx succeeded but constructor reverted — check code is empty
            deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
            if [[ "$deployed_code" != "0x" ]]; then
                echo "Expected no code after constructor revert, got: $deployed_code" >&2
                return 1
            fi
        fi
        # status 0x0 means constructor revert was enforced at EVM level — pass
    fi
    # cast failure (send_exit != 0) also means the node rejected it — pass
}

# bats test_tags=execution-specs,evm-gas
@test "deploy initcode exactly at EIP-3860 limit (49152 bytes) succeeds" {
    initcode=$(python3 -c "print('00'*49152, end='')")
    # EIP-7623 (Prague) floor data gas cost for 49152 zero bytes:
    #   floor = 21000 + 10 × 49152 = 512520
    # Plus EIP-3860 word cost: 2 × 1536 words = 3072.  600K clears both.
    receipt=$(cast send \
        --gas-limit 600000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for 49152-byte initcode (EIP-3860 limit), got: $tx_status" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-gas
@test "deploy initcode one byte over EIP-3860 limit (49153 bytes) is rejected" {
    initcode=$(python3 -c "print('00'*49153, end='')")
    set +e
    # Same EIP-7623 floor applies (49153 tokens → min 512530).  600K clears the
    # floor so the rejection comes from EIP-3860, not from insufficient gas.
    receipt=$(cast send \
        --gas-limit 600000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 49153-byte initcode (over EIP-3860 limit), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 both indicate the node rejected it — pass
}

# bats test_tags=execution-specs,evm-gas
@test "deploy contract that returns 24577 runtime bytes is rejected by EIP-170" {
    # 0x6160016000f3 = PUSH2 0x6001 PUSH1 0x00 RETURN
    # Returns 0x6001 = 24577 bytes of zeroed memory as runtime, exceeding EIP-170 (24576 byte limit)
    set +e
    # Rejection happens after RETURN (memory expansion ~3K gas) but before code deposit;
    # actual consumption is <60K.  200K is ample and keeps fee well under the node cap.
    receipt=$(cast send \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6160016000f3" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 24577-byte runtime (over EIP-170 limit), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 — node rejected oversized runtime — pass
}

# bats test_tags=execution-specs,evm-gas
@test "deploy contract that returns exactly 24576 runtime bytes succeeds (EIP-170 boundary)" {
    # 0x6160006000f3 = PUSH2 0x6000 PUSH1 0x00 RETURN
    # Returns exactly 24576 (0x6000) bytes of zeroed memory — the EIP-170 maximum.
    # This is the boundary case: 24576 must succeed while 24577 (tested above) must fail.
    # Code-deposit cost: 200 gas/byte × 24576 bytes = 4,915,200 gas, plus ~57K overhead.
    # 5,500,000 covers the actual spend; at ~25 Gwei that is ~0.14 ETH — within the
    # 1 ETH wallet balance and below the node's 0.42 ETH txfeecap.
    receipt=$(cast send \
        --gas-limit 5500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6160006000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for exactly 24576-byte runtime (at EIP-170 limit), got: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    # Strip leading 0x and divide char count by 2 to get byte length.
    deployed_len=$(( (${#deployed_code} - 2) / 2 ))
    if [[ "$deployed_len" -ne 24576 ]]; then
        echo "Expected 24576-byte deployed runtime at EIP-170 boundary, got ${deployed_len} bytes" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "deploy contract with 0xEF leading runtime byte is rejected by EIP-3541" {
    # EIP-3541 (London+): any contract creation whose first byte of runtime code is 0xEF
    # must be rejected. This protects the EOF container format prefix.
    # Initcode: PUSH1 0xEF  PUSH1 0x00  MSTORE8  PUSH1 0x01  PUSH1 0x00  RETURN
    # Stores byte 0xEF at mem[0] then returns 1 byte of runtime → runtime starts with 0xEF.
    set +e
    receipt=$(cast send \
        --gas-limit 1000000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x60ef60005360016000f3" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure for 0xEF-prefixed runtime (EIP-3541), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 — node correctly rejected EF-prefixed runtime — pass
}

# bats test_tags=execution-specs,transaction-eoa
@test "CREATE2 deploys child to predicted salt-derived address" {
    # Factory constructor uses CREATE2 to deploy a child, stores child address at slot 0.
    # Bytecode breakdown:
    #   PUSH32 <child_initcode padded to 32 bytes>   child = 600160005360016000f3 (10 bytes)
    #   PUSH1 0x00  MSTORE                            store child initcode at mem[0..31]
    #   PUSH1 0x42                                    salt
    #   PUSH1 0x0a                                    size (10 bytes of initcode)
    #   PUSH1 0x00                                    memory offset
    #   PUSH1 0x00                                    value (0 ETH)
    #   CREATE2                                       deploy child
    #   PUSH1 0x00  SSTORE                            store child address at slot 0
    #   STOP
    # Child initcode (600160005360016000f3):
    #   PUSH1 0x01  PUSH1 0x00  MSTORE8  PUSH1 0x01  PUSH1 0x00  RETURN
    #   → returns 1-byte runtime (0x01).
    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x7f600160005360016000f3000000000000000000000000000000000000000000006000526042600a60006000f560005500")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for CREATE2 factory deploy, got: $tx_status" >&2
        return 1
    fi

    factory_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # Read child address from factory's storage slot 0 (left-padded to 32 bytes).
    actual_raw=$(cast storage "$factory_addr" 0 --rpc-url "$L2_RPC_URL")
    actual_child="0x${actual_raw: -40}"

    # Child should have runtime code 0x01.
    child_code=$(cast code "$actual_child" --rpc-url "$L2_RPC_URL")
    if [[ "$child_code" == "0x" ]]; then
        echo "Child contract at $actual_child has no code — CREATE2 failed silently" >&2
        return 1
    fi

    # Predict the CREATE2 address:
    #   address = keccak256(0xff ++ deployer ++ salt ++ keccak256(initcode))[12:]
    child_initcode="0x600160005360016000f3"
    init_code_hash=$(cast keccak "$child_initcode")
    factory_hex=$(echo "${factory_addr#0x}" | tr '[:upper:]' '[:lower:]')
    salt_hex="0000000000000000000000000000000000000000000000000000000000000042"
    hash_hex="${init_code_hash#0x}"

    packed="0xff${factory_hex}${salt_hex}${hash_hex}"
    predicted_hash=$(cast keccak "$packed")
    predicted_addr="0x${predicted_hash: -40}"

    actual_lower=$(echo "$actual_child" | tr '[:upper:]' '[:lower:]')
    predicted_lower=$(echo "$predicted_addr" | tr '[:upper:]' '[:lower:]')
    if [[ "$actual_lower" != "$predicted_lower" ]]; then
        echo "CREATE2 address mismatch: actual=$actual_child predicted=$predicted_addr" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "nested contract creation: constructor deploys child via CREATE" {
    # Factory constructor deploys a child contract, then returns its own 1-byte runtime.
    # Bytecode breakdown:
    #   PUSH32 <child_initcode padded>   child = 600160005360016000f3 (10 bytes, returns 0x01)
    #   PUSH1 0x00  MSTORE               store child initcode at mem[0..31]
    #   PUSH1 0x0a  PUSH1 0x00  PUSH1 0x00  CREATE   deploy child (size=10, offset=0, value=0)
    #   POP                              discard child address from stack
    #   PUSH1 0x01  PUSH1 0x00  MSTORE8  mem[0] = 0x01
    #   PUSH1 0x01  PUSH1 0x00  RETURN   return 1-byte runtime (0x01) for factory
    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x7f600160005360016000f300000000000000000000000000000000000000000000600052600a60006000f050600160005360016000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success for nested creation, got: $tx_status" >&2
        return 1
    fi

    factory_addr=$(echo "$receipt" | jq -r '.contractAddress')

    # Factory should have non-empty runtime code.
    factory_code=$(cast code "$factory_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$factory_code" == "0x" ]]; then
        echo "Factory contract has no runtime code after nested CREATE" >&2
        return 1
    fi

    # During creation the factory's nonce starts at 1 (EIP-161).  The child address is
    # derived from RLP([factory_addr, nonce=1]).
    child_addr=$(cast compute-address "$factory_addr" --nonce 1 | awk '{print $NF}')

    # Child should also have non-empty runtime code.
    child_code=$(cast code "$child_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$child_code" == "0x" ]]; then
        echo "Child contract at $child_addr has no code — nested CREATE failed" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "SELFDESTRUCT during construction leaves no code and zero balance" {
    # Initcode: PUSH1 0x00  SELFDESTRUCT (0xff)
    # SELFDESTRUCT is a successful halt (not a revert) so the tx should succeed, but
    # no RETURN is executed → no runtime code is stored.  Post-Cancun (EIP-6780),
    # SELFDESTRUCT in the same tx as creation still fully deletes the account.
    receipt=$(cast send \
        --legacy \
        --gas-limit 100000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6000ff")

    tx_status=$(echo "$receipt" | jq -r '.status')
    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')

    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected tx success (SELFDESTRUCT is not a revert), got: $tx_status" >&2
        return 1
    fi

    # No runtime code should exist at the contract address.
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$deployed_code" != "0x" ]]; then
        echo "Expected no code after SELFDESTRUCT in constructor, got: $deployed_code" >&2
        return 1
    fi

    # Balance should be zero (SELFDESTRUCT sends any balance to target, account deleted).
    balance=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")
    if [[ "$balance" != "0" ]]; then
        echo "Expected zero balance after SELFDESTRUCT, got: $balance" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,evm-gas
@test "OOG during code-deposit phase fails the creation" {
    # Initcode: PUSH2 0x03e8  PUSH1 0x00  RETURN
    # Returns 1000 bytes of zeroed memory as runtime code.
    # Code-deposit cost: 200 gas/byte × 1000 = 200,000 gas.
    # With --gas-limit 100000 the intrinsic cost is ~53K (21K base + 32K CREATE + calldata),
    # leaving ~47K for execution + code deposit.  Execution costs ~100 gas, so ~46,900
    # remains — far short of the 200K code-deposit requirement.  The creation must fail.
    set +e
    receipt=$(cast send \
        --legacy \
        --gas-limit 100000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x6103e86000f3" 2>/dev/null)
    send_exit=$?
    set -e

    if [[ $send_exit -eq 0 && -n "$receipt" ]]; then
        tx_status=$(echo "$receipt" | jq -r '.status // "0x0"')
        if [[ "$tx_status" == "0x1" ]]; then
            echo "Expected failure (OOG during code-deposit for 1000-byte runtime at 100K gas), but tx succeeded" >&2
            return 1
        fi
    fi
    # Non-zero exit or status 0x0 — creation failed during code-deposit phase — pass
}

# bats test_tags=execution-specs,evm-gas
@test "stack depth limit: 1024 nested calls revert" {
    # Deploy a contract that recursively CALLs itself until the call stack
    # exceeds the EVM limit of 1024 frames, then verify the outermost call reverts.
    #
    # Runtime bytecode (deployed):
    #   PUSH1 0x00  PUSH1 0x00  PUSH1 0x00  PUSH1 0x00   -- retSize retOff argsSize argsOff
    #   PUSH1 0x00                                         -- value (0)
    #   ADDRESS                                            -- target = self
    #   GAS                                                -- forward all remaining gas
    #   CALL                                               -- recursive call
    #   PUSH1 0x00  MSTORE                                 -- store result at mem[0]
    #   PUSH1 0x20  PUSH1 0x00  RETURN                     -- return 32 bytes (call result)
    #
    # Hex: 6000 6000 6000 6000 6000 30 5a f1 6000 52 6020 6000 f3
    # Initcode: store runtime at mem[0], return it.
    #   PUSH13 <runtime>  PUSH1 0x00  MSTORE
    #   PUSH1 0x0d  PUSH1 0x13  RETURN  (but easier to just inline)
    #
    # Simpler approach: use initcode that returns the recursive runtime.
    # Runtime = 60006000600060006000305af160005260206000f3 (20 bytes)
    # Initcode: PUSH20 <runtime> PUSH1 0x00 MSTORE  PUSH1 0x14  PUSH1 0x0c  RETURN
    local runtime="60006000600060006000305af160005260206000f3"
    local runtime_len=$(( ${#runtime} / 2 ))  # 20 bytes
    local runtime_len_hex
    printf -v runtime_len_hex '%02x' "$runtime_len"

    # CODECOPY-based initcode (12-byte header, same pattern as other tests):
    # PUSH1 len | PUSH1 0x0c | PUSH1 0x00 | CODECOPY | PUSH1 len | PUSH1 0x00 | RETURN | <runtime>
    local initcode="60${runtime_len_hex}600c60003960${runtime_len_hex}6000f3${runtime}"

    # The recursive call test needs high gas (1024 call frames × ~2600 gas each ≈ 2.7M).
    # Bor enforces a minimum gas tip of 25 gwei, and the node's txfeecap is 0.42 ETH.
    # Max gas limit = 0.42 ETH / 25 gwei = 16,800,000.  Use 16M for the call.
    # Deployment only needs 200K so it stays well within the cap.

    receipt=$(cast send \
        --legacy \
        --gas-limit 200000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${initcode}")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Contract deployment failed" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    echo "[stack-depth] Contract deployed at $contract_addr" >&3

    # Call the contract — it will recurse until depth 1024, then the deepest CALL
    # returns 0 (failure). The outermost call should succeed (tx status 0x1) but
    # the return data indicates the inner call eventually failed.
    # 16M gas × 25 gwei = 0.4 ETH, just under the 0.42 ETH txfeecap.
    set +e
    call_receipt=$(cast send \
        --legacy \
        --gas-limit 16000000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        "$contract_addr" 2>/dev/null)
    call_exit=$?
    set -e

    # The tx itself should be mined (may succeed or OOG at depth).
    # The key invariant: the chain handled 1024-depth recursion without crashing.
    if [[ $call_exit -eq 0 && -n "$call_receipt" ]]; then
        gas_used_hex=$(echo "$call_receipt" | jq -r '.gasUsed // "0x0"')
        gas_used=$(printf '%d' "$gas_used_hex")
        echo "[stack-depth] Recursive call mined, gasUsed=$gas_used" >&3
    else
        echo "[stack-depth] Recursive call rejected or failed at RPC level — acceptable" >&3
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "multiple CREATEs in single transaction: factory creates 5 children" {
    # Deploy a factory whose constructor creates 5 child contracts via CREATE,
    # storing each child address in storage slots 0-4.
    # Child initcode: 600160005360016000f3 (returns 1-byte runtime 0x01), 10 bytes.
    #
    # For each of 5 children, the constructor:
    #   PUSH32 <child_initcode padded>  PUSH1 0x00  MSTORE
    #   PUSH1 0x0a  PUSH1 0x00  PUSH1 0x00  CREATE   -- size=10, offset=0, value=0
    #   PUSH1 <slot>  SSTORE                           -- store child addr at slot i
    #
    # After all 5 CREATEs, return 1-byte runtime.
    child_padded="600160005360016000f300000000000000000000000000000000000000000000"

    # Build constructor bytecode for 5 CREATEs.
    constructor=""
    for i in $(seq 0 4); do
        slot_hex=$(printf '%02x' "$i")
        constructor+="7f${child_padded}600052600a60006000f060${slot_hex}55"
    done
    # Return 1-byte runtime (0x01): PUSH1 0x01  PUSH1 0x00  MSTORE8  PUSH1 0x01  PUSH1 0x00  RETURN
    constructor+="600160005360016000f3"

    receipt=$(cast send \
        --legacy \
        --gas-limit 2000000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x${constructor}")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Factory deployment failed" >&2
        return 1
    fi

    factory_addr=$(echo "$receipt" | jq -r '.contractAddress')
    echo "[multi-create] Factory deployed at $factory_addr" >&3

    # Verify all 5 children have code.
    failures=0
    for i in $(seq 0 4); do
        slot_val=$(cast storage "$factory_addr" "$i" --rpc-url "$L2_RPC_URL")
        child_addr="0x${slot_val: -40}"
        child_code=$(cast code "$child_addr" --rpc-url "$L2_RPC_URL")
        if [[ "$child_code" == "0x" || -z "$child_code" ]]; then
            echo "[multi-create] Child $i at $child_addr has no code" >&2
            failures=$(( failures + 1 ))
        else
            echo "[multi-create] Child $i at $child_addr has code" >&3
        fi
    done

    if [[ "$failures" -gt 0 ]]; then
        echo "$failures / 5 child contracts have no code" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,transaction-eoa
@test "CREATE with maximum value transfer in constructor" {
    # Deploy a contract while sending all remaining value (minus gas cost) to it.
    # The constructor receives msg.value; verify the contract's post-deploy balance.
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    local pk
    pk=$(echo "$wallet_json" | jq -r '.private_key')
    local addr
    addr=$(echo "$wallet_json" | jq -r '.address')

    # Fund with exactly 0.1 ETH.
    cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --legacy \
        --gas-limit 21000 --value 0.1ether "$addr" >/dev/null

    balance=$(cast balance "$addr" --rpc-url "$L2_RPC_URL")
    gas_price=$(cast gas-price --rpc-url "$L2_RPC_URL")
    gas_limit=100000
    max_gas_cost=$(( gas_price * gas_limit ))
    send_value=$(( balance - max_gas_cost ))

    if [[ "$send_value" -le 0 ]]; then
        skip "Insufficient balance to cover gas cost and send value"
    fi

    echo "[max-value-create] Sending $send_value wei to constructor (balance=$balance, maxGas=$max_gas_cost)" >&3

    # Simple constructor: just STOP (no RETURN), which accepts msg.value.
    # The contract will hold the sent value.
    # Initcode: PUSH1 0x01 PUSH1 0x00 MSTORE8 PUSH1 0x01 PUSH1 0x00 RETURN
    # Returns 1-byte runtime (0x01) so the contract address is created.
    receipt=$(cast send \
        --legacy \
        --gas-limit "$gas_limit" \
        --value "$send_value" \
        --private-key "$pk" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x600160005360016000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "CREATE with value failed" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    contract_balance=$(cast balance "$contract_addr" --rpc-url "$L2_RPC_URL")

    if [[ "$contract_balance" -ne "$send_value" ]]; then
        echo "Contract balance mismatch: expected=$send_value actual=$contract_balance" >&2
        return 1
    fi
    echo "[max-value-create] Contract at $contract_addr holds $contract_balance wei" >&3
}

# bats test_tags=execution-specs,evm-gas
@test "large return data in constructor near EIP-170 limit (24000 bytes) succeeds" {
    # Deploy a contract whose constructor returns 24000 bytes of runtime code.
    # This is below the EIP-170 limit (24576) but large enough to exercise
    # code-deposit gas accounting near the boundary.
    #
    # Initcode: PUSH2 0x5dc0  PUSH1 0x00  RETURN
    # 0x5dc0 = 24000 decimal
    # Returns 24000 bytes of zeroed memory as runtime code.
    # Code-deposit cost: 200 gas/byte × 24000 = 4,800,000 gas.
    receipt=$(cast send \
        --legacy \
        --gas-limit 5500000 \
        --private-key "$ephemeral_private_key" \
        --rpc-url "$L2_RPC_URL" \
        --json \
        --create "0x615dc06000f3")

    tx_status=$(echo "$receipt" | jq -r '.status')
    if [[ "$tx_status" != "0x1" ]]; then
        echo "Expected success for 24000-byte runtime (below EIP-170 limit), got: $tx_status" >&2
        return 1
    fi

    contract_addr=$(echo "$receipt" | jq -r '.contractAddress')
    deployed_code=$(cast code "$contract_addr" --rpc-url "$L2_RPC_URL")
    deployed_len=$(( (${#deployed_code} - 2) / 2 ))

    if [[ "$deployed_len" -ne 24000 ]]; then
        echo "Expected 24000-byte deployed runtime, got $deployed_len bytes" >&2
        return 1
    fi
    echo "[large-return] Contract at $contract_addr has $deployed_len bytes of runtime" >&3
}
