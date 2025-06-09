#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
contracts_version="$AGGLAYER_CONTRACTS_VERSION"

# Remove cdk-node/aggkit db
cdk_node_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep cdk-node-001[^-] | awk '{print $1}')
cdk_node_container_name=cdk-node-001--$cdk_node_uuid
docker exec -it $cdk_node_container_name rm -rf /tmp
docker exec -it $cdk_node_container_name mkdir /tmp

# Stop sending certificates to agglayer
echo "Stopping the aggsender (cdk-node/aggkit) service..."
kurtosis service stop $kurtosis_enclave_name cdk-node-001

# Get agglayer configs
agglayer_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep agglayer[^-] | awk '{print $1}')
agglayer_container_name=agglayer--$agglayer_uuid
docker cp $agglayer_container_name:/etc/zkevm/agglayer-config.toml .
docker cp $agglayer_container_name:/etc/zkevm/agglayer.keystore .

# Replace prover url to something recognizable by agglayer container
sed -i 's|prover-entrypoint = "http://[^:]*:4445"|prover-entrypoint = "http://agglayer-prover:4445"|' ./agglayer-config.toml
sed -i '/\[rpc\]/!b;n;c\ngrpc-port = 4443\nreadrpc-port = 4444\nadmin-port = 4446' ./agglayer-config.toml

# Stop agglayer service
echo "Stopping the agglayer service..."
kurtosis service stop $kurtosis_enclave_name agglayer
echo "Removing the agglayer service..."
kurtosis service rm $kurtosis_enclave_name agglayer

# Get agglayer-prover configs
agglayer_prover_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep agglayer-prover[^-] | awk '{print $1}')
agglayer_prover_container_name=agglayer-prover--$agglayer_prover_uuid
docker cp $agglayer_prover_container_name:/etc/zkevm/agglayer-prover-config.toml .

# Stop agglayer-prover service
echo "Stopping the agglayer-prover service..."
kurtosis service stop $kurtosis_enclave_name agglayer-prover
echo "Removing the agglayer-prover service..."
kurtosis service rm $kurtosis_enclave_name agglayer-prover

# Attach the new agglayer and agglayer-prover v0.3.x service
docker compose up -d > docker-compose.log 2>&1

echo "Starting the aggsender (cdk-node/aggkit) service..."
kurtosis service start $kurtosis_enclave_name cdk-node-001