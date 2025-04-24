#!/bin/env bash

kurtosis_hash="86d88c638b807cc16bb58149fa0bf45543cb806a"
kurtosis_enclave_name="pp-to-fep-test"

# Spin up the network
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/nightly/op-rollup/op-default.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"

#     _       _     _   ____       _ _               _____
#    / \   __| | __| | |  _ \ ___ | | |_   _ _ __   |_   _|   _ _ __   ___
#   / _ \ / _` |/ _` | | |_) / _ \| | | | | | '_ \    | || | | | '_ \ / _ \
#  / ___ \ (_| | (_| | |  _ < (_) | | | |_| | |_) |   | || |_| | |_) |  __/
# /_/   \_\__,_|\__,_| |_| \_\___/|_|_|\__,_| .__/    |_| \__, | .__/ \___|
#                                           |_|           |___/|_|
contracts_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

agglayer_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep agglayer[^-] | awk '{print $1}')
agglayer_container_name=agglayer--$agglayer_uuid

# Read the agglayer vkey value
agglayer_vkey=$(docker exec -it "$agglayer_container_name" agglayer vkey | tr -d "\r\n")

# Get the deployment details
docker cp $contracts_container_name:/opt/zkevm/combined.json .

rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)

jq --arg vkey "$agglayer_vkey" '.programVKey = $vkey' assets/add_rollup_type.json  > add_rollup_type.json
jq --arg rm "$rollup_manager_address" '.polygonRollupManagerAddress = $rm' add_rollup_type.json > _t; mv _t add_rollup_type.json

# Move the config file into the container
docker cp add_rollup_type.json $contracts_container_name:/opt/zkevm-contracts/tools/addRollupType

# this step might print errors related to verification
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/addRollupType/addRollupType.ts --network localhost

#  _   _           _       _         ____       _ _
# | | | |_ __   __| | __ _| |_ ___  |  _ \ ___ | | |_   _ _ __
# | | | | '_ \ / _` |/ _` | __/ _ \ | |_) / _ \| | | | | | '_ \
# | |_| | |_) | (_| | (_| | ||  __/ |  _ < (_) | | | |_| | |_) |
#  \___/| .__/ \__,_|\__,_|\__\___| |_| \_\___/|_|_|\__,_| .__/
#       |_|                                              |_|

# Set the urls
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)
l2_rpc_url=$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)
l2_node_url=$(kurtosis port print $kurtosis_enclave_name op-cl-1-op-node-op-geth-001 http)

# Get the current rollup type count and make sure that it make sense
rollup_type_count=$(cast call --rpc-url "$l1_rpc_url" $(jq -r '.polygonRollupManagerAddress' combined.json) 'rollupTypeCount() external view returns (uint32)')
if [[ $rollup_type_count -ne 2 ]]; then
    printf "Expected a rollup type count of 2 but got %d\n" "$rollup_type_count"
    exit 1
fi

# Create the upgrade data - Carlos
# upgrade_data=$(cast calldata "initAggchainManager(address)" 0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa)
# Create the upgrade data - John
upgrade_data=$(cast calldata "initAggchainManager(address)" 0xE34aaF64b29273B7D567FCFc40544c014EEe9970)
rollup_address=$(jq -r '.rollupAddress' combined.json)

# Set the values in the update rollup json and copy the updated file into the container
jq \
    --arg u "$upgrade_data" \
    --arg rm "$rollup_manager_address" \
    --arg r "$rollup_address" '.rollups[0].rollupAddress = $r | .rollups[0].upgradeData = $u | .polygonRollupManagerAddress = $rm' \
    assets/updateRollup.json  > updateRollup.json
docker cp updateRollup.json $contracts_container_name:/opt/zkevm-contracts/tools/updateRollup

# Execute the update rollup script
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/updateRollup/updateRollup.ts --network localhost

#  ___       _ _   _       _ _           ____       _ _
# |_ _|_ __ (_) |_(_) __ _| (_)_______  |  _ \ ___ | | |_   _ _ __
#  | || '_ \| | __| |/ _` | | |_  / _ \ | |_) / _ \| | | | | | '_ \
#  | || | | | | |_| | (_| | | |/ /  __/ |  _ < (_) | | | |_| | |_) |
# |___|_| |_|_|\__|_|\__,_|_|_/___\___| |_| \_\___/|_|_|\__,_| .__/
#                                                            |_|

docker cp $contracts_container_name:/opt/contract-deploy/create_new_rollup.json initialize_rollup.json

cast rpc --rpc-url "$l2_node_url" admin_stopSequencer

current_unsafe_block=$(cast rpc --rpc-url "$l2_node_url" optimism_outputAtBlock 0x0 | jq '.syncStatus.unsafe_l2.number')

cast rpc --rpc-url "$l2_node_url" optimism_outputAtBlock $(printf "0x%x" $current_unsafe_block) | jq '.' > output.json

# TODO this is very hacky.. There are some things in this that don't actually come from rollup config. And then some values are formatted differently
cast rpc --rpc-url "$l2_node_url" optimism_rollupConfig | jq '.' | jq --indent 2 '{
  genesis: {
    l1: {
      number:              .genesis.l1.number,
      hash:                .genesis.l1.hash
    },
    l2: {
      number:              .genesis.l2.number,
      hash:                .genesis.l2.hash
    },
    l2_time:               .genesis.l2_time,
    system_config: {
      batcherAddress:      .genesis.system_config.batcherAddr,
      overhead:            "0x0",
      scalar:              .genesis.system_config.scalar,
      gasLimit:            .genesis.system_config.gasLimit,
      "baseFeeScalar": null,
      "blobBaseFeeScalar": null,
      "eip1559Denominator": 0,
      "eip1559Elasticity": 0,
      "operatorFeeScalar": null,
      "operatorFeeConstant": null
    }
  },

  block_time:                 .block_time,
  max_sequencer_drift:        .max_sequencer_drift,
  seq_window_size:            .seq_window_size,
  channel_timeout:            .channel_timeout,
  "granite_channel_timeout": 50,

  l1_chain_id:                .l1_chain_id,
  l2_chain_id:                .l2_chain_id,

  base_fee_params: {
    max_change_denominator: "0x32",
    elasticity_multiplier: "0x6"
  },
  canyon_base_fee_params: {
    max_change_denominator: "0xfa",
    elasticity_multiplier: "0x6"
  },


  regolith_time:              .regolith_time,
  canyon_time:                .canyon_time,
  delta_time:                 .delta_time,
  ecotone_time:               .ecotone_time,
  fjord_time:                 .fjord_time,
  granite_time:               .granite_time,
  holocene_time:              .holocene_time,

  batch_inbox_address:        .batch_inbox_address,
  deposit_contract_address:   .deposit_contract_address,
  l1_system_config_address:   .l1_system_config_address,
  protocol_versions_address:  "0x0000000000000000000000000000000000000000",
  interop_message_expiry_window: 3600
}' | sed 's/"scalar": "0x01/"scalar": "0x1/' | head -c -1 > rollup.json

rollup_config_hash=0x$(sha256sum rollup.json | awk '{print $1}')

# TODO make sure the submission interval of 1 makes sense
# TODO figure out if the range vkey committment and aggregation key can be read from somewhere
# TODO block time should come from the rollup config
jq \
    --arg rch "$rollup_config_hash" \
    --slurpfile o output.json \
   '.aggchainParams.initParams.l2BlockTime = 1 |
    .aggchainParams.initParams.startingOutputRoot = $o[0].outputRoot |
    .aggchainParams.initParams.startingBlockNumber = $o[0].blockRef.number |
    .aggchainParams.initParams.startingTimestamp = $o[0].blockRef.timestamp |
    .aggchainParams.initParams.submissionInterval = 1 |
    .aggchainParams.initParams.aggregationVkey = "0x00e85a8274b6b98b791afeef499b00895c59b5e2e118844dda57eda801dbb10d" |
    .aggchainParams.initParams.rangeVkeyCommitment = "0x0367776036b0d8b12720eab775b651c7251e63a249cb84f63eb1c20418b24e9c" |
    .aggchainParams.initParams.rollupConfigHash = $rch |
    .realVerifier = true |
    .consensusContractName = "AggchainFEP"
'  initialize_rollup.json > _t; mv _t initialize_rollup.json

docker cp initialize_rollup.json $contracts_container_name:/opt/zkevm-contracts/tools/initializeRollup/
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/initializeRollup/initializeRollup.ts --network localhost

# TODO figure out what the input should be
# https://github.com/ethereum-optimism/optimism/blob/6d9d43cb6f2721c9638be9fe11d261c0602beb54/op-node/node/api.go#L63
# start it back up
cast rpc --rpc-url "$l2_node_url" admin_startSequencer 0xd1a48f5c16f86a30caa51f22c916d213cc8fdc28465e577e396bd1eea91acdf0

# stop the propooser
kurtosis service stop "$kurtosis_enclave_name" op-proposer-001
