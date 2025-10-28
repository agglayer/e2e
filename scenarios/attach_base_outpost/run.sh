#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

# https://superbridge.app/base-sepolia
base_rpc_url=${BASE_RPC_URL}
base_private_key=${BASE_PRIVATE_KEY}
base_admin=$(cast wallet address --private-key $base_private_key)

kurtosis_enclave_name=${ENCLAVE_NAME:-"outpost"}
kurtosis_tag=${KURTOSIS_PACKAGE_TAG:-"11aad0a28a2d6000f5506d9f4344e768dd1ba49d"}
docker_network_name="kt-$kurtosis_enclave_name"


 ##                                               ##                      ##              ####                                                    
 ##                       ##                      ##                      ##              ####                                             ##     
 ##                       ##                                              ##                ##                                             ##     
 ##   ##:##    ####.########### .####.  :#####. ####    :#####.      :###.## .####: ##.###: ##    .####. ##    #### #:##: .####: ##.#### #######  
 ##  ##: ##    ################.######.######## ####   ########     :#######.######:#######:##   .######.:##  ## ########.######:####### #######  
 ##:##:  ##    #####.     ##   ###  #####:  .:#   ##   ##:  .:#     ###  #####:  :#####  #####   ###  ### ##: ##.##.##.####:  :#####  :##  ##     
 ####    ##    ####       ##   ##.  .####### .    ##   ##### .      ##.  .############.  .####   ##.  .## ###:## ## ## ############    ##  ##     
 #####   ##    ####       ##   ##    ##.######:   ##   .######:     ##    ############    ####   ##    ## .## #  ## ## ############    ##  ##     
 ##.###  ##    ####       ##   ##.  .##   .: ##   ##      .: ##     ##.  .####      ##.  .####   ##.  .##  ####. ## ## ####      ##    ##  ##     
 ##  ##: ##:  #####       ##.  ###  ####:.  :##   ##   #:.  :##     ###  ######.  :####  #####:  ###  ###  :###  ## ## #####.  :###    ##  ##.    
 ##  :##  #########       #####.######.########################     :#######.##############:#####.######.   ##   ## ## ##.#########    ##  #####  
 ##   ###  ###.####       .#### .####. . ####  ########. ####        :###.## .#####:##.###: .#### .####.    ##.  ## ## ## .#####:##    ##  .####  
                                                                                    ##                     :##                                    
                                                                                    ##                    ###:                                    
                                                                                    ##                    ###

# Have to run it locally now due to custom bridge modifications
# kurtosis run --enclave "$kurtosis_enclave_name" "github.com/0xPolygon/kurtosis-cdk@$kurtosis_tag"

echo "🔗 Getting admin_private_key and keystore_password values..."
contracts_url="$(kurtosis port print $kurtosis_enclave_name contracts-001 http)"

admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_admin_private_key')"
admin_addr=$(cast wallet address --private-key $admin_private_key)
keystore_password="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_keystore_password')"

l1_preallocated_mnemonic="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.l1_preallocated_mnemonic')"
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")
l1_preallocated_address=$(cast wallet address --mnemonic "$l1_preallocated_mnemonic")

l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)
l1_rpc_url_kurtosis="http://el-1-geth-lighthouse:8545"
l1_chainid=$(cast chain-id --rpc-url "$l1_rpc_url")


echo '██╗     ██████╗     ██╗    ██╗ █████╗ ██╗     ██╗     ███████╗████████╗███████╗'
echo '██║     ╚════██╗    ██║    ██║██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝██╔════╝'
echo '██║      █████╔╝    ██║ █╗ ██║███████║██║     ██║     █████╗     ██║   ███████╗'
echo '██║     ██╔═══╝     ██║███╗██║██╔══██║██║     ██║     ██╔══╝     ██║   ╚════██║'
echo '███████╗███████╗    ╚███╔███╔╝██║  ██║███████╗███████╗███████╗   ██║   ███████║'
echo '╚══════╝╚══════╝     ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝'

names=("admin" "sequencer" "aggkit")
names_json=$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)
wallets=$(cast wallet new --number ${#names[@]} --json | \
jq --argjson names "$names_json" '
  to_entries
  | map({ key: $names[.key], value: .value })
  | from_entries
')

# admin_addr=$(echo $wallets | jq -r .admin.address)
# admin_pkey=$(echo $wallets | jq -r .admin.private_key)
# sequencer_addr=$(echo $wallets | jq -r .sequencer.address)
# sequencer_pkey=$(echo $wallets | jq -r .sequencer.private_key)
aggkit_addr=$(echo $wallets | jq -r .aggkit.address)
aggkit_pkey=$(echo $wallets | jq -r .aggkit.private_key)

echo "Aggkit address: $aggkit_addr, private key: $aggkit_pkey"


echo ' █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗    ███╗   ██╗███████╗████████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗'
echo '██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║  ██║    ████╗  ██║██╔════╝╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝'
echo '███████║   ██║      ██║   ███████║██║     ███████║    ██╔██╗ ██║█████╗     ██║   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ '
echo '██╔══██║   ██║      ██║   ██╔══██║██║     ██╔══██║    ██║╚██╗██║██╔══╝     ██║   ██║███╗██║██║   ██║██╔══██╗██╔═██╗ '
echo '██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██║    ██║ ╚████║███████╗   ██║   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗'
echo '╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝'

rollupTypeId=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .rollupTypeId)
rollupManagerAddress=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .polygonRollupManagerAddress)
rollupTypeCount=$(cast call $rollupManagerAddress 'rollupTypeCount() returns (uint32)' --rpc-url $l1_rpc_url)
rollupCount=$(cast call $rollupManagerAddress 'rollupCount() returns (uint32)' --rpc-url $l1_rpc_url)

echo "We have $rollupTypeCount rollup types and $rollupCount rollups on the L1 RollupManager at $rollupManagerAddress"

# export function encodeInitializeBytesLegacy(admin, sequencer, gasTokenAddress, sequencerURL, networkName) {
#     return ethers.AbiCoder.defaultAbiCoder().encode(
#         ['address', 'address', 'address', 'string', 'string'],
#         [admin, sequencer, gasTokenAddress, sequencerURL, networkName],
#     );
# }
# initializeBytesAggchain=\
# $(cast abi-encode 'initializeBytesAggchain(address,address,address,string,string)' \
#     $base_admin \
#     $aggkit_addr \
#     "$(cast address-zero)" \
#     "$base_rpc_url" \
#     "base outpost")

# Now the init bytes are just the aggchain manager address
initializeBytesAggchain=$(cast abi-encode 'foo(address)' $admin_addr)

base_chain_id=$(cast chain-id --rpc-url "$base_rpc_url")
echo "Base chain ID: $base_chain_id"

# attachAggchainToAL(rollupTypeID,chainID,initializeBytesAggchain)
calldata=$(cast calldata 'attachAggchainToAL(uint32,uint64,bytes)' $rollupTypeId $base_chain_id "$initializeBytesAggchain")
echo "Using calldata: $calldata"

cast send \
    --rpc-url $l1_rpc_url \
    --private-key $admin_private_key \
    $rollupManagerAddress \
    'attachAggchainToAL(uint32,uint64,bytes)' \
    $rollupTypeId \
    $base_chain_id \
    "$initializeBytesAggchain"

newRollupCount=$(cast call $rollupManagerAddress 'rollupCount() returns (uint32)' --rpc-url $l1_rpc_url)
# Lëts check that the rollup was attached
if [[ $newRollupCount -eq $((rollupCount + 1)) ]]; then
    rollupId=$(cast call $rollupManagerAddress 'chainIDToRollupID(uint64)' $base_chain_id --rpc-url $l1_rpc_url | cast to-dec)
    rollup_addr=$(cast decode-abi 'output() returns (address)' "$(cast call --rpc-url $l1_rpc_url $rollupManagerAddress 'rollupIDToRollupData(uint32)' $rollupId)")
    echo "Rollup successfully attached! New rollup count: $newRollupCount, new Rollup ID: $rollupId, new Rollup Address: $rollup_addr"
else
    echo "Rollup attachment failed! Expected rollup count: $((rollupCount + 1)), got: $newRollupCount"
    exit 1
fi


 ####   . ####:            ##              ####                                                                                
 ####   #######:           ##              ####                                          ##                             ##     
   ##   #:.   ##           ##                ##                                          ##                             ##     
   ##         ##      :###.## .####: ##.###: ##    .####. ##    ##      .####. ##    ###########.###:  .####.  :#####.#######  
   ##        :#      :#######.######:#######:##   .######.:##  ##      .######.##    ################:.######.###############  
   ##        ##      ###  #####:  :#####  #####   ###  ### ##: ##.     ###  #####    ##  ##   ###  ######  #####:  .:#  ##     
   ##      .##:      ##.  .############.  .####   ##.  .## ###:##      ##.  .####    ##  ##   ##.  .####.  .####### .   ##     
   ##     .##:       ##    ############    ####   ##    ## .## #       ##    ####    ##  ##   ##    ####    ##.######:  ##     
   ##    :##:        ##.  .####      ##.  .####   ##.  .##  ####.      ##.  .####    ##  ##   ##.  .####.  .##   .: ##  ##     
   ##:  :##:         ###  ######.  :####  #####:  ###  ###  :###       ###  #####:  ###  ##.  ###  ######  ####:.  :##  ##.    
   #############     :#######.##############:#####.######.   ##        .######. #######  ############:.######.########  #####  
    ############      :###.## .#####:##.###: .#### .####.    ##.        .####.   ###.##  .######.###:  .####. . ####    .####  
                                     ##                     :##                               ##                               
                                     ##                    ###:                               ##                               
                                     ##                    ###                                ##                               

# We will use this block for the bridge to avoid syncing the whole network
base_init_block=$(cast block-number --rpc-url $base_rpc_url)
echo "Base init block: $base_init_block"

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo DEPLOYER_PRIVATE_KEY=\"$base_private_key\" > /opt/agglayer-contracts/.env"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo CUSTOM_PROVIDER=\"$base_rpc_url\" >> /opt/agglayer-contracts/.env"

deploy_parameters_json='{
    "network": {
        "chainID": '"$base_chain_id"',
        "rollupID": '"$rollupId"',
        "networkName": "BaseOutpostChain",
        "tokenName": "BaseETH",
        "tokenSymbol": "BASEETH",
        "tokenDecimals": 18
    },
    "timelock": {
        "timelockDelay": 60,
        "timelockAdminAddress": "'"$base_admin"'"
    },
    "bridge": {
        "bridgeManager": "'"$base_admin"'",
        "sovereignWETHAddress": "'"$(cast address-zero)"'",
        "sovereignWETHAddressIsNotMintable": false,
        "emergencyBridgePauser": "'"$base_admin"'",
        "emergencyBridgeUnpauser": "'"$base_admin"'"
    },
    "globalExitRoot": {
        "globalExitRootUpdater": "'"$aggkit_addr"'",
        "globalExitRootRemover": "'"$aggkit_addr"'"
    },
    "aggOracleCommittee": {
        "useAggOracleCommittee": false
    }
}'

echo "Executing L2 deploy outpost tool"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo '$deploy_parameters_json' > /opt/agglayer-contracts/tools/deployOutpostChain/deploy_parameters.json"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && npx hardhat run ./tools/deployOutpostChain/deployOutpostChain.ts --network custom"

deploy_output=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "cat /opt/agglayer-contracts/tools/deployOutpostChain/deploy_output_*.json")

ger_proxy_addr=$(echo $deploy_output | jq -r .contracts.globalExitRootManagerL2SovereignChainAddress)
bridge_proxy_addr=$(echo $deploy_output | jq -r .contracts.bridgeL2SovereignChainAddress)
gas_token_addr=$(echo $deploy_output | jq -r .network.gasTokenAddress)
wrapped_token_addr=$(echo $deploy_output | jq -r .contracts.WETH)
wrapped_token_addr_live=$(cast call --rpc-url $base_rpc_url $bridge_proxy_addr 'WETHToken()' | cast parse-bytes32-address)
if [[ "$wrapped_token_addr" != "$wrapped_token_addr_live" ]]; then
    echo "Wrapped token address mismatch: $wrapped_token_addr != $wrapped_token_addr_live"
    exit 1
else
    echo "Wrapped token address matches: $wrapped_token_addr == $wrapped_token_addr_live"
fi

echo -e "Base Outpost Chain deployed! \n\tGER Proxy Address: $ger_proxy_addr \n\tBridge Proxy Address: $bridge_proxy_addr \n\tGas Token Address: $gas_token_addr \n\tWrapped Token Address: $wrapped_token_addr"



    ##              ##           ##                   ##                                                                  
    ##              ##           ##         ####      ##                                     #### ####                    
    ##              ##   ##      ##         ####      ##                                     #### ####                    
                         ##                   ##                                               ##   ##                    
  ####   ##.####  #### ####### ####    :####  ##    ####   ######## .####:      ##.#### .####. ##   ##   ##    ####.###:  
  ####   #######  #### ####### ####    ###### ##    ####   ########.######:     #######.######.##   ##   ##    #########: 
    ##   ###  :##   ##   ##      ##    #:  :####      ##       :##:##:  :##     ###.   ###  #####   ##   ##    #####  ### 
    ##   ##    ##   ##   ##      ##     :#######      ##      :##: ########     ##     ##.  .####   ##   ##    ####.  .## 
    ##   ##    ##   ##   ##      ##   .#########      ##     :##:  ########     ##     ##    ####   ##   ##    ####    ## 
    ##   ##    ##   ##   ##      ##   ## .  ####      ##    :##:   ##           ##     ##.  .####   ##   ##    ####.  .## 
    ##   ##    ##   ##   ##.     ##   ##:  #####:     ##   :##:    ###.  :#     ##     ###  #####:  ##:  ##:  ######  ### 
 ##########    ####################################################.#######     ##     .######.########## ##############: 
 ##########    ##########.############  ###.##.#################### .#####:     ##      .####. .####.####  ###.####.###:  
                                                                                                                 ##       
                                                                                                                 ##       
                                                                                                                 ##       
    # function initialize(
    #     address _admin,
    #     address _trustedSequencer,
    #     address _gasTokenAddress,
    #     string memory _trustedSequencerURL,
    #     string memory _networkName,
    #     bool _useDefaultSigners,
    #     SignerInfo[] memory _signersToAdd,
    #     uint256 _newThreshold
    # )
cast send \
    --rpc-url $l1_rpc_url \
    --private-key $admin_private_key \
    $rollup_addr \
    'initialize(address,address,address,string,string,bool,(address,string)[],uint256)' \
    $admin_addr \
    $aggkit_addr \
    $gas_token_addr \
    "$base_rpc_url" \
    "BaseOutpostChain" \
    false \
    "[($aggkit_addr, localhost)]" \
    1


echo " ██████╗ ██╗   ██╗███╗   ██╗     █████╗  ██████╗  ██████╗ ██╗  ██╗██╗████████╗"
echo " ██╔══██╗██║   ██║████╗  ██║    ██╔══██╗██╔════╝ ██╔════╝ ██║ ██╔╝██║╚══██╔══╝"
echo " ██████╔╝██║   ██║██╔██╗ ██║    ███████║██║  ███╗██║  ███╗█████╔╝ ██║   ██║   "
echo " ██╔══██╗██║   ██║██║╚██╗██║    ██╔══██║██║   ██║██║   ██║██╔═██╗ ██║   ██║   "
echo " ██║  ██║╚██████╔╝██║ ╚████║    ██║  ██║╚██████╔╝╚██████╔╝██║  ██╗██║   ██║   "
echo " ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝   "

# Lets use same docker image than the one deployed for cdk
aggkit_image=$(docker ps | grep aggkit-001-- | awk '{print $2}')

# We need a folder to store files for aggkit, lets use tmp for now:
datadir=/tmp/aggkit-base
rm -fr $datadir
mkdir -p $datadir/tmp
chmod 777 $datadir/tmp

# params required for aggkit
l1_bridge_addr=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .polygonZkEVMBridgeAddress)
l1_ger_addr=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .polygonZkEVMGlobalExitRootAddress)
polTokenAddress=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .polTokenAddress)
block_number=$(curl -s "${contracts_url}/opt/output/combined.json" | jq -r .deploymentRollupManagerBlockNumber)

# prepare keystore for aggsender and aggoracle
cast wallet import --keystore-dir $datadir --private-key "$aggkit_pkey" --unsafe-password "secret" "aggkit.keystore"

# aggkit needs some funds
cast send --legacy --rpc-url $base_rpc_url --private-key $base_private_key --value 0.1ether $aggkit_addr 

# checking the current set address:
# cast call $ger_proxy_addr 'globalExitRootUpdater()' --rpc-url $base_rpc_url

# > ${datadir}/aggkit-config.toml cat <<EOF
# PathRWData = "/etc/aggkit/tmp/"
# L1URL="$l1_rpc_url_kurtosis"
# L2URL="$base_rpc_url"
# # GRPC port for Aggkit v0.3
# # readport for Aggkit v0.2
# AggLayerURL="http://agglayer:4443"

# # set var as number, not string
# NetworkID = $rollupId

# L2Coinbase =  "$base_admin"
# SequencerPrivateKeyPath = ""
# SequencerPrivateKeyPassword  = ""

# AggregatorPrivateKeyPath = ""
# AggregatorPrivateKeyPassword  = ""
# SenderProofToL1Addr = ""
# polygonBridgeAddr = "$l1_bridge_addr"

# RPCURL = "$base_rpc_url"
# WitnessURL = ""

# rollupCreationBlockNumber = "$block_number"
# rollupManagerCreationBlockNumber = "$block_number"
# genesisBlockNumber = "$block_number"

# [L1Config]
# chainId = "$l1_chainid"
# polygonZkEVMGlobalExitRootAddress = "$l1_ger_addr"
# polygonRollupManagerAddress = "$rollupManagerAddress"
# polTokenAddress = "$polTokenAddress"
# polygonZkEVMAddress = "$rollup_addr"

# [L2Config]
# GlobalExitRootAddr = "$ger_proxy_addr"

# [Log]
# Environment = "development"
# Level = "info"
# Outputs = ["stderr"]

# [RPC]
# Port = 5576

# [AggSender]
# AggsenderPrivateKey = {Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}
# Mode="PessimisticProof"
# RequireNoFEPBlockGap = true

# [AggOracle]
# WaitPeriodNextGER="5000ms"

# [AggOracle.EVMSender]
# GlobalExitRootL2 = "$ger_proxy_addr"

# [AggOracle.EVMSender.EthTxManager]
# PrivateKeys = [{Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}]

# [AggOracle.EVMSender.EthTxManager.Etherman]
# # For some weird reason that needs to be set to L2 chainid, not L1
# L1ChainID = "$base_chain_id"

# [BridgeL2Sync]
# BridgeAddr = "$bridge_proxy_addr"
# BlockFinality = "FinalizedBlock"

# [L1InfoTreeSync]
# InitialBlock = "$block_number"

# [Metrics]
# Enabled = false
# EOF

> ${datadir}/aggkit-config-new.toml cat <<EOF
PathRWData = "/etc/aggkit/tmp/"
L1URL = "$l1_rpc_url_kurtosis"
L2URL = "$base_rpc_url"

AggLayerURL = "http://agglayer:4443"
AggchainProofURL= "aggkit-prover-001:4446"

NetworkID = $rollupId
SequencerPrivateKeyPath = "/etc/aggkit/aggkit.keystore"
SequencerPrivateKeyPassword  = "secret"

polygonBridgeAddr = "$l1_bridge_addr"
RPCURL = "$base_rpc_url"

rollupCreationBlockNumber = "$block_number"
rollupManagerCreationBlockNumber = "$block_number"
genesisBlockNumber = "$block_number"

[L1Config]
URL = "$l1_rpc_url_kurtosis"
chainId = "$l1_chainid"
polygonZkEVMGlobalExitRootAddress = "$l1_ger_addr"
polygonRollupManagerAddress = "$rollupManagerAddress"
polTokenAddress = "$polTokenAddress"
polygonZkEVMAddress = "$rollup_addr"

[L2Config]
GlobalExitRootAddr = "$ger_proxy_addr"

[Log]
Environment = "development"
Level = "info"
Outputs = ["stderr"]

[RPC]
Port = "5576"

[REST]
Port = "5577"

[AggSender]
AggSenderPrivateKey = {Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}
Mode = "PessimisticProof"
CheckStatusCertificateInterval = "1s"

[AggSender.AggkitProverClient]
UseTLS = false
BlockFinality = "LatestBlock"

[AggSender.AgglayerClient]
[[AggSender.AgglayerClient.APIRateLimits]]
MethodName = "SendCertificate"
[AggSender.AgglayerClient.APIRateLimits.RateLimit]
NumRequests = 0
[AggSender.AgglayerClient.GRPC]
URL = "http://agglayer:4443"
MinConnectTimeout = "5s"
RequestTimeout = "300s"
UseTLS = false
[AggSender.AgglayerClient.GRPC.Retry]
InitialBackoff = "1s"
MaxBackoff = "10s"
BackoffMultiplier = 2.0
MaxAttempts = 20


[AggOracle]
WaitPeriodNextGER = "10s"
EnableAggOracleCommittee = false
[AggOracle.EVMSender]
GlobalExitRootL2 = "$ger_proxy_addr"
WaitPeriodMonitorTx = "10s"
[AggOracle.EVMSender.EthTxManager]
PrivateKeys = [{Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}]
[AggOracle.EVMSender.EthTxManager.Etherman]
L1ChainID = "$base_chain_id"

[BridgeL2Sync]
BridgeAddr = "$bridge_proxy_addr"
BlockFinality = "FinalizedBlock"
InitialBlockNum = "$base_init_block"

[L1InfoTreeSync]
InitialBlock = "$block_number"

[L2GERSync]
BlockFinality = "LatestBlock"

[ClaimSponsor]
Enabled = "false"

[AggchainProofGen]
SovereignRollupAddr = "$rollup_addr"
GlobalExitRootL2 = "$ger_proxy_addr"
[AggchainProofGen.AggkitProverClient]
[Profiling]
ProfilingHost = "0.0.0.0"
ProfilingPort = 6060
ProfilingEnabled = true

[Validator]
EnableRPC = true
Signer = { Method = "local", Path = "/etc/aggkit/aggkit.keystore", Password = "secret" }
Mode = "PessimisticProof"

[Validator.ServerConfig]
Host = "0.0.0.0"
Port = 5578
MaxDecodingMessageSize = 1073741824  # 1GB

[Validator.LerQuerierConfig]
RollupManagerAddr = "$rollupManagerAddress"
RollupCreationBlockL1 = "$block_number"

[Validator.AgglayerClient]
Cached = true

[Validator.AgglayerClient.ConfigurationCache]
TTL = "15m"
Capacity = 100

[Validator.AgglayerClient.GRPC]
URL = "http://agglayer:4443"
UseTLS = false
EOF

# run aggkit
# first, stop and remove any existing container with the same name
if docker ps -q --filter "name=aggkit-base" | grep -q .; then
    docker stop aggkit-base
fi

docker run -it \
    --rm \
    --detach \
    --network $docker_network_name \
    --name aggkit-base \
    -v $datadir:/etc/aggkit \
    "$aggkit_image" \
    run \
    --cfg=/etc/aggkit/aggkit-config-new.toml \
    --components=aggsender,aggoracle


echo " ██████╗ ██╗   ██╗███╗   ██╗    ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗"
echo " ██╔══██╗██║   ██║████╗  ██║    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝"
echo " ██████╔╝██║   ██║██╔██╗ ██║    ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  "
echo " ██╔══██╗██║   ██║██║╚██╗██║    ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  "
echo " ██║  ██║╚██████╔╝██║ ╚████║    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗"
echo " ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝"


# Fund the L2 claimtx manager
claimtxmanager_address=$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r .args.zkevm_l2_claimtxmanager_address)
claimtxmanager_balance=$(cast balance --rpc-url $base_rpc_url $claimtxmanager_address)
claimtxmanager_min_balance=$(cast to-wei 0.1)
if [[ $(echo "$claimtxmanager_balance < $claimtxmanager_min_balance" | bc -l) -eq 1 ]]; then
    echo "Claimtxmanager balance is less than $claimtxmanager_min_balance: $claimtxmanager_balance, sending $claimtxmanager_min_balance to $claimtxmanager_address"
    cast send --legacy --rpc-url $base_rpc_url --value $claimtxmanager_min_balance --private-key $base_private_key $claimtxmanager_address
else
    echo "Claimtxmanager balance is sufficient: $claimtxmanager_balance"
fi

# add our network to the bridge config
kurtosis service exec $kurtosis_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2URLs = \[.*)(\])#\1, \"'${base_rpc_url}'\"\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(RequireSovereignChainSmcs = \[.*)(\])#\1, true\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2PolygonZkEVMGlobalExitRootAddresses = \[.*)(\])#\1, \"'${ger_proxy_addr}'\"\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2PolygonBridgeAddresses = \[.*)(\])#\1, \"'${bridge_proxy_addr}'\"\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2GenBlockNumbers = \[.*)(\])#\1, '${base_init_block}'\2#" /etc/zkevm/bridge-config.toml'

# get kurtosis bridge docker name and restart it
bridge_docker_name=zkevm-bridge-service-001--$(kurtosis service inspect $kurtosis_enclave_name zkevm-bridge-service-001 --full-uuid | grep UUID | sed  's/.*: //')
docker restart $bridge_docker_name



echo '██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗███████╗              ████████╗██╗  ██╗███████╗'
echo '██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝              ╚══██╔══╝╚██╗██╔╝██╔════╝'
echo '██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗    █████╗       ██║    ╚███╔╝ ███████╗'
echo '██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║    ╚════╝       ██║    ██╔██╗ ╚════██║'
echo '██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗███████║                 ██║   ██╔╝ ██╗███████║'
echo '╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚══════╝'

source ../../core/helpers/scripts/erc20.bash
source ../../core/helpers/scripts/bridging.bash
erc20_init "$wrapped_token_addr" "$base_rpc_url"

bridge_url=$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)

# Create and fund new wallet for bridge testing
tmp_test_wallet_json=$(cast wallet new --json)
test_addr=$(echo "$tmp_test_wallet_json" | jq -r '.[0].address')
test_pkey=$(echo "$tmp_test_wallet_json" | jq -r '.[0].private_key')
echo "Test wallet address: $test_addr, private key: $test_pkey"
cast send --rpc-url $l1_rpc_url --value 10ether --private-key $l1_preallocated_private_key $test_addr

# amount to deposit
deposit_amount="0.01ether"
wei_deposit_amount=$(echo "$deposit_amount" | sed 's/ether//g' | cast to-wei)
 
l1_balance_before=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_native_balance_before=$(cast balance --rpc-url $base_rpc_url $test_addr)
l2_gas_token_balance_before=$(erc20_balance "$test_addr")
echo "L1 balance before: $l1_balance_before, L2 native balance before: $l2_native_balance_before, L2 gas token balance before: $l2_gas_token_balance_before, Test wallet address: $test_addr"


# Deposit on L1 - Bridge to L2
deposit_output=$(polycli ulxly bridge asset \
    --value $wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $l1_bridge_addr \
    --destination-address $test_addr \
    --destination-network $rollupId \
    --rpc-url $l1_rpc_url \
    --private-key $test_pkey \
    --chain-id $l1_chainid |& tee /dev/stderr)

deposit_count=$(polycli_bridge_asset_get_info "$deposit_output" "$l1_rpc_url" "$l1_bridge_addr" | jq -r '.depositCount')
echo "Waiting and then claiming on L2 deposit count: $deposit_count"
sleep 60

# claim everything on L2, it should be already claimed by the bridge service autoclaimer
polycli ulxly claim-everything \
    --bridge-address $bridge_proxy_addr \
    --destination-address $test_addr \
    --rpc-url $base_rpc_url \
    --private-key $test_pkey \
    --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url

l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_native_balance_after=$(cast balance --rpc-url $base_rpc_url $test_addr)
l2_gas_token_balance_after=$(erc20_balance "$test_addr")
echo "L1 balance before: $l1_balance_before, L1 balance after : $l1_balance_after, L1 Balance diff  : $(echo "$l1_balance_after - $l1_balance_before" | bc)"
echo "L2 native balance before: $l2_native_balance_before, L2 native balance after : $l2_native_balance_after, L2 native Balance diff  : $(echo "$l2_native_balance_after - $l2_native_balance_before" | bc)"
echo "L2 gas token balance before: $l2_gas_token_balance_before, L2 gas token balance after : $l2_gas_token_balance_after, L2 gas token Balance diff  : $(echo "$l2_gas_token_balance_after - $l2_gas_token_balance_before" | bc)"

expected_l2_gas_token_balance=$wei_deposit_amount
if [[ $(echo "$l2_gas_token_balance_after < $expected_l2_gas_token_balance" | bc -l) -eq 1 ]]; then
    echo "ERROR: L2 gas token balance is not $expected_l2_gas_token_balance: $l2_gas_token_balance_afte"
else
    echo "L2 gas token balance is expected: $l2_gas_token_balance_after"
fi




# Bridge back to L1
half_wei_deposit_amount=$((wei_deposit_amount / 2))
quarter_wei_deposit_amount=$((wei_deposit_amount / 4))

l1_balance_before=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_native_balance_before=$(cast balance --rpc-url $base_rpc_url $test_addr)
l2_gas_token_balance_before=$(erc20_balance "$test_addr")
echo "L1 balance before: $l1_balance_before, L2 native balance before: $l2_native_balance_before, L2 gas token balance before: $l2_gas_token_balance_before, Test wallet address: $test_addr"

# fund to pay gas cost on Base
cast send --rpc-url $base_rpc_url --value 0.001ether --private-key $base_private_key $test_addr

# Deposit on L2 -- bridge to L1, exit, that should trigger a certificate when finalized
polycli ulxly bridge weth \
    --value $half_wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $bridge_proxy_addr \
    --destination-address $test_addr \
    --destination-network 0 \
    --token-address $wrapped_token_addr \
    --rpc-url $base_rpc_url \
    --private-key $test_pkey \
    --chain-id $base_chain_id

echo "Waiting and then claiming"
sleep 60

# Claim on L1
polycli ulxly claim-everything \
    --bridge-address $l1_bridge_addr \
    --destination-address $test_addr \
    --rpc-url $l1_rpc_url \
    --private-key $test_pkey \
    --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url
sleep 10
l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)

# lets loop until l1 balance is updated
while [ $((l1_balance_after == l1_balance_before)) -eq 1 ]; do
    echo "Current L1 balance for $test_addr is trhe same than before: $l1_balance_after == $l1_balance_before, waiting/claiming..."
    sleep 10
    polycli ulxly claim-everything \
        --bridge-address $l1_bridge_addr \
        --destination-address $test_addr \
        --rpc-url $l1_rpc_url \
        --private-key $test_pkey \
        --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url
    l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
done

l2_native_balance_after=$(cast balance --rpc-url $base_rpc_url $test_addr)
l2_gas_token_balance_after=$(erc20_balance "$test_addr")
echo "L1 balance before: $l1_balance_before, L1 balance after : $l1_balance_after, L1 Balance diff  : $(echo "$l1_balance_after - $l1_balance_before" | bc)"
echo "L2 native balance before: $l2_native_balance_before, L2 native balance after : $l2_native_balance_after, L2 native Balance diff  : $(echo "$l2_native_balance_after - $l2_native_balance_before" | bc)"
echo "L2 gas token balance before: $l2_gas_token_balance_before, L2 gas token balance after : $l2_gas_token_balance_after, L2 gas token Balance diff  : $(echo "$l2_gas_token_balance_after - $l2_gas_token_balance_before" | bc)"

expected_l1_balance=$((l1_balance_before + half_wei_deposit_amount))
if [[ $(echo "$l1_balance_after < $expected_l1_balance" | bc -l) -eq 1 ]]; then
    echo "ERROR: L1 balance is not $expected_l1_balance: $l1_balance_after"
else
    echo "L1 balance is expected: $l1_balance_after"
fi
