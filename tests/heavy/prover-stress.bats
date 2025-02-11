#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup
}

# bats file_tags=stress,prover-stress
@test "rpc and sequencer handles two large transactions" {
    load "$PROJECT_ROOT/core/helpers/scripts/deploy_test_contracts.sh"

    cast wallet address --private-key $private_key
    salt=0x0000000000000000000000000000000000000000000000000000000000000000
    stress_addr=$(cast create2 --salt $salt --init-code "$(cat core/contracts/bin/evm-stress.bin)")
    deployed_code=$(cast code --rpc-url "$l2_rpc_url" "$stress_addr")
    if [[ $deployed_code == "0x" ]]; then
        cast send --legacy --rpc-url "$l2_rpc_url" --private-key "$private_key" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$salt$(cat core/contracts/bin/evm-stress.bin)"
    fi

    rm -f test-txs.ndjson

    for i in {0..51}; do
        lim=1000000
        if [[ $i =~ ^(28|30)$ ]]; then
            lim=10000
        fi
        cast send --gas-limit 29000000 \
             --json \
             --legacy \
             --private-key "$private_key" \
             --rpc-url "$l2_rpc_url" \
             "$stress_addr" \
             $(cast abi-encode 'f(uint256 action, uint256 limit)' "$i" "$lim") | jq -c '.' | tee -a test-txs.ndjson
    done

    failed_txs=$(jq -r 'select(.status == "0x0")' test-txs.ndjson)

    if [[ -n "$failed_txs" ]]; then
        echo "There was a failure in our test contracts"
        echo "$failed_txs"
        exit 1
    fi
}
