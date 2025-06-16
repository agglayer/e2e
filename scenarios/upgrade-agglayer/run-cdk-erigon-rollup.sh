#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
contracts_version="$AGGLAYER_CONTRACTS_VERSION"

# This step MUST be the first deployment - it is the default.
# echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██    ██  █████  ██      ██ ██████  ██ ██    ██ ███    ███ '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██    ██ ██   ██ ██      ██ ██   ██ ██ ██    ██ ████  ████ '
# echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██    ██ ███████ ██      ██ ██   ██ ██ ██    ██ ██ ████ ██ '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██      ██  ██  ██   ██ ██      ██ ██   ██ ██ ██    ██ ██  ██  ██ '
# echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████       ████   ██   ██ ███████ ██ ██████  ██  ██████  ██      ██ '

# # Spin up cdk-erigon validium
# kurtosis run \
#          --enclave "$kurtosis_enclave_name" \
#          "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"

# contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
# contracts_container_name=contracts-001--$contracts_uuid

# # Get the deployment details
# docker cp $contracts_container_name:/opt/zkevm/combined.json .
# rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)
# l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
# l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' combined.json)

# L1_BRIDGE_ADDR=$l1_bridge_address
# L2_BRIDGE_ADDR=$l2_bridge_address
# export L1_BRIDGE_ADDR
# export L2_BRIDGE_ADDR


# echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████  ██████         ██████  ███████ ████████ ██   ██     ██████  ██████  '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██    ██ ██   ██       ██       ██         ██    ██   ██     ██   ██ ██   ██ '
# echo '███████    ██       ██    ███████ ██      ███████     ██    ██ ██████  █████ ██   ███ █████      ██    ███████     ██████  ██████  '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██    ██ ██            ██    ██ ██         ██    ██   ██     ██      ██      '
# echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████  ██             ██████  ███████    ██    ██   ██     ██      ██      '
                                                                                                                                   
# # Spin up cdk-op-geth pp
# kurtosis run \
#          --enclave "$kurtosis_enclave_name" \
#          --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/jihwan/contracts/v9.0.0-rc.2-pp/.github/tests/chains/cdk-op-geth-pp.yml" \
#          "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"                                                                                                                


echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██████   ██████  ██      ██      ██    ██ ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██   ██ ██    ██ ██      ██      ██    ██ ██   ██ '
echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██████  ██    ██ ██      ██      ██    ██ ██████  '
echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██     ██   ██ ██    ██ ██      ██      ██    ██ ██      '
echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████     ██   ██  ██████  ███████ ███████  ██████  ██      '

# Spin up cdk-erigon rollup
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file ./cdk-erigon-rollup-single-network.yml \
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

# echo ' █████  ████████ ████████  █████   ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██████  ██  ██████   ██████  ███    ██     ██████  ██████  '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██       ██    ██ ████   ██     ██   ██ ██   ██ '
# echo '███████    ██       ██    ███████ ██      ███████     ██      ██   ██ █████   █████ █████   ██████  ██ ██   ███ ██    ██ ██ ██  ██     ██████  ██████  '
# echo '██   ██    ██       ██    ██   ██ ██      ██   ██     ██      ██   ██ ██  ██        ██      ██   ██ ██ ██    ██ ██    ██ ██  ██ ██     ██      ██      '
# echo '██   ██    ██       ██    ██   ██  ██████ ██   ██      ██████ ██████  ██   ██       ███████ ██   ██ ██  ██████   ██████  ██   ████     ██      ██      '

# # Spin up cdk-erigon pp
# kurtosis run \
#          --enclave "$kurtosis_enclave_name" \
#          --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/refs/heads/jihwan/contracts/v9.0.0-rc.2-pp/.github/tests/chains/cdk-erigon-pessimistic.yml" \
#          "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"


echo '██████  ██    ██ ███    ██     ██      ██   ██ ██      ██    ██     ██████  ██████  ██ ██████   ██████  ██ ███    ██  ██████  '
echo '██   ██ ██    ██ ████   ██     ██       ██ ██  ██       ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██ ████   ██ ██       '
echo '██████  ██    ██ ██ ██  ██     ██        ███   ██        ████       ██████  ██████  ██ ██   ██ ██   ███ ██ ██ ██  ██ ██   ███ '
echo '██   ██ ██    ██ ██  ██ ██     ██       ██ ██  ██         ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██ ██  ██ ██ ██    ██ '
echo '██   ██  ██████  ██   ████     ███████ ██   ██ ███████    ██        ██████  ██   ██ ██ ██████   ██████  ██ ██   ████  ██████  '

# Modify agglayer config
agglayer_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep -E "^[0-9a-f]{32}[[:space:]]+agglayer([[:space:]]+|$)" | awk '{print $1}')
agglayer_container_name=agglayer--$agglayer_uuid

# Add lines under [full-node-rpcs]
docker exec -it $agglayer_container_name sed -i '/^\[full-node-rpcs\]/a # RPC of the second PP network\n2 = "http://op-el-1-op-geth-op-node-002:8545"' /etc/zkevm/agglayer-config.toml
docker exec -it $agglayer_container_name sed -i '/^\[full-node-rpcs\]/a # RPC of the third rollup node\n3 = "http://cdk-erigon-rpc-001:8123"' /etc/zkevm/agglayer-config.toml
docker exec -it $agglayer_container_name sed -i '/^\[full-node-rpcs\]/a # RPC of the fourth PP network\n4 = "http://cdk-erigon-rpc-004:8123"' /etc/zkevm/agglayer-config.toml

# Add lines under [proof-signers]
docker exec -it $agglayer_container_name sed -i '/^\[proof-signers\]/a # Sequencer address for PP network\n2 = "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"' /etc/zkevm/agglayer-config.toml
docker exec -it $agglayer_container_name sed -i '/^\[proof-signers\]/a # Sequencer address for third rollup\n3 = "0x3bd49B59d0d61e83FA5C7856312b9bfEddbCbDA8"' /etc/zkevm/agglayer-config.toml
docker exec -it $agglayer_container_name sed -i '/^\[proof-signers\]/a # Sequencer address for fourth PP network\n4 = "0x0d59BC8C02A089D48d9Cd465b74Cb6E23dEB950D"' /etc/zkevm/agglayer-config.toml

kurtosis service stop $kurtosis_enclave_name agglayer
kurtosis service start $kurtosis_enclave_name agglayer

# Run bridging helper function
run_lxly_bridging() {
    local test_name="$1"
    local rpc_url="$2"
    local bridge_service_name="$3"
    local claimtxmanager_address="$4"
    local l2_bridge_addr="$5"
    local l2_private_key="$6"

    echo "Test $test_name" >&2

    # Set env variables
    export L2_RPC_URL=$(kurtosis port print $kurtosis_enclave_name "$rpc_url" rpc)
    export BRIDGE_SERVICE_URL=$(kurtosis port print $kurtosis_enclave_name "$bridge_service_name" rpc)
    export CLAIMTXMANAGER_ADDR=$claimtxmanager_address
    export L2_BRIDGE_ADDR=$l2_bridge_addr
    export KURTOSIS_ENCLAVE_NAME=$kurtosis_enclave_name

    # Run e2e bridge tests
    bats ./tests/lxly/lxly.bats

    # Check exit status
    if [[ $? -ne 0 ]]; then
        echo "Bats tests failed for $test_name. ❌" >&2
        exit 1
    fi

    echo "Bats tests passed for $test_name. ✅" >&2
}

run_agglayer_bridging() {
    local test_name="$1"
    local rpc_url="$2"
    local bridge_service_name="$3"
    local claimtxmanager_address="$4"
    local l2_bridge_addr="$5"
    local l2_private_key="$6"
    local l1_bridge_addr="$7"

    echo "Test $test_name" >&2

    # Set env variables
    export KURTOSIS_ENCLAVE_NAME=$kurtosis_enclave_name
    export L2_RPC_URL=$(kurtosis port print $kurtosis_enclave_name "$rpc_url" rpc)
    export BRIDGE_SERVICE_URL=$(kurtosis port print $kurtosis_enclave_name "$bridge_service_name" rpc)
    export CLAIMTXMANAGER_ADDR=$claimtxmanager_address
    export L1_BRIDGE_ADDR=$l1_bridge_addr
    export L2_BRIDGE_ADDR=$l2_bridge_addr

    # Run e2e bridge tests
    bats ./tests/agglayer/bridges.bats

    # Check exit status
    if [[ $? -ne 0 ]]; then
        echo "Bats tests failed for $test_name. ❌" >&2
        exit 1
    fi

    echo "Bats tests passed for $test_name. ✅" >&2
}

# Run tests in parallel
cd ../../
pids=()
# run_lxly_bridging "CDK-Erigon Validium Bridging" "cdk-erigon-rpc-001" "zkevm-bridge-service-001" "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8" "$l2_bridge_address" "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" > ./scenarios/upgrade-agglayer/cdk-erigon-validium-bridging.log 2>&1 & pids+=($!)
# run_agglayer_bridging "CDK-OPGeth-PP Bridging" "op-el-1-op-geth-op-node-002" "sovereign-bridge-service-002" "0x99e73731E5f6A6bB29AFD5e38D047Ce9Cc10C684" "0x21200F7501bEe9a06628d27c5e59b0F34E54487e" "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" "0xD71f8F956AD979Cc2988381B8A743a2fE280537D" > ./scenarios/upgrade-agglayer/op-geth-pp-bridging.log 2>&1 & pids+=($!)
run_lxly_bridging "CDK-Erigon Rollup Bridging" "cdk-erigon-rpc-001" "zkevm-bridge-service-001" "0x1a1C53bA714643B53b39D82409915b513349a1ff" "$l2_bridge_address" "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" > ./scenarios/upgrade-agglayer/cdk-erigon-rollup-bridging.log 2>&1 & pids+=($!)
# run_lxly_bridging "CDK-Erigon PP Bridging" "cdk-erigon-rpc-004" "zkevm-bridge-service-004" "0x1359D1eAf25aADaA04304Ee7EFC5b94C43e0e1D5" "$l2_bridge_address" "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" > ./scenarios/upgrade-agglayer/cdk-erigon-pp-bridging.log 2>&1 & pids+=($!)

failed=0
for pid in "${pids[@]}"; do
    wait $pid || failed=1
done
if [[ $failed -eq 1 ]]; then
    echo "One or more bridging tests failed. Check the output logs for more information."
    exit 1
fi

# Wait for all background processes to complete
wait
cd ./scenarios/upgrade-agglayer/

echo '██████  ██    ██ ██      ██          ██       █████  ████████ ███████ ███████ ████████      ██████  ██████  ███    ██ ████████ ██████   █████   ██████ ████████ ███████ '
echo '██   ██ ██    ██ ██      ██          ██      ██   ██    ██    ██      ██         ██        ██      ██    ██ ████   ██    ██    ██   ██ ██   ██ ██         ██    ██      '
echo '██████  ██    ██ ██      ██          ██      ███████    ██    █████   ███████    ██        ██      ██    ██ ██ ██  ██    ██    ██████  ███████ ██         ██    ███████ '
echo '██      ██    ██ ██      ██          ██      ██   ██    ██    ██           ██    ██        ██      ██    ██ ██  ██ ██    ██    ██   ██ ██   ██ ██         ██         ██ '
echo '██       ██████  ███████ ███████     ███████ ██   ██    ██    ███████ ███████    ██         ██████  ██████  ██   ████    ██    ██   ██ ██   ██  ██████    ██    ███████ '
                                                                                                                                                                        
# Commands to checkout newer contracts branch
if [[ $contracts_version == "feature/upgradev3-unsafeSkipStorageCheck" ]]; then
    docker exec -w /opt/zkevm-contracts -it $contracts_container_name git fetch origin
fi
docker exec -w /opt/zkevm-contracts -it $contracts_container_name git fetch --all
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

# docker exec -w /opt/zkevm-contracts -it $contracts_container_name sed -i '$aDEPLOYER_PRIVATE_KEY="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"' .env
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

    # Modified upgradeV3 script for testing purposes
    docker exec -w /opt/zkevm-contracts -it $contracts_container_name rm ./upgrade/upgradeV3/upgradeV3.ts
    docker cp assets/upgradeV3.ts $contracts_container_name:/opt/zkevm-contracts/upgrade/upgradeV3

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
  echo "Checking operation $schedule_tx_hash (Attempt $((retries + 1))/$max_retries)..."
  check_output=$(check_ready 2>/dev/null) || { echo "Error: check_ready command failed"; exit 1; }
  echo "check_ready output: $check_output"
  if [[ $check_output =~ ^(true|1)$ ]]; then
    echo "Operation ready. Executing..."
    cast send "$timelock_address" --private-key "$pvt_key" --rpc-url "http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)" "$execute_data"
    [[ $? -eq 0 ]] && { echo "Execution successful."; exit 0; } || { echo "Execution failed."; exit 1; }
  else
    if [[ $retries -ge 12 ]]; then
      cast send "$timelock_address" --private-key "$pvt_key" --rpc-url "http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)" "$execute_data"
      if [[ $? -eq 0 ]]; then
        echo "Execution successful at retries >= 12. Breaking loop."
        break
      else
        echo "Execution failed at retries >= 12. Continuing..."
      fi
    fi
    echo "Operation not ready. Retrying in $retry_interval seconds..."
    sleep "$retry_interval"
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

# Run tests in parallel
cd ../../
pids=()
# run_lxly_bridging "CDK-Erigon Validium Bridging" "cdk-erigon-rpc-001" "zkevm-bridge-service-001" "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8" "$l2_bridge_address" > ./scenarios/upgrade-agglayer/cdk-erigon-validium-bridging.log 2>&1 & pids+=($!)
# run_agglayer_bridging "CDK-OPGeth-PP Bridging" "op-el-1-op-geth-op-node-002" "sovereign-bridge-service-002" "0x99e73731E5f6A6bB29AFD5e38D047Ce9Cc10C684" "0x21200F7501bEe9a06628d27c5e59b0F34E54487e" "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" "0xD71f8F956AD979Cc2988381B8A743a2fE280537D" > ./scenarios/upgrade-agglayer/op-geth-pp-bridging.log 2>&1 & pids+=($!)
run_lxly_bridging "CDK-Erigon Rollup Bridging" "cdk-erigon-rpc-001" "zkevm-bridge-service-001" "0x1a1C53bA714643B53b39D82409915b513349a1ff" "$l2_bridge_address" > ./scenarios/upgrade-agglayer/cdk-erigon-rollup-bridging.log 2>&1 & pids+=($!)
# run_lxly_bridging "CDK-Erigon PP Bridging" "cdk-erigon-rpc-004" "zkevm-bridge-service-004" "0x1359D1eAf25aADaA04304Ee7EFC5b94C43e0e1D5" "$l2_bridge_address" > ./scenarios/upgrade-agglayer/cdk-erigon-pp-bridging.log 2>&1 & pids+=($!)

failed=0
for pid in "${pids[@]}"; do
    wait $pid || failed=1
done
if [[ $failed -eq 1 ]]; then
    echo "One or more bridging tests failed."
    exit 1
fi

# Wait for all background processes to complete
wait
cd ./scenarios/upgrade-agglayer/

exit