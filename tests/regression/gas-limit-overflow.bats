#!/usr/bin/env bats

setup() {
    readonly private_key=${PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    readonly rpc_url=${RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
}


# bats file_tags=gas-limit-overflow
@test "rpc and sequencer handles two large transactions" {    
    if ! cast block-number --rpc-url "$rpc_url" ; then
        exit 1
    fi

    eth_address=$(cast wallet address --private-key "$private_key")
    balance=$(cast balance --rpc-url "$rpc_url" "$eth_address")

    if [[ $balance -eq 0 ]]; then
        echo "The test account is not funded" >&2
        exit 1
    fi
    deployment_proxy=$(cast code --rpc-url "$rpc_url" 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    if [[ $deployment_proxy == "0x" ]]; then
        cast send --legacy --value 0.1ether --rpc-url "$rpc_url" --private-key "$private_key" 0x3fab184622dc19b6109349b94811493bf2a45362
        cast publish --rpc-url "$rpc_url" 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
    fi

    salt=0x0000000000000000000000000000000000000000000000000000000000000000
    counters_addr=$(cast create2 --salt $salt --init-code "$(cat core/contracts/bin/zkevm-counters.bin)")
    >&2 echo "$counters_addr"
    deployed_code=$(cast code --rpc-url "$rpc_url" "$counters_addr")
    if [[ $deployed_code == "0x" ]]; then
        >&2 echo cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$salt$(cat core/contracts/bin/zkevm-counters.bin)" 
        cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" 0x4e59b44847b379578588920ca78fbf26c0b4956c "$salt$(cat core/contracts/bin/zkevm-counters.bin)"
    fi

    polycli loadtest \
            --send-only \
            --rpc-url "$rpc_url" \
            --private-key "$private_key" \
            --requests 5 \
            --mode contract-call \
            --contract-address "$counters_addr" \
            --gas-limit 15000100 \
            --calldata "$(cast abi-encode 'f(uint256)' 2)"

    start_bn=$(cast block-number --rpc-url "$rpc_url")
    sleep 12
    end_bn=$(cast block-number --rpc-url "$rpc_url")

    if [[ $end_bn -le $start_bn ]]; then
        >&2 echo "The RPC seems to be halted"
        exit 1
    fi
}
