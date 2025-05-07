#!/bin/env bash

source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"


curl -s https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/chains/op-succinct-real-prover.yml > tmp-pp.yml

# TODO we should make sure that op_succinct can run with PP
# Create a yaml file that has the pp consense configured but ideally a real prover
yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.sp1_prover_key = $sp1key |
.args.consensus_contract_type = "pessimistic" |
.deployment_stages.deploy_op_succinct = false
' tmp-pp.yml > initial-pp.yml

# TEMPORARY TO SPEED UP TESTING
yq -y --arg sp1key "$SP1_NETWORK_KEY" --arg sl "$SPAN_LENGTH_OVERRIDE" '
.optimism_package.chains[0].batcher_params.max_channel_duration = 2 |
.args.op_succinct_proposer_span_proof = $sl |
.args.l1_seconds_per_slot = 1' initial-pp.yml > _t; mv _t initial-pp.yml

# Spin up the network
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "initial-pp.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"


echo '   #                     ######                                        #######                     '
echo '  # #   #####  #####     #     #  ####  #      #      #    # #####        #    #   # #####  ###### '
echo ' #   #  #    # #    #    #     # #    # #      #      #    # #    #       #     # #  #    # #      '
echo '#     # #    # #    #    ######  #    # #      #      #    # #    #       #      #   #    # #####  '
echo '####### #    # #    #    #   #   #    # #      #      #    # #####        #      #   #####  #      '
echo '#     # #    # #    #    #    #  #    # #      #      #    # #            #      #   #      #      '
echo '#     # #####  #####     #     #  ####  ###### ######  ####  #            #      #   #      ###### '


contracts_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

agglayer_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep agglayer[^-] | awk '{print $1}')
agglayer_container_name=agglayer--$agglayer_uuid

aggkit_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep aggkit-001 | awk '{print $1}')
aggkit_container_name=aggkit-001--$aggkit_uuid

# TODO there is an issue here. the aggkit prover should have the -001 suffix
aggkit_prover_uuid=$(kurtosis enclave inspect --full-uuids pp-to-fep-test | grep aggkit-prover[^-] | awk '{print $1}')
aggkit_prover_container_name=aggkit-prover--$aggkit_prover_uuid

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


echo '#     #                                      ######                                     '
echo '#     # #####  #####    ##   ##### ######    #     #  ####  #      #      #    # #####  '
echo '#     # #    # #    #  #  #    #   #         #     # #    # #      #      #    # #    # '
echo '#     # #    # #    # #    #   #   #####     ######  #    # #      #      #    # #    # '
echo '#     # #####  #    # ######   #   #         #   #   #    # #      #      #    # #####  '
echo '#     # #      #    # #    #   #   #         #    #  #    # #      #      #    # #      '
echo ' #####  #      #####  #    #   #   ######    #     #  ####  ###### ######  ####  #     '

# Set the urls
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)
l2_rpc_url=$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)
l2_node_url=$(kurtosis port print $kurtosis_enclave_name op-cl-1-op-node-op-geth-001 http)

# TOOD We should add some pause here to make sure that there are some bridges sent... we can check that the pending certificate is not null
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.'

# Stopping the bridge spammer for our own sanity
kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001

# TODO use this in the future to block the upgrade This should be `null`... Basically we want to make sure everything is settled
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.'

# FIXME We should probably stop the agg kit at this point? Is there a risk that a certificate is sent / settled during the upgrade process
# I assume we should stop the sequencer before we update it
cast rpc --rpc-url "$l2_node_url" admin_stopSequencer > stop.out

# We're going to update the aggkit now so that we don't settle additional certs.
docker exec -u root -it "$aggkit_container_name" sed -i 's/Mode="PessimisticProof"/Mode="AggchainProof"/' /etc/aggkit/config.toml
kurtosis service stop "$kurtosis_enclave_name" aggkit-001

# Get the current rollup type count and make sure that it make sense
rollup_type_count=$(cast call --rpc-url "$l1_rpc_url" $(jq -r '.polygonRollupManagerAddress' combined.json) 'rollupTypeCount() external view returns (uint32)')
if [[ $rollup_type_count -ne 2 ]]; then
    printf "Expected a rollup type count of 2 but got %d\n" "$rollup_type_count"
    exit 1
fi

# Create the upgrade data
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


echo '###                                                   ######                                     '
echo ' #  #    # # ##### #   ##   #      # ###### ######    #     #  ####  #      #      #    # #####  '
echo ' #  ##   # #   #   #  #  #  #      #     #  #         #     # #    # #      #      #    # #    # '
echo ' #  # #  # #   #   # #    # #      #    #   #####     ######  #    # #      #      #    # #    # '
echo ' #  #  # # #   #   # ###### #      #   #    #         #   #   #    # #      #      #    # #####  '
echo ' #  #   ## #   #   # #    # #      #  #     #         #    #  #    # #      #      #    # #      '
echo '### #    # #   #   # #    # ###### # ###### ######    #     #  ####  ###### ######  ####  #    '


docker cp $contracts_container_name:/opt/contract-deploy/create_new_rollup.json initialize_rollup.json

# TRYFIX - Maybe we can read the block number from the last settled PP
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


echo '######                                       ###                             '
echo '#     # ###### #      #####   ####  #   #     #  #    # ###### #####    ##   '
echo '#     # #      #      #    # #    #  # #      #  ##   # #      #    #  #  #  '
echo '#     # #####  #      #    # #    #   #       #  # #  # #####  #    # #    # '
echo '#     # #      #      #####  #    #   #       #  #  # # #      #####  ###### '
echo '#     # #      #      #      #    #   #       #  #   ## #      #   #  #    # '
echo '######  ###### ###### #       ####    #      ### #    # #      #    # #    # '


# TODO figure out what the input should be
# https://github.com/ethereum-optimism/optimism/blob/6d9d43cb6f2721c9638be9fe11d261c0602beb54/op-node/node/api.go#L63
# start it back up
cast rpc --rpc-url "$l2_node_url" admin_startSequencer $(cat stop.out)

# stop the proposer
# TODO check to see why this isn't running anymore
if [[ false ]]; then
    kurtosis service stop "$kurtosis_enclave_name" op-proposer-001
fi

# TODO there are some env variables that seem unnecessary now
# server
docker run \
       --rm -d \
       --name op-succinct-server \
       --network kt-$kurtosis_enclave_name \
       -e "NETWORK_PRIVATE_KEY=$SP1_NETWORK_KEY" \
       -e "NETWORK_RPC_URL=https://rpc.production.succinct.xyz" \
       -e "AGG_PROOF_MODE=compressed" \
       -e "L2_RPC=http://op-el-1-op-geth-op-node-001:8545" \
       -e "L2_NODE_RPC=http://op-cl-1-op-node-op-geth-001:8547" \
       -e "PRIVATE_KEY=0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31" \
       -e "L1_RPC=http://el-1-geth-lighthouse:8545" \
       -e "OP_SUCCINCT_MOCK=false" \
       -e "L1_BEACON_RPC=http://cl-1-lighthouse-geth:4000" \
       -e "ETHERSCAN_API_KEY=" \
       -e "PORT=3000" \
       ghcr.io/agglayer/op-succinct/succinct-proposer:v1.2.12-agglayer

# Proposer
# TODO the db seems to be created automatically. We should remove thie template in kurtosis
docker run \
       --rm -d \
       --name op-succinct-proposer \
       --network kt-$kurtosis_enclave_name \
       -e "VERIFIER_ADDRESS=0xf22E2B040B639180557745F47aB97dFA95B1e22a" \
       -e "PRIVATE_KEY=0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31" \
       -e "L1_BEACON_RPC=http://cl-1-lighthouse-geth:4000" \
       -e "ETHERSCAN_API_KEY=" \
       -e "OP_SUCCINCT_AGGLAYER=true" \
       -e "L2_NODE_RPC=http://op-cl-1-op-node-op-geth-001:8547" \
       -e "L1_RPC=http://el-1-geth-lighthouse:8545" \
       -e "MAX_CONCURRENT_PROOF_REQUESTS=1" \
       -e "MAX_CONCURRENT_WITNESS_GEN=1" \
       -e "OP_SUCCINCT_SERVER_URL=http://op-succinct-server:3000" \
       -e "L2OO_ADDRESS=0x414e9E227e4b589aF92200508aF5399576530E4e" \
       -e "MAX_BLOCK_RANGE_PER_SPAN_PROOF=$SPAN_LENGTH_OVERRIDE" \
       -e "OP_SUCCINCT_MOCK=false" \
       -e "L2_RPC=http://op-el-1-op-geth-op-node-001:8545" \
       ghcr.io/agglayer/op-succinct/op-proposer:v1.2.12-agglayer


docker exec -u root -it "$aggkit_prover_container_name" sed -i 's/proposer-endpoint.*/proposer-endpoint = "http:\/\/op-succinct-proposer:8545"/' /etc/aggkit/aggkit-prover-config.toml
kurtosis service stop "$kurtosis_enclave_name" aggkit-prover
kurtosis service start "$kurtosis_enclave_name" aggkit-prover

kurtosis service start "$kurtosis_enclave_name" aggkit-001

kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001


################################################################################

exit

# TODO use this in the future to block the upgrade This should be `null`
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.'

cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq '.'
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata'  | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o'

cast abi-encode --packed 'f(bytes,uint64,uint64,uint64,bytes)' 0x00 1 1 1 0xFFFFFFFFFFFFFF

cast tx --rpc-url http://$(kurtosis port print pp-to-fep-test  el-1-geth-lighthouse rpc) 0x793b0deb01dc2e6d679752a636e8774d4ba6c433beee3609855d5b78cefe560e

docker stop op-succinct-proposer
docker stop op-succinct-server

