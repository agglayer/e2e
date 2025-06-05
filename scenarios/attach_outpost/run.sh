#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

# l1 variables
l1_preallocated_mnemonic="$L1_PREALLOCATED_MNEMONIC"
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")


# l2 variables
op_deployer_image="$OP_DEPLOYER_IMAGE"
op_geth_image="$OP_GETH_IMAGE"
op_node_image="$OP_NODE_IMAGE"
op_batcher_image="$OP_BATCHER_IMAGE"
op_proposer_image="$OP_PROPOSER_IMAGE"
l2_datadir=./data
l2_chain_id=223344
tmp_l2_admin_json=$(cast wallet new --json)
l2_admin_addr=$(echo "$tmp_l2_admin_json" | jq -r '.[0].address')
l2_admin_pkey=$(echo "$tmp_l2_admin_json" | jq -r '.[0].private_key')

# infra variables
kurtosis_agl_enclave_name="$AGL_ENCLAVE_NAME"
kurtosis_agl_tag="$AGL_KURTOSIS_PACKAGE_TAG"
docker_network_name="kt-$kurtosis_agl_enclave_name"


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

# Gather required L1 params from deployed kurtosis enclave
l1_rpc_url=http://$(kurtosis port print $kurtosis_agl_enclave_name el-1-geth-lighthouse rpc)
l1_rpc_url_kurtosis="http://el-1-geth-lighthouse:8545"
l1_ws_url=ws://$(kurtosis port print $kurtosis_agl_enclave_name el-1-geth-lighthouse ws)
l1_beacon_url=$(kurtosis port print $kurtosis_agl_enclave_name cl-1-lighthouse-geth http)
l1_beacon_url_kurtosis="http://cl-1-lighthouse-geth:4000"
l1_chainid=$(cast chain-id --rpc-url "$l1_rpc_url")


echo '██╗███████╗ ██████╗ ██╗      █████╗ ████████╗███████╗██████╗     ██╗     ██████╗ '
echo '██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗    ██║     ╚════██╗'
echo '██║███████╗██║   ██║██║     ███████║   ██║   █████╗  ██║  ██║    ██║      █████╔╝'
echo '██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██╔══╝  ██║  ██║    ██║     ██╔═══╝ '
echo '██║███████║╚██████╔╝███████╗██║  ██║   ██║   ███████╗██████╔╝    ███████╗███████╗'
echo '╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═════╝     ╚══════╝╚══════╝'
                                                                                 
mkdir -p "$l2_datadir/deploy" "$l2_datadir/geth" "$l2_datadir/safedb"

# op deployer to generate intent.toml
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $l2_datadir/deploy:/workdir \
    "$op_deployer_image" \
    init \
    --l1-chain-id $l1_chainid \
    --l2-chain-ids $l2_chain_id \
    --workdir /workdir \
    --intent-config-type "custom"

# replace values in intent.toml
sed -i 's/configType = ".*"/configType = "standard-overrides"/' $l2_datadir/deploy/intent.toml
sed -i 's/l1ChainID = .*/l1ChainID = '$l1_chainid'/' $l2_datadir/deploy/intent.toml

sed -i 's/SuperchainProxyAdminOwner = ".*"/SuperchainProxyAdminOwner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/SuperchainGuardian = ".*"/SuperchainGuardian = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/ProtocolVersionsOwner = ".*"/ProtocolVersionsOwner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml

sed -i 's|l1ContractsLocator = ".*"|l1ContractsLocator = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz"|' "$l2_datadir/deploy/intent.toml"
sed -i 's|l2ContractsLocator = ".*"|l2ContractsLocator = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz"|' "$l2_datadir/deploy/intent.toml"

sed -i 's/baseFeeVaultRecipient = ".*"/baseFeeVaultRecipient = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/l1FeeVaultRecipient = ".*"/l1FeeVaultRecipient = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/sequencerFeeVaultRecipient = ".*"/sequencerFeeVaultRecipient = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml

sed -i 's/eip1559DenominatorCanyon = .*/eip1559DenominatorCanyon = '250'/' $l2_datadir/deploy/intent.toml
sed -i 's/eip1559Denominator = .*/eip1559Denominator = '250'/' $l2_datadir/deploy/intent.toml
sed -i 's/eip1559Elasticity = .*/eip1559Elasticity = '6'/' $l2_datadir/deploy/intent.toml

sed -i 's/l1ProxyAdminOwner = ".*"/l1ProxyAdminOwner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/l2ProxyAdminOwner = ".*"/l2ProxyAdminOwner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/systemConfigOwner = ".*"/systemConfigOwner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml

sed -i 's/unsafeBlockSigner = ".*"/unsafeBlockSigner = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/batcher = ".*"/batcher = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/proposer = ".*"/proposer = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml
sed -i 's/challenger = ".*"/challenger = "'$l2_admin_addr'"/' $l2_datadir/deploy/intent.toml

>> $l2_datadir/deploy/intent.toml cat <<EOF
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
    -v $l2_datadir/deploy:/workdir \
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
    -v $l2_datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect genesis \
    --workdir /workdir \
    --outfile /workdir/genesis.json \
    $l2_chain_id

# Get rollup config
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $l2_datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect rollup \
    --workdir /workdir \
    --outfile /workdir/rollup.json \
    $l2_chain_id

# get l1 addresses
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $l2_datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect l1 \
    --workdir /workdir \
    --outfile /workdir/l1.json \
    $l2_chain_id

# get deploy config
docker run -it --rm \
    --network $docker_network_name \
    --name opdeployer \
    -v $l2_datadir/deploy:/workdir \
    "$op_deployer_image" \
    inspect deploy-config \
    --workdir /workdir \
    --outfile /workdir/deploy-config.json \
    $l2_chain_id

# op geth init
docker run -it --rm \
    --network $docker_network_name \
    --name opgeth \
    -v $l2_datadir/geth:/workdir \
    -v $l2_datadir/deploy:/genesis \
    "$op_geth_image" \
    init \
    --state.scheme=hash \
    --datadir=/workdir \
    /genesis/genesis.json

# run geth
docker run -it --detach \
    --network $docker_network_name \
    --name opgeth \
    -v $l2_datadir/geth:/datadir \
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

sleep 3

# run op-node
docker run -it --detach \
    --network $docker_network_name \
    --name opnode \
    -v $l2_datadir/geth:/datadir \
    -v $l2_datadir/deploy:/deploy \
    -v $l2_datadir/safedb:/safedb \
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
cast send --rpc-url $l1_rpc_url --value 2ether --private-key $l1_preallocated_private_key $l2_admin_addr

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
    --private-key=$l2_admin_pkey \
    --data-availability-type=blobs \
    --throttle-block-size=400000

# fund the proposer
cast send --rpc-url $l1_rpc_url --value 2ether --private-key $l1_preallocated_private_key $l2_admin_addr

l1_op_dispute_addr=$(jq -r '.DisputeGameFactoryProxy' $l2_datadir/deploy/l1.json)

# run op-proposer, required for bridges
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
  --private-key=$l2_admin_pkey


echo '██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗███████╗              ████████╗██╗  ██╗███████╗'
echo '██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝              ╚══██╔══╝╚██╗██╔╝██╔════╝'
echo '██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗    █████╗       ██║    ╚███╔╝ ███████╗'
echo '██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║    ╚════╝       ██║    ██╔██╗ ╚════██║'
echo '██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗███████║                 ██║   ██╔╝ ██╗███████║'
echo '╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚══════╝'
# Create some activity on both l1 and l2 before attaching the outpost

l1_op_bridge_addr=$(jq -r '.L1StandardBridgeProxy' $l2_datadir/deploy/l1.json)
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
                                                                                                                    