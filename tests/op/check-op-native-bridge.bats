#!/usr/bin/env bats
# bats file_tags=op

setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    l2_private_key="${L1_PRIVATE_KEY:-12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
}

@test "Check L2 OP native bridge is disabled" {
    # /// @notice Sends ETH to a receiver's address on the other chain. Note that if ETH is sent to a
    # ///         smart contract and the call fails, the ETH will be temporarily locked in the
    # ///         StandardBridge on the other chain until the call is replayed. If the call cannot be
    # ///         replayed with any amount of gas (call always reverts), then the ETH will be
    # ///         permanently locked in the StandardBridge on the other chain. ETH will also
    # ///         be locked if the receiver is the other bridge, because finalizeBridgeETH will revert
    # ///         in that case.
    # /// @param _to          Address of the receiver.
    # /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    # /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    # ///                     not be triggered with this data, but it will be emitted and can be used
    # ///                     to identify the transaction.
    op_l2_standard_bridge_addr="0x4200000000000000000000000000000000000010"

    run cast send --rpc-url $l2_rpc_url "$op_l2_standard_bridge_addr" \
        --private-key $l2_private_key \
        --value :"$(date +%s)" \
        "bridgeETHTo(address,uint32,bytes)" \
        "0xC0FFEE0000000000000000000000000000000000" \
        "$(cast gas-price --rpc-url $l2_rpc_url)" \
        "0x"

    # Check if the command failed (non-zero exit status)
    [[ "$status" -ne 0 ]]
}