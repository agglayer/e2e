#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"

# Spin up the network
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"

contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

# Get the deployment details
docker cp $contracts_container_name:/opt/zkevm/combined.json .
rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)
l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' combined.json)

L1_BRIDGE_ADDR=$l1_bridge_address
L2_BRIDGE_ADDR=$l2_bridge_address


# echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
# echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
# echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
# echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
# echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

# # Run e2e bridge tests L2 <-> L1
# cd ../../
# bats ./tests/lxly/lxly.bats

# # Check the exit status of the bats test
# if [[ $? -ne 0 ]]; then
#     echo "Bats tests failed. Exiting script."
#     exit 1
# fi

# cd ./scenarios/upgrade-rollup-manager/
# echo "Bats tests passed. Continuing script."


echo '██████  ██    ██ ██      ██          ██       █████  ████████ ███████ ███████ ████████      ██████  ██████  ███    ██ ████████ ██████   █████   ██████ ████████ ███████ '
echo '██   ██ ██    ██ ██      ██          ██      ██   ██    ██    ██      ██         ██        ██      ██    ██ ████   ██    ██    ██   ██ ██   ██ ██         ██    ██      '
echo '██████  ██    ██ ██      ██          ██      ███████    ██    █████   ███████    ██        ██      ██    ██ ██ ██  ██    ██    ██████  ███████ ██         ██    ███████ '
echo '██      ██    ██ ██      ██          ██      ██   ██    ██    ██           ██    ██        ██      ██    ██ ██  ██ ██    ██    ██   ██ ██   ██ ██         ██         ██ '
echo '██       ██████  ███████ ███████     ███████ ██   ██    ██    ███████ ███████    ██         ██████  ██████  ██   ████    ██    ██   ██ ██   ██  ██████    ██    ███████ '
                                                                                                                                                                        
# Commands to checkout newer contracts branch
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git fetch --all
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git stash
# docker exec -w /opt/zkevm-contracts -it $contracts_container_name git checkout feature/forge-doc
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git checkout feature/upgradev3-unsafeSkipStorageCheck
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git stash apply
docker exec -w /opt/zkevm-contracts -it $contracts_container_name rm -rf node_modules/
docker exec -w /opt/zkevm-contracts -it $contracts_container_name rm -rf /root/.cache/hardhat-nodejs/
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npm i
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat compile


# echo '██████  ███████ ██████  ██       ██████  ██    ██     ██    ██ ███████ ██████  ██ ███████ ██ ███████ ██████  '
# echo '██   ██ ██      ██   ██ ██      ██    ██  ██  ██      ██    ██ ██      ██   ██ ██ ██      ██ ██      ██   ██ '
# echo '██   ██ █████   ██████  ██      ██    ██   ████       ██    ██ █████   ██████  ██ █████   ██ █████   ██████  '
# echo '██   ██ ██      ██      ██      ██    ██    ██         ██  ██  ██      ██   ██ ██ ██      ██ ██      ██   ██ '
# echo '██████  ███████ ██      ███████  ██████     ██          ████   ███████ ██   ██ ██ ██      ██ ███████ ██   ██ '
                                                                                                   
# docker cp deploy_verifier_parameters.json $contracts_container_name:/opt/zkevm-contracts/tools/deployVerifier
# docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./tools/deployVerifier/deployVerifier.ts --network localhost


echo '██████  ███████ ██████  ██       ██████  ██    ██      █████   ██████   ██████  ██       █████  ██    ██ ███████ ██████   ██████   █████  ████████ ███████ ██     ██  █████  ██    ██ '
echo '██   ██ ██      ██   ██ ██      ██    ██  ██  ██      ██   ██ ██       ██       ██      ██   ██  ██  ██  ██      ██   ██ ██       ██   ██    ██    ██      ██     ██ ██   ██  ██  ██  '
echo '██   ██ █████   ██████  ██      ██    ██   ████       ███████ ██   ███ ██   ███ ██      ███████   ████   █████   ██████  ██   ███ ███████    ██    █████   ██  █  ██ ███████   ████   '
echo '██   ██ ██      ██      ██      ██    ██    ██        ██   ██ ██    ██ ██    ██ ██      ██   ██    ██    ██      ██   ██ ██    ██ ██   ██    ██    ██      ██ ███ ██ ██   ██    ██    '
echo '██████  ███████ ██      ███████  ██████     ██        ██   ██  ██████   ██████  ███████ ██   ██    ██    ███████ ██   ██  ██████  ██   ██    ██    ███████  ███ ███  ██   ██    ██    '

verifier_address=$(jq -r '.verifierAddress' combined.json)
jq --arg va "$verifier_address" '.verifierAddress = $va' assets/deploy_parameters.json  > deploy_parameters.json

docker cp deploy_parameters.json $contracts_container_name:/opt/zkevm-contracts/tools/deployAggLayerGateway
output=$(docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./tools/deployAggLayerGateway/deployAggLayerGateway.ts --network localhost)
agglayer_gateway_address=$(echo "$output" | grep "aggLayerGatewayContract deployed to:" | sed 's/.*deployed to: \(0x[a-fA-F0-9]\{40\}\).*/\1/')


echo '██ ███    ██ ██ ████████ ██  █████  ████████ ███████     ██    ██ ██████   ██████  ██████   █████  ██████  ███████ '
echo '██ ████   ██ ██    ██    ██ ██   ██    ██    ██          ██    ██ ██   ██ ██       ██   ██ ██   ██ ██   ██ ██      '
echo '██ ██ ██  ██ ██    ██    ██ ███████    ██    █████       ██    ██ ██████  ██   ███ ██████  ███████ ██   ██ █████   '
echo '██ ██  ██ ██ ██    ██    ██ ██   ██    ██    ██          ██    ██ ██      ██    ██ ██   ██ ██   ██ ██   ██ ██      '
echo '██ ██   ████ ██    ██    ██ ██   ██    ██    ███████      ██████  ██       ██████  ██   ██ ██   ██ ██████  ███████ '

jq \
    --arg rma "$rollup_manager_address" \
    --arg aga "$agglayer_gateway_address" '.rollupManagerAddress = $rma | .aggLayerGatewayAddress = $aga' \
    assets/upgrade_parameters.json  > upgrade_parameters.json

docker cp upgrade_parameters.json $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./upgrade/upgradeV3/upgradeV3.ts --network localhost
docker cp $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3/upgrade_output.json .

exit