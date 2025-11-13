
# shellcheck source=scenarios/common/load-env.sh
source ../common/load-env.sh
load_env

workdir=$(pwd)
docker_network="zkevm"
docker network create $docker_network


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
claimsponsor=$(cast wallet new --json | jq .[0])
echo $sequencer > keys/sequencer.json
echo $aggregator > keys/aggregator.json
echo $aggoracle > keys/aggoracle.json
echo $claimsponsor > keys/claimsponsor.json

sequencer_addr=$(cat keys/sequencer.json | jq -r .address)
sequencer_pkey=$(cat keys/sequencer.json | jq -r .private_key)
aggregator_addr=$(cat keys/aggregator.json | jq -r .address)
aggregator_pkey=$(cat keys/aggregator.json | jq -r .private_key)
# aggoracle_addr=$(cat keys/aggoracle.json | jq -r .address)
aggoracle_pkey=$(cat keys/aggoracle.json | jq -r .private_key)
claimsponsor_addr=$(cat keys/claimsponsor.json | jq -r .address)
claimsponsor_pkey=$(cat keys/claimsponsor.json | jq -r .private_key)

# create keystores for both
rm -f keys/sequencer.keystore && cast wallet import --private-key $sequencer_pkey --unsafe-password "secret" --keystore-dir keys/ sequencer.keystore
rm -f keys/aggregator.keystore && cast wallet import --private-key $aggregator_pkey --unsafe-password "secret" --keystore-dir keys/ aggregator.keystore
rm -f keys/aggoracle.keystore && cast wallet import --private-key $aggoracle_pkey --unsafe-password "secret" --keystore-dir keys/ aggoracle.keystore
rm -f keys/claimsponsor.keystore && cast wallet import --private-key $claimsponsor_pkey --unsafe-password "secret" --keystore-dir keys/ claimsponsor.keystore


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
    -v "$(pwd)/datadir:/datadir" \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    --config="./mainnet.yaml" --datadir="/datadir" --zkevm.l1-rpc-url=$L1_RPC

mkdir -p $workdir/configs
docker cp erigon:/home/erigon/mainnet.yaml $workdir/configs/

local_l2_rpc="http://localhost:8545"
# docker_l2_rpc="http://erigon:8545"

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

(cd $workdir || exit 1)

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

docker stop erigon

cd $workdir || exit 1
# Lets start anvil fork in 10' aprox (10' * 60s / 12s/block = 50 blocks)
fork_block=$(cast bn --rpc-url $L1_RPC)
echo "Starting anvil fork from block $fork_block"
docker run \
    -d \
    -p 8123:8545 \
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
    --fork-block-number $fork_block

l1_shadow_fork_url="http://anvil:8545"
l1_shadow_fork_url_local="http://localhost:8123"

                                              
# https://www.notion.so/polygontechnology/Unwind-process-on-prod-ready-networks-13e80500116a80af9b69dd2689f59f10
                                                                               #### ####   ##                      ##       
                           ##                           ##                     #### ####   ##                      ##       
                           ##                           ##                       ##   ##   ##                      ##       
    ####: .####. ##.#### #########.####:####     ####:#######     ##.#### .####. ##   ##   ##.###:  :####     ####:##   ##: 
  #######.######.####### ####################  ##############     #######.######.##   ##   #######: ######  #########  ##:  
  ##:  :####  ######  :##  ##   ###.   #:  :## ##:  :#  ##        ###.   ###  #####   ##   ###  ### #:  :## ##:  :###:##:   
 ##.     ##.  .####    ##  ##   ##      :#######.       ##        ##     ##.  .####   ##   ##.  .##  :#######.     ####     
 ##      ##    ####    ##  ##   ##    .#########        ##        ##     ##    ####   ##   ##    ##.#########      #####    
 ##.     ##.  .####    ##  ##   ##    ## .  ####.       ##        ##     ##.  .####   ##   ##.  .#### .  ####.     ##.###   
  ##:  .####  #####    ##  ##.  ##    ##:  ### ##:  .#  ##.       ##     ###  #####:  ##:  ###  #####:  ### ##:  .###  ##:  
  #######.######.##    ##  #######    ######## #######  #####     ##     .######.#################:######## #########  :##  
    ####: .####. ##    ##  .######      ###.##   ####:  .####     ##      .####. .####.######.###:   ###.##   ####:##   ### 

rollupdata=$(cast call --rpc-url $l1_shadow_fork_url_local $AGGLAYER_MANAGER 'rollupIDToRollupDataDeserialized(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' $ROLLUP_ID --json)
rollup_address=$(echo $rollupdata | jq -r '.[0]')
rollup_admin=$(cast call $rollup_address 'admin()(address)' --rpc-url $l1_shadow_fork_url_local)
last_sequenced_batch=$(echo $rollupdata | jq -r '.[5]')
last_verified_batch=$(echo $rollupdata | jq -r '.[6]')
echo "Last sequenced batch: $last_sequenced_batch | Last verified batch: $last_verified_batch"

echo "Rolling back to batch $last_verified_batch"
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $AGGLAYER_ADMIN
cast send --unlocked --from $AGGLAYER_ADMIN $AGGLAYER_MANAGER "rollbackBatches(address,uint64)" $rollup_address $last_verified_batch --rpc-url $l1_shadow_fork_url_local
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $AGGLAYER_ADMIN


                             ##                    
                             ##                 ## 
                             ##                 ## 
                                                ## 
 ##    ####.#### ##      ######   ##.####  :###.## 
 ##    ######### ##.    .######   ####### :####### 
 ##    #####  :## #: ## :#   ##   ###  :#####  ### 
 ##    ####    ##:#:.##.:#:  ##   ##    ####.  .## 
 ##    ####    ## # :##:##   ##   ##    ####    ## 
 ##    ####    ## ## ## ##   ##   ##    ####.  .## 
 ##:  #####    ## ###::##    ##   ##    #####  ### 
  #########    ## :##..##:##########    ##:####### 
   ###.####    ## .##  ## ##########    ## :###.## 

cd $workdir/erigon || exit 1
docker run \
    -it \
    --rm \
    --network $docker_network \
    --name erigon \
    -v "$(pwd)/datadir:/datadir" \
    --entrypoint /bin/sh \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    -c "integration state_stages_zkevm  --config=./mainnet.yaml --chain hermez-mainnet --datadir /datadir --unwind-batch-no=$last_verified_batch"


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
cd $workdir || exit 1
echo "zkevm.sequencer-block-seal-time: 3s" >> configs/mainnet.yaml
echo "zkevm.sequencer-batch-seal-time: 15s" >> configs/mainnet.yaml
echo "zkevm.sequencer-batch-verification-timeout: 30m" >> configs/mainnet.yaml
echo "zkevm.sequencer-timeout-on-empty-tx-pool: 250ms" >> configs/mainnet.yaml
echo "zkevm.executor-strict: false" >> configs/mainnet.yaml
echo "zkevm.data-stream-host: 0.0.0.0" >> configs/mainnet.yaml
echo "zkevm.data-stream-port: 6900" >> configs/mainnet.yaml
sed -i 's|^zkevm.l1-rpc-url: https://rpc.eth.gateway.fm/$|zkevm.l1-rpc-url: '$l1_shadow_fork_url'|' configs/mainnet.yaml
sed -i 's|zkevm.address-sequencer: "0x148Ee7dAF16574cD020aFa34CC658f8F3fbd2800"|zkevm.address-sequencer: "'$sequencer_addr'"|' configs/mainnet.yaml


  ##.#### .####:  :#####. .####:  :###.####    ## .####: ##.####    ####: .####:  
  #######.######:########.######::#########    ##.######:#######  #######.######: 
  ###.   ##:  :####:  .:###:  :#####  #####    ####:  :#####  :## ##:  :###:  :## 
  ##     ############# . ##########.  .####    ############    ####.     ######## 
  ##     ########.######:##########    ####    ############    ####      ######## 
  ##     ##         .: ####      ##.  .####    ####      ##    ####.     ##       
  ##     ###.  :##:.  :#####.  :####  #####:  ######.  :###    ## ##:  .####.  :# 
  ##     .###############.#######:####### #######.#########    ## #######.####### 
  ##      .#####:. ####   .#####: :###.##  ###.## .#####:##    ##   ####: .#####: 
                                       ##                                         
                                       ##                                         
                                       ##                                         
(cd $workdir || exit 1) && docker run \
    -it \
    --rm \
    --network $docker_network \
    --name erigon \
    -v "$(pwd)/erigon/datadir:/datadir" \
    -v "$(pwd)/configs:/etc/cdk-erigon" \
    --env CDK_ERIGON_SEQUENCER=1 \
    --entrypoint /bin/sh \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    -c "cdk-erigon --config=/etc/cdk-erigon/mainnet.yaml --datadir /datadir --zkevm.sequencer-resequence-strict=true --zkevm.sequencer-resequence=true --zkevm.sequencer-resequence-reuse-l1-info-index=true"

# CTRL-C when it says: [5/13 Execution] Resequencing completed. Please restart sequencer without resequence flag.

(cd $workdir || exit 1) && rm -fr erigon/datadir/data-stream.*

                                                                           ##                            
                               ####                                        ##                            
                               ####                                        ##                            
                                 ##                                                                      
  ##.#### .####:  :###:####    ####    :####  ##.####      .####: ##.########    :###:## .####. ##.####  
  #######.######:.#########    ####    ###### #######     .######:###########   .#######.######.#######  
  ###.   ##:  :#####  #####    ####    #:  :#####.        ##:  :#####.     ##   ###  ######  ######  :## 
  ##     ##########.  .####    ####     :#######          ##########       ##   ##.  .####.  .####    ## 
  ##     ##########    ####    ####   .#########          ##########       ##   ##    ####    ####    ## 
  ##     ##      ##.  .####    ####   ## .  ####          ##      ##       ##   ##.  .####.  .####    ## 
  ##     ###.  :####  #####:  #####:  ##:  #####          ###.  :###       ##   ###  ######  #####    ## 
  ##     .#######.####### ######################          .#########    ########.#######.######.##    ## 
  ##      .#####: :###:##  ###.##.####  ###.####           .#####:##    ######## :###:## .####. ##    ## 
                  #.  :##                                                        #.  :##                 
                  ######                                                         ######                  
                   ####:                                                         :####:                  

(cd $workdir || exit 1) && docker run \
    --rm -d \
    --network $docker_network \
    --name erigon \
    -p 8545:8545 \
    --env CDK_ERIGON_SEQUENCER=1 \
    -v "$(pwd)/erigon/datadir:/datadir" \
    -v "$(pwd)/configs:/etc/cdk-erigon" \
    ghcr.io/0xpolygon/cdk-erigon:v2.61.24 \
    --config="/etc/cdk-erigon/mainnet.yaml" --datadir="/datadir" --zkevm.l1-rpc-url=$l1_shadow_fork_url


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
(cd $workdir || exit 1) && docker run \
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

ger_address=$(cast call --rpc-url $l1_shadow_fork_url_local $AGGLAYER_MANAGER 'globalExitRootManager()(address)')

sed -i 's/REPLACE_SEQUENCER_ADDRESS/'$sequencer_addr'/' agglayer/agglayer.toml
sed -i 's|REPLACE_L1_RPC|'$l1_shadow_fork_url'|' agglayer/agglayer.toml
# WS for Anvil not available?
sed -i 's|REPLACE_L1_WS|ws://anvil:8545|' agglayer/agglayer.toml
sed -i 's/REPLACE_AGGLAYER_MANAGER/'$AGGLAYER_MANAGER'/' agglayer/agglayer.toml
sed -i 's/REPLACE_GER/'$ger_address'/' agglayer/agglayer.toml

# Start the Agglayer Node
(cd $workdir || exit 1) && docker run \
    -d \
    --rm \
    --name agglayer \
    --network $docker_network \
    -v "$(pwd)/agglayer:/etc/agglayer:rw" \
    --entrypoint agglayer \
    -p 4444:4444 \
    -p 4443:4443 \
    -p 4446:4446 \
    ghcr.io/agglayer/agglayer:0.4.0 \
    run --cfg /etc/agglayer/agglayer.toml


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
cast send --unlocked --from $rollup_admin --rpc-url $l1_shadow_fork_url_local $rollup_address 'setTrustedSequencer(address)' $sequencer_addr
# Stop impersonation
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $rollup_admin

# Mint to new sequencer address
unknown_address=0xbC9f74b3b14f460a6c47dCdDFd17411cBc7b6c53
amount_to_mint=$(cast to-hex "$(cast to-wei 100)")
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $unknown_address
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $unknown_address $amount_to_mint
cast send --unlocked --from $unknown_address --rpc-url $l1_shadow_fork_url_local $POL_ADDR 'mint(address,uint256)' $sequencer_addr 10000000000000000000
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $unknown_address

# Approve
amount_to_approve=$(cast to-hex "$(cast to-wei 100)")
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_setBalance $sequencer_addr $amount_to_approve
cast send --rpc-url $l1_shadow_fork_url_local --private-key $sequencer_pkey $POL_ADDR 'approve(address,uint256)(bool)' $rollup_address 10000000000000000000

## Grant Aggregator Role
# Impersonate Polygon admin to grant aggregator role
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $AGGLAYER_ADMIN
# Grant TRUSTED_AGGREGATOR_ROLE to our Agglayer account
cast send --unlocked --from $AGGLAYER_ADMIN --rpc-url $l1_shadow_fork_url_local $AGGLAYER_MANAGER 'grantRole(bytes32 role, address account)' "$(cast keccak TRUSTED_AGGREGATOR_ROLE)" $aggregator_addr
# Stop impersonation
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $AGGLAYER_ADMIN


                                    ##          
                         ##         ##          
                         ##         ##   ##     
                         ##              ##     
   ####   :###:## :###:####   ##: #### #######  
  ###### .#######.#########  ##:  #### #######  
  #:  :#####  ######  #####:##:     ##   ##     
    #######.  .####.  .######       ##   ##     
  #########    ####    #######      ##   ##     
 ## .  ####.  .####.  .####.###     ##   ##     
 ##:  ######  ######  #####  ##:    ##   ##.    
 ########.#######.#########  :## #############  
   ###.## :###:## :###:####   ###########.####  
          #.  :## #.  :##                       
          ######  ######                        
           ####:  :####:                        

# Start Aggkit
cd $workdir || exit 1
rm -fr aggkit && mkdir -p aggkit/tmp && chmod -R 777 aggkit/tmp
cp configs/aggkit-config.toml.template aggkit/aggkit-config.toml
cp keys/*.keystore aggkit/

sed -i 's|REPLACE_CLAIMSPONSOR_ADDRESS|'$claimsponsor_addr'|' aggkit/aggkit-config.toml

docker run \
    -d \
    --network $docker_network \
    --rm \
    --name aggkit \
    -v "$(pwd)/aggkit:/etc/aggkit" \
    ghcr.io/agglayer/aggkit:0.7.1 \
    run --cfg=/etc/aggkit/aggkit-config.toml --components=aggsender


                                             ##         
                                             ##         
                                             ##         
 ##    ####.###:  :###:####.####:####   :###.## .####:  
 ##    #########:.#################### :#######.######: 
 ##    #####  ######  ######.   #:  :#####  #####:  :## 
 ##    ####.  .####.  .####      :#######.  .########## 
 ##    ####    ####    ####    .#########    ########## 
 ##    ####.  .####.  .####    ## .  ####.  .####       
 ##:  ######  ######  #####    ##:  ######  ######.  :# 
  ##############:.#########    ########:#######.####### 
   ###.####.###:  :###:####      ###.## :###.## .#####: 
         ##       #.  :##                               
         ##       ######                                
         ##       :####:                                



# Impersonate admin for migration
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_impersonateAccount $AGGLAYER_ADMIN
# Initialize migration of rollup 3 (OKX) to type 11 (PP)
tx_block_number=$(cast send \
    --unlocked \
    --from $AGGLAYER_ADMIN \
    --rpc-url $l1_shadow_fork_url_local \
    $AGGLAYER_MANAGER "initMigration(uint32,uint32,bytes)" 1 14 "$(cast calldata 'migrateFromLegacyConsensus()')" --json | jq -r .blockNumber)
# Stop impersonation
cast rpc --rpc-url $l1_shadow_fork_url_local anvil_stopImpersonatingAccount $AGGLAYER_ADMIN

zkevm_verified_batch_number=$(cast rpc zkevm_verifiedBatchNumber)
previous_block_hash=$(cast rpc zkevm_getBatchByNumber $zkevm_verified_batch_number --json | jq -r .blocks[-1])
max_l2_block=$(printf "%d\n" "$(cast rpc eth_getBlockByHash "$previous_block_hash" | jq -r .number)")
cd $workdir || exit 1
sed -i 's|# MaxL2BlockNumber = 0|MaxL2BlockNumber = '$max_l2_block'|' aggkit/aggkit-config.toml
sed -i 's|DryRun = true|DryRun = false|' aggkit/aggkit-config.toml

current_finalized=$(cast bn --rpc-url $l1_shadow_fork_url_local finalized)
while [ $current_finalized -lt $tx_block_number ]; do
    echo "Waiting for migration to be finalized... Current finalized block: $current_finalized, Target block: $tx_block_number"
    current_finalized=$(cast bn --rpc-url $l1_shadow_fork_url_local finalized)
    sleep 10
done
echo "Migration finalized at block: $tx_block_number. Current finalized block: $current_finalized"

# restart aggkit
docker stop aggkit
docker run \
    -d \
    --network $docker_network \
    --rm \
    --name aggkit \
    -v "$(pwd)/aggkit:/etc/aggkit" \
    ghcr.io/agglayer/aggkit:0.7.1 \
    run --cfg=/etc/aggkit/aggkit-config.toml --components=aggsender
