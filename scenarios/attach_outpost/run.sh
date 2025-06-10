#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

# l1 variables
l1_preallocated_mnemonic="$L1_PREALLOCATED_MNEMONIC"
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")
l1_preallocated_address=$(cast wallet address --mnemonic "$l1_preallocated_mnemonic")

# l2 variables
op_deployer_image="$OP_DEPLOYER_IMAGE"
op_geth_image="$OP_GETH_IMAGE"
op_node_image="$OP_NODE_IMAGE"
op_batcher_image="$OP_BATCHER_IMAGE"
op_proposer_image="$OP_PROPOSER_IMAGE"
l2_chain_id=223344
aggkit_image="$AGGKIT_IMAGE"

# infra variables
agglayer_contracts_tag=$AGGLAYER_CONTRACTS_TAG
kurtosis_agl_enclave_name="$AGL_ENCLAVE_NAME"
kurtosis_agl_tag="$AGL_KURTOSIS_PACKAGE_TAG"
docker_network_name="kt-$kurtosis_agl_enclave_name"
datadir=./data

# some init
sudo rm -fr "$datadir" agglayer-contracts


echo '██╗     ██╗                   █████╗  ██████╗ ██╗                   ██████╗ ███╗   ███╗'
echo '██║    ███║                  ██╔══██╗██╔════╝ ██║                   ██╔══██╗████╗ ████║'
echo '██║    ╚██║    █████╗        ███████║██║  ███╗██║         █████╗    ██████╔╝██╔████╔██║'
echo '██║     ██║    ╚════╝        ██╔══██║██║   ██║██║         ╚════╝    ██╔══██╗██║╚██╔╝██║'
echo '███████╗██║                  ██║  ██║╚██████╔╝███████╗              ██║  ██║██║ ╚═╝ ██║'
echo '╚══════╝╚═╝                  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝              ╚═╝  ╚═╝╚═╝     ╚═╝'

# Spin up base network, we mainly need the agglayer to attach the outpost to
kurtosis run \
    --enclave "$kurtosis_agl_enclave_name" \
    "github.com/0xPolygon/kurtosis-cdk@$kurtosis_agl_tag" \
    '{"l1_preallocated_mnemonic": "'"$l1_preallocated_mnemonic"'"}'

# "zkevm_l2_admin_address": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
# "zkevm_l2_admin_private_key": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
# hardocoded for now, its used to attack network to rollupmanager
zkevm_l2_admin_private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"

# zkevm_l2_claimtxmanager_address": "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8",
# zkevm_l2_claimtxmanager_private_key": "0x8d5c9ecd4ba2a195db3777c8412f8e3370ae9adffac222a54a84e116c7f8b934",
# hardocded right now, we need to fund it on our l2
zkevm_l2_claimtxmanager_address="0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"
zkevm_l2_claimtxmanager_private_key="0x8d5c9ecd4ba2a195db3777c8412f8e3370ae9adffac222a54a84e116c7f8b934"

# Gather required L1 params from deployed kurtosis enclave
l1_rpc_url=http://$(kurtosis port print $kurtosis_agl_enclave_name el-1-geth-lighthouse rpc)
l1_rpc_url_kurtosis="http://el-1-geth-lighthouse:8545"
l1_ws_url=ws://$(kurtosis port print $kurtosis_agl_enclave_name el-1-geth-lighthouse ws)
l1_beacon_url=$(kurtosis port print $kurtosis_agl_enclave_name cl-1-lighthouse-geth http)
l1_beacon_url_kurtosis="http://cl-1-lighthouse-geth:4000"
l1_chainid=$(cast chain-id --rpc-url "$l1_rpc_url")


echo '██╗     ██████╗     ██╗    ██╗ █████╗ ██╗     ██╗     ███████╗████████╗███████╗'
echo '██║     ╚════██╗    ██║    ██║██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝██╔════╝'
echo '██║      █████╔╝    ██║ █╗ ██║███████║██║     ██║     █████╗     ██║   ███████╗'
echo '██║     ██╔═══╝     ██║███╗██║██╔══██║██║     ██║     ██╔══╝     ██║   ╚════██║'
echo '███████╗███████╗    ╚███╔███╔╝██║  ██║███████╗███████╗███████╗   ██║   ███████║'
echo '╚══════╝╚══════╝     ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝'

mkdir -p "$datadir/deploy" "$datadir/geth" "$datadir/safedb" "$datadir/aggkit/tmp"

names=("l2admin" "batcher" "proposer" "sequencer")
names_json=$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)
cast wallet new --number ${#names[@]} --json | \
jq --argjson names "$names_json" '
  to_entries
  | map({ key: $names[.key], value: .value })
  | from_entries
' > $datadir/l2_wallets.json

l2_admin_addr=$(jq -r .l2admin.address $datadir/l2_wallets.json)
l2_admin_pkey=$(jq -r .l2admin.private_key $datadir/l2_wallets.json)
batcher_addr=$(jq -r .batcher.address $datadir/l2_wallets.json)
batcher_pkey=$(jq -r .batcher.private_key $datadir/l2_wallets.json)
proposer_addr=$(jq -r .proposer.address $datadir/l2_wallets.json)
proposer_pkey=$(jq -r .proposer.private_key $datadir/l2_wallets.json)
sequencer_addr=$(jq -r .sequencer.address $datadir/l2_wallets.json)
sequencer_pkey=$(jq -r .sequencer.private_key $datadir/l2_wallets.json)


echo '██╗███████╗ ██████╗ ██╗      █████╗ ████████╗███████╗██████╗     ██╗     ██████╗ '
echo '██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗    ██║     ╚════██╗'
echo '██║███████╗██║   ██║██║     ███████║   ██║   █████╗  ██║  ██║    ██║      █████╔╝'
echo '██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██╔══╝  ██║  ██║    ██║     ██╔═══╝ '
echo '██║███████║╚██████╔╝███████╗██║  ██║   ██║   ███████╗██████╔╝    ███████╗███████╗'
echo '╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═════╝     ╚══════╝╚══════╝'

# op deployer to generate intent.toml
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    init \
    --l1-chain-id $l1_chainid \
    --l2-chain-ids $l2_chain_id \
    --workdir /workdir \
    --intent-config-type "custom"

# replace values in intent.toml
sed -i 's/configType = ".*"/configType = "standard-overrides"/' $datadir/deploy/intent.toml
sed -i 's/l1ChainID = .*/l1ChainID = '$l1_chainid'/' $datadir/deploy/intent.toml

sed -i 's/SuperchainProxyAdminOwner = ".*"/SuperchainProxyAdminOwner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/SuperchainGuardian = ".*"/SuperchainGuardian = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/ProtocolVersionsOwner = ".*"/ProtocolVersionsOwner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml

sed -i 's|l1ContractsLocator = ".*"|l1ContractsLocator = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz"|' "$datadir/deploy/intent.toml"
sed -i 's|l2ContractsLocator = ".*"|l2ContractsLocator = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz"|' "$datadir/deploy/intent.toml"

sed -i 's/baseFeeVaultRecipient = ".*"/baseFeeVaultRecipient = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/l1FeeVaultRecipient = ".*"/l1FeeVaultRecipient = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/sequencerFeeVaultRecipient = ".*"/sequencerFeeVaultRecipient = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml

sed -i 's/eip1559DenominatorCanyon = .*/eip1559DenominatorCanyon = '250'/' $datadir/deploy/intent.toml
sed -i 's/eip1559Denominator = .*/eip1559Denominator = '250'/' $datadir/deploy/intent.toml
sed -i 's/eip1559Elasticity = .*/eip1559Elasticity = '6'/' $datadir/deploy/intent.toml

sed -i 's/l1ProxyAdminOwner = ".*"/l1ProxyAdminOwner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/l2ProxyAdminOwner = ".*"/l2ProxyAdminOwner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/systemConfigOwner = ".*"/systemConfigOwner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml

sed -i 's/unsafeBlockSigner = ".*"/unsafeBlockSigner = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml
sed -i 's/batcher = ".*"/batcher = "'$batcher_addr'"/' $datadir/deploy/intent.toml
sed -i 's/proposer = ".*"/proposer = "'$proposer_addr'"/' $datadir/deploy/intent.toml
sed -i 's/challenger = ".*"/challenger = "'$l2_admin_addr'"/' $datadir/deploy/intent.toml

>> $datadir/deploy/intent.toml cat <<EOF
[globalDeployOverrides]
  l2BlockTime = 1
  gasLimit = 60000000
  l2OutputOracleSubmissionInterval = 180
  sequencerWindowSize = 3600
EOF

# opadmin needs some funds to deploy
cast send --rpc-url $l1_rpc_url --value 2ether --private-key $l1_preallocated_private_key $l2_admin_addr

# deploy the contracts
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    apply \
    --workdir /workdir \
    --l1-rpc-url $l1_rpc_url_kurtosis \
    --private-key $l1_preallocated_private_key \
    --deployment-target live 

# Get genesis file
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect genesis \
    --workdir /workdir \
    --outfile /workdir/genesis.json \
    $l2_chain_id

# Get rollup config
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect rollup \
    --workdir /workdir \
    --outfile /workdir/rollup.json \
    $l2_chain_id

# get l1 addresses
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect l1 \
    --workdir /workdir \
    --outfile /workdir/l1.json \
    $l2_chain_id

# get deploy config
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect deploy-config \
    --workdir /workdir \
    --outfile /workdir/deploy-config.json \
    $l2_chain_id

# op geth init
docker run -it --rm \
    --network $docker_network_name \
    --name opgeth \
    -v $datadir/geth:/workdir \
    -v $datadir/deploy:/genesis \
    "$op_geth_image" \
    init \
    --state.scheme=hash \
    --datadir=/workdir \
    /genesis/genesis.json

# run geth
docker run -it --detach \
    --network $docker_network_name \
    --name opgeth \
    -v $datadir/geth:/datadir \
    -p 8545:8545 \
    "$op_geth_image" \
    --datadir /datadir \
    --http \
    --http.corsdomain="*" \
    --http.vhosts="*" \
    --http.addr=0.0.0.0 \
    --http.api=admin,engine,net,eth,web3,debug,miner,txpool \
    --ws \
    --ws.addr=0.0.0.0 \
    --ws.port=8546 \
    --ws.origins="*" \
    --ws.api=debug,eth,txpool,net,engine \
    --syncmode=full \
    --gcmode=archive \
    --nodiscover \
    --maxpeers=0 \
    --networkid=$l2_chain_id \
    --authrpc.vhosts="*" \
    --authrpc.addr=0.0.0.0 \
    --authrpc.port=8551 \
    --authrpc.jwtsecret=/datadir/jwt.txt \
    --rpc.allow-unprotected-txs \
    --rollup.disabletxpoolgossip=true \
    --miner.gaslimit=90000000

l2_rpc_url=http://localhost:8545
l2_rpc_url_docker=http://opgeth:8545

sleep 3

# run op-node
docker run -it --detach \
    --network $docker_network_name \
    --name opnode \
    -v $datadir/geth:/datadir \
    -v $datadir/deploy:/deploy \
    -v $datadir/safedb:/safedb \
    "$op_node_image" \
    op-node \
    --l2=http://opgeth:8551 \
    --l2.jwt-secret=/datadir/jwt.txt \
    --sequencer.enabled \
    --sequencer.l1-confs=5 \
    --verifier.l1-confs=4 \
    --rollup.config=/deploy/rollup.json \
    --rpc.addr=0.0.0.0 \
    --p2p.disable \
    --rpc.enable-admin \
    --l1=$l1_rpc_url_kurtosis \
    --l1.beacon=$l1_beacon_url_kurtosis \
    --l1.rpckind=standard \
    --safedb.path=/safedb

sleep 5

# fund the batcher
cast send --rpc-url $l1_rpc_url --value 2ether --private-key $l1_preallocated_private_key $batcher_addr

# run op-batcher
docker run -it --detach \
    --network $docker_network_name \
    --name opbatcher \
    "$op_batcher_image" \
    op-batcher \
    --l2-eth-rpc=http://opgeth:8545 \
    --rollup-rpc=http://opnode:9545 \
    --poll-interval=1s \
    --sub-safety-margin=6 \
    --num-confirmations=1 \
    --safe-abort-nonce-too-low-count=3 \
    --resubmission-timeout=30s \
    --rpc.addr=0.0.0.0 \
    --rpc.port=3548 \
    --rpc.enable-admin \
    --max-channel-duration=25 \
    --l1-eth-rpc=$l1_rpc_url_kurtosis \
    --private-key=$batcher_pkey \
    --data-availability-type=blobs \
    --throttle-block-size=400000

# fund the proposer
cast send --rpc-url $l1_rpc_url --value 2ether --private-key $l1_preallocated_private_key $proposer_addr

l1_op_dispute_addr=$(jq -r '.DisputeGameFactoryProxy' $datadir/deploy/l1.json)

# run op-proposer
docker run -it --detach \
    --network $docker_network_name \
    --name opproposer \
    "$op_proposer_image" \
    op-proposer \
  --poll-interval=20s \
  --rpc.port=8560 \
  --rollup-rpc=http://opnode:9545 \
  --game-factory-address="$l1_op_dispute_addr" \
  --game-type=1 \
  --proposal-interval=420s \
  --l1-eth-rpc=$l1_rpc_url_kurtosis \
  --private-key=$proposer_pkey


echo '██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗███████╗              ████████╗██╗  ██╗███████╗'
echo '██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝              ╚══██╔══╝╚██╗██╔╝██╔════╝'
echo '██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗    █████╗       ██║    ╚███╔╝ ███████╗'
echo '██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║    ╚════╝       ██║    ██╔██╗ ╚════██║'
echo '██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗███████║                 ██║   ██╔╝ ██╗███████║'
echo '╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚══════╝'
# Create some activity on both l1 and l2 before attaching the outpost

l1_op_bridge_addr=$(jq -r '.L1StandardBridgeProxy' $datadir/deploy/l1.json)
l2_op_bridge_addr="0x4200000000000000000000000000000000000010"

tmp_test_wallet_json=$(cast wallet new --json)
test_addr=$(echo "$tmp_test_wallet_json" | jq -r '.[0].address')
test_pkey=$(echo "$tmp_test_wallet_json" | jq -r '.[0].private_key')

# Balance on L1
cast send --rpc-url $l1_rpc_url --value 100ether --private-key $l1_preallocated_private_key $test_addr

# Balance on L2 through the bridge
cast send --rpc-url $l1_rpc_url --value 50ether --private-key $test_pkey $l1_op_bridge_addr
test_l2_balance=$(cast balance --rpc-url $l2_rpc_url $test_addr)
while [[ $test_l2_balance == "0" ]]; do
    echo "Waiting for L2 balance to be updated..."
    sleep 5
    test_l2_balance=$(cast balance --rpc-url $l2_rpc_url $test_addr)
done
test_l1_balance=$(cast balance --rpc-url $l1_rpc_url $test_addr)

echo "Test wallet address=$test_addr, l1balance=$test_l1_balance, l2balance=$test_l2_balance"

# Spam on L1
polycli loadtest \
    --rpc-url $l1_rpc_url \
    --private-key $l1_preallocated_private_key \
    --verbosity 600 \
    --requests 500 \
    --rate-limit 50 \
    --mode uniswapv3

# Spam on L2
polycli loadtest \
    --rpc-url $l2_rpc_url \
    --private-key $test_pkey \
    --verbosity 600 \
    --requests 500 \
    --rate-limit 50 \
    --mode uniswapv3

# Report balances after spam and tests
test_l1_balance=$(cast balance --rpc-url $l1_rpc_url $test_addr)
test_l2_balance=$(cast balance --rpc-url $l2_rpc_url $test_addr)
echo "Test wallet address=$test_addr, l1balance=$test_l1_balance, l2balance=$test_l2_balance"

# Random L1 -> L2 bridges
echo "Sending random L1 -> L2 bridges..."
for i in {1..25}; do
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')
    cast send --rpc-url $l1_rpc_url --value 0.2ether --private-key $l1_preallocated_private_key $random_addr
    cast send --rpc-url $l1_rpc_url --value 0.1ether --private-key $random_pkey $l1_op_bridge_addr
done

# Random L2 -> L1 bridges
echo "Sending random L2 -> L1 bridges..."
for i in {1..25}; do
    tmp_random_wallet_json=$(cast wallet new --json)
    random_addr=$(echo "$tmp_random_wallet_json" | jq -r '.[0].address')
    random_pkey=$(echo "$tmp_random_wallet_json" | jq -r '.[0].private_key')
    cast send --rpc-url $l2_rpc_url --value 0.2ether --private-key $test_pkey $random_addr
    cast send --rpc-url $l2_rpc_url --value 0.1ether --private-key $random_pkey $l2_op_bridge_addr
done

# create a reference wallet to check after the outpost is attached
tmp_reference_wallet_json=$(cast wallet new --json)
reference_addr=$(echo "$tmp_reference_wallet_json" | jq -r '.[0].address')
reference_pkey=$(echo "$tmp_reference_wallet_json" | jq -r '.[0].private_key')

# Balance on L1
cast send --rpc-url $l1_rpc_url --value 100ether --private-key $l1_preallocated_private_key $reference_addr

# Balance on L2 through the bridge
cast send --rpc-url $l1_rpc_url --value 50ether --private-key $reference_pkey $l1_op_bridge_addr
ref_l2_balance=$(cast balance --rpc-url $l2_rpc_url $reference_addr)
while [[ $ref_l2_balance == "0" ]]; do
    echo "Waiting for L2 balance to be updated..."
    sleep 5
    ref_l2_balance=$(cast balance --rpc-url $l2_rpc_url $reference_addr)
done
ref_l1_balance=$(cast balance --rpc-url $l1_rpc_url $reference_addr)

echo "Test wallet address=$reference_addr, l1balance=$ref_l1_balance, l2balance=$ref_l2_balance"


echo ' █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗    ███╗   ██╗███████╗████████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗'
echo '██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║  ██║    ████╗  ██║██╔════╝╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝'
echo '███████║   ██║      ██║   ███████║██║     ███████║    ██╔██╗ ██║█████╗     ██║   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ '
echo '██╔══██║   ██║      ██║   ██╔══██║██║     ██╔══██║    ██║╚██╗██║██╔══╝     ██║   ██║███╗██║██║   ██║██╔══██╗██╔═██╗ '
echo '██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██║    ██║ ╚████║███████╗   ██║   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗'
echo '╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝'

# export function encodeInitializeBytesLegacy(admin, sequencer, gasTokenAddress, sequencerURL, networkName) {
#     return ethers.AbiCoder.defaultAbiCoder().encode(
#         ['address', 'address', 'address', 'string', 'string'],
#         [admin, sequencer, gasTokenAddress, sequencerURL, networkName],
#     );
# }
initializeBytesAggchain=\
$(cast abi-encode 'initializeBytesAggchain(address,address,address,string,string)' \
    $l2_admin_addr \
    $sequencer_addr \
    $(cast address-zero) \
    "http://opnode" \
    "outpost")

rollupTypeId=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm-contracts/deployment/v2/create_rollup_output*.json | jq -r .rollupTypeId" | head -1)
rollupManagerAddress=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm/combined.json | jq -r .polygonRollupManagerAddress | head -1")
rollupTypeCount=$(cast call $rollupManagerAddress 'rollupTypeCount() returns (uint32)' --rpc-url $l1_rpc_url)
rollupCount=$(cast call $rollupManagerAddress 'rollupCount() returns (uint32)' --rpc-url $l1_rpc_url)

echo "We have $rollupTypeCount rollup types and $rollupCount rollups on the L1 RollupManager at $rollupManagerAddress"

# attachAggchainToAL(rollupTypeID,chainID,initializeBytesAggchain)
calldata=$(cast calldata 'attachAggchainToAL(uint32,uint64,bytes)' $rollupTypeId $l2_chain_id "$initializeBytesAggchain")
echo "Using calldata: $calldata"

cast send \
    --rpc-url $l1_rpc_url \
    --private-key $zkevm_l2_admin_private_key \
    $rollupManagerAddress \
    'attachAggchainToAL(uint32,uint64,bytes)' \
    $rollupTypeId \
    $l2_chain_id \
    "$initializeBytesAggchain"

newRollupCount=$(cast call $rollupManagerAddress 'rollupCount() returns (uint32)' --rpc-url $l1_rpc_url)
# Lëts check that the rollup was attached
if [[ $newRollupCount -eq $((rollupCount + 1)) ]]; then
    rollupId=$(cast call $rollupManagerAddress 'chainIDToRollupID(uint64)' $l2_chain_id --rpc-url $l1_rpc_url | cast to-dec)
    echo "Rollup successfully attached! New rollup count: $newRollupCount, new Rollup ID: $rollupId"   
else
    echo "Rollup attachment failed! Expected rollup count: $((rollupCount + 1)), got: $newRollupCount"
    exit 1
fi

rollup_addr=$(cast decode-abi 'output() returns (address)' $(cast call --rpc-url $l1_rpc_url $rollupManagerAddress 'rollupIDToRollupData(uint32)' $rollupId))


echo '██╗     ██████╗      ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  █████╗  ██████╗████████╗███████╗'
echo '██║     ╚════██╗    ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝'
echo '██║      █████╔╝    ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝███████║██║        ██║   ███████╗'
echo '██║     ██╔═══╝     ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██╔══██║██║        ██║   ╚════██║'
echo '███████╗███████╗    ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║██║  ██║╚██████╗   ██║   ███████║'
echo '╚══════╝╚══════╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚══════╝'

rm -fr agglayer-contracts
git clone https://github.com/agglayer/agglayer-contracts.git
cd agglayer-contracts
git checkout $agglayer_contracts_tag
nvm use v20.19.0
rm -fr node_modules && npm i
npx hardhat compile

forge build contracts/v2/sovereignChains/BridgeL2SovereignChain.sol contracts/v2/sovereignChains/GlobalExitRootManagerL2SovereignChain.sol

l2_admin_nonce=$(cast nonce --rpc-url $l2_rpc_url $l2_admin_addr)

# Get addresses that will be deployed
bridge_impl_addr=$(cast compute-address --nonce "$l2_admin_nonce" $l2_admin_addr | sed 's/.*: //')
ger_impl_addr=$(cast compute-address --nonce $((l2_admin_nonce + 1)) $l2_admin_addr | sed 's/.*: //')
ger_proxy_addr=$(cast compute-address --nonce $((l2_admin_nonce + 2)) $l2_admin_addr | sed 's/.*: //')
bridge_proxy_addr=$(cast compute-address --nonce $((l2_admin_nonce + 3)) $l2_admin_addr | sed 's/.*: //')

# Fund the L2 admin account
cast send --rpc-url $l1_rpc_url --value 51ether --private-key $l1_preallocated_private_key $l2_admin_addr
cast send --rpc-url $l1_rpc_url --value 50ether --private-key $l2_admin_pkey $l1_op_bridge_addr
l2_admin_balance=$(cast balance --rpc-url $l2_rpc_url $l2_admin_addr)
while [[ $l2_admin_balance == "0" ]]; do
    echo "Waiting for L2 balance to be updated..."
    sleep 5
    l2_admin_balance=$(cast balance --rpc-url $l2_rpc_url $l2_admin_addr)
done
echo "L2 admin address=$test_addr, l2balance=$l2_admin_balance"

# Fund the bridge
cast send --rpc-url $l1_rpc_url --value 100ether --private-key $l1_preallocated_private_key $l1_op_bridge_addr
l2_preallocated_balance=$(cast balance --rpc-url $l2_rpc_url $l1_preallocated_address)
while [[ $l2_preallocated_balance == "0" ]]; do
    echo "Waiting for L2 balance to be updated..."
    sleep 5
    l2_preallocated_balance=$(cast balance --rpc-url $l2_rpc_url $l1_preallocated_address)
done
echo "L2 preallocated address=$l1_preallocated_address, l2balance=$l2_preallocated_balance"
cast send --rpc-url $l2_rpc_url --value 99ether --private-key $l1_preallocated_private_key $bridge_proxy_addr

# Deploy the contracts
echo "Deploying BridgeL2SovereignChain at $bridge_impl_addr"
forge create --legacy --broadcast --rpc-url $l2_rpc_url --private-key $l2_admin_pkey BridgeL2SovereignChain
echo "Deploying GlobalExitRootManagerL2SovereignChain at $ger_impl_addr"
forge create --legacy --broadcast --rpc-url $l2_rpc_url --private-key $l2_admin_pkey GlobalExitRootManagerL2SovereignChain --constructor-args "$bridge_proxy_addr"
echo "Deploying TransparentUpgradeableProxy for GlobalExitRootManagerL2SovereignChain at $ger_proxy_addr"
calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $sequencer_addr $sequencer_addr)
forge create --legacy --broadcast --rpc-url $l2_rpc_url --private-key $l2_admin_pkey TransparentUpgradeableProxy --constructor-args "$ger_impl_addr" $l2_admin_addr "$calldata"
echo "Deploying TransparentUpgradeableProxy for BridgeL2SovereignChain at $bridge_proxy_addr"
_networkID=$rollupId
_gasTokenAddress=$(cast address-zero)
_gasTokenNetwork=0
_globalExitRootManager=$ger_proxy_addr
_polygonRollupManager=$rollupManagerAddress
_gasTokenMetadata=0x
_bridgeManager=$l2_admin_addr
_sovereignWETHAddress=$(cast address-zero)
_sovereignWETHAddressIsNotMintable=false
_emergencyBridgePauser=$l2_admin_addr
_emergencyBridgeUnpauser=$l2_admin_addr
_proxiedTokensManager=$l2_admin_addr
calldata=$(cast calldata 'function initialize(uint32,address,uint32,address,address,bytes,address,address,bool,address,address,address)' \
    $_networkID "$_gasTokenAddress" $_gasTokenNetwork "$_globalExitRootManager" "$_polygonRollupManager" $_gasTokenMetadata $_bridgeManager \
    "$_sovereignWETHAddress" $_sovereignWETHAddressIsNotMintable "$_emergencyBridgePauser" "$_emergencyBridgeUnpauser" "$_proxiedTokensManager")
forge create --legacy --broadcast --rpc-url $l2_rpc_url --private-key $l2_admin_pkey TransparentUpgradeableProxy --constructor-args "$bridge_impl_addr" $l2_admin_addr "$calldata"

cd -


echo " ██████╗ ██╗   ██╗███╗   ██╗     █████╗  ██████╗  ██████╗ ██╗  ██╗██╗████████╗"
echo " ██╔══██╗██║   ██║████╗  ██║    ██╔══██╗██╔════╝ ██╔════╝ ██║ ██╔╝██║╚══██╔══╝"
echo " ██████╔╝██║   ██║██╔██╗ ██║    ███████║██║  ███╗██║  ███╗█████╔╝ ██║   ██║   "
echo " ██╔══██╗██║   ██║██║╚██╗██║    ██╔══██║██║   ██║██║   ██║██╔═██╗ ██║   ██║   "
echo " ██║  ██║╚██████╔╝██║ ╚████║    ██║  ██║╚██████╔╝╚██████╔╝██║  ██╗██║   ██║   "
echo " ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝   "

# params required for aggkit
l1_bridge_addr=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm/combined.json | jq -r .polygonZkEVMBridgeAddress" | head -1)
l1_ger_addr=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm/combined.json | jq -r .polygonZkEVMGlobalExitRootAddress" | head -1)
polTokenAddress=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm/combined.json | jq -r .polTokenAddress" | head -1)
block_number=$(kurtosis service exec $kurtosis_agl_enclave_name contracts-001 "cat /opt/zkevm/combined.json | jq -r .deploymentRollupManagerBlockNumber" | head -1)

# prepare keystore for aggsender and aggoracle
cast wallet import --keystore-dir $datadir/aggkit --private-key "$sequencer_pkey" --unsafe-password "secret" "sequencer.keystore"

# Fund sequencer on L2
cast send --rpc-url $l1_rpc_url --private-key $l1_preallocated_private_key --value 10ether $sequencer_addr 
cast send --rpc-url $l1_rpc_url --private-key $sequencer_pkey --value 9ether $l1_op_bridge_addr 

# checking the current set address:
# cast call $ger_proxy_addr 'globalExitRootUpdater()'

# needs write permissions
chmod 777 $datadir/aggkit/tmp

> ${datadir}/aggkit/aggkit-config.toml cat <<EOF
PathRWData = "/etc/aggkit/tmp/"
L1URL="$l1_rpc_url_kurtosis"
L2URL="$l2_rpc_url_docker"
# GRPC port for Aggkit v0.3
# readport for Aggkit v0.2
AggLayerURL="agglayer:4443"

ForkId = 12
ContractVersions = "banana"
IsValidiumMode = false
# set var as number, not string
NetworkID = $rollupId

L2Coinbase =  "$l2_admin_addr"
SequencerPrivateKeyPath = ""
SequencerPrivateKeyPassword  = ""

AggregatorPrivateKeyPath = ""
AggregatorPrivateKeyPassword  = ""
SenderProofToL1Addr = ""
polygonBridgeAddr = "$l1_bridge_addr"

RPCURL = "$l2_rpc_url_docker"
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
AggsenderPrivateKey = {Path = "/etc/aggkit/sequencer.keystore", Password = "secret"}
Mode="PessimisticProof"
BlockFinality = "FinalizedBlock"
RequireNoFEPBlockGap = true

[AggOracle]
BlockFinality = "FinalizedBlock"
WaitPeriodNextGER="5000ms"

[AggOracle.EVMSender]
GlobalExitRootL2 = "$ger_proxy_addr"

[AggOracle.EVMSender.EthTxManager]
PrivateKeys = [{Path = "/etc/aggkit/sequencer.keystore", Password = "secret"}]

[AggOracle.EVMSender.EthTxManager.Etherman]
# For some weird reason that needs to be set to L2 chainid, not L1
L1ChainID = "$l2_chain_id"

[BridgeL2Sync]
BridgeAddr = "$bridge_proxy_addr"
BlockFinality = "FinalizedBlock"

[L1InfoTreeSync]
InitialBlock = "$block_number"

[Metrics]
Enabled = false
EOF

# aggoracle/sender needs some funds
cast send --rpc-url $l1_rpc_url --value 10ether --private-key $l1_preallocated_private_key $sequencer_addr

# run aggkit
docker run -it --detach \
    --network $docker_network_name \
    --name aggkit \
    -v $datadir/aggkit:/etc/aggkit \
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
cast send --rpc-url $l1_rpc_url --value 5ether --private-key $l1_preallocated_private_key $zkevm_l2_claimtxmanager_address
cast send --rpc-url $l1_rpc_url --value 4ether --private-key $zkevm_l2_claimtxmanager_private_key $l1_op_bridge_addr
l2_claimtx_balance=$(cast balance --rpc-url $l2_rpc_url $zkevm_l2_claimtxmanager_address)
while [[ $l2_claimtx_balance == "0" ]]; do
    echo "Waiting for L2 balance to be updated..."
    sleep 5
    l2_claimtx_balance=$(cast balance --rpc-url $l2_rpc_url $zkevm_l2_claimtxmanager_address)
done
echo "L2 claimtx address=$zkevm_l2_claimtxmanager_address, l2balance=$l2_claimtx_balance"

# add our network to the bridge config
kurtosis service exec $kurtosis_agl_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2URLs = \[.*)(\])#\1, \"'${l2_rpc_url_docker}'\"\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_agl_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(RequireSovereignChainSmcs = \[.*)(\])#\1, true\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_agl_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2PolygonZkEVMGlobalExitRootAddresses = \[.*)(\])#\1, \"'${ger_proxy_addr}'\"\2#" /etc/zkevm/bridge-config.toml'
kurtosis service exec $kurtosis_agl_enclave_name zkevm-bridge-service-001 'sed -i -E "s#(L2PolygonBridgeAddresses = \[.*)(\])#\1, \"'${bridge_proxy_addr}'\"\2#" /etc/zkevm/bridge-config.toml'

# get kurtosis bridge docker name and restart it
bridge_docker_name=zkevm-bridge-service-001--$(kurtosis service inspect $kurtosis_agl_enclave_name zkevm-bridge-service-001 --full-uuid | grep UUID | sed  's/.*: //')
docker restart $bridge_docker_name


echo '██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗███████╗              ████████╗██╗  ██╗███████╗'
echo '██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝              ╚══██╔══╝╚██╗██╔╝██╔════╝'
echo '██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗    █████╗       ██║    ╚███╔╝ ███████╗'
echo '██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║    ╚════╝       ██║    ██╔██╗ ╚════██║'
echo '██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗███████║                 ██║   ██╔╝ ██╗███████║'
echo '╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚══════╝'
# Create some activity on both l1 and l2 before attaching the outpost

bridge_url=$(kurtosis port print $kurtosis_agl_enclave_name zkevm-bridge-service-001 rpc)

tmp_test_wallet_json=$(cast wallet new --json)
test_addr=$(echo "$tmp_test_wallet_json" | jq -r '.[0].address')
test_pkey=$(echo "$tmp_test_wallet_json" | jq -r '.[0].private_key')

# Balance on L1
cast send --rpc-url $l1_rpc_url --value 100ether --private-key $l1_preallocated_private_key $test_addr

# amount to deposit
deposit_amount="10ether"
wei_deposit_amount=$(echo "$deposit_amount" | sed 's/ether//g' | cast to-wei)
 
l1_balance_before=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_balance_before=$(cast balance --rpc-url $l2_rpc_url $test_addr)

# Deposit on L1
polycli ulxly bridge asset \
    --value $wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $l1_bridge_addr \
    --destination-address $test_addr \
    --destination-network $rollupId \
    --rpc-url $l1_rpc_url \
    --private-key $test_pkey \
    --chain-id $l1_chainid

sleep 300

# Claim * on L2
polycli ulxly claim-everything \
    --bridge-address $bridge_proxy_addr \
    --destination-address $test_addr \
    --rpc-url $l2_rpc_url \
    --private-key $zkevm_l2_claimtxmanager_private_key \
    --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url

l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_balance_after=$(cast balance --rpc-url $l2_rpc_url $test_addr)
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
l2_balance_before=$(cast balance --rpc-url $l2_rpc_url $test_addr)

deposit_amount="5ether"
wei_deposit_amount=$(echo "$deposit_amount" | sed 's/ether//g' | cast to-wei)

# Deposit on L2
polycli ulxly bridge asset \
    --value $wei_deposit_amount \
    --gas-limit 1250000 \
    --bridge-address $bridge_proxy_addr \
    --destination-address $test_addr \
    --destination-network 0 \
    --rpc-url $l2_rpc_url \
    --private-key $test_pkey \
    --chain-id $l2_chain_id

sleep 1500

# Claim * on L1
polycli ulxly claim-everything \
    --bridge-address $l1_bridge_addr \
    --destination-address $test_addr \
    --rpc-url $l1_rpc_url \
    --private-key $test_pkey \
    --bridge-service-map '0='$bridge_url',1='$bridge_url',2='$bridge_url

l1_balance_after=$(cast balance --rpc-url $l1_rpc_url $test_addr)
l2_balance_after=$(cast balance --rpc-url $l2_rpc_url $test_addr)
echo "L1 balance before: $l1_balance_before"
echo "L1 balance after : $l1_balance_after"
echo "L1 Balance diff  : $(echo "$l1_balance_after - $l1_balance_before" | bc)"
echo "L2 balance before: $l2_balance_before"
echo "L2 balance after : $l2_balance_after"
echo "L2 Balance diff  : $(echo "$l2_balance_after - $l2_balance_before" | bc)"
