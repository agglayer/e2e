#!/bin/bash

# shellcheck source=scenarios/common/load-env.sh
source ../common/load-env.sh
load_env

workdir=$(pwd)
docker_network="zkevm"
docker network create $docker_network


                                   ##                      ##                                                                                             
                                   ##                      ##                 ####                                        ##                              
                                   ##                      ##                 ####                                        ##                              
                                                                                ##                                        ##                              
 ##.###:  .####: ##.###### #:##: ####    :#####. :#####. ####    .####. ##.#### ##    .####:  :#####. :#####.     ##########   ##:.####: ##:  :#### #:##: 
 #######:.######:############### ####   ################ ####   .######.####### ##   .######:################     ##########  ##:.######: ##  ## ######## 
 ###  #####:  :#####.   ##.##.##   ##   ##:  .:###:  .:#   ##   ###  ######  :####   ##:  :####:  .:###:  .:#         :##:##:##: ##:  :##:##  ##:##.##.## 
 ##.  .############     ## ## ##   ##   ##### . ##### .    ##   ##.  .####    ####   ############# . ##### .         :##: ####   ######## ##..## ## ## ## 
 ##    ############     ## ## ##   ##   .######:.######:   ##   ##    ####    ####   ########.######:.######:       :##:  #####  ######## ##::## ## ## ## 
 ##.  .####      ##     ## ## ##   ##      .: ##   .: ##   ##   ##.  .####    ####   ##         .: ##   .: ##      :##:   ##.### ##       :####: ## ## ## 
 ###  ######.  :###     ## ## ##   ##   #:.  :###:.  :##   ##   ###  #####    ####:  ###.  :##:.  :###:.  :##     :##:    ##  ##:###.  :#  ####  ## ## ## 
 #######:.#########     ## ## ##################################.######.##    #######.#######################     ##########  :##.#######  ####  ## ## ## 
 ##.###:  .#####:##     ## ## ##########. ####  . ####  ######## .####. ##    ##.#### .#####:. ####  . ####       ##########   ###.#####:  :##:  ## ## ## 
 ##                                                                                                                                                       
 ##                                                                                                                                                       
 ##                                                                                                                                                       

# mainnet
(cd $workdir || exit 1) && mkdir -p erigon/datadir && cd erigon || exit 1
if [ ! -f "zkevm-mainnet-erigon-snapshot.tgz" ]; then
    # WARNING: THIS FILES TAKES 60GB OF DISK SPACE
    wget -c https://storage.googleapis.com/zkevm-mainnet-snapshots/zkevm-mainnet-erigon-snapshot.tgz
fi
# if datadir is empty, extract the snapshot
if [ -z "$(ls -A datadir)" ]; then
    # WARNING: UNCOMPRESSED FILES WILL TAKE AN EXTRA 150GB OF DISK SPACE
    tar xzvf zkevm-mainnet-erigon-snapshot.tgz -C "datadir"
    sudo chmod -R 777 datadir/
fi

docker run \
    -d \
    --rm \
    --network $docker_network \
    --name erigon \
    -p 8545:8545 \
    -v "$(pwd)"/datadir:/datadir \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    --config="./mainnet.yaml" --datadir="/datadir" --zkevm.l1-rpc-url=$L1_RPC

local_l2_rpc="http://localhost:8545"
docker_l2_rpc="http://erigon:8545"


 ##                                                                                          
 ##                                                                            ##            
 ##                                                                            ##            
 ##   ##:.####: ##    ##      :####     ####:   ####: .####. ##    ####.#### ####### :#####. 
 ##  ##:.######::##  ##       ######  ####### #######.######.##    ######### ############### 
 ##:##: ##:  :## ##: ##.      #:  :## ##:  :# ##:  :####  #####    #####  :##  ##   ##:  .:# 
 ####   ######## ###:##        :#######.     ##.     ##.  .####    ####    ##  ##   ##### .  
 #####  ######## .## #       .#########      ##      ##    ####    ####    ##  ##   .######: 
 ##.### ##        ####.      ## .  ####.     ##.     ##.  .####    ####    ##  ##      .: ## 
 ##  ##:###.  :#  :###       ##:  ### ##:  .# ##:  .####  #####:  #####    ##  ##.  #:.  :## 
 ##  :##.#######   ##        ######## ####### #######.######. #########    ##  ############# 
 ##   ###.#####:   ##.         ###.##   ####:   ####: .####.   ###.####    ##  .####. ####   
                   ##                                                                        
                 ###:                                                                        
                 ###                                                                         

(cd $workdir || exit 1) && mkdir -p keys

# create new wallets for sequencer and aggregator
sequencer=$(cast wallet new --json | jq .[0])
aggregator=$(cast wallet new --json | jq .[0])
aggoracle=$(cast wallet new --json | jq .[0])
echo $sequencer > keys/sequencer.json
echo $aggregator > keys/aggregator.json
echo $aggoracle > keys/aggoracle.json

sequencer_addr=$(cat keys/sequencer.json | jq -r .address)
sequencer_pkey=$(cat keys/sequencer.json | jq -r .private_key)
aggregator_addr=$(cat keys/aggregator.json | jq -r .address)
aggregator_pkey=$(cat keys/aggregator.json | jq -r .private_key)
aggoracle_pkey=$(cat keys/aggoracle.json | jq -r .private_key)

# create keystores for both
rm -f keys/sequencer.keystore && cast wallet import --private-key $sequencer_pkey --unsafe-password "secret" --keystore-dir keys/ sequencer.keystore
rm -f keys/aggregator.keystore && cast wallet import --private-key $aggregator_pkey --unsafe-password "secret" --keystore-dir keys/ aggregator.keystore
rm -f keys/aggoracle.keystore && cast wallet import --private-key $aggoracle_pkey --unsafe-password "secret" --keystore-dir keys/ aggoracle.keystore


    ####:     #####:       ##   ###                                     ##         
   ######     #######      ##   ##                                      ##         
  ##:  .#     ##  :##:     ## :##:                                      ##         
 ##           ##   :##     ##.##:                 ##.####  .####.  :###.## .####:  
 ##.          ##   .##     #####                  ####### .######.:#######.######: 
 ##           ##    ##     #####                  ###  :#####  ######  #####:  :## 
 ##           ##    ##     #####:                 ##    ####.  .####.  .########## 
 ##.          ##   .##     ##::##       #####     ##    ####    ####    ########## 
 ##           ##   :##     ##  ##       #####     ##    ####.  .####.  .####       
  ##:  .#     ##  :##:     ##  :##                ##    #####  ######  ######.  :# 
   ######     #######      ##   ##                ##    ##.######.:#######.####### 
    ####:     #####:       ##   :##               ##    ## .####.  :###.## .#####: 

cd $workdir || exit 1
mkdir -p cdk/data && chmod -R 777 cdk/data
cp configs/cdk-node-template.toml cdk/cdk-node.toml
cp keys/*.keystore cdk/
sed -i 's|REPLACE_L1_RPC|'$L1_RPC'|' cdk/cdk-node.toml
sed -i 's|REPLACE_L2_RPC|'$docker_l2_rpc'|' cdk/cdk-node.toml
# sed -i 's|REPLACE_AGGREGATOR_ADDRESS|'$aggregator_addr'|' cdk/cdk-node.toml

echo "Starting cdk-node..."
docker run \
    -d \
    --rm \
    -p 50081:50081 \
    --name cdk-node \
    --network $docker_network \
    -v "$(pwd)"/cdk:/etc/cdk \
    ghcr.io/0xpolygon/cdk:0.5.4 \
    cdk-node run --cfg=/etc/cdk/cdk-node.toml --components=sequence-sender,aggregator


                    ##                                                                                                                                           
                    ##                                                                                                                             :####         
                    ##                             ##                                                                                              #####         
                                                   ##                                                                                              ##            
 ## #:##: :####   ####   ##.#### ##.####  .####: #######      :#####. .####:  :###.####    ## .####: ##.####    ####: .####: ##.####        ####:####### :###:## 
 ######## ######  ####   ####### ####### .######:#######     ########.######::#########    ##.######:#######  #######.######:#######      ##############.####### 
 ##.##.## #:  :##   ##   ###  :#####  :####:  :##  ##        ##:  .:###:  :#####  #####    ####:  :#####  :## ##:  :###:  :#####.         ##:  :#  ##   ###  ### 
 ## ## ##  :#####   ##   ##    ####    ##########  ##        ##### . ##########.  .####    ############    ####.     ##########          ##.       ##   ##.  .## 
 ## ## ##.#######   ##   ##    ####    ##########  ##        .######:##########    ####    ############    ####      ##########          ##        ##   ##    ## 
 ## ## #### .  ##   ##   ##    ####    ####        ##           .: ####      ##.  .####    ####      ##    ####.     ##      ##          ##.       ##   ##.  .## 
 ## ## ####:  ###   ##   ##    ####    #####.  :#  ##.       #:.  :#####.  :####  #####:  ######.  :###    ## ##:  .####.  :###           ##:  .#  ##   ###  ### 
 ## ## ####################    ####    ##.#######  #####     ########.#######:####### #######.#########    ## #######.#########           #######  ##   .####### 
 ## ## ##  ###.############    ####    ## .#####:  .####     . ####   .#####: :###.##  ###.## .#####:##    ##   ####: .#####:##             ####:  ##    :###:## 
                                                                                   ##                                                                    #.  :## 
                                                                                   ##                                                                    ######  
                                                                                   ##                                                                    :####:  
(cd $workdir || exit 1) && rm -f configs/mainnet.yaml
docker cp erigon:/home/erigon/mainnet.yaml configs/
echo "zkevm.sequencer-block-seal-time: 3s" >> configs/mainnet.yaml
echo "zkevm.sequencer-batch-seal-time: 15s" >> configs/mainnet.yaml
echo "zkevm.sequencer-batch-verification-timeout: 30m" >> configs/mainnet.yaml
echo "zkevm.sequencer-timeout-on-empty-tx-pool: 250ms" >> configs/mainnet.yaml
echo "zkevm.executor-strict: false" >> configs/mainnet.yaml
echo "zkevm.data-stream-host: 0.0.0.0" >> configs/mainnet.yaml
echo "zkevm.data-stream-port: 6900" >> configs/mainnet.yaml


                    ##          
                    ##          
                    ##   ##     
                         ##     
##      ##:####   #### #######  
##.    .########  #### #######  
 #: ## :# #:  :##   ##   ##     
 #:.##.:#: :#####   ##   ##     
 # :##:##.#######   ##   ##     
 ## ## #### .  ##   ##   ##     
 ###::## ##:  ###   ##   ##.    
  ##..##:#####################  
  ##  ##   ###.##########.####  

cd $workdir || exit 1

pless_last_block=$(cast bn --rpc-url $local_l2_rpc)
zkevm_last_block=$(cast bn --rpc-url $L2_RPC)
while [ $pless_last_block -lt $zkevm_last_block ]; do
    pless_diff=$(($zkevm_last_block - $pless_last_block))
    echo "Pless last block: $pless_last_block, Zkevm last block: $zkevm_last_block | Pless is $pless_diff blocks behind"
    sleep 5
    pless_last_block=$(cast bn --rpc-url $local_l2_rpc)
    zkevm_last_block=$(cast bn --rpc-url $L2_RPC)
done
echo "Pless and Zkevm are fully synced at block $pless_last_block"

cdknode_l1infotree_block=$(echo "select max(num) from block;" | sqlite3 cdk/data/L1InfoTreeSync)
if [ -z "$cdknode_l1infotree_block" ]; then
    cdknode_l1infotree_block=0
fi
cdknode_aggregator_sync_block=$(echo "select max(block_num) from block;" | sqlite3 cdk/data/aggregator_sync_db.sqlite)
if [ -z "$cdknode_aggregator_sync_block" ]; then
    cdknode_aggregator_sync_block=0
fi
l1_last_block=$(cast bn --rpc-url $L1_RPC finalized)
# L1InfoTreeSync gets synced up to finalized
l1_diff_a=$(($l1_last_block - $cdknode_l1infotree_block))
# AggregatorSync gets close to finalized, but not exactly, my assumption is that it's get up to latest verification/sequencing block?
l1_diff_b=$(($l1_last_block - $cdknode_aggregator_sync_block))
while [ $l1_diff_a -gt 0 ] || [ $l1_diff_b -gt 25 ]; do
    echo "L1 finalized block: $l1_last_block | CDK-NODE L1InfoTreeSync block: $cdknode_l1infotree_block ($l1_diff_a behind) | CDK-NODE AggregatorSync block: $cdknode_aggregator_sync_block ($l1_diff_b behind)"
    # Sleep for a whole L1 block time
    sleep 12
    cdknode_l1infotree_block=$(echo "select max(num) from block;" | sqlite3 cdk/data/L1InfoTreeSync)
    if [ -z "$cdknode_l1infotree_block" ]; then
        cdknode_l1infotree_block=0
    fi
    cdknode_aggregator_sync_block=$(echo " select max(block_num) from block;" | sqlite3 cdk/data/aggregator_sync_db.sqlite)
    if [ -z "$cdknode_aggregator_sync_block" ]; then
        cdknode_aggregator_sync_block=0
    fi
    l1_last_block=$(cast bn --rpc-url $L1_RPC finalized)
    l1_diff_a=$(($l1_last_block - $cdknode_l1infotree_block))
    l1_diff_b=$(($l1_last_block - $cdknode_aggregator_sync_block))
done
echo "L1 finalized block: $l1_last_block | CDK-NODE L1InfoTreeSync block: $cdknode_l1infotree_block | CDK-NODE AggregatorSync block: $cdknode_aggregator_sync_block"

                                                                                                           
 ####    .###                ##                    ##                         :####               ##       
 ####    ####                ##                    ##                         #####               ##       
   ##    #:##                ##                    ##                         ##                  ##       
   ##      ##         :#####.##.####  :####   :###.## .####. ##      ##     ####### .####. ##.######   ##: 
   ##      ##        ###############  ###### :#######.######.##.    .##     #######.######.#########  ##:  
   ##      ##        ##:  .:####  :## #:  :#####  ######  ### #: ## :#        ##   ###  ######.   ##:##:   
   ##      ##        ##### . ##    ##  :#######.  .####.  .##:#:.##.:#:       ##   ##.  .####     ####     
   ##      ##        .######:##    ##.#########    ####    ## # :##:##        ##   ##    ####     #####    
   ##      ##           .: ####    #### .  ####.  .####.  .## ## ## ##        ##   ##.  .####     ##.###   
   ##:     ##        #:.  :####    ####:  ######  ######  ### ###::##         ##   ###  #####     ##  ##:  
   #############     ##########    ##########:#######.######. :##..##:        ##   .######.##     ##  :##  
    ############     . ####  ##    ##  ###.## :###.## .####.  .##  ##         ##    .####. ##     ##   ### 

docker stop cdk-node
docker stop erigon
docker rm erigon
docker rm cdk-node

(cd $workdir || exit 1) && mkdir -p anvil
# Lets start anvil fork in 10' aprox (10' * 60s / 12s/block = 50 blocks)
fork_block=$(cast bn --rpc-url $L1_RPC)
echo "Starting anvil fork from block $fork_block"
docker run \
    -d \
    -p 8123:8545 \
    --rm \
    --name anvil \
    --network $docker_network \
    --entrypoint "anvil" \
    ghcr.io/foundry-rs/foundry:latest \
    --block-time 12 \
    --host 0.0.0.0 \
    --fork-url $L1_RPC \
    --no-rpc-rate-limit \
    --retries 3 \
    --timeout 120000 \
    --state ./anvil \
    --fork-block-number $fork_block

l1_shadow_fork_url="http://anvil:8545"
l1_shadow_fork_url_local="http://localhost:8123"


 ####   . ####:        :####               ##       
 ####   #######:       #####               ##       
   ##   #:.   ##       ##                  ##       
   ##         ##     ####### .####. ##.######   ##: 
   ##        :#      #######.######.#########  ##:  
   ##        ##        ##   ###  ######.   ##:##:   
   ##      .##:        ##   ##.  .####     ####     
   ##     .##:         ##   ##    ####     #####    
   ##    :##:          ##   ##.  .####     ##.###   
   ##:  :##:           ##   ###  #####     ##  ##:  
   #############       ##   .######.##     ##  :##  
    ############       ##    .####. ##     ##   ### 

# START ERIGON in sequencer mode
cd $workdir || exit 1
sed -i 's|^zkevm.l1-rpc-url: https://rpc.eth.gateway.fm/$|zkevm.l1-rpc-url: '$l1_shadow_fork_url'|' configs/mainnet.yaml
sed -i 's|zkevm.address-sequencer: "0x148Ee7dAF16574cD020aFa34CC658f8F3fbd2800"|zkevm.address-sequencer: "'$sequencer_addr'"|' configs/mainnet.yaml

(cd $workdir || exit 1) && docker run \
    --rm -d \
    --network $docker_network \
    --name erigon \
    -p 8545:8545 \
    --env CDK_ERIGON_SEQUENCER=1 \
    -v "$(pwd)"/erigon/datadir:/datadir \
    -v "$(pwd)"/configs:/etc/cdk-erigon \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    --config="/etc/cdk-erigon/mainnet.yaml" --datadir="/datadir" --zkevm.l1-rpc-url=$l1_shadow_fork_url

# Wait until out new sequencer generates new blocks
current_block=$(cast bn --rpc-url http://localhost:8545)
new_block=$current_block
while [ $new_block -eq $current_block ]; do
    echo "L2 current block: $current_block, waiting for new block to be produced..."
    sleep 5
    new_block=$(cast bn --rpc-url http://localhost:8545)
done
echo "Erigon generated a new block: $new_block (initial block: $current_block)"


                                                                                      ##                                                      
    ####:#####:  ##   ###                           ##                                ##                                           ##         
   ############# ##   ##                            ##                                ##   ##                                      ##         
  ##:  .###  :##:## :##:                            ##                                     ##                                      ##         
 ##      ##   :####.##:       ##.####  .####.  :###.## .####:      ##      ####.######## ####### .####:      ## #:##: .####.  :###.## .####:  
 ##.     ##   .#######        ####### .######.:#######.######:     ##.    .############# #######.######:     ########.######.:#######.######: 
 ##      ##    #######        ###  :#####  ######  #####:  :##      #: ## :# ###.     ##   ##   ##:  :##     ##.##.#####  ######  #####:  :## 
 ##      ##    #######:       ##    ####.  .####.  .##########     :#:.##.:#:##       ##   ##   ########     ## ## ####.  .####.  .########## 
 ##.     ##   .####::##       ##    ####    ####    ##########      # :##:## ##       ##   ##   ########     ## ## ####    ####    ########## 
 ##      ##   :####  ##       ##    ####.  .####.  .####            ## ## ## ##       ##   ##   ##           ## ## ####.  .####.  .####       
  ##:  .###  :##:##  :##      ##    #####  ######  ######.  :#      ###::##  ##       ##   ##.  ###.  :#     ## ## #####  ######  ######.  :# 
   ############# ##   ##      ##    ##.######.:#######.#######      :##..##: ##    #############.#######     ## ## ##.######.:#######.####### 
    ####:#####:  ##   :##     ##    ## .####.  :###.## .#####:      .##  ##  ##    ########.#### .#####:     ## ## ## .####.  :###.## .#####: 

# Lets start CDK-NODE again syncing from our L1 / L2 forks.
cd $workdir || exit 1
cp -f configs/cdk-node-template.toml cdk/cdk-node.toml
sed -i 's|REPLACE_L1_RPC|'$l1_shadow_fork_url'|' cdk/cdk-node.toml
sed -i 's|REPLACE_L2_RPC|'$docker_l2_rpc'|' cdk/cdk-node.toml
sed -i 's|REPLACE_AGGREGATOR_ADDRESS|'$aggregator_addr'|' cdk/cdk-node.toml
echo "Starting cdk-node..."
docker run \
    -d \
    -p 50081:50081 \
    --name cdk-node \
    --network $docker_network \
    -v "$(pwd)"/cdk:/etc/cdk \
    ghcr.io/0xpolygon/cdk:0.5.4 \
    cdk-node run --cfg=/etc/cdk/cdk-node.toml --components=sequence-sender,aggregator

cdknode_l1infotree_block=$(echo "select max(num) from block;" | sqlite3 cdk/data/L1InfoTreeSync)
cdknode_aggregator_sync_block=$(echo "select max(block_num) from block;" | sqlite3 cdk/data/aggregator_sync_db.sqlite)
l1_last_block=$(cast bn --rpc-url $l1_shadow_fork_url_local finalized)
echo "L1 finalized block: $l1_last_block | CDK-NODE L1InfoTreeSync block: $cdknode_l1infotree_block | CDK-NODE AggregatorSync block: $cdknode_aggregator_sync_block"

# Lets start our CDK-NODE to sequence/verify
sleep 60
sed -i 's|SyncModeOnlyEnabled = true|SyncModeOnlyEnabled = false|' cdk/cdk-node.toml
docker restart cdk-node


    ##                                                                                  
    ##                                                                                  
    ##                                                                    ##            
                                                                          ##            
  ####   ## #:##:##.###:  .####: ##.#### :#####. .####. ##.####  :####  ####### .####:  
  ####   ###############:.######:###############.######.#######  ###### #######.######: 
    ##   ##.##.#####  #####:  :#####.   ##:  .:####  ######  :## #:  :##  ##   ##:  :## 
    ##   ## ## ####.  .############     ##### . ##.  .####    ##  :#####  ##   ######## 
    ##   ## ## ####    ############     .######:##    ####    ##.#######  ##   ######## 
    ##   ## ## ####.  .####      ##        .: ####.  .####    #### .  ##  ##   ##       
    ##   ## ## #####  ######.  :###     #:.  :#####  #####    ####:  ###  ##.  ###.  :# 
 ########## ## #########:.#########     ########.######.##    ##########  #####.####### 
 ########## ## ####.###:  .#####:##     . ####   .####. ##    ##  ###.##  .#### .#####: 
                 ##                                                                     
                 ##                                                                     
                 ##                                                                     

rollupdata=$(cast call --rpc-url $l1_shadow_fork_url_local $AGGLAYER_MANAGER 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' $ROLLUP_ID --json)
rollup_address=$(echo $rollupdata | jq -r '.[0]')
rollup_admin=$(cast call $rollup_address 'admin()(address)' --rpc-url $l1_shadow_fork_url_local)

## Grant Sequencer role
# Impersonate admin account to grant permissions
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $rollup_admin
# Set our test account as the trusted sequencer
cast send --unlocked --from $rollup_admin --rpc-url $l1_shadow_fork_url_local $ROLLUP_ADDRESS 'setTrustedSequencer(address)' $sequencer_addr
# Stop impersonation
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $rollup_admin

# Mint to new sequencer address
unknown_address=0xbC9f74b3b14f460a6c47dCdDFd17411cBc7b6c53
amount_to_mint=$(cast to-hex "$(cast to-wei 100)")
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $unknown_address
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $unknown_address $amount_to_mint
cast send --unlocked --from $unknown_address --rpc-url $l1_shadow_fork_url_local $POL_ADDR 'mint(address,uint256)' $sequencer_addr 9345375970000000000000000
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $unknown_address

# Approve
amount_to_approve=$(cast to-hex "$(cast to-wei 100)")
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $sequencer_addr $amount_to_approve
cast send --rpc-url $l1_shadow_fork_url_local --private-key $sequencer_pkey $POL_ADDR 'approve(address,uint256)(bool)' $rollup_address 9345375970000000000000000

## Grant Aggregator Role
# Impersonate Polygon admin to grant aggregator role
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $AGGLAYER_ADMIN
# Grant TRUSTED_AGGREGATOR_ROLE to our Agglayer account
cast send --unlocked --from $AGGLAYER_ADMIN --rpc-url $l1_shadow_fork_url_local $AGGLAYER_MANAGER 'grantRole(bytes32 role, address account)' "$(cast keccak TRUSTED_AGGREGATOR_ROLE)" $aggregator_addr
# Stop impersonation
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $AGGLAYER_ADMIN


                          ##                                         
                          ##   :####                   #### ####     
                          ##   #####                   #### ####     
                               ##                        ##   ##     
 ##:  :## .####: ##.######## #########    ##      :####  ##   ##     
  ##  ## .######:########### #######:##  ##       ###### ##   ##     
  ##  ##:##:  :#####.     ##   ##    ##: ##.      #:  :####   ##     
  ##..## ##########       ##   ##    ###:##        :#######   ##     
  ##::## ##########       ##   ##    .## #       .#########   ##     
   ####: ##      ##       ##   ##     ####.      ## .  ####   ##     
   ####  ###.  :###       ##   ##     :###       ##:  #####:  ##:    
   ####  .#########    ##########      ##        ##################  
    ##:   .#####:##    ##########      ##.         ###.##.####.####  
                                       ##                            
                                     ###:                            
                                     ###                             
docker stop cdk-node
docker rm cdk-node
# start aggregator only
docker run \
    -d \
    -p 50081:50081 \
    --name cdk-node \
    --network $docker_network \
    -v "$(pwd)"/cdk:/etc/cdk \
    ghcr.io/0xpolygon/cdk:0.5.4 \
    cdk-node run --cfg=/etc/cdk/cdk-node.toml --components=aggregator












echo "Waiting for erigon to start up...."
sleep 10

target_block=$(cast bn --rpc-url $L2_RPC)
current_block=$(cast bn --rpc-url http://localhost:8545)
while [ $current_block -lt $target_block ]; do
    echo "Current block: $current_block, waiting until it reaches $target_block..."
    sleep 5 && current_block=$(cast bn --rpc-url http://localhost:8545)
done
echo "Erigon is synced up to block $current_block"



# set 100 ether to sequencer and aggregator
sequencer_balance=$(cast to-hex "$(cast to-wei 100)")
aggregator_balance=$(cast to-hex "$(cast to-wei 100)")
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $sequencer_addr $sequencer_balance
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $aggregator_addr $aggregator_balance







                       ####                                   
                       ####                                   
                         ##                                   
   ####   :###:## :###:####    :####  ##    ## .####: ##.#### 
  ###### .#######.#########    ###### :##  ## .######:####### 
  #:  :#####  ######  #####    #:  :## ##: ##.##:  :#####.    
    #######.  .####.  .####     :##### ###:## ##########      
  #########    ####    ####   .####### .## #  ##########      
 ## .  ####.  .####.  .####   ## .  ##  ####. ##      ##      
 ##:  ######  ######  #####:  ##:  ###  :###  ###.  :###      
 ########.#######.####################   ##   .#########      
   ###.## :###:## :###:##.####  ###.##   ##.   .#####:##      
          #.  :## #.  :##               :##                   
          ######  ######               ###:                   
           ####:  :####:               ###                    

# Start the Agglayer Prover
docker run \
    -d \
    --rm \
    --name agglayer-prover \
    --network $docker_network \
    -v "$(pwd)/configs:/etc/agglayer:ro" \
    -e "SP1_PRIVATE_KEY=$SP1_KEY" \
    -e "NETWORK_RPC_URL=https://rpc.production.succinct.xyz" \
    -e "RUST_BACKTRACE=1" \
    -e "NETWORK_PRIVATE_KEY=$SP1_KEY" \
    --entrypoint agglayer \
    ghcr.io/agglayer/agglayer:0.4.0 \
    prover --cfg /etc/agglayer/agglayer-prover.toml

# Start the Agglayer
(cd $workdir || exit 1) && sudo rm -fr agglayer && mkdir -p agglayer && chmod -R 777 agglayer
cp keys/aggregator.keystore agglayer/aggregator.keystore
cp configs/agglayer-template.toml agglayer/agglayer.toml

ger_address=$(cast call --rpc-url $l1_shadow_fork_url $AGGLAYER_MANAGER 'globalExitRootManager()(address)')

sed -i 's/REPLACE_SEQUENCER_ADDRESS/'$sequencer_addr'/' agglayer/agglayer.toml
sed -i 's|REPLACE_L1_RPC|'$L1_RPC'|' agglayer/agglayer.toml
sed -i 's|REPLACE_L1_WS|'$L1_WS'|' agglayer/agglayer.toml
sed -i 's/REPLACE_AGGLAYER_MANAGER/'$AGGLAYER_MANAGER'/' agglayer/agglayer.toml
sed -i 's/REPLACE_GER/'$ger_address'/' agglayer/agglayer.toml

# Start the Agglayer Node
docker run \
    -d \
    --rm \
    --name agglayer \
    --network $docker_network \
    -v "$(pwd)/agglayer:/etc/agglayer:rw" \
    --entrypoint agglayer \
    ghcr.io/agglayer/agglayer:0.4.0 \
    run --cfg /etc/agglayer/agglayer.toml



                                                                                                                                                          
