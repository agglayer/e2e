#!/usr/bin/env bats

setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}
    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print "$kurtosis_enclave_name" el-1-geth-lighthouse rpc)"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    l2_node_url=${L2_NODE_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-cl-1-op-node-op-geth-001 http)"}
    rollup_manager_address=${ROLLUP_MANAGER_ADDRESS:-"0x6c6c009cC348976dB4A908c92B24433d4F6edA43"}
    rollup_address=${ROLLUP_ADDRESS:-"0x414e9E227e4b589aF92200508aF5399576530E4e"}
    optimistic_mode_manager_pvk=${OPTIMISTIC_MODE_MANAGER_PVK:-"0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"}
    timeout=${TIMEOUT:-5000}
    retry_interval=${RETRY_INTERVAL:-50}
    
    load "../../core/helpers/agglayer-certificates-checks.bash"
    agglayer_certificates_checks_setup
}

@test "Enable OptimisticMode" {
contracts_uuid=$(kurtosis enclave inspect --full-uuids "$kurtosis_enclave_name" | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

wait_for_non_null_cert

# Stopping the bridge spammer for our own sanity
if docker ps | grep -q "bridge-spammer-001"; then
    echo "Stopping bridge spammer..."
    kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001 || { echo "Error: Failed to stop spammer"; exit 1; }
    echo "Spammer stopped."
else
    echo "bridge-spammer-001 does not exist in enclave $kurtosis_enclave_name. Skipping stop operation."
fi

print_settlement_info

wait_for_null_cert

echo "Checking last settled certificate"
latest_settled_l2_block=$(cast rpc --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata'  | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
echo "$latest_settled_l2_block"

cast rpc --rpc-url "$l2_node_url" admin_stopSequencer > stop.out
kurtosis service stop "$kurtosis_enclave_name" aggkit-001

jq --arg ra "$rollup_address" --arg opmanpvk "$optimistic_mode_manager_pvk" \
   '.rollupAddress = $ra | .optimisticModeManagerPvk = $opmanpvk' \
   assets/parameters.json > parameters.json


docker cp parameters.json "$contracts_container_name":/opt/zkevm-contracts/tools/aggchainFEPTools/changeOptimisticMode
docker exec -w /opt/zkevm-contracts -it "$contracts_container_name" npx hardhat run tools/aggchainFEPTools/changeOptimisticMode/changeOptimisticMode.ts --network localhost

# The optimistic mode is enabled in the above script. The below command is left for reference to manually enable optimisticMode by calling the rollup contract.
# sovereignadmin address, also the optimisticModeManager address
# "zkevm_l2_sovereignadmin_address": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
# "zkevm_l2_sovereignadmin_private_key": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0",
# cast send $rollup_address "enableOptimisticMode()" --rpc-url "$l1_rpc_url" --private-key "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"

# Check optimisticMode enabled
# Call the optimisticMode() function using cast
if [[ 'true' == $(cast call "$rollup_address" 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url") ]]; then
    echo "Success: optimisticMode() returned true"
else
    echo "Error: optimisticMode() did not return true"
    exit 1
fi

# TODO figure out what the input should be
# https://github.com/ethereum-optimism/optimism/blob/6d9d43cb6f2721c9638be9fe11d261c0602beb54/op-node/node/api.go#L63
# start it back up
cast rpc --rpc-url "$l2_node_url" admin_startSequencer "$(cat stop.out)"
kurtosis service start "$kurtosis_enclave_name" aggkit-001
kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001
}

@test "Disable OptimisticMode" {
contracts_uuid=$(kurtosis enclave inspect --full-uuids "$kurtosis_enclave_name" | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

wait_for_non_null_cert

# Stopping the bridge spammer for our own sanity
if docker ps | grep -q "bridge-spammer-001"; then
    echo "Stopping bridge spammer..."
    kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001 || { echo "Error: Failed to stop spammer"; exit 1; }
    echo "Spammer stopped."
else
    echo "bridge-spammer-001 does not exist in enclave $kurtosis_enclave_name. Skipping stop operation."
fi

print_settlement_info

wait_for_null_cert

kurtosis service stop "$kurtosis_enclave_name" aggkit-001

jq --arg ra "$rollup_address" '.rollupAddress = $ra | .optimisticMode = false' assets/parameters.json  > parameters.json

docker cp parameters.json "$contracts_container_name":/opt/zkevm-contracts/tools/aggchainFEPTools/changeOptimisticMode
docker exec -w /opt/zkevm-contracts -it "$contracts_container_name" npx hardhat run tools/aggchainFEPTools/changeOptimisticMode/changeOptimisticMode.ts --network localhost

if [[ 'false' == $(cast call "$rollup_address" 'optimisticMode()(bool)' --rpc-url "$l1_rpc_url") ]]; then
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
}