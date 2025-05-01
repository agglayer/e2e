#!/usr/bin/env bats

setup () {
    rpc_url=${RPC_URL:-"http://127.0.0.1:8545"}
    from_address="0x23458eF4300B5431078F90dBEE6244eDe634748a"

    # Preinstalls
    safe_addr=${SAFE_ADDR:-"0x69f4D1788e39c87893C980c06EdF4b7f686e2938"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L40
    safe_l2_addr=${SAFE_L2_ADDR:-"0xfb1bffC9d739B8D520DaF37dF666da4C687191EA"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L41
    multi_send_addr=${MULTI_SEND_ADDR:-"0x998739BFdAAdde7C933B942a68053933098f9EDa"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L42
    multi_send_call_only_addr=${MULTI_SEND_CALL_ONLY_ADDR:-"0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L43
    safe_singleton_factory_addr=${SAFE_SINGLETON_FACTORY_ADDR:-"0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L44
    multicall3_addr=${MULTICALL3_ADDR:-"0xcA11bde05977b3631167028862bE2a173976CA11"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L45
    create2_deployer_addr=${CREATE2_DEPLOYER_ADDR:-"0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L46
    createx_addr=${CREATEX_ADDR:-"0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L47
    arachnid_deployer_addr=${ARACHNID_DEPLOYER_ADDR:-"0x4e59b44847b379578588920cA78FbF26c0B4956C"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L48
    permit2_addr=${PERMIT2_ADDR:-"0x000000000022D473030F116dDEE9F6B43aC78BA3"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L49
    erc_4337_v6_entry_point_addr=${ERC_4337_V6_ENTRY_POINT_ADDR:-"0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L50
    erc_4337_v6_sender_creator_addr=${ERC_4337_V6_SENDER_CREATOR_ADDR:-"0x7fc98430eaedbb6070b35b39d798725049088348"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L51
    erc_4337_v7_entry_point_addr=${ERC_4337_V7_ENTRY_POINT_ADDR:-"0x0000000071727De22E5E9d8BAf0edAc6f37da032"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L52
    erc_4337_v7_sender_creator_addr=${ERC_4337_V7_SENDER_CREATOR_ADDR:-"0xEFC2c1444eBCC4Db75e7613d20C6a62fF67A167C"} # https://github.com/ethereum-optimism/specs/blob/ac76ef498f311d139632f991ed0aa927dc263b6a/specs/protocol/preinstalls.md?plain=1#L53

    # Other
    lxly_bridge_addr=${LXLY_BRIDGE_ADDR:-"0x528e26b25a34a4A5d0dbDa1d57D318153d2ED582"}
    multicall_addr=${MULTICALL_ADDR:-"0x4e1d97344FFa4B55A2C6335574982aa9cB627C4F"}
    multicall2_addr=${MULTICALL2_ADDR:-"0xfC0F3dADD7aE3708f352610aa71dF7C93087a676"}
}

assert_has_code() {
    local contract_address="$1"
    if ! cast code --rpc-url "$rpc_url" "$contract_address" ; then
        echo "Unable to check code at $contract_address"
        exit 1
    fi
    if [[ $(cast code --rpc-url "$rpc_url" "$contract_address") == "0x" ]]; then
        echo "There was no code at $contract_address"
        exit 1
    fi
}
assert_code_hash() {
    # 00000001: PUSH20 <<contract address>>
    # 00000016: EXTCODEHASH
    # 00000017: PUSH0
    # 00000018: MSTORE
    # 00000019: PUSH1 0x20
    # 0000001b: PUSH0
    # 0000001c: RETURN
    local contract_address="$1"
    local asserted_hash="$2"
    local actual_code_hash=$(cast call --rpc-url "$rpc_url" --create "0x73$(echo $contract_address | sed 's/0x//')3f5f5260205ff3")
    if [[ "$asserted_hash" != "$actual_code_hash" ]]; then
        echo "Expected $asserted_hash but got $actual_code_hash at address $contract_address"
        exit 1
    fi
}
assert_successful_call() {
    local contract_address="$1"
    local method_sig="$2"
    if ! cast call --rpc-url "$rpc_url" "$contract_address" "$method_sig" ; then
        echo "Unable to call $method_sig in contract at address $contract_address"
        exit 1
    fi
}

assert_call_value() {
    local contract_address="$1"
    local method_sig="$2"
    local asserted_value="$3"
    call_value=$(cast call --rpc-url "$rpc_url" "$contract_address" "$method_sig")
    if [[ "$call_value" != "$asserted_value" ]] ; then
        echo "Expected $asserted_value but got $call_value when calling $method_sig on $contract_address"
        exit 1
    fi
}

@test "spot check Safe contract" {
    assert_has_code "$safe_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L86C13-L86C45929
    assert_code_hash "$safe_addr" "0xbba688fbdb21ad2bb58bc320638b43d94e7d100f6f3ebaab0a4e4de6304b1c2e"
    assert_successful_call "$safe_addr" "nonce()(uint256)"
    assert_successful_call "$safe_addr" "VERSION()(string)"
    assert_call_value "$safe_addr" "VERSION()(string)" '"1.3.0"'
    assert_successful_call "$safe_addr" "domainSeparator()(bytes32)"
}

@test "spot check SafeL2 contract" {
    assert_has_code "$safe_l2_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L89C13-L89C47613
    assert_code_hash "$safe_l2_addr" "0x21842597390c4c6e3c1239e434a682b054bd9548eee5e9b1d6a4482731023c0f"
    assert_successful_call "$safe_l2_addr" "nonce()(uint256)"
    assert_successful_call "$safe_l2_addr" "VERSION()(string)"
    assert_call_value "$safe_l2_addr" "VERSION()(string)" '"1.3.0"'
    assert_successful_call "$safe_l2_addr" "domainSeparator()(bytes32)"
}

@test "spot check MultiSend contract" {
    assert_has_code "$multi_send_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L101C13-L101C1271
    assert_code_hash "$multi_send_addr" "0x81db0e4afdf5178583537b58c5ad403bd47a4ac7f9bde2442ef3e341d433126a"

    if ! cast call --value 1 --from "$from_address" --rpc-url "$rpc_url" --create 0x7f8d80ff0a000000000000000000000000000000000000000000000000000000005f527c20000000000000000000000000000000000000000000000000000000006020527c55012d3f769b1ba9d5917f3a772dae0f68dfc7e1d082000000000000006040526701000000000000006060525f6080525f60a0525f60d060c05f73$(echo "$multi_send_addr" | sed 's/0x//')5af450 ; then
        echo "There was an issue calling the multisend contract"
        exit 1
    fi
}

@test "spot check MultiSendCallOnly contract" {
    assert_has_code "$multi_send_call_only_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L92
    assert_code_hash "$multi_send_call_only_addr" "0xa9865ac2d9c7a1591619b188c4d88167b50df6cc0c5327fcbd1c8c75f7c066ad"

    if ! cast call --value 1 --from "$from_address" --rpc-url "$rpc_url" --create 0x7f8d80ff0a000000000000000000000000000000000000000000000000000000005f527c20000000000000000000000000000000000000000000000000000000006020527c55012d3f769b1ba9d5917f3a772dae0f68dfc7e1d082000000000000006040526701000000000000006060525f6080525f60a0525f60d060c05f73$(echo "$multi_send_addr" | sed 's/0x//')5af450 ; then
        echo "There was an issue calling the multisend contract"
        exit 1
    fi
}

@test "spot check SafeSingletonFactory contract" {
    assert_has_code "$safe_singleton_factory_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L95
    assert_code_hash "$safe_singleton_factory_addr" "0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989"
}

@test "spot check Multicall3 contract" {
    assert_has_code "$multicall3_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L80C13-L80C7629
    assert_code_hash "$multicall3_addr" "0xd5c15df687b16f2ff992fc8d767b4216323184a2bbc6ee2f9c398c318e770891"
}

@test "spot check Create2Deployer contract" {
    assert_has_code "$create2_deployer_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L83C13-L83C3181
    assert_code_hash "$create2_deployer_addr" "0xb0550b5b431e30d38000efb7107aaa0ade03d48a7198a140edda9d27134468b2"
}

@test "spot check CreateX contract" {
    assert_has_code "$createx_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L116
    assert_code_hash "$createx_addr" "0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f"
}

@test "spot check Arachnid's Deterministic Deployment Proxy contract" {
    assert_has_code "$arachnid_deployer_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L98
    assert_code_hash "$arachnid_deployer_addr" "0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989"
}

@test "spot check Permit2 contract" {
    assert_has_code "$permit2_addr"
    # This code is actual a template so the hash on chain is not expected to match the hash from the repo
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L77
    assert_code_hash "$permit2_addr" "0x9ddc0bd3354535f5d9aa52cfab76d1c371d303ceb5058ee62d318bec16c3c3e8"
    assert_successful_call "$permit2_addr" "DOMAIN_SEPARATOR()(bytes32)"
}

@test "spot check ERC-4337 v0.6.0 EntryPoint contract" {
    assert_has_code "$erc_4337_v6_entry_point_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L107C13-L107C47391
    assert_code_hash "$erc_4337_v6_entry_point_addr" "0xc93c806e738300b5357ecdc2e971d6438d34d8e4e17b99b758b1f9cac91c8e70"
}

@test "spot check ERC-4337 v0.6.0 SenderCreator contract" {
    assert_has_code "$erc_4337_v6_sender_creator_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L104C13-L104C1069
    assert_code_hash "$erc_4337_v6_sender_creator_addr" "0xae818091eaaf1b6175ee41472359a689f3823d0908a41e2e5c4ad508f2fc04a3"
}

@test "spot check ERC-4337 v0.7.0 EntryPoint contract" {
    assert_has_code "$erc_4337_v7_entry_point_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L107C13-L107C47391
    assert_code_hash "$erc_4337_v7_entry_point_addr" "0x8db5ff695839d655407cc8490bb7a5d82337a86a6b39c3f0258aa6c3b582fc58"
}

@test "spot check ERC-4337 v0.7.0 SenderCreator contract" {
    assert_has_code "$erc_4337_v7_sender_creator_addr"
    # https://github.com/ethereum-optimism/optimism/blob/c8b9f62736a7dad7e569719a84c406605f4472e6/packages/contracts-bedrock/src/libraries/Preinstalls.sol#L104C13-L104C1069
    assert_code_hash "$erc_4337_v7_sender_creator_addr" "0x283c9d14378f5f4c4e24045b87d621d48443fa5b4af7dd7180a599b3756a7689"
}

#  _   _                                              _
# | \ | | ___  _ __         __ _  ___ _ __   ___  ___(_)___
# |  \| |/ _ \| '_ \ _____ / _` |/ _ \ '_ \ / _ \/ __| / __|
# | |\  | (_) | | | |_____| (_| |  __/ | | |  __/\__ \ \__ \
# |_| \_|\___/|_| |_|      \__, |\___|_| |_|\___||___/_|___/
#                          |___/

@test "spot check PolygonZkEVMBridgeV2 contract" {
    assert_has_code "$lxly_bridge_addr"
    assert_code_hash "$lxly_bridge_addr" "0xdcce4ba4cd504d8e268fe8e5d81e6bba52ee564429488f58ebecc20e6969b755"
    assert_successful_call "$lxly_bridge_addr" "networkID()(uint32)"
    assert_successful_call "$lxly_bridge_addr" "lastUpdatedDepositCount()(uint32)"
}

@test "spot check Multicall1 contract" {
    assert_has_code "$multicall_addr"
    # https://github.com/mds1/multicall3/blob/main/src/Multicall.sol
    assert_code_hash "$multicall_addr" "0xa3efe06775a1c62bbd5cd80b4933403a752ca21748f4ba162d7ef4f0ce293916"
}

@test "spot check Multicall2 contract" {
    assert_has_code "$multicall2_addr"
    # https://github.com/mds1/multicall3/blob/main/src/Multicall2.sol
    assert_code_hash "$multicall2_addr" "0xd68a1d2401a359f968b182a1746881574b946d1f03f8751441228443495c7193"
}
