#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"

# If condition for CI to determines whether to use mock prover or network prover
if [[ $MOCK_MODE == true ]]; then
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/chains/op-succinct.yml" > initial-fep.yml
else
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/chains/op-succinct-real-prover.yml" > tmp-fep.yml

    # Create a yml with FEP consensus with a real SP1 Key if needed
    yq -y --arg sp1key "$SP1_NETWORK_KEY" '
    .args.sp1_prover_key = $sp1key
    ' tmp-fep.yml > initial-fep.yml

    # TEMPORARY TO SPEED UP TESTING
    yq -y --arg sp1key "$SP1_NETWORK_KEY" --arg rpi "$RANGE_PROOF_INTERVAL_OVERRIDE" '
    .optimism_package.chains[0].batcher_params.max_channel_duration = 2 |
    .args.op_succinct_range_proof_interval = $rpi |
    .args.l1_seconds_per_slot = 1' initial-fep.yml > _t; mv _t initial-fep.yml
fi


# Spin up the network
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "initial-fep.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"


echo '███████ ███    ██  █████  ██████  ██      ███████      ██████  ██████  ████████ ██ ███    ███ ██ ███████ ████████ ██  ██████ ███    ███  ██████  ██████  ███████ '
echo '██      ████   ██ ██   ██ ██   ██ ██      ██          ██    ██ ██   ██    ██    ██ ████  ████ ██ ██         ██    ██ ██      ████  ████ ██    ██ ██   ██ ██      '
echo '█████   ██ ██  ██ ███████ ██████  ██      █████       ██    ██ ██████     ██    ██ ██ ████ ██ ██ ███████    ██    ██ ██      ██ ████ ██ ██    ██ ██   ██ █████   '
echo '██      ██  ██ ██ ██   ██ ██   ██ ██      ██          ██    ██ ██         ██    ██ ██  ██  ██ ██      ██    ██    ██ ██      ██  ██  ██ ██    ██ ██   ██ ██      '
echo '███████ ██   ████ ██   ██ ██████  ███████ ███████      ██████  ██         ██    ██ ██      ██ ██ ███████    ██    ██  ██████ ██      ██  ██████  ██████  ███████ '
                                                                                                                                                                 

contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

# Get the deployment details
docker cp $contracts_container_name:/opt/zkevm/combined.json .

rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)

# Set the urls
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)
l2_rpc_url=$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)
l2_node_url=$(kurtosis port print $kurtosis_enclave_name op-cl-1-op-node-op-geth-001 http)
# The timeout might be too large, but it should allow sufficient time for the certificates to settle.
# TODO this timeout approach allows us to run the script without needing to manually check and continue the next steps. But there might be better approaches.
timeout=5000
retry_interval=50

check_non_null() [[ -n "$1" && "$1" != "null" ]]
check_null() [[ "$1" == "null" ]]

function wait_for_non_null_cert() {
    echo "Checking non-null certificate..."
    start=$((SECONDS))
    while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_non_null "$output"; do
        [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for non-null certificate"; exit 1; }
        echo "Retrying..."
        sleep $retry_interval
    done
    echo "Non-null latest pending certificate: $output"
}

function wait_for_null_cert() {
    echo "Checking null last pending certificate..."
    start=$((SECONDS))
    while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_null "$output"; do
        [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for null certificate"; exit 1; }
        echo "Retrying: $output"
        sleep $retry_interval
    done
    echo "Null latest pending certificate confirmed"
}

function print_settlement_info() {
    # We should loop until this number is greater than 1... This indicated a finalized L1 settlement
    printf "The latest block number recorded on L1: "
    cast call --rpc-url "$l1_rpc_url" $(jq -r '.rollupAddress' combined.json) 'latestBlockNumber() external view returns (uint256)'

    # We can make sure there is an event as well
    echo "VerifyPessimisticStateTransition(uint32,bytes32,bytes32,bytes32,bytes32,bytes32,address) events recorded: "
    cast logs --json  --rpc-url "$l1_rpc_url" --address $(jq -r '.polygonRollupManagerAddress' combined.json)  0xdf47e7dbf79874ec576f516c40bc1483f7c8ddf4b45bfd4baff4650f1229a711 | jq '.'

    # We can check for an 'OutputProposed(bytes32,uint256,uint256,uint256)' event to make sure the block number has advanced
    echo "OutputProposed(bytes32,uint256,uint256,uint256) events recorded: "
    cast logs --json  --rpc-url "$l1_rpc_url" --address  $(jq -r '.rollupAddress' combined.json) 0xa7aaf2512769da4e444e3de247be2564225c2e7a8f74cfe528e46e17d24868e2| jq '.'
}

wait_for_non_null_cert

# Stopping the bridge spammer for our own sanity
echo "Stopping bridge spammer..."
kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001 || { echo "Error: Failed to stop spammer"; exit 1; }
echo "Spammer stopped."

print_settlement_info

wait_for_null_cert

echo "Checking last settled certificate"
latest_settled_l2_block=$(cast rpc --rpc-url $(kurtosis port print $kurtosis_enclave_name agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata'  | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
echo $latest_settled_l2_block

cast rpc --rpc-url "$l2_node_url" admin_stopSequencer > stop.out
kurtosis service stop "$kurtosis_enclave_name" aggkit-001

rollup_address=$(jq -r '.rollupAddress' combined.json)

jq --arg ra "$rollup_address" '.rollupAddress = $ra' assets/parameters.json  > parameters.json

docker cp parameters.json $contracts_container_name:/opt/zkevm-contracts/tools/aggchainFEPTools/changeOptimisticMode
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/aggchainFEPTools/changeOptimisticMode/changeOptimisticMode.ts --network localhost

# The optimistic mode is enabled in the above script. The below command is left for reference to manually enable optimisticMode by calling the rollup contract.
# sovereignadmin address, also the optimisticModeManager address
# "zkevm_l2_sovereignadmin_address": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
# "zkevm_l2_sovereignadmin_private_key": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0",
# cast send $rollup_address "enableOptimisticMode()" --rpc-url "$l1_rpc_url" --private-key "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"

# Check optimisticMode enabled
# Call the optimisticMode() function using cast
if [[ 'true' == $(cast call $rollup_address 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url") ]]; then
    echo "Success: optimisticMode() returned true"
else
    echo "Error: optimisticMode() did not return true"
    exit 1
fi

# TODO figure out what the input should be
# https://github.com/ethereum-optimism/optimism/blob/6d9d43cb6f2721c9638be9fe11d261c0602beb54/op-node/node/api.go#L63
# start it back up
cast rpc --rpc-url "$l2_node_url" admin_startSequencer $(cat stop.out)
kurtosis service start "$kurtosis_enclave_name" aggkit-001

kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001


echo '██████  ██ ███████  █████  ██████  ██      ███████      ██████  ██████  ████████ ██ ███    ███ ██ ███████ ████████ ██  ██████     ███    ███  ██████  ██████  ███████ '
echo '██   ██ ██ ██      ██   ██ ██   ██ ██      ██          ██    ██ ██   ██    ██    ██ ████  ████ ██ ██         ██    ██ ██          ████  ████ ██    ██ ██   ██ ██      '
echo '██   ██ ██ ███████ ███████ ██████  ██      █████       ██    ██ ██████     ██    ██ ██ ████ ██ ██ ███████    ██    ██ ██          ██ ████ ██ ██    ██ ██   ██ █████   '
echo '██   ██ ██      ██ ██   ██ ██   ██ ██      ██          ██    ██ ██         ██    ██ ██  ██  ██ ██      ██    ██    ██ ██          ██  ██  ██ ██    ██ ██   ██ ██      '
echo '██████  ██ ███████ ██   ██ ██████  ███████ ███████      ██████  ██         ██    ██ ██      ██ ██ ███████    ██    ██  ██████     ██      ██  ██████  ██████  ███████ '

wait_for_non_null_cert

kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001 || { echo "Error: Failed to stop spammer"; exit 1; }

print_settlement_info

wait_for_null_cert

kurtosis service stop "$kurtosis_enclave_name" aggkit-001

jq --arg ra "$rollup_address" '.rollupAddress = $ra | .optimisticMode = false' assets/parameters.json  > parameters.json

docker cp parameters.json $contracts_container_name:/opt/zkevm-contracts/tools/aggchainFEPTools/changeOptimisticMode
docker exec -w /opt/zkevm-contracts -it $contracts_container_name npx hardhat run tools/aggchainFEPTools/changeOptimisticMode/changeOptimisticMode.ts --network localhost

if [[ 'false' == $(cast call $rollup_address 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url") ]]; then
    echo "Success: optimisticMode() returned false"
else
    echo "Error: optimisticMode() did not return false"
    exit 1
fi

kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001
kurtosis service start "$kurtosis_enclave_name" aggkit-001

wait_for_non_null_cert

print_settlement_info

wait_for_null_cert

print_settlement_info

exit
