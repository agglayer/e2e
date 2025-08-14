#!/usr/bin/env bats
# bats file_tags=dapps

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
    rip7212_addr=${RIP7212_ADDR:-"0x0000000000000000000000000000000000000100"}

    # Other
    lxly_bridge_addr=${LXLY_BRIDGE_ADDR:-"0x528e26b25a34a4A5d0dbDa1d57D318153d2ED582"}
    multicall_addr=${MULTICALL_ADDR:-"0x4e1d97344FFa4B55A2C6335574982aa9cB627C4F"}
    multicall2_addr=${MULTICALL2_ADDR:-"0xfC0F3dADD7aE3708f352610aa71dF7C93087a676"}
    batch_distributor_addr=${BATCH_DISTRIBUTOR_ADDR:-"0x36C38895A20c835F9A6A294821D669995eB2265E"}
    seaport_v16_addr=${SEAPORT_V16_ADDR:-"0x0000000000FFe8B47B3e2130213B802212439497"}
    seaport_controller_addr=${SEAPORT_CONTROLLER_ADDR:-"0x00000000F9490004C11Cef243f5400493c00Ad63"}

    # Sushi
    sushi_router_addr=${SUSHI_ROUTER_ADDR:-"0xAC4c6e212A361c968F1725b4d055b47E63F80b75"}
    sushi_v3_factory_addr=${SUSHI_V3_FACTORY_ADDR:-"0x9B3336186a38E1b6c21955d112dbb0343Ee061eE"}
    sushi_v3_position_manager_addr=${SUSHI_V3_POSITION_MANAGER_ADDR:-"0x1400feFD6F9b897970f00Df6237Ff2B8b27Dc82C"}

    # Morpho
    morpho_blue_addr=${MORPHO_BLUE_ADDR:-"0xC263190b99ceb7e2b7409059D24CB573e3bB9021"}
    morpho_adaptive_irm_addr=${MORPHO_ADAPTIVE_IRM_ADDR:-"0x9eB6d0D85FCc07Bf34D69913031ade9E16BD5dB0"}
    morpho_chainlink_oracle_v2_factory_addr=${MORPHO_CHAINLINK_ORACLE_V2_FACTORY_ADDR:-"0xe795DD345aD7E1bC9e8F6B4437a21704d731F9E0"}
    morpho_metamorpho_factory_addr=${MORPHO_METAMORPHO_FACTORY_ADDR:-"0x505619071bdCDeA154f164b323B6C42Fc14257f7"}
    morpho_bundler3_addr=${MORPHO_BUNDLER3_ADDR:-"0xD0bDf3E62F6750Bd83A50b4001743898Af287009"}
    morpho_public_allocator=${MORPHO_PUBLIC_ALLOCATOR:-"0x8FfD3815919081bDb60CD8079C68444331B65042"}

    # Yearn
    yearn_ausd_addr=${YEARN_AUSD_ADDR:-"0xAe4b2FCf45566893Ee5009BA36792D5078e4AD60"}
    yearn_weth_addr=${YEARN_WETH_ADDR:-"0xccc0fc2e34428120f985b460b487eb79e3c6fa57"}

    # Agora
    agora_ausd_addr=${AGORA_AUSD_ADDR:-"0xa9012a055bd4e0eDfF8Ce09f960291C09D5322dC"}

    # Universal
    universal_btc_addr=${UNIVERSAL_BTC_ADDR:-"0xB295FDad3aD8521E9Bc20CAeBB36A4258038574e"}
    universal_sol_addr=${UNIVERSAL_SOL_ADDR:-"0x79b2417686870EFf463E37a1cA0fDA1c7e2442cE"}
    universal_xrp_addr=${UNIVERSAL_XRP_ADDR:-"0x26435983DF976A02C55aC28e6F67C6477bBd95E7"}

    # Vault Bridge
    vb_weth_addr=${VB_WETH_ADDR:-"0x17B8Ee96E3bcB3b04b3e8334de4524520C51caB4"}
    vb_weth_converter_addr=${VB_WETH_CONVERTER_ADDR:-"0x3aFbD158CF7B1E6BE4dAC88bC173FA65EBDf2EcD"}
    vb_usdc_addr=${VB_USDC_ADDR:-"0x102E14ffF48170F2e5b6d0e30259fCD4eE5E28aE"}
    vb_usdc_converter_addr=${VB_USDC_CONVERTER_ADDR:-"0x28FDCaF075242719b16D342866c9dd84cC459533"}
    vb_usdt_addr=${VB_USDT_ADDR:-"0xDe51Ef59663e79B494E1236551187399D3359C92"}
    vb_usdt_converter_addr=${VB_USDT_CONVERTER_ADDR:-"0x8f3a47e64d3AD1fBdC5C23adD53183CcCD05D8a4"}
    vb_wbtc_addr=${VB_WBTC_ADDR:-"0x1538aDF273f6f13CcdcdBa41A5ce4b2DC2177D1C"}
    vb_wbtc_converter_addr=${VB_WBTC_CONVERTER_ADDR:-"0x3Ef265DD0b4B86fC51b08D5B03699E57d52C9B27"}
    vb_usds_addr=${VB_USDS_ADDR:-"0xD416d04845d299bCC0e5105414C99fFc88f0C97d"}
    vb_usda_converter=${VB_USDA_CONVERTER:-"0x56342E6093381E2Bd732FFd6141b22136efB98Bf"}

    # MultiSigs	
    # BridgeAdmin Tatara	0x165BD6204Df6A4C47875D62582dc7C1Ed6477c17

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
    call_value=$(cast call --rpc-url "$rpc_url" "$contract_address" $method_sig) # method_sig is deliberately unquoted here to allow for arguments
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
    assert_successful_call "$lxly_bridge_addr" "WETHToken()(address)"
}

@test "spot check Multicall1 contract" {
    assert_has_code "$multicall_addr"
    # Build locally and compare
    # https://github.com/mds1/multicall3/blob/main/src/Multicall.sol
    assert_code_hash "$multicall_addr" "0xa3efe06775a1c62bbd5cd80b4933403a752ca21748f4ba162d7ef4f0ce293916"
}

@test "spot check Multicall2 contract" {
    assert_has_code "$multicall2_addr"
    # Build locally and compare
    # https://github.com/mds1/multicall3/blob/main/src/Multicall2.sol
    assert_code_hash "$multicall2_addr" "0xd68a1d2401a359f968b182a1746881574b946d1f03f8751441228443495c7193"
}

@test "spot check BatchDistributor contract" {
    assert_has_code "$batch_distributor_addr"
    # https://github.com/pcaversaccio/batch-distributor/blob/main/contracts/BatchDistributor.sol
    assert_code_hash "$batch_distributor_addr" "0x7a7d4bf7ce271d08a86b6857c37fe38a0369a809e85dbf93350ae2274f7b7362"
    if ! cast call --value 1 --from "$from_address" --rpc-url "$rpc_url" "$batch_distributor_addr" 'distributeEther(((address,uint256)[]))' '([(0x6E53ad5E1cc50424494510899313689F031a95B4,1)])'; then
        echo "Unable to call batch distributor contract"
        exit 1
    fi
}

@test "spot check RIP-7212 contract" {
    if [[ $(cast call --rpc-url "$rpc_url" "$rip7212_addr" 0xb7b8486d949d2beef140ca44d4c8c0524dd53a250fadefa477b2db15b7d38776beb9e3aacfdc1408bfe5f876d9ab6f7c50e06a2d5f68aa500b9a2ff896587597ba72bb78539ef6de9188a0ce5e6d694e2b0cb5aeda35d7ccbb335f6cb5e97d8832f6471f0e06a4830d24eaecfac34e12ad223211a89c42aaf11f44ce3364233a4cfeddbcb7aa6aad4226715338725398546cb20ba2e8b133b2abae61cfc624d0) != "0x0000000000000000000000000000000000000000000000000000000000000001" ]] ; then
        echo "RIP-7212 signature verification failed"
        exit 1
    fi
}

@test "spot check Seaport 1.6 contract" {
    skip # the address 0x0000000000FFe8B47B3e2130213B802212439497 seems like it's tied to the immutable create 2 factory. Not seaport
    assert_has_code "$seaport_v16_addr"
    assert_code_hash "$seaport_v16_addr" "0x767db8f19b71e367540fa372e8e81e4dcb7ca8feede0ae58a0c0bd08b7320dee"
}

@test "spot check Seaport Conduit Controller contract" {
    assert_has_code "$seaport_controller_addr"
    # https://github.com/ProjectOpenSea/seaport-1.6/blob/main/src/core/conduit/ConduitController.sol
    assert_code_hash "$seaport_controller_addr" "0x880348b652e7cce91216153a4d0107e70c77b92192f3d7a127ff1f1351961948"
    assert_successful_call "$seaport_controller_addr" 'getConduitCodeHashes()(bytes32,bytes32)'
}

# RedSnwapper
@test "spot check Sushi Router contract" {
    assert_has_code "$sushi_router_addr"
    assert_code_hash "$sushi_router_addr" "0x09a33bedcf9669b6acb4e832804cfd8457d73b96074af0868a0085657633ed49"
    assert_successful_call "$sushi_router_addr" 'safeExecutor()(address)'
}
@test "spot check Sushi V3 Factory contract" {
    assert_has_code "$sushi_v3_factory_addr"
    # The code has the contract address in the code, so the hash will change every time. Below, we are manually stripping the hash from the binary and comparing
    # https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Factory.sol
    # assert_code_hash "$sushi_v3_factory_addr" "0x504e3ac046d292105b81fb528cd5e90ae46ef726302d7149d285a3c9ab85d8c6"
    tmp_data="$(mktemp)"
    cast code --rpc-url "$rpc_url" "$sushi_v3_factory_addr" | sed 's/0x//' | xxd -r -p > "$tmp_data"
    dd bs=1 count=1360 if="$tmp_data" of="$tmp_data.head" status=none
    tail -c +1394 "$tmp_data" > "$tmp_data.tail"
    cat "$tmp_data.head" "$tmp_data.tail" > "$tmp_data.stripped"
    if ! sha256sum --check  <<< "a9772b0dc2c135f7e2d5b713114787ea0457fc53e1297b06389dad75b7d2099b $tmp_data.stripped" ; then
        echo "The stripped contract hash did not match the expected value"
        exit 1
    fi
    rm "$tmp_data" "$tmp_data.head" "$tmp_data.tail" "$tmp_data.stripped"
}
@test "spot check Sushi V3 Position Manager contract" {
    assert_has_code "$sushi_v3_position_manager_addr"
    # The implementation doesn't line up with the code here.. But it's verified
    # https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol
    assert_code_hash "$sushi_v3_position_manager_addr" "0x79368aa40096d0e7c5e791bece4a154bc70e7c50add0614419b75cb34f001f85"
    assert_successful_call "$sushi_v3_position_manager_addr" "WETH9()(address)"
    assert_successful_call "$sushi_v3_position_manager_addr" "factory()(address)"
    assert_successful_call "$sushi_v3_position_manager_addr" "baseURI()(address)"
}

@test "spot check Morpho blue contract" {
    assert_has_code "$morpho_blue_addr"
    # This code doesn't exactly match what's compiled, but it's very close. It will change with each deployment
    # assert_code_hash "$morpho_blue_addr" "0x6deb704c10ef04484f673e7dd93390a46d78168e183b5bd8723da73dca212877"
    assert_successful_call "$morpho_blue_addr" "DOMAIN_SEPARATOR()(bytes32)"
    assert_successful_call "$morpho_blue_addr" "feeRecipient()(address)"
}

@test "spot check Morpho AdaptiveCurveIrm contract" {
    assert_has_code "$morpho_adaptive_irm_addr"
    assert_code_hash "$morpho_adaptive_irm_addr" "0x9777879d622ba73f476f34b5dda84c9c70b2432255a865ea8b602c443e75f7ec"
    assert_call_value "$morpho_adaptive_irm_addr" "MORPHO()(address)" "$morpho_blue_addr"
}

@test "spot check Morpho Chainlink Oracle contract" {
    assert_has_code "$morpho_chainlink_oracle_v2_factory_addr"
    assert_code_hash "$morpho_chainlink_oracle_v2_factory_addr" "0x535cbea6cb733b4afdb01e5c88ed057b16bea4a28c0adc5b4f02de09694ecfd2"
    assert_call_value "$morpho_chainlink_oracle_v2_factory_addr" "isMorphoChainlinkOracleV2(address)(bool) 0x0000000000000000000000000000000000000000" "false"
}

@test "spot check Morpho Metamorpho Factory contract" {
    assert_has_code "$morpho_metamorpho_factory_addr"
    assert_code_hash "$morpho_metamorpho_factory_addr" "0x65de735d0731cb772a9fe815eaeb18af38e47c08b77bfacf218eeb8ae02083d1"
    assert_call_value "$morpho_metamorpho_factory_addr" "MORPHO()(address)" "$morpho_blue_addr"
    assert_call_value "$morpho_metamorpho_factory_addr" "isMetaMorpho(address)(bool) 0x0000000000000000000000000000000000000000" "false"
}

@test "spot check Morpho Bundler3 contract" {
    assert_has_code "$morpho_bundler3_addr"
    # Exact hash match for this:
    # https://github.com/morpho-org/bundler3/blob/main/src/Bundler3.sol
    assert_code_hash "$morpho_bundler3_addr" "0xd3912f2b89d1e2848544ca398d337f59950ffb9ecc38a7bd644063fa094c8454"
}

@test "spot check Morpho Public Allocator contract" {
    assert_has_code "$morpho_public_allocator"
    assert_code_hash "$morpho_public_allocator" "0xb5ccbbd4c0638cf582ec3f95914a062d58682e585af17c0c664eb5141c2bc2b1"
    assert_call_value "$morpho_public_allocator" "MORPHO()(address)" "$morpho_blue_addr"
}

@test "spot check Yearn AUSD contract" {
    assert_has_code "$yearn_ausd_addr"
    # Proxy
    assert_code_hash "$yearn_ausd_addr" "0x9cbbbf6a1173fae2d7728e88b6e98819cdb39903e9df82fef7b439675b52d86a"
    implementation_addr=$(cast code --rpc-url "$rpc_url" "$yearn_ausd_addr" | sed 's/0x363d3d373d3d3d363d73\(.\{40\}\)5af43d82803e903d91602b57fd5bf3/0x\1/')
    assert_has_code "$implementation_addr"
    assert_code_hash "$implementation_addr" "0xcf95c532cb05bdfdbcfcb5ade8957e84b69091d0260b667ebc5627ca9efbfd65"
    assert_call_value "$yearn_ausd_addr" "apiVersion()(string)" '"3.0.4"'
    assert_call_value "$yearn_ausd_addr" "name()(string)" '"AUSD yVault"'
}

@test "spot check Yearn WETH contract" {
    assert_has_code "$yearn_weth_addr"
    # Proxy
    assert_code_hash "$yearn_weth_addr" "0x9cbbbf6a1173fae2d7728e88b6e98819cdb39903e9df82fef7b439675b52d86a"
    implementation_addr=$(cast code --rpc-url "$rpc_url" "$yearn_weth_addr" | sed 's/0x363d3d373d3d3d363d73\(.\{40\}\)5af43d82803e903d91602b57fd5bf3/0x\1/')
    assert_has_code "$implementation_addr"
    assert_code_hash "$implementation_addr" "0xcf95c532cb05bdfdbcfcb5ade8957e84b69091d0260b667ebc5627ca9efbfd65"
    assert_call_value "$yearn_weth_addr" "apiVersion()(string)" '"3.0.4"'
    assert_call_value "$yearn_weth_addr" "name()(string)" '"WETH yVault"'
}

# https://github.com/agora-finance/agora-dollar-evm/blob/master/src/contracts/proxy/AgoraDollarErc1967Proxy.sol
@test "spot check Agora AUSD contract" {
    assert_has_code "$agora_ausd_addr"
    assert_code_hash "$agora_ausd_addr" "0x9136a47182d5cc37ad65b84dfecc2c61c9de45494efbed5be9c7737a9472153e"
}

@test "spot check Universal BTC contract" {
    assert_has_code "$universal_btc_addr"
    #proxy
    assert_code_hash "$universal_btc_addr" "0xd0d05c4e937613645bf5d0f7ba931b1a2092cf39ba783cbdf67c6964e1c62ced"
    beacon_addr=$(cast storage --rpc-url "$rpc_url" "$universal_btc_addr"  0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 | sed 's/0x0\{24\}\(.\{40\}\)$/0x\1/')
    assert_has_code "$beacon_addr"
    assert_code_hash "$beacon_addr" "0x21ded60bf10c0f66ee44cc22b55685a7572192f8bc185a93d0acf9bc7149b305"
    implementation_addr=$(cast call --rpc-url "$rpc_url" "$beacon_addr" 'implementation()(address)')
    assert_has_code "$implementation_addr"
    assert_code_hash "$implementation_addr" "0x396d815ec88d4f538e2d410bd74e82d85db3a7bb72bd91fb8fe30774945445c1"
    assert_successful_call "$universal_btc_addr" "totalSupply()(uint256)"
    assert_call_value "$universal_btc_addr" "symbol()(string)" '"uBTC"'
    assert_call_value "$universal_btc_addr" "name()(string)" '"Bitcoin (Universal)"'
}
@test "spot check Universal SOL contract" {
    assert_has_code "$universal_sol_addr"
    #proxy
    assert_code_hash "$universal_sol_addr" "0xd0d05c4e937613645bf5d0f7ba931b1a2092cf39ba783cbdf67c6964e1c62ced"
    beacon_addr=$(cast storage --rpc-url "$rpc_url" "$universal_sol_addr"  0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 | sed 's/0x0\{24\}\(.\{40\}\)$/0x\1/')
    assert_has_code "$beacon_addr"
    assert_code_hash "$beacon_addr" "0x21ded60bf10c0f66ee44cc22b55685a7572192f8bc185a93d0acf9bc7149b305"
    implementation_addr=$(cast call --rpc-url "$rpc_url" "$beacon_addr" 'implementation()(address)')
    assert_has_code "$implementation_addr"
    assert_code_hash "$implementation_addr" "0x396d815ec88d4f538e2d410bd74e82d85db3a7bb72bd91fb8fe30774945445c1"
    assert_successful_call "$universal_sol_addr" "totalSupply()(uint256)"
    assert_call_value "$universal_sol_addr" "symbol()(string)" '"uSOL"'
    assert_call_value "$universal_sol_addr" "name()(string)" '"Solana (Universal)"'
}
@test "spot check Universal XRP contract" {
    assert_has_code "$universal_xrp_addr"
    #proxy
    assert_code_hash "$universal_xrp_addr" "0xd0d05c4e937613645bf5d0f7ba931b1a2092cf39ba783cbdf67c6964e1c62ced"
    beacon_addr=$(cast storage --rpc-url "$rpc_url" "$universal_xrp_addr"  0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 | sed 's/0x0\{24\}\(.\{40\}\)$/0x\1/')
    assert_has_code "$beacon_addr"
    assert_code_hash "$beacon_addr" "0x21ded60bf10c0f66ee44cc22b55685a7572192f8bc185a93d0acf9bc7149b305"
    implementation_addr=$(cast call --rpc-url "$rpc_url" "$beacon_addr" 'implementation()(address)')
    assert_has_code "$implementation_addr"
    assert_code_hash "$implementation_addr" "0x396d815ec88d4f538e2d410bd74e82d85db3a7bb72bd91fb8fe30774945445c1"
    assert_successful_call "$universal_xrp_addr" "totalSupply()(uint256)"
    assert_call_value "$universal_xrp_addr" "symbol()(string)" '"uXRP"'
    assert_call_value "$universal_xrp_addr" "name()(string)" '"XRP (Universal)"'
}
