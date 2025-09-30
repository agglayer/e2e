#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

# l1 variables
l1_preallocated_mnemonic=${L1_PREALLOCATED_MNEMONIC:-"giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"}
l1_preallocated_private_key=$(cast wallet private-key --mnemonic "$l1_preallocated_mnemonic")
l2_admin_private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
l2_admin_address=$(cast wallet address --private-key "$l2_admin_private_key")
l2_trusted_sequencer="0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"

# infra variables
kurtosis_enclave_name=${AGL_ENCLAVE_NAME:-"upgradeV12"}
kurtosis_repo_tag=${CDK_KURTOSIS_PACKAGE_TAG:-"v0.4.18"}

docker_network_name="kt-$kurtosis_enclave_name"


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

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && git fetch && git stash push -m \"kurtosise\" && git checkout v12.1.0 && git stash pop"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npm i"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo DEPLOYER_PRIVATE_KEY="$l2_admin_private_key" > /opt/zkevm-contracts/.env"

rollup_manager_address=$(1| | jq -r .polygonRollupManagerAddress)
upgrade_parameters='{
    "tagSCPreviousVersion": "v1.1.0",
    "rollupManagerAddress": "'$rollup_manager_address'",
    "timelockDelay": 3600,
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

# monitor timelock?


while [ $(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' 'isOperationReady(bytes32)(bool)' $(echo 1 | cast to-bytes32)") == "false" ]; do
    echo "Operation not ready. Retrying in 10 seconds..."
    sleep 10
done

executeData=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && cat /opt/zkevm-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .executeData")
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' '$executeData'"

