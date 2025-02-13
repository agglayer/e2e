#!/bin/bash

### Certificate Spammer valid-cert
export CDK_NETWORKCONFIG_L1_L1CHAINID="$(cast chain-id --rpc-url $(kurtosis port print cdk el-1-geth-lighthouse rpc))"
export CDK_NETWORKCONFIG_L1_GLOBALEXITROOTMANAGERADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polygonZkEVMGlobalExitRootAddress" | awk -F'"' '{print $4}')"
export CDK_NETWORKCONFIG_L1_ROLLUPMANAGERADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polygonRollupManagerAddress" | awk -F'"' '{print $4}')"
export CDK_NETWORKCONFIG_L1_POLADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polTokenAddress" | awk -F'"' '{print $4}')"
export CDK_NETWORKCONFIG_L1_ZKEVMADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm-contracts/sovereign-rollup-out.json' | tail -n +2 | jq | grep "sovereignRollupContract" | awk -F'"' '{print $4}')"

export CDK_ETHERMAN_URL="http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
export CDK_ETHERMAN_ETHERMANCONFIG_URL=$CDK_ETHERMAN_URL
export CDK_ETHERMAN_ETHERMANCONFIG_L1CHAINID=$CDK_L1CONFIG_CHAINID

export CDK_COMMON_NETWORKID=2
export CDK_COMMON_ISVALIDIUMMODE=false
export CDK_COMMON_CONTRACTVERSIONS="banana"

export CDK_LOG_LEVEL="debug"

export CDK_REORGDETECTORL1_DBPATH="./cdk-databases/reorgdetectorl1.sqlite"

export CDK_REORGDETECTORL2_DBPATH="./cdk-databases/reorgdetectorl2.sqlite"

export CDK_BRIDGEL2SYNC_DBPATH="./cdk-databases/bridgel2sync.sqlite"
export CDK_BRIDGEL2SYNC_BRIDGEADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm-contracts/sovereign-rollup-out.json' | tail -n +2 | jq | grep "bridge_proxy_addr" | awk -F'"' '{print $4}')"

export CDK_L1INFOTREESYNC_DBPATH="./cdk-databases/L1InfoTreeSync.sqlite"
export CDK_L1INFOTREESYNC_GLOBALEXITROOTADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polygonZkEVMGlobalExitRootAddress" | awk -F'"' '{print $4}')"
export CDK_L1INFOTREESYNC_ROLLUPMANAGERADDR="$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polygonRollupManagerAddress" | awk -F'"' '{print $4}')"
export CDK_L1INFOTREESYNC_URLRPCL1=$CDK_ETHERMAN_URL
export CDK_L1INFOTREESYNC_INITIALBLOCK=0

export CDK_AGGSENDER_STORAGEPATH="./cdk-databases/aggsender.sqlite"
export CDK_AGGSENDER_AGGLAYERURL="$(kurtosis port print cdk agglayer agglayer)"
export CDK_AGGSENDER_AGGSENDERPRIVATEKEY_PATH="./test.keystore.sequencer"
export CDK_AGGSENDER_AGGSENDERPRIVATEKEY_PASSWORD="testonly"
export CDK_AGGSENDER_URLRPCL2="$(kurtosis port print cdk op-el-1-op-geth-op-node-op-kurtosis rpc)"

export L1_Bridge_ADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | tail -n +2 | jq | grep "polygonZkEVMBridgeAddress" | awk -F'"' '{print $4}')

echo "ENV set sucessfully"
