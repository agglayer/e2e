#!/bin/env bash

# kurtosis
kurtosis_enclave_name="upgradeV12"
kurtosis_repo_tag="1d26548a5917f24282fc97ecb25594238c2a4104"  # main at 16/Oct/2025
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

kurtosis run --enclave "$kurtosis_enclave_name" "github.com/0xPolygon/kurtosis-cdk@$kurtosis_repo_tag" --args-file=validium.yml

contracts_url="$(kurtosis port print $kurtosis_enclave_name contracts-001 http)"

l2_admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_admin_private_key')"
l2_admin_address=$(cast wallet address --private-key "$l2_admin_private_key")
l2_trusted_sequencer="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_sequencer_address')"


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

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && git fetch && git stash push -m \"kurtosis\" && git checkout v12.1.0 && git stash pop"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && npm i"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo DEPLOYER_PRIVATE_KEY=\"$l2_admin_private_key\" > /opt/agglayer-contracts/.env"

rollup_manager_address=$(curl -s "${contracts_url}/opt/output/combined-001.json" | jq -r '.polygonRollupManagerAddress')
timelock_ctrl_address=$(curl -s "${contracts_url}/opt/output/combined-001.json" | jq -r '.timelockContractAddress')

# Get current min delay
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

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo '$upgrade_parameters' > /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_parameters.json"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && npx hardhat run ./upgrade/upgradeV12/upgradeV12.ts --network localhost"

scheduleData=$(curl -s "${contracts_url}/opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json" | jq -r '.scheduleData')
timelock_address=$(curl -s "${contracts_url}/opt/output/combined-001.json" | jq -r '.timelockContractAddress')

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

targets=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && cat /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.targets | \"[\" + (map(.) | join(\", \")) + \"]\"'")
values=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && cat /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.values | \"[\" + (map(.) | join(\", \")) + \"]\"'")
payloads=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && cat /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r '.decodedScheduleData.payloads | \"[\" + (map(.) | join(\", \")) + \"]\"'")
predecessor=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && cat /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .decodedScheduleData.predecessor")
salt=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/agglayer-contracts/ && cat /opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json | jq -r .decodedScheduleData.salt")

# Get operation id (hashOperationBatch)
echo "Calling hashOperationBatch with params: $targets, $values, $payloads, $predecessor, $salt"
operationId=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' 'hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)' '$targets' '$values' '$payloads' '$predecessor' '$salt'")
echo "Operation id: $operationId"

# wait for operation to be ready
while [ "$(kurtosis service exec $kurtosis_enclave_name contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' 'isOperationReady(bytes32)(bool)' '$operationId'")" == "false" ]; do
    echo "Operation not ready. Retrying in 10 seconds..."
    sleep 10
done

# Execute operation
executeData=$(curl -s "${contracts_url}/opt/agglayer-contracts/upgrade/upgradeV12/upgrade_output.json" | jq -r '.executeData')
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$timelock_address' '$executeData'"


                                                                                 ##                                           
               ##      ##                                     ##                 ##          ##:  :####   ###                 
               ##      ##                                     ##                 ##          ##    ####   ##                  
               ##      ##                                     ##                             :##  ##:## :##:                  
   ####   :###.## :###.##      :####   :###:## :###:##   ####:##.####  :####   ####   ##.####:##  ##:##.##:   .####: ##    ## 
  ###### :#######:#######      ###### .#######.####### ##############  ######  ####   ####### ## .## #####   .######::##  ##  
  #:  :#####  ######  ###      #:  :#####  ######  ### ##:  :####  :## #:  :##   ##   ###  :####::## #####   ##:  :## ##: ##. 
   #  .####.  .##       :#######.  .####.  .####.     ##    ##  :#####   ##   ##    ####::## #####:  ######## ###:##  
  #########    ####    ##     .#########    ####    ####      ##    ##.#######   ##   ##    ##:####: ##::##  ######## .## #   
 ## .  ####.  .####.  .##     ## .  ####.  .####.  .####.     ##    #### .  ##   ##   ##    ##.####. ##  ##  ##        ####.  
 ##:  ######  ######  ###     ##:  ######  ######  ### ##:  .###    ####:  ###   ##   ##    ## ####  ##  :## ###.  :#  :###   
 ########:#######:#######     ########.#######.####### #########    ####################    ## ####  ##   ## .#######   ##    
   ###.## :###.## :###.##       ###.## :###:## :###:##   ####:##    ##  ###.############    ##  ##   ##   :## .#####:   ##.   
                                       #.  :## #.  :##                                                                 :##    
                                       ######  ######                                                                 ###:    
                                        ####:  :####:                                                                 ###     

agglayergw_address=$(curl -s "$(kurtosis port print $kurtosis_enclave_name contracts-001 http)"/opt/zkevm/combined.json | jq -r .aggLayerGatewayAddress)

# https://github.com/agglayer/provers/releases/tag/v1.4.2
defaultAggchainSelector=0x00060001
newAggchainVKey=0x374ee73950cdb07d1b8779d90a8467df232639c13f9536b03f1ba76a2aa5dac6
echo "Adding default Aggchain VKey: $defaultAggchainSelector, $newAggchainVKey"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'addDefaultAggchainVKey(bytes4,bytes32)()' '$defaultAggchainSelector' '$newAggchainVKey'"

echo "kurtosis_enclave_name: $kurtosis_enclave_name"
echo "agglayergw_address: $agglayergw_address"
echo "defaultAggchainSelector: $defaultAggchainSelector"
echo "newAggchainVKey: $newAggchainVKey"

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'getDefaultAggchainVKey(bytes4)(bytes32)' '0x00060001'"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'defaultAggchainVKeys(bytes4)(bytes32)' '0x00060001'"

kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'getDefaultAggchainVKey(bytes4)(bytes32)' '0x00040001'"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'defaultAggchainVKeys(bytes4)(bytes32)' '0x00040001'"


               ##      ##                    ##:  :####   ###                 
               ##      ##                    ##    ####   ##                  
               ##      ##                    :##  ##:## :##:                  
   ####   :###.## :###.##     ##.###: ##.###::##  ##:##.##:   .####: ##    ## 
  ###### :#######:#######     #######:#######:## .## #####   .######::##  ##  
  #:  :#####  ######  ###     ###  ######  #####::## #####   ##:  :## ##: ##. 
    #######.  .####.  .##     ##.  .####.  .####::## #####:  ######## ###:##  
  #########    ####    ##     ##    ####    ##:####: ##::##  ######## .## #   
 ## .  ####.  .####.  .##     ##.  .####.  .##.####. ##  ##  ##        ####.  
 ##:  ######  ######  ###     ###  ######  ### ####  ##  :## ###.  :#  :###   
 ########:#######:#######     #######:#######: ####  ##   ## .#######   ##    
   ###.## :###.## :###.##     ##.###: ##.###:   ##   ##   :## .#####:   ##.   
                              ##      ##                               :##    
                              ##      ##                              ###:    
                              ##      ##                              ###     
                                                                              

# Lets retrieve current selector and vkey from agglayer, so we can retrieve current verifier address used
current_pp_selector=$(kurtosis service exec "$kurtosis_enclave_name" agglayer "agglayer vkey-selector")
current_pp_vkey=$(kurtosis service exec "$kurtosis_enclave_name" agglayer "agglayer vkey")

echo "Agglayer component current PP Selector: $current_pp_selector, Current PP VKey: $current_pp_vkey"

# from selector, les retrieve vkey and verifier from AgglayerGW
vkey_route=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast call --rpc-url http://el-1-geth-lighthouse:8545 --json '$agglayergw_address' 'pessimisticVKeyRoutes(bytes4)(address,bytes32)' '$current_pp_selector'")
vkey_route_verifier=$(echo "$vkey_route" | jq -r '.[0]')
vkey_route_vkey=$(echo "$vkey_route" | jq -r '.[1]')
echo "AgglayerGW contract current PP VKey: $vkey_route_vkey, AgglayerGW contract current PP Verifier: $vkey_route_verifier"

# Just as sanity check, vkey/selector provided by agglayer component must match with vkey/selector from AgglayerGW contract
if [ "$current_pp_vkey" != "$vkey_route_vkey" ]; then
    echo "ERROR: Vkey does not match"
    exit 1
else
    echo "OK Vkey matches, verifier: $vkey_route_verifier"
fi

# https://github.com/agglayer/agglayer/releases/tag/v0.4.0-rc.13
# this is the selector and vkey for this release
pessimisticVKeySelector=0x00000008
pessimisticVKey=0x000055f14384bdb5bb092fd7e5152ec31856321c5a30306ab95836bdf5cdb639
# Verifier is the same that we already had, since SP1 v5 is still used (it may change if we were using a newer SP1 version)
# https://github.com/succinctlabs/sp1-contracts/blob/main/contracts/src/v5.0.0/SP1VerifierPlonk.sol
echo "Adding new Pessimistic VKey: $pessimisticVKeySelector, $pessimisticVKey, $vkey_route_verifier"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$agglayergw_address' 'addPessimisticVKeyRoute(bytes4,address,bytes32)()' '$pessimisticVKeySelector' '$vkey_route_verifier' '$pessimisticVKey'"


                                                                                                #### ####                ########                     ###########:   
                                  ##                                                            #### ####                ########                     #############  
                                  ##                                                              ##   ##                   ##                          ##  ##  :##: 
    ####:##.#### .####:  :####  ####### .####:      ##.####  .####: ##      ##     ##.#### .####. ##   ##   ##    ####.###: ####    ####.###:  .####:   ##  ##   :## 
  ##############.######: ###### #######.######:     ####### .######:##.    .##     #######.######.##   ##   ##    #########:##:##  ## #######:.######:  ##  ##   .## 
  ##:  :####.   ##:  :## #:  :##  ##   ##:  :##     ###  :####:  :## #: ## :#      ###.   ###  #####   ##   ##    #####  ##### ##: ##.###  #####:  :##  ##  ##    ## 
 ##.     ##     ########  :#####  ##   ########     ##    ##########:#:.##.:#:     ##     ##.  .####   ##   ##    ####.  .#### ###:## ##.  .##########  ##  ##    ## 
 ##      ##     ########.#######  ##   ########     ##    ########## # :##:##      ##     ##    ####   ##   ##    ####    #### .## #  ##    ##########  ##  ##   .## 
 ##.     ##     ##      ## .  ##  ##   ##           ##    ####       ## ## ##      ##     ##.  .####   ##   ##    ####.  .####  ####. ##.  .####        ##  ##   :## 
  ##:  .###     ###.  :###:  ###  ##.  ###.  :#     ##    #####.  :# ###::##       ##     ###  #####:  ##:  ##:  ######  #####  :###  ###  ######.  :#  ##  ##  :##: 
  #########     .###############  #####.#######     ##    ##.####### :##..##:      ##     .######.########## ##############:##   ##   #######:.####################  
    ####:##      .#####:  ###.##  .#### .#####:     ##    ## .#####: .##  ##       ##      .####. .####.####  ###.####.###: ##   ##.  ##.###:  .#####:###########:   
                                                                                                                    ##          :##   ##                             
                                                                                                                    ##         ###:   ##                             
                                                                                                                    ##         ###    ##                             

# 0x0 fields are not used but needs to be set
add_rollup_type_json='{
  "type": "EOA",
  "consensusContract": "AggchainFEP",
  "consensusContractAddress": "",
  "polygonRollupManagerAddress": "'$rollup_manager_address'",
  "verifierAddress": "0x0000000000000000000000000000000000000000",
  "description": "Type: AggchainFEPv3",
  "forkID": 0,
  "deployerPvtKey": "'$l2_admin_private_key'",
  "maxFeePerGas": "",
  "maxPriorityFeePerGas": "",
  "multiplierGas": "",
  "genesisRoot": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "programVKey": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "outputPath": "add_rollup_type_output_fep_v3.json"
}'

echo "Adding new rollup type for FEP v3"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "echo '$add_rollup_type_json' > /opt/zkevm-contracts/tools/addRollupType/add_rollup_type.json"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cd /opt/zkevm-contracts/ && npx hardhat run ./tools/addRollupType/addRollupType.ts --network localhost"

new_rollup_type_id=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cat /opt/zkevm-contracts/tools/addRollupType/add_rollup_type_output_fep_v3.json | jq -r '.rollupTypeID'")


           ##                                                                                          ##            
           ##                                                                                          ##            
   #####.####### .####. ##.###:         ####: .####. ## #:##:##.###:  .####. ##.####  .####: ##.#### ####### :#####. 
 ###############.######.#######:      #######.######.###############:.######.####### .######:####### ############### 
 ##:  .:#  ##   ###  ######  ###      ##:  :####  #####.##.#####  ######  ######  :####:  :#####  :##  ##   ##:  .:# 
 ##### .   ##   ##.  .####.  .##     ##.     ##.  .#### ## ####.  .####.  .####    ############    ##  ##   ##### .  
  ######:  ##   ##    ####    ##     ##      ##    #### ## ####    ####    ####    ############    ##  ##   .######: 
       ##  ##   ##.  .####.  .##     ##.     ##.  .#### ## ####.  .####.  .####    ####      ##    ##  ##      .: ## 
 #:.  :##  ##.  ###  ######  ###      ##:  .####  ##### ## #####  ######  #####    #####.  :###    ##  ##.  #:.  :## 
 ########  #####.######.#######:      #######.######.## ## #########:.######.##    ##.#########    ##  ############# 
   ####    .#### .####. ##.###:         ####: .####. ## ## ####.###:  .####. ##    ## .#####:##    ##  .####. ####   
                        ##                                   ##                                                      
                        ##                                   ##                                                      
                        ##                                   ##                                                      

# TO CONFIRM IF WE NEED TO STOP SERVICES
kurtosis service stop "$kurtosis_enclave_name" bridge-spammer-001
sleep 10
kurtosis service stop "$kurtosis_enclave_name" aggkit-001-bridge
kurtosis service stop "$kurtosis_enclave_name" aggkit-001
kurtosis service stop "$kurtosis_enclave_name" aggkit-prover-001
kurtosis service stop "$kurtosis_enclave_name" agglayer
kurtosis service stop "$kurtosis_enclave_name" agglayer-prover
kurtosis service stop "$kurtosis_enclave_name" op-succinct-proposer-001


                                             ##                          #### ####                    
                                             ##                          #### ####                    
                                             ##                            ##   ##                    
 ##    ####.###:  :###:####.####:####   :###.## .####:      ##.#### .####. ##   ##   ##    ####.###:  
 ##    #########:.#################### :#######.######:     #######.######.##   ##   ##    #########: 
 ##    #####  ######  ######.   #:  :#####  #####:  :##     ###.   ###  #####   ##   ##    #####  ### 
 ##    ####.  .####.  .####      :#######.  .##########     ##     ##.  .####   ##   ##    ####.  .## 
 ##    ####    ####    ####    .#########    ##########     ##     ##    ####   ##   ##    ####    ## 
 ##    ####.  .####.  .####    ## .  ####.  .####           ##     ##.  .####   ##   ##    ####.  .## 
 ##:  ######  ######  #####    ##:  ######  ######.  :#     ##     ###  #####:  ##:  ##:  ######  ### 
  ##############:.#########    ########:#######.#######     ##     .######.########## ##############: 
   ###.####.###:  :###:####      ###.## :###.## .#####:     ##      .####. .####.####  ###.####.###:  
         ##       #.  :##                                                                    ##       
         ##       ######                                                                     ##       
         ##       :####:                                                                     ##       

# function updateRollup(
#         ITransparentUpgradeableProxy rollupContract,
#         uint32 newRollupTypeID,
#         bytes memory upgradeData
# )
upgradeData=$(cast calldata "upgradeFromPreviousFEP()")
rollup_address=$(kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cat /opt/zkevm/combined-001.json | jq -r '.rollupAddress'")
echo "Calling updateRollup with params: $rollup_address, $new_rollup_type_id, $upgradeData"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$rollup_manager_address' 'updateRollup(address,uint32,bytes)' '$rollup_address' '$new_rollup_type_id' '$upgradeData'"


                         ##    ####                      ##          :####             ####        ##:  :####                              
                         ##    ####                      ##          #####             ####   ##   ##    ####                              
                         ##      ##                      ##          ##                  ##   ##   :##  ##:##                              
   ####: ##.####  :####  ##.###: ##    .####:       :###.## .####: #######:####  ##    #### #######:##  ##:##   ##:.####: ##    ## :#####. 
  ######:#######  ###### #######:##   .######:     :#######.######:############# ##    #### ####### ## .## ##  ##:.######::##  ## ######## 
 ##:  :#####  :## #:  :#####  #####   ##:  :##     ###  #####:  :##  ##   #:  :####    ####   ##    ##::## ##:##: ##:  :## ##: ##.##:  .:# 
 ##########    ##  :#######.  .####   ########     ##.  .##########  ##    :#######    ####   ##    ##::## ####   ######## ###:## ##### .  
 ##########    ##.#########    ####   ########     ##    ##########  ##  .#########    ####   ##    :####: #####  ######## .## #  .######: 
 ##      ##    #### .  ####.  .####   ##           ##.  .####        ##  ## .  ####    ####   ##    .####. ##.### ##        ####.    .: ## 
 ###.  :###    ####:  ######  #####:  ###.  :#     ###  ######.  :#  ##  ##:  #####:  #####:  ##.    ####  ##  ##:###.  :#  :###  #:.  :## 
  #########    #################:#####.#######     :#######.#######  ##  ######## #################  ####  ##  :##.#######   ##   ######## 
   #####:##    ##  ###.####.###: .#### .#####:      :###.## .#####:  ##    ###.##  ###.##.####.####   ##   ##   ###.#####:   ##.  . ####   
                                                                                                                             ##            
                                                                                                                           ###:            
                                                                                                                           ###             
# TODO: It should be already enabled, so some previous step may be missing something.
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$rollup_address' 'enableUseDefaultVkeysFlag()'"


                                                                 ##                                                                ##            
               ##      ##                                        ##                                                         :####  ##            
               ##      ##                                        ##                     ##                                  #####  ##            
               ##      ##                                                               ##                                  ##                   
   ####   :###.## :###.##      :#####.##    ##   ####:   ####: ####   ##.####    ####:#######        ####: .####. ##.#### ###########    :###:## 
  ###### :#######:#######     ##########    ## ####### ####### ####   #######  ##############      #######.######.####### ###########   .####### 
  #:  :#####  ######  ###     ##:  .:###    ## ##:  :# ##:  :#   ##   ###  :## ##:  :#  ##         ##:  :####  ######  :##  ##     ##   ###  ### 
    #######.  .####.  .##     ##### . ##    ####.     ##.        ##   ##    ####.       ##        ##.     ##.  .####    ##  ##     ##   ##.  .## 
  #########    ####    ##     .######:##    ####      ##         ##   ##    ####        ##        ##      ##    ####    ##  ##     ##   ##    ## 
 ## .  ####.  .####.  .##        .: ####    ####.     ##.        ##   ##    ####.       ##        ##.     ##.  .####    ##  ##     ##   ##.  .## 
 ##:  ######  ######  ###     #:.  :####:  ### ##:  .# ##:  .#   ##   ##    ## ##:  .#  ##.        ##:  .####  #####    ##  ##     ##   ###  ### 
 ########:#######:#######     ######## ####### ####### #################    ## #######  #####      #######.######.##    ##  ##  ########.####### 
   ###.## :###.## :###.##     . ####    ###.##   ####:   ####:##########    ##   ####:  .####        ####: .####. ##    ##  ##  ######## :###:## 
                                                                                                                                         #.  :## 
                                                                                                                                         ######  
                                                                                                                                          ####:  

op_succinct_image=ghcr.io/agglayer/op-succinct/op-succinct:v3.1.0-agglayer

opsuccinctl2ooconfig=$(docker run --rm -it \
  --network $docker_network_name \
  --name op-succinct-tmp \
  --env L1_RPC=http://el-1-geth-lighthouse:8545 \
  --env L1_BEACON_RPC=http://el-1-geth-lighthouse:8545 \
  --env L2_RPC=http://op-el-1-op-geth-op-node-001:8545 \
  --env L2_NODE_RPC=http://op-cl-1-op-node-op-geth-001:8547 \
  --env OP_SUCCINCT_MOCK="false" \
  $op_succinct_image \
  bash -c "fetch-l2oo-config --output-dir /tmp/output && cat /tmp/output/opsuccinctl2ooconfig.json"
)


# function addOpSuccinctConfig(
#     bytes32 _configName,
#     bytes32 _rollupConfigHash,
#     bytes32 _aggregationVkey,
#     bytes32 _rangeVkeyCommitment
# )
config_name=$(cast keccak $op_succinct_image)
rollup_config_hah=$(echo $opsuccinctl2ooconfig | jq -r '.rollupConfigHash')
aggregation_vkey=$(echo $opsuccinctl2ooconfig | jq -r '.aggregationVkey')
range_vkey_commitment=$(echo $opsuccinctl2ooconfig | jq -r '.rangeVkeyCommitment')

echo "Calling addOpSuccinctConfig with params: $config_name, $rollup_config_hah, $aggregation_vkey, $range_vkey_commitment"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$rollup_address' 'addOpSuccinctConfig(bytes32,bytes32,bytes32,bytes32)' '$config_name' '$rollup_config_hah' '$aggregation_vkey' '$range_vkey_commitment'"


                                                                                     ##                                                                ##            
               ####                                                                  ##                                                         :####  ##            
               ####                     ##                                           ##                     ##                                  #####  ##            
                 ##                     ##                                                                  ##                                  ##                   
   #####. .####: ##    .####:    ####:#######      :#####.##    ##   ####:   ####: ####   ##.####    ####:#######        ####: .####. ##.#### ###########    :###:## 
 ########.######:##   .######: ##############     ##########    ## ####### ####### ####   #######  ##############      #######.######.####### ###########   .####### 
 ##:  .:###:  :####   ##:  :## ##:  :#  ##        ##:  .:###    ## ##:  :# ##:  :#   ##   ###  :## ##:  :#  ##         ##:  :####  ######  :##  ##     ##   ###  ### 
 ##### . ##########   ##########.       ##        ##### . ##    ####.     ##.        ##   ##    ####.       ##        ##.     ##.  .####    ##  ##     ##   ##.  .## 
  ######:##########   ##########        ##        .######:##    ####      ##         ##   ##    ####        ##        ##      ##    ####    ##  ##     ##   ##    ## 
       ####      ##   ##      ##.       ##           .: ####    ####.     ##.        ##   ##    ####.       ##        ##.     ##.  .####    ##  ##     ##   ##.  .## 
 #:.  :#####.  :###:  ###.  :# ##:  .#  ##.       #:.  :####:  ### ##:  .# ##:  .#   ##   ##    ## ##:  .#  ##.        ##:  .####  #####    ##  ##     ##   ###  ### 
 ########.############.####### #######  #####     ######## ####### ####### #################    ## #######  #####      #######.######.##    ##  ##  ########.####### 
   ####   .#####:.#### .#####:   ####:  .####     . ####    ###.##   ####:   ####:##########    ##   ####:  .####        ####: .####. ##    ##  ##  ######## :###:## 
                                                                                                                                                             #.  :## 
                                                                                                                                                             ######  
                                                                                                                                                              ####:  

echo "Selecteing OpSuccinctConfig: $config_name"
kurtosis service exec "$kurtosis_enclave_name" contracts-001 "cast send --private-key '$l2_admin_private_key' --rpc-url http://el-1-geth-lighthouse:8545 '$rollup_address' 'selectOpSuccinctConfig(bytes32)()' '$config_name'"


                                                                                                  ##            
                                                                                                  ##            
 ##.####  .####: ##      ##        ####: .####. ## #:##:##.###:  .####. ##.####  .####: ##.#### ####### :#####. 
 ####### .######:##.    .##      #######.######.###############:.######.####### .######:####### ############### 
 ###  :####:  :## #: ## :#       ##:  :####  #####.##.#####  ######  ######  :####:  :#####  :##  ##   ##:  .:# 
 ##    ##########:#:.##.:#:     ##.     ##.  .#### ## ####.  .####.  .####    ############    ##  ##   ##### .  
 ##    ########## # :##:##      ##      ##    #### ## ####    ####    ####    ############    ##  ##   .######: 
 ##    ####       ## ## ##      ##.     ##.  .#### ## ####.  .####.  .####    ####      ##    ##  ##      .: ## 
 ##    #####.  :# ###::##        ##:  .####  ##### ## #####  ######  #####    #####.  :###    ##  ##.  #:.  :## 
 ##    ##.####### :##..##:       #######.######.## ## #########:.######.##    ##.#########    ##  ############# 
 ##    ## .#####: .##  ##          ####: .####. ## ## ####.###:  .####. ##    ## .#####:##    ##  .####. ####   
                                                        ##                                                      
                                                        ##                                                      
                                                        ##                                                      
agglayer_image=ghcr.io/agglayer/agglayer:0.4.0-rc.15
aggkit_image=ghcr.io/agglayer/aggkit:0.7.0-beta10
aggkit_prover_image=ghcr.io/agglayer/aggkit-prover:1.4.2

kurtosis service update --image $agglayer_image $kurtosis_enclave_name agglayer-prover

# Agglayer state is stored in /etc/agglayer, which is not preserved by doing a kurtosis service update
agglayer_etc_agglayer=$(docker inspect agglayer--"$(kurtosis service inspect $kurtosis_enclave_name agglayer --full-uuid | grep UUID | sed  's/.*: //')" | jq -r .[0].Mounts[0].Source)
docker run -it \
    --detach \
    --network $docker_network_name \
    --name agglayer \
    -v $agglayer_etc_agglayer:/etc/agglayer \
    "$agglayer_image" \
    agglayer \
    run \
    --cfg \
    /etc/agglayer/agglayer-config.toml

# Op-succinct-proposer
# Raw config name here, not the keccak hash
kurtosis service update --image $op_succinct_image --env "OP_SUCCINCT_CONFIG_NAME=$op_succinct_image" $kurtosis_enclave_name op-succinct-proposer-001

# Aggkit-prover
kurtosis service update --image $aggkit_prover_image $kurtosis_enclave_name aggkit-prover-001

# Aggkit state is stored in /etc/aggkit and /tmp, which is not preserved by doing a kurtosis service update
aggkit_etc_aggkit=$(docker inspect aggkit-001--"$(kurtosis service inspect $kurtosis_enclave_name aggkit-001 --full-uuid | grep UUID | sed  's/.*: //')" | jq -r '.[0].Mounts[] | select(.Destination == "/etc/aggkit") | .Source')
aggkit_tmp=$(docker inspect aggkit-001--"$(kurtosis service inspect $kurtosis_enclave_name aggkit-001 --full-uuid | grep UUID | sed  's/.*: //')" | jq -r '.[0].Mounts[] | select(.Destination == "/tmp") | .Source')

mkdir aggkit_tmp
sudo bash -c "cp -r \"$aggkit_tmp\"/* aggkit_tmp/"
sudo chmod -R 777 aggkit_tmp
docker run -it \
    --detach \
    --network $docker_network_name \
    --name aggkit-001 \
    -v $aggkit_etc_aggkit:/etc/aggkit \
    -v aggkit_tmp:/tmp \
    "$aggkit_image" \
    run \
    --cfg=/etc/aggkit/config.toml \
    --components=aggsender,aggoracle

# To review: something may be wrong on kurtosis, because when updating services, aggkit fails, we need to set all files on /etc/aggkit
# kurtosis service update --image $aggkit_image --files "/etc/aggkit/:aggkit-config-artifact|aggkit-sequencer-keystore|aggkit-claimtxmanager-keystore|aggoracle-keystore" upgradeV12 aggkit-001

kurtosis service start "$kurtosis_enclave_name" bridge-spammer-001
