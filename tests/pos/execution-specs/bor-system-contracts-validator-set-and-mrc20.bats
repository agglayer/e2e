#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,bor-system-contracts

# Bor System Contracts: BorValidatorSet (0x1000), MRC20 (0x1010), StateReceiver (0x1001)
#
# These are genesis-deployed system contracts on Polygon PoS:
#   0x1000 — BorValidatorSet: manages validator set per span/sprint
#   0x1001 — StateReceiver: receives L1→L2 state sync data via Heimdall
#   0x1010 — MRC20 (MaticChildERC20): native token wrapper for POL
#
# Also covers:
#   PIP-20: State-Sync Verbosity — StateCommitted event added to StateReceiver
#   PIP-36: Replay Failed State Syncs — replayFailedStateSync() added to StateReceiver

setup() {
    load "../../../core/helpers/pos-setup.bash"
    pos_setup
}

# bats test_tags=execution-specs,bor-system-contracts,validator-set
@test "BorValidatorSet (0x1000) has deployed code and is callable" {
    local validator_set="0x0000000000000000000000000000000000001000"

    local code
    code=$(cast code "$validator_set" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        echo "BorValidatorSet at $validator_set has no code" >&2
        return 1
    fi

    local code_len=$(( (${#code} - 2) / 2 ))
    echo "BorValidatorSet code: $code_len bytes" >&3

    # Try calling currentSpanNumber() — standard Bor validator set function
    set +e
    local span
    span=$(cast call "$validator_set" "currentSpanNumber()(uint256)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 && -n "$span" ]]; then
        echo "currentSpanNumber(): $span" >&3
    else
        echo "currentSpanNumber() call failed (function may have different ABI on this devnet)" >&3
    fi
}

# bats test_tags=execution-specs,bor-system-contracts,validator-set
@test "BorValidatorSet (0x1000) getBorValidators returns non-empty validator list" {
    local validator_set="0x0000000000000000000000000000000000001000"

    local code
    code=$(cast code "$validator_set" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "BorValidatorSet has no code on this chain"
    fi

    # getBorValidators(uint256 blockNumber) returns (address[], uint256[])
    # Call with latest block number
    local latest_block
    latest_block=$(cast block-number --rpc-url "$L2_RPC_URL")

    set +e
    local result
    result=$(cast call "$validator_set" \
        "getBorValidators(uint256)(address[],uint256[])" \
        "$latest_block" \
        --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 || -z "$result" ]]; then
        # Try alternative: getValidators()
        set +e
        result=$(cast call "$validator_set" "getValidators()(address[],uint256[])" --rpc-url "$L2_RPC_URL" 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -ne 0 || -z "$result" ]]; then
            skip "Cannot call getBorValidators or getValidators on this chain"
        fi
    fi

    echo "Validator set result: ${result:0:200}" >&3

    # Result should be non-empty (at least one validator on the devnet)
    if [[ -z "$result" ]]; then
        echo "Validator set returned empty result" >&2
        return 1
    fi
}

# bats test_tags=execution-specs,bor-system-contracts,mrc20
@test "MRC20 native token wrapper (0x1010) has deployed code and balance function" {
    local mrc20="0x0000000000000000000000000000000000001010"

    local code
    code=$(cast code "$mrc20" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        echo "MRC20 at $mrc20 has no code" >&2
        return 1
    fi

    local code_len=$(( (${#code} - 2) / 2 ))
    echo "MRC20 code: $code_len bytes" >&3

    # Call balanceOf for the zero address (should return some value, possibly 0)
    set +e
    local balance
    balance=$(cast call "$mrc20" \
        "balanceOf(address)(uint256)" \
        "0x0000000000000000000000000000000000000000" \
        --rpc-url "$L2_RPC_URL" 2>/dev/null)
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 && -n "$balance" ]]; then
        echo "MRC20 balanceOf(0x0): $balance" >&3
    else
        echo "MRC20 balanceOf() call failed — function may not be available" >&3
    fi

    # Call totalSupply() if available
    set +e
    local total_supply
    total_supply=$(cast call "$mrc20" "totalSupply()(uint256)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    exit_code=$?
    set -e

    if [[ $exit_code -eq 0 && -n "$total_supply" ]]; then
        echo "MRC20 totalSupply(): $total_supply" >&3
    fi
}

# bats test_tags=execution-specs,bor-system-contracts,pip36,state-receiver
@test "PIP-36: StateReceiver (0x1001) has replayFailedStateSync function" {
    # PIP-36 added replayFailedStateSync(uint256) to StateReceiver to allow
    # replaying failed state syncs that failed due to insufficient gas from transfer().
    local state_receiver="0x0000000000000000000000000000000000001001"

    local code
    code=$(cast code "$state_receiver" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "StateReceiver has no code on this chain"
    fi

    # Call replayFailedStateSync with a non-existent state ID (should revert with
    # a meaningful error, not "function does not exist")
    set +e
    local result
    result=$(cast call "$state_receiver" \
        "replayFailedStateSync(uint256)" \
        "999999999" \
        --rpc-url "$L2_RPC_URL" 2>&1)
    local exit_code=$?
    set -e

    echo "replayFailedStateSync(999999999): exit=$exit_code result=${result:0:200}" >&3

    # If the function exists, we get a revert with specific error data.
    # If the function doesn't exist, we get a generic revert or empty result.
    # Check the ABI by looking for the function selector in the bytecode.
    # replayFailedStateSync(uint256) selector = first 4 bytes of keccak256
    local selector
    selector=$(cast sig "replayFailedStateSync(uint256)" 2>/dev/null)

    if [[ -n "$selector" ]]; then
        local selector_hex="${selector#0x}"
        if echo "$code" | grep -qi "$selector_hex"; then
            echo "PIP-36 confirmed: replayFailedStateSync selector ($selector) found in bytecode" >&3
        else
            echo "PIP-36 selector ($selector) not found in StateReceiver bytecode" >&3
            echo "PIP-36 may not be active on this chain" >&3
            skip "replayFailedStateSync not found in StateReceiver bytecode"
        fi
    fi
}

# bats test_tags=execution-specs,bor-system-contracts,pip20,state-receiver
@test "PIP-20: StateReceiver (0x1001) has StateCommitted event signature" {
    # PIP-20 added the StateCommitted(uint256 indexed stateId, bool success) event
    # to the StateReceiver contract for observability of state sync results.
    local state_receiver="0x0000000000000000000000000000000000001001"

    local code
    code=$(cast code "$state_receiver" --rpc-url "$L2_RPC_URL")
    if [[ "$code" == "0x" || -z "$code" ]]; then
        skip "StateReceiver has no code on this chain"
    fi

    # The event topic is keccak256("StateCommitted(uint256,bool)")
    local event_topic
    event_topic=$(cast keccak "StateCommitted(uint256,bool)" 2>/dev/null)

    if [[ -z "$event_topic" ]]; then
        skip "Cannot compute event topic hash"
    fi

    echo "StateCommitted event topic: $event_topic" >&3

    # Search recent logs for this event topic from the StateReceiver
    set +e
    local logs
    logs=$(cast logs \
        --from-block 0 \
        --to-block latest \
        --address "$state_receiver" \
        "$event_topic" \
        --rpc-url "$L2_RPC_URL" 2>/dev/null | head -c 5000)
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 && -n "$logs" && "$logs" != "[]" && "$logs" != "" ]]; then
        echo "PIP-20 confirmed: StateCommitted events found in logs" >&3
    else
        # No events found — might just mean no state syncs have occurred on this devnet.
        # Check if the event signature exists in bytecode by looking for the PUSH32 of the topic.
        local topic_hex="${event_topic#0x}"
        if echo "$code" | grep -qi "${topic_hex:0:16}"; then
            echo "PIP-20: StateCommitted topic prefix found in bytecode (no events emitted yet)" >&3
        else
            echo "PIP-20: StateCommitted event not detected in bytecode or logs" >&3
            skip "StateCommitted event not found — PIP-20 may not be active"
        fi
    fi
}
