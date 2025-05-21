#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
# Change these image versions to the needed images
aggkit_image="ghcr.io/agglayer/aggkit:0.3.0-beta6"
agglayer_image="ghcr.io/agglayer/agglayer:0.3.0-rc.20"
aggkit_prover_image="$AGGKIT_PROVER_IMAGE"
zkevm_contracts_image="jhkimqd/zkevm-contracts:v10.1.0-rc.5-fork.12"

curl -s https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/chains/op-succinct-real-prover.yml > tmp-pp.yml
# curl -s https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/chains/op-succinct.yml > tmp-pp.yml

# TODO we should make sure that op_succinct can run with PP
# Create a yaml file that has the pp consense configured but ideally a real prover
yq -y --arg sp1key "$SP1_NETWORK_KEY" --arg aggkit_image "$aggkit_image" --arg agglayer_image "$agglayer_image" --arg aggkit_prover_image "$aggkit_prover_image" --arg zkevm_contracts_image "$zkevm_contracts_image" '
.args.sp1_prover_key = $sp1key |
.args.consensus_contract_type = "pessimistic" |
.args.aggkit_image = $aggkit_image |
.args.agglayer_image = $agglayer_image |
.args.aggkit_prover_image = $aggkit_prover_image |
.args.zkevm_contracts_image = $zkevm_contracts_image |
.args.pp_vkey_hash = "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be" |
.args.aggchain_vkey_hash = "0x1e82b1193be48c5c6ba14dda2bcc29ab4d3dc3a2379198ac1f8571040d0a7a4d" |
.deployment_stages.deploy_op_succinct = false
' tmp-pp.yml > initial-pp.yml

# TEMPORARY TO SPEED UP TESTING
yq -y --arg sp1key "$SP1_NETWORK_KEY" --arg rpi "$RANGE_PROOF_INTERVAL_OVERRIDE" '
.optimism_package.chains[0].batcher_params.max_channel_duration = 2 |
.args.op_succinct_range_proof_interval = $rpi |
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
# The timeout might be too large, but it should allow sufficient time for the certificates to settle.
# TODO this timeout approach allows us to run the script without needing to manually check and continue the next steps. But there might be better approaches.
timeout=2000
retry_interval=20

check_non_null() [[ -n "$1" && "$1" != "null" ]]
check_null() [[ "$1" == "null" ]]

# TOOD We should add some pause here to make sure that there are some bridges sent... we can check that the pending certificate is not null
echo "Checking non-null certificate..."
start=$((SECONDS))
while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_non_null "$output"; do
  [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for non-null certificate"; exit 1; }
  echo "Retrying..."
  sleep $retry_interval
done
echo "Non-null latest pending certificate: $output"

# Stopping the bridge spammer for our own sanity
echo "Stopping bridge spammer..."
kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001 || { echo "Error: Failed to stop spammer"; exit 1; }
echo "Spammer stopped."

# TODO use this in the future to block the upgrade This should be `null`... Basically we want to make sure everything is settled
echo "Checking null last pending certificate..."
start=$((SECONDS))
while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_null "$output"; do
  [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for null certificate"; exit 1; }
  echo "Retrying: $output"
  sleep $retry_interval
done
echo "Null latest pending certificate confirmed"

echo "Checking last settled certificate"
latest_settled_l2_block=$(cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata'  | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
echo $latest_settled_l2_block

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
# current_unsafe_block=$(cast rpc --rpc-url "$l2_node_url" optimism_outputAtBlock 0x0 | jq '.syncStatus.unsafe_l2.number')

cast rpc --rpc-url "$l2_node_url" optimism_outputAtBlock $(printf "0x%x" $latest_settled_l2_block) | jq '.' > output.json

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
      "operatorFeeScalar": 0,
      "operatorFeeConstant": 0
    }
  },
  block_time:                 .block_time,
  max_sequencer_drift:        .max_sequencer_drift,
  seq_window_size:            .seq_window_size,
  channel_timeout:            .channel_timeout,
  "granite_channel_timeout": 50,
  l1_chain_id:                .l1_chain_id,
  l2_chain_id:                .l2_chain_id,

  regolith_time:              .regolith_time,
  canyon_time:                .canyon_time,
  delta_time:                 .delta_time,
  ecotone_time:               .ecotone_time,
  fjord_time:                 .fjord_time,
  granite_time:               .granite_time,
  holocene_time:              .holocene_time,
  isthmus_time:               .isthmus_time,

  batch_inbox_address:        .batch_inbox_address,
  deposit_contract_address:   .deposit_contract_address,
  l1_system_config_address:   .l1_system_config_address,
  protocol_versions_address:  "0x0000000000000000000000000000000000000000",
  interop_message_expiry_window: 3600,
  "alt_da": null,
  "chain_op_config": {
    "eip1559Elasticity": "0x6",
    "eip1559Denominator": "0x32",
    "eip1559DenominatorCanyon": "0xfa"
  }
}' | sed 's/"scalar": "0x01/"scalar": "0x1/' | head -c -1 > rollup.json

rollup_config_hash=0x$(sha256sum rollup.json | awk '{print $1}')

# TODO make sure the submission interval of 1 makes sense
# TODO figure out if the range vkey committment and aggregation key can be read from somewhere
# TODO block time should come from the rollup config
jq \
    --arg rch "$rollup_config_hash" \
    --argjson latest_settled_block "$latest_settled_l2_block" \
    --slurpfile o output.json \
   '.aggchainParams.initParams.l2BlockTime = 1 |
    .aggchainParams.initParams.startingOutputRoot = $o[0].outputRoot |
    .aggchainParams.initParams.startingBlockNumber = $latest_settled_block |
    .aggchainParams.initParams.startingTimestamp = $o[0].blockRef.timestamp |
    .aggchainParams.initParams.submissionInterval = 1 |
    .aggchainParams.initParams.aggregationVkey = "0x00c34e1ea92b8e3708fb2213142e746caa75a01308f817af6310976012a6fe40" |
    .aggchainParams.initParams.rangeVkeyCommitment = "0x35882a76205af8c12eaeea7551ff8dbc392dc2a95b0f7f31660a5468237d4434" |
    .aggchainParams.initParams.rollupConfigHash = $rch |
    .realVerifier = true |
    .consensusContractName = "AggchainFEP"
'  initialize_rollup.json > _t; mv _t initialize_rollup.json

docker cp initialize_rollup.json $contracts_container_name:/opt/zkevm-contracts/tools/initializeRollup/
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/initializeRollup/initializeRollup.ts --network localhost

# FIXME - Temporary work around to make sure the default aggkey is configured
cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "addDefaultAggchainVKey(bytes4,bytes32)" "0x00010001" "0x1e82b1193be48c5c6ba14dda2bcc29ab4d3dc3a2379198ac1f8571040d0a7a4d"
# cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "addDefaultAggchainVKey(bytes4,bytes32)" "0x00000001" "4b7898a6472e298b19bee7254bc684525bce910466fc339c76d65af11e332e69"
# cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "addDefaultAggchainVKey(bytes4,bytes32)" "0x00000002" "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be"
# cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "updateDefaultAggchainVKey(bytes4,bytes32)" "0x00010001" "0x1e82b1193be48c5c6ba14dda2bcc29ab4d3dc3a2379198ac1f8571040d0a7a4d"
# cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "updateDefaultAggchainVKey(bytes4,bytes32)" "0x00000001" "4b7898a6472e298b19bee7254bc684525bce910466fc339c76d65af11e332e69"
# cast send --rpc-url "$l1_rpc_url" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "updateDefaultAggchainVKey(bytes4,bytes32)" "0x00000002" "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be"

if ! cast call --rpc-url "$l1_rpc_url" "0xf22E2B040B639180557745F47aB97dFA95B1e22a" "getDefaultAggchainVKey(bytes4)" "0x00010001"; then
    echo "Error: getDefaultAggchainVKey returned AggchainVKeyNotFound()"
    exit 1s
fi

# Save Rollup Information to a file.
cast call --json --rpc-url "$l1_rpc_url" "$rollup_manager_address" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "1" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > ./rollup-out.json

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

echo "Starting up aggkit service..."
kurtosis service start "$kurtosis_enclave_name" aggkit-001

docker compose up -d

kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001

################################################################################

exit

# TODO use this in the future to block the upgrade This should be `null`
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.'

cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq '.'
cast rpc --rpc-url $(kurtosis port print pp-to-fep-test agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata'  | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o'

cast abi-encode --packed 'f(bytes,uint64,uint64,uint64,bytes)' 0x00 1 1 1 0xFFFFFFFFFFFFFF

cast tx --rpc-url http://$(kurtosis port print pp-to-fep-test  el-1-geth-lighthouse rpc) 0x793b0deb01dc2e6d679752a636e8774d4ba6c433beee3609855d5b78cefe560e

docker compose down
# docker stop aggkit-prover-001
# docker stop op-succinct-proposer-001
# docker stop op-succinct-server

