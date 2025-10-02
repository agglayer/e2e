#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

# kurtosis
kurtosis_enclave_name="upgradeV12"
kurtosis_repo_tag="v0.4.18"
docker_network_name="kt-$kurtosis_enclave_name"

# preallocated variables to make things coherent and easier
l1_preallocated_mnemonic="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")
l2_admin_private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
l2_admin_address=$(cast wallet address --private-key "$l2_admin_private_key")
l2_trusted_sequencer="0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"


 ##                                               ##                      ##              ####                                                    
 ##                       ##                      ##                      ##              ####                                             ##     
 ##                       ##                                              ##                ##                                             ##     
 ##   ##:##    ####.########### .####.  :#####. ####    :#####.      :###.## .####: ##.###: ##    .####. ##    #### #:##: .####: ##.#### #######  
 ##  ##: ##    ################.######.######## ####   ########     :#######.######:#######:##   .######.:##  ## ########.######:####### #######  
 ##:##:  ##    #####.     ##   ###  #####:  .:#   ##   ##:  .:#     ###  #####:  :#####  #####   ###  ### ##: ##.##.##.####:  :#####  :##  ##     
 ####    ##    ####       ##   ##.  .####### .    ##   ##### .      ##.  .############.  .####   ##.  .## ###:## ## ## ############    ##  ##     
 #####   ##    ####       ##   ##    ##.######:   ##   .######:     ##    ############    ####   ##    ## .## #  ## ## ############    ##  ##     
 ##.###  ##    ####       ##   ##.  .##   .: ##   ##      .: ##     ##.  .####      ##.  .####   ##.  .##  ####. ## ## ####      ##    ##  ##     
 ##  ##: ##:  #####       ##.  ###  ####:.  :##   ##   #:.  :##     ###  ######.  :####  #####:  ###  ###  :###  ## ## #####.  :###    ##  ##.    
 ##  :##  #########       #####.######.########################     :#######.##############:#####.######.   ##   ## ## ##.#########    ##  #####  
 ##   ###  ###.####       .#### .####. . ####  ########. ####        :###.## .#####:##.###: .#### .####.    ##.  ## ## ## .#####:##    ##  .####  
                                                                                    ##                     :##                                    
                                                                                    ##                    ###:                                    
                                                                                    ##                    ###                                     

kurtosis run --enclave "$kurtosis_enclave_name" "github.com/0xPolygon/kurtosis-cdk@$kurtosis_repo_tag" --args-file=fep.yml


                                                                                                                      ##         
                           ##                           ##                                                            ##         
                           ##                           ##                                                            ##         
    ####: .####. ##.#### #########.####:####     ####:####### :#####.     ##    ####.###:  :###:####.####:####   :###.## .####:  
  #######.######.####### ####################  ######################     ##    #########:.#################### :#######.######: 
  ##:  :####  ######  :##  ##   ###.   #:  :## ##:  :#  ##   ##:  .:#     ##    #####  ######  ######.   #:  :#####  #####:  :## 
 ##.     ##.  .####    ##  ##   ##      :#######.       ##   ##### .      ##    ####.  .####.  .####      :#######.  .########## 
 ##      ##    ####    ##  ##   ##    .#########        ##   .######:     ##    ####    ####    ####    .#########    ########## 
 ##.     ##.  .####    ##  ##   ##    ## .  ####.       ##      .: ##     ##    ####.  .####.  .####    ## .  ####.  .####       
  ##:  .####  #####    ##  ##.  ##    ##:  ### ##:  .#  ##.  #:.  :##     ##:  ######  ######  #####    ##:  ######  ######.  :# 
  #######.######.##    ##  #######    ######## #######  #############      ##############:.#########    ########:#######.####### 
    ####: .####. ##    ##  .######      ###.##   ####:  .####. ####         ###.####.###:  :###:####      ###.## :###.## .#####: 
                                                                                  ##       #.  :##                               
                                                                                  ##       ######                                
                                                                                  ##       :####:                                

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && git fetch && git stash push -m \"kurtosis\" && git checkout v12.1.0 && git stash pop"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npm i"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo DEPLOYER_PRIVATE_KEY="$l2_admin_private_key" > /opt/zkevm-contracts/.env"

rollup_manager_address=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cat /opt/zkevm/combined-001.json | jq -r .polygonRollupManagerAddress")
timelock_ctrl_address=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cat /opt/zkevm/combined-001.json | jq -r .timelockContractAddress")

min_delay=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_ctrl_address' 'getMinDelay()' | cast to-dec")
# version=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$rollup_manager_address' 'ROLLUP_MANAGER_VERSION()' | cast to-ascii")

upgrade_parameters='{
    "tagSCPreviousVersion": "Jesus_told_me_thats_unused",
    "rollupManagerAddress": "'$rollup_manager_address'",
    "timelockDelay": '$min_delay',
    "timelockSalt": "",
    "maxFeePerGas": "",
    "maxPriorityFeePerGas": "",
    "multiplierGas": "",
    "timelockAdminAddress": "'$l2_admin_address'",
    "unsafeMode": true,
    "initializeAgglayerGateway": {
        "multisigRole": "'$l2_admin_address'",
        "signersToAdd": [
            {
                "addr": "'$l2_trusted_sequencer'",
                "url": "http://op-el-1-op-geth-op-node-001:8545"
            }
        ],
        "newThreshold": 1
    },
    "forkParams": {
        "rpc": "http://el-1-geth-lighthouse:8545",
        "network": "localhost"
    }
}'

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo '$upgrade_parameters' > /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_parameters.json"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npx hardhat run ./upgrade/upgradeV12/upgradeV12.ts --network localhost"

scheduleData=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .scheduleData")
timelock_address=$(curl -s $(kurtosis port print $kurtosis_enclave_name contracts-001 http)//opt/zkevm/combined.json | jq -r .timelockContractAddress)

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' '$scheduleData'"

# function hashOperationBatch(
#         address[] calldata targets,
#         uint256[] calldata values,
#         bytes[] calldata payloads,
#         bytes32 predecessor,
#         bytes32 salt
#     ) public pure virtual returns (bytes32 hash) {
#         return keccak256(abi.encode(targets, values, payloads, predecessor, salt));
#     }

targets=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.targets | \"[\" + (map(.) | join(\", \")) + \"]\"'")
values=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.values | \"[\" + (map(.) | join(\", \")) + \"]\"'")
payloads=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.payloads | \"[\" + (map(.) | join(\", \")) + \"]\"'")
predecessor=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .decodedScheduleData.predecessor")
salt=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .decodedScheduleData.salt")

operationId=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' 'hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)' '$targets' '$values' '$payloads' '$predecessor' '$salt'")

while [ $(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' 'isOperationReady(bytes32)(bool)' '$operationId'") == "false" ]; do
    echo "Operation not ready. Retrying in 10 seconds..."
    sleep 10
done

executeData=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .executeData")
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' '$executeData'"


-- ADD ROUTES TO AGL

--. selectedOpSuccinctConfigName

-- addopsuccinct config, execute with new params
# update rollup

add_rollup_type_json='{
    "type": "EOA",
    "consensusContract": "AggchainFEP",
    "description": "V12 upgrade",
    "deployerPvtKey": "$l2_admin_private_key",
    "programVKey": "0x374ee73950cdb07d1b8779d90a8467df232639c13f9536b03f1ba76a2aa5dac6",
    "polygonRollupManagerAddress": "$rollup_manager_address"
}'

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo '$add_rollup_type_json' > /opt/zkevm-contracts/tools/addRollupType/add_rollup_type.json"
# Workaround for HardhatEthersProvider.resolveName not implemented error
# Use a different approach to avoid the resolveName issue
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npx hardhat run ./tools/addRollupType/addRollupType.ts --network localhost" || {
    echo "First attempt failed, trying alternative approach..."
    kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npx hardhat run ./tools/addRollupType/addRollupType.ts --network hardhat"
}
