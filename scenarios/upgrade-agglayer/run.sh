#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
contracts_version="$AGGLAYER_CONTRACTS_VERSION"

# This step MUST be the first deployment - it is the default.
echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██    ██  █████  ██      ██ ██████  ██ ██    ██ ███    ███ '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██    ██ ██   ██ ██      ██ ██   ██ ██ ██    ██ ████  ████ '
echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██    ██ ███████ ██      ██ ██   ██ ██ ██    ██ ██ ████ ██ '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██      ██  ██  ██   ██ ██      ██ ██   ██ ██ ██    ██ ██  ██  ██ '
echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████       ████   ██   ██ ███████ ██ ██████  ██  ██████  ██      ██ '

# Spin up cdk-erigon validium
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
export L1_BRIDGE_ADDR
export L2_BRIDGE_ADDR


echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████  ██████         ██████  ███████ ████████ ██   ██     ██████  ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██    ██ ██   ██       ██       ██         ██    ██   ██     ██   ██ ██   ██ '
echo '███████    ██       ██    ███████ ██      ███████     ██    ██ ██████  █████ ██   ███ █████      ██    ███████     ██████  ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██    ██ ██            ██    ██ ██         ██    ██   ██     ██      ██      '
echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████  ██             ██████  ███████    ██    ██   ██     ██      ██      '
                                                                                                                                   
# Spin up cdk-op-geth pp
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/jihwan/contracts/v9.0.0-rc.2-pp/.github/tests/chains/cdk-op-geth-pp.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"                                                                                                                


echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██████  ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██   ██ ██   ██ '
echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██████  ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██     ██      ██      '
echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████     ██      ██      '

# Spin up cdk-erigon pp
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/jihwan/contracts/v9.0.0-rc.2-pp/.github/tests/chains/cdk-erigon-pessimistic.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"


echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██████   ██████  ██      ██      ██    ██ ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██   ██ ██    ██ ██      ██      ██    ██ ██   ██ '
echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██████  ██    ██ ██      ██      ██    ██ ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██     ██   ██ ██    ██ ██      ██      ██    ██ ██      '
echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████     ██   ██  ██████  ███████ ███████  ██████  ██      '

# Spin up cdk-erigon rollup
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/jihwan/contracts/v9.0.0-rc.2-pp/.github/tests/chains/cdk-erigon-rollup.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"                                                                                                                                                                     


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-OPGeth-PP Bridging"
L2_RPC_URL=$(kurtosis port print cdk op-el-1-op-geth-op-node-002 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon Validium Bridging"
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon Rollup Bridging"
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon PP Bridging"
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"


echo '██████  ██    ██ ██      ██          ██       █████  ████████ ███████ ███████ ████████      ██████  ██████  ███    ██ ████████ ██████   █████   ██████ ████████ ███████ '
echo '██   ██ ██    ██ ██      ██          ██      ██   ██    ██    ██      ██         ██        ██      ██    ██ ████   ██    ██    ██   ██ ██   ██ ██         ██    ██      '
echo '██████  ██    ██ ██      ██          ██      ███████    ██    █████   ███████    ██        ██      ██    ██ ██ ██  ██    ██    ██████  ███████ ██         ██    ███████ '
echo '██      ██    ██ ██      ██          ██      ██   ██    ██    ██           ██    ██        ██      ██    ██ ██  ██ ██    ██    ██   ██ ██   ██ ██         ██         ██ '
echo '██       ██████  ███████ ███████     ███████ ██   ██    ██    ███████ ███████    ██         ██████  ██████  ██   ████    ██    ██   ██ ██   ██  ██████    ██    ███████ '
                                                                                                                                                                        
# Commands to checkout newer contracts branch
if [[ $contracts_version == "feature/upgradev3-unsafeSkipStorageCheck" ]]; then
    docker exec -w /opt/zkevm-contracts -it $contracts_container_name git fetch origin
fi
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git stash
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git checkout $contracts_version --force
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

docker exec -w /opt/zkevm-contracts -it $contracts_container_name sed -i '$aDEPLOYER_PRIVATE_KEY="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"' .env
docker cp deploy_parameters.json $contracts_container_name:/opt/zkevm-contracts/tools/deployAggLayerGateway
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./tools/deployAggLayerGateway/deployAggLayerGateway.ts --network localhost
docker cp $contracts_container_name:/opt/zkevm-contracts/tools/deployAggLayerGateway/deploy_output.json .
agglayer_gateway_address=$(jq -r '.aggLayerGatewayAddress' deploy_output.json)


echo '██ ███    ██ ██ ████████ ██  █████  ████████ ███████     ██    ██ ██████   ██████  ██████   █████  ██████  ███████ '
echo '██ ████   ██ ██    ██    ██ ██   ██    ██    ██          ██    ██ ██   ██ ██       ██   ██ ██   ██ ██   ██ ██      '
echo '██ ██ ██  ██ ██    ██    ██ ███████    ██    █████       ██    ██ ██████  ██   ███ ██████  ███████ ██   ██ █████   '
echo '██ ██  ██ ██ ██    ██    ██ ██   ██    ██    ██          ██    ██ ██      ██    ██ ██   ██ ██   ██ ██   ██ ██      '
echo '██ ██   ████ ██    ██    ██ ██   ██    ██    ███████      ██████  ██       ██████  ██   ██ ██   ██ ██████  ███████ '

echo "Check Rollup Manager Contract Version Before Upgrade"
rollup_manager_version=$(cast call $rollup_manager_address "ROLLUP_MANAGER_VERSION()(string)" --rpc-url http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc))

# Expected version
expected_version=\"pessimistic\"

# Check if the version matches
if [[ "$rollup_manager_version" != "$expected_version" ]]; then
    echo "Error: Expected ROLLUP_MANAGER_VERSION to be $expected_version, but got $rollup_manager_version"
    exit 1
else
    echo "Version check passed: $rollup_manager_version"
fi

jq \
    --arg rma "$rollup_manager_address" \
    --arg aga "$agglayer_gateway_address" '.rollupManagerAddress = $rma | .aggLayerGatewayAddress = $aga' \
    assets/upgrade_parameters.json  > upgrade_parameters.json

# Check if contracts version is feature/upgradev3-unsafeSkipStorageCheck
if [[ $contracts_version == "feature/upgradev3-unsafeSkipStorageCheck" || $contracts_version == "feature/tools-fixes" ]]; then

    # # Modified upgradeV3 script for testing purposes
    # docker exec -w /opt/zkevm-contracts -it $contracts_container_name rm ./upgrade/upgradeV3/upgradeV3.ts
    # docker cp assets/upgradeV3.ts $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3

    docker cp upgrade_parameters.json $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3
    docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./upgrade/upgradeV3/upgradeV3.ts --network localhost
    docker cp $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3/upgrade_output.json .
else
    docker cp upgrade_parameters.json $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeAL
    docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run ./upgrade/upgradeAL/upgradeALV3.ts --network localhost
    docker cp $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeAL/upgrade_output.json .
fi

# Trigger the upgrade after the timelock delay
timelock_address=$(jq -r '.timelockContractAddress' combined.json)
pvt_key=$(jq -r '.deployerPvtKey' upgrade_parameters.json)
execute_data=$(jq -r '.executeData' upgrade_output.json)
schedule_tx_hash=$(jq -r '.scheduleTxHash' upgrade_output.json)

# Check operation readiness
check_ready() {
  cast call "$timelock_address" "isOperationReady(bytes32)(bool)" "$schedule_tx_hash" --rpc-url http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc) 2>/dev/null
}

max_retries=360
retry_interval=10
# Retry loop
for ((retries=0; retries<max_retries; retries++)); do
  echo "Checking operation $OPERATION_ID (Attempt $((retries + 1))/$max_retries)..."
  if [[ $(check_ready) =~ ^(true|1)$ ]]; then
    echo "Operation ready. Executing..."
    cast send $timelock_address --private-key $pvt_key --rpc-url http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc) "$execute_data"
    [[ $? -eq 0 ]] && { echo "Execution successful."; exit 0; } || { echo "Execution failed."; exit 1; }
  else
    echo "Operation not ready. Retrying in $retry_interval seconds..."
    sleep $retry_interval
  fi
done

echo "Check Rollup Manager Contract Version After Upgrade"
rollup_manager_version=$(cast call $rollup_manager_address "ROLLUP_MANAGER_VERSION()(string)" --rpc-url http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc))

# Expected version
expected_version=\"al-v0.3.0\"

# Check if the version matches
if [[ "$rollup_manager_version" != "$expected_version" ]]; then
    echo "Error: Expected ROLLUP_MANAGER_VERSION to be $expected_version, but got $rollup_manager_version"
    exit 1
else
    echo "Version check passed: $rollup_manager_version"
fi

echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-OPGeth-PP Bridging"
L2_RPC_URL=$(kurtosis port print cdk op-el-1-op-geth-op-node-002 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon Validium Bridging"
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"

echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon Rollup Bridging"
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"

echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

echo "Test CDK-Erigon PP Bridging"
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)
# L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-003 rpc)
L2_RPC_URL=$(kurtosis port print cdk cdk-erigon-rpc-004 rpc)

# Run e2e bridge tests L2 <-> L1
cd ../../
bats ./tests/lxly/lxly.bats

# Check the exit status of the bats test
if [[ $? -ne 0 ]]; then
    echo "Bats tests failed. Exiting script. ❌"
    exit 1
fi

cd ./scenarios/upgrade-agglayer/
echo "Bats tests passed. Continuing script. ✅"

exit