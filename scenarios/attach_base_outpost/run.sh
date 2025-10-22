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


echo '██╗     ██╗                   █████╗  ██████╗ ██╗                   ██████╗ ███╗   ███╗'
echo '██║    ███║                  ██╔══██╗██╔════╝ ██║                   ██╔══██╗████╗ ████║'
echo '██║    ╚██║    █████╗        ███████║██║  ███╗██║         █████╗    ██████╔╝██╔████╔██║'
echo '██║     ██║    ╚════╝        ██╔══██║██║   ██║██║         ╚════╝    ██╔══██╗██║╚██╔╝██║'
echo '███████╗██║                  ██║  ██║╚██████╔╝███████╗              ██║  ██║██║ ╚═╝ ██║'
echo '╚══════╝╚═╝                  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝              ╚═╝  ╚═╝╚═╝     ╚═╝'

kurtosis run --enclave "$kurtosis_enclave_name" "github.com/0xPolygon/kurtosis-cdk@$kurtosis_tag"

echo "🔗 Getting admin_private_key and keystore_password values..."
contracts_url="$(kurtosis port print $kurtosis_enclave_name contracts-001 http)"

admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_admin_private_key')"
keystore_password="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_keystore_password')"

l1_preallocated_mnemonic="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.l1_preallocated_mnemonic')"
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")
#l1_preallocated_address=$(cast wallet address --mnemonic "$l1_preallocated_mnemonic")

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
initializeBytesAggchain=\
$(cast abi-encode 'initializeBytesAggchain(address,address,address,string,string)' \
    $base_admin \
    $aggkit_addr \
    "$(cast address-zero)" \
    "$base_rpc_url" \
    "base outpost")

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


echo '██╗     ██████╗      ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  █████╗  ██████╗████████╗███████╗'
echo '██║     ╚════██╗    ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝'
echo '██║      █████╔╝    ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝███████║██║        ██║   ███████╗'
echo '██║     ██╔═══╝     ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██╔══██║██║        ██║   ╚════██║'
echo '███████╗███████╗    ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║██║  ██║╚██████╗   ██║   ███████║'
echo '╚══════╝╚══════╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚══════╝'

# Let's check it has at least 1 ether
one_ether=$(cast to-wei 1)
base_admin_balance=$(cast balance --rpc-url $base_rpc_url $base_admin)
base_admin_nonce=$(cast nonce --rpc-url $base_rpc_url $base_admin)

if [[ $(echo "$base_admin_balance < $one_ether" | bc -l) -eq 1 ]]; then
    echo "Base admin balance is less than 1 ether: $base_admin_balance"
    exit 1
else
    echo "Base admin balance is sufficient: $base_admin_balance, Nonce: $base_admin_nonce"
fi

# Get addresses that will be deployed, nonce is used to fund the bridge, so we start from +1
bridge_impl_addr=$(cast compute-address --nonce $((base_admin_nonce + 0)) $base_admin | sed 's/.*: //')
ger_impl_addr=$(cast compute-address --nonce $((base_admin_nonce + 1)) $base_admin | sed 's/.*: //')
ger_proxy_addr=$(cast compute-address --nonce $((base_admin_nonce + 2)) $base_admin | sed 's/.*: //')
bridge_proxy_addr=$(cast compute-address --nonce $((base_admin_nonce + 3)) $base_admin | sed 's/.*: //')

# Fund the bridge
# EVM error: CreateCollision
# cast send --legacy --rpc-url $base_rpc_url --value $(cast to-wei 0.5) --private-key $base_private_key $bridge_proxy_addr

# Deploy the contracts
echo "Deploying BridgeL2SovereignChain at $bridge_impl_addr"
cmd="cd agglayer-contracts && forge create --json --via-ir --optimize --optimizer-runs 200 --legacy --broadcast --rpc-url $base_rpc_url --private-key $base_private_key BridgeL2SovereignChain"
bridge_impl_addr_deployed=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "$cmd" | jq -r .deployedTo)
if [[ "$bridge_impl_addr_deployed" != "$bridge_impl_addr" ]]; then
    echo "BridgeL2SovereignChain deployment failed! Expected address: $bridge_impl_addr, got: $bridge_impl_addr_deployed"
    # exit 1
else
    echo "BridgeL2SovereignChain deployment successful! Deployed address: $bridge_impl_addr_deployed"
fi

echo "Deploying GlobalExitRootManagerL2SovereignChain at $ger_impl_addr"
cmd="cd agglayer-contracts && forge create --json --via-ir --optimize --optimizer-runs 200 --legacy --broadcast --rpc-url $base_rpc_url --private-key $base_private_key GlobalExitRootManagerL2SovereignChain --constructor-args \"$bridge_proxy_addr\""
ger_impl_addr_deployed=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "$cmd" | jq -r .deployedTo)
if [[ "$ger_impl_addr_deployed" != "$ger_impl_addr" ]]; then
    echo "GlobalExitRootManagerL2SovereignChain deployment failed! Expected address: $ger_impl_addr, got: $ger_impl_addr_deployed"
    # exit 1
else
    echo "GlobalExitRootManagerL2SovereignChain deployment successful! Deployed address: $ger_impl_addr_deployed"
fi

echo "Deploying TransparentUpgradeableProxy for GlobalExitRootManagerL2SovereignChain at $ger_proxy_addr"
calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $aggkit_addr $aggkit_addr)
cmd="cd agglayer-contracts && forge create --json --via-ir --optimize --optimizer-runs 200 --legacy --broadcast --rpc-url $base_rpc_url --private-key $base_private_key TransparentUpgradeableProxy --constructor-args \"$ger_impl_addr\" $base_admin \"$calldata\""
ger_proxy_addr_deployed=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "$cmd" | jq -r .deployedTo)
if [[ "$ger_proxy_addr_deployed" != "$ger_proxy_addr" ]]; then
    echo "TransparentUpgradeableProxy for GlobalExitRootManagerL2SovereignChain deployment failed! Expected address: $ger_proxy_addr, got: $ger_proxy_addr_deployed"
    # exit 1
else
    echo "TransparentUpgradeableProxy for GlobalExitRootManagerL2SovereignChain deployment successful! Deployed address: $ger_proxy_addr_deployed"
fi

echo "Deploying TransparentUpgradeableProxy for BridgeL2SovereignChain at $bridge_proxy_addr"
_networkID=$rollupId
_gasTokenAddress=$(cast address-zero)
_gasTokenNetwork=0
_globalExitRootManager=$ger_proxy_addr
_polygonRollupManager=$rollupManagerAddress
_gasTokenMetadata=0x
_bridgeManager=$base_admin
_sovereignWETHAddress=$(cast address-zero)
_sovereignWETHAddressIsNotMintable=false
_emergencyBridgePauser=$base_admin
_emergencyBridgeUnpauser=$base_admin
_proxiedTokensManager=$base_admin
calldata=$(cast calldata 'function initialize(uint32,address,uint32,address,address,bytes,address,address,bool,address,address,address)' \
    $_networkID "$_gasTokenAddress" $_gasTokenNetwork "$_globalExitRootManager" "$_polygonRollupManager" $_gasTokenMetadata $_bridgeManager \
    "$_sovereignWETHAddress" $_sovereignWETHAddressIsNotMintable "$_emergencyBridgePauser" "$_emergencyBridgeUnpauser" "$_proxiedTokensManager")

cmd="cd agglayer-contracts && forge create --json --via-ir --optimize --optimizer-runs 200 --legacy --broadcast --rpc-url $base_rpc_url --private-key $base_private_key TransparentUpgradeableProxy --constructor-args $bridge_impl_addr $base_admin $calldata"
bridge_proxy_addr_deployed=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "$cmd" | jq -r .deployedTo)
if [[ "$bridge_proxy_addr_deployed" != "$bridge_proxy_addr" ]]; then
    echo "TransparentUpgradeableProxy for BridgeL2SovereignChain deployment failed! Expected address: $bridge_proxy_addr, got: $bridge_proxy_addr_deployed"
    # exit 1
else
    echo "TransparentUpgradeableProxy for BridgeL2SovereignChain deplotment successful! Deployed address: $bridge_proxy_addr_deployed"
fi


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

> ${datadir}/aggkit-config.toml cat <<EOF
PathRWData = "/etc/aggkit/tmp/"
L1URL="$l1_rpc_url_kurtosis"
L2URL="$base_rpc_url"
# GRPC port for Aggkit v0.3
# readport for Aggkit v0.2
AggLayerURL="agglayer:4443"

ForkId = 12
ContractVersions = "banana"
IsValidiumMode = false
# set var as number, not string
NetworkID = $rollupId

L2Coinbase =  "$base_admin"
SequencerPrivateKeyPath = ""
SequencerPrivateKeyPassword  = ""

AggregatorPrivateKeyPath = ""
AggregatorPrivateKeyPassword  = ""
SenderProofToL1Addr = ""
polygonBridgeAddr = "$l1_bridge_addr"

RPCURL = "$base_rpc_url"
WitnessURL = ""

rollupCreationBlockNumber = "$block_number"
rollupManagerCreationBlockNumber = "$block_number"
genesisBlockNumber = "$block_number"

[L1Config]
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
Port = 5576

[AggSender]
AggsenderPrivateKey = {Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}
Mode="PessimisticProof"
RequireNoFEPBlockGap = true

[AggOracle]
WaitPeriodNextGER="5000ms"

[AggOracle.EVMSender]
GlobalExitRootL2 = "$ger_proxy_addr"

[AggOracle.EVMSender.EthTxManager]
PrivateKeys = [{Path = "/etc/aggkit/aggkit.keystore", Password = "secret"}]

[AggOracle.EVMSender.EthTxManager.Etherman]
# For some weird reason that needs to be set to L2 chainid, not L1
L1ChainID = "$pos_chain_id"

[BridgeL2Sync]
BridgeAddr = "$bridge_proxy_addr"
BlockFinality = "FinalizedBlock"

[L1InfoTreeSync]
InitialBlock = "$block_number"

[Metrics]
Enabled = false
EOF

# run aggkit
docker run -it \
    --rm \
    --detach \
    --network $docker_network_name \
    --name aggkit-base \
    -v $datadir:/etc/aggkit \
    "$aggkit_image" \
    run \
    --cfg=/etc/aggkit/aggkit-config.toml \
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

# get kurtosis bridge docker name and restart it
bridge_docker_name=zkevm-bridge-service-001--$(kurtosis service inspect $kurtosis_enclave_name zkevm-bridge-service-001 --full-uuid | grep UUID | sed  's/.*: //')
docker restart $bridge_docker_name



echo '██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗███████╗              ████████╗██╗  ██╗███████╗'
echo '██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝              ╚══██╔══╝╚██╗██╔╝██╔════╝'
echo '██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗    █████╗       ██║    ╚███╔╝ ███████╗'
echo '██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║    ╚════╝       ██║    ██╔██╗ ╚════██║'
echo '██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗███████║                 ██║   ██╔╝ ██╗███████║'
echo '╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚══════╝'
# Create some activity on both l1 and l2 before attaching the outpost

bridge_url=$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)

tmp_test_wallet_json=$(cast wallet new --json)
test_addr=$(echo "$tmp_test_wallet_json" | jq -r '.[0].address')
test_pkey=$(echo "$tmp_test_wallet_json" | jq -r '.[0].private_key')

# Balance on L1
cast send --rpc-url $l1_rpc_url --value 10ether --private-key $l1_preallocated_private_key $test_addr

# amount to deposit
deposit_amount="0.01ether"
wei_deposit_amount=$(echo "$deposit_amount" | sed 's/ether//g' | cast to-wei)
 
l1_balance_before=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_balance_before=$(cast balance --rpc-url $base_rpc_url $test_addr)
echo "L1 balance before: $l1_balance_before, L2 balance before: $l2_balance_before"





# WE HAVE NO BALANCE L2, EVERYTHING IS KINDA BLOCKED HERE



# Deposit on L1 -- bridge to L2
polycli ulxly bridge asset \
    --value $wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $l1_bridge_addr \
    --destination-address $test_addr \
    --destination-network $rollupId \
    --rpc-url $l1_rpc_url \
    --private-key $test_pkey \
    --chain-id $l1_chainid

sleep 10
expected_l2_balance=$((l2_balance_before + wei_deposit_amount))
l2_balance_after=$(cast balance --rpc-url $base_rpc_url $test_addr)

while [ $((l2_balance_after == expected_l2_balance)) -eq 0 ]; do
    echo "Current L2 balance for $test_addr is $l2_balance_after, waiting..."
    sleep 10
    l2_balance_after=$(cast balance --rpc-url $base_rpc_url $test_addr)
done

l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
echo "L1 balance before: $l1_balance_before"
echo "L1 balance after : $l1_balance_after"
echo "L1 Balance diff  : $(echo "$l1_balance_after - $l1_balance_before" | bc)"
echo "L2 balance before: $l2_balance_before"
echo "L2 balance after : $l2_balance_after"
echo "L2 Balance diff  : $(echo "$l2_balance_after - $l2_balance_before" | bc)"


#
# The other way
#

l1_balance_before=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_balance_before=$(cast balance --rpc-url $pos_rpc_url $test_addr)

deposit_amount="1ether"
wei_deposit_amount=$(echo "$deposit_amount" | sed 's/ether//g' | cast to-wei)

# Deposit on L2 -- bridge to L1, exit, that should trigger a certificate when finalized
polycli ulxly bridge asset \
    --value $wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $bridge_proxy_addr \
    --destination-address $test_addr \
    --destination-network 0 \
    --rpc-url $pos_rpc_url \
    --private-key $test_pkey \
    --chain-id $pos_chain_id

sleep 10
l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)

# lets loop while l1 balance is equal to l1_balance_before
while [ $((l1_balance_after == l1_balance_before)) -eq 0 ]; do
    echo "Current L1 balance for $test_addr is $l1_balance_after, waiting/claiming..."
    polycli ulxly claim-everything \
        --bridge-address $l1_bridge_addr \
        --destination-address $test_addr \
        --rpc-url $l1_rpc_url \
        --private-key $test_pkey \
        --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url
    sleep 10
    l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
done

l2_balance_after=$(cast balance --rpc-url $pos_rpc_url $test_addr)
echo "L1 balance before: $l1_balance_before"
echo "L1 balance after : $l1_balance_after"
echo "L1 Balance diff  : $(echo "$l1_balance_after - $l1_balance_before" | bc)"
echo "L2 balance before: $l2_balance_before"
echo "L2 balance after : $l2_balance_after"
echo "L2 Balance diff  : $(echo "$l2_balance_after - $l2_balance_before" | bc)"
