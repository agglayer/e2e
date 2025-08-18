#!/bin/env bash
set -e

# Check before sourcing
if [ -f ../common/load-env.sh ]; then
    source ../common/load-env.sh
else
    echo "load-env.sh not found!"
    exit 1
fi

if [ -f .env ]; then
    source .env
else
    echo ".env not found — shell exiting."
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# Usage: ./run.sh <from-tag> <to-tag> [action]
#   <from-tag>      e.g. 0.3.0-rc.21
#   <to-tag>        e.g. 0.3.5
#   [1]             optional: perform upgrade from kurtosis base image (either 1(kurtosis base image) or 2(base image from cli))
#   [action]        optional: perform downgrade back to <from-tag>
# Exit immediately if no args provided
if [[ $# -lt 2 ]]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 <from-tag> <to-tag> [action]"
  exit 1
fi


PREV_FROM_TAG="$FROM_TAG"
PREV_TO_TAG="$TO_TAG"



FROM_TAG="$1"
TO_TAG="$2"
ACTION="${3:-upgrade}"


if [[ "$ACTION" == "downgrade" ]]; then
  if [[ "$TO_TAG" == "$PREV_FROM_TAG" && "$FROM_TAG" == "$PREV_TO_TAG" ]]; then
    echo "✅ Downgrade tags match previous upgrade."
  else
    echo "❌ Downgrade tag mismatch!"
    echo "Expected FROM_TAG=$PREV_TO_TAG, TO_TAG=$PREV_FROM_TAG"
    echo "Got      FROM_TAG=$FROM_TAG, TO_TAG=$TO_TAG"
    exit 1
  fi
fi

# Compose full image references
IMAGE_BASE="ghcr.io/agglayer/agglayer"
FROM_IMAGE="${IMAGE_BASE}:${FROM_TAG}"
TO_IMAGE="${IMAGE_BASE}:${TO_TAG}"



sed -i "s#^FROM_IMAGE=.*#FROM_IMAGE=$FROM_IMAGE#" .env
sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env
sed -i "s#^FROM_TAG=.*#FROM_TAG=$FROM_TAG#" .env
sed -i "s#^TO_TAG=.*#TO_TAG=$TO_TAG#" .env


kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"


echo ":-kurtosis hash:= $kurtosis_hash"
echo ":-enclave name:= $kurtosis_enclave_name"
echo ":-from image:= $FROM_IMAGE"
echo ":-to image:= $TO_IMAGE"
echo ":-from tag:= $FROM_TAG"
echo ":-to tag:= $TO_TAG"
echo ":-action:= $ACTION"



# Create a yml files with a real SP1 keys if needed
yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.agglayer_prover_sp1_key = $sp1key
' ./assets/cdk-erigon-validium.yml > initial-cdk-erigon-validium.yml

yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.agglayer_prover_sp1_key = $sp1key
' ./assets/cdk-erigon-rollup.yml > initial-cdk-erigon-rollup.yml

yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.agglayer_prover_sp1_key = $sp1key
' ./assets/cdk-erigon-pp.yml > initial-cdk-erigon-pp.yml


# checks if the user is requesting for downgrade
if [[ "$ACTION" == "downgrade" ]]; then

      # check if there is a running enclave
      enclaveExist=$(kurtosis enclave ls | awk '$3 == "RUNNING" {print $2; exit}')
      if [[ "$enclaveExist" != "$kurtosis_enclave_name" ]]; then
          echo "Enclave name is not $kurtosis_enclave_name. Exiting...OR No Running enclave "
          exit 1
      fi


      prev_aglr_readrpc=$(kurtosis service inspect cdk agglayer --output json | jq -r '.ports["aglr-readrpc"].number')

      if [[ "$prev_aglr_readrpc" == "9090" ]]; then
          prev_aglr_readrpc="4444"
      else
          prev_aglr_readrpc="9090"
      fi

      
      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   R U N N I N G   D O W N G R A D E   F O R   A G G L A Y E R   F R O M   S U P L I E D   T A G       ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝'

    kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer \
        --image "$TO_IMAGE" \
        --ports aglr-readrpc=9090,prometheus=9092


      sleep 10

      kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer-prover \
        --image "$TO_IMAGE" \
        --ports api=4445,prometheus=9093 

    



      

      echo "DOWNGRADED: C O N F I R M I N G   R U N N I N G  A G G L A Y E R   W I T H   T A R G E T   D O W N G R A D E   V E R S I O N:  $TO_TAG "
      echo "=========================================================================================================================================="
      kurtosis service inspect cdk agglayer --output json
      echo "=========================================================================================================================================="


      echo '╔════════════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   🎉 💃💃💃💃💃   D O W N G R A D I N G    A G G L A Y E R   S U C C E S S F U L L  🎉 💃💃💃💃💃          ║'
      echo '╚════════════════════════════════════════════════════════════════════════════════════════════════════════════╝'

else
      echo '╔═══════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N   V A L I D I U M  ║'
      echo '╚═══════════════════════════════════════════════════════════════╝'


      kurtosis run \
              --enclave "$kurtosis_enclave_name" \
              --args-file ./initial-cdk-erigon-validium.yml \
              "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"
      

              contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
              contracts_container_name=contracts-001--$contracts_uuid

              # Get the deployment details
              docker cp $contracts_container_name:/opt/zkevm/combined.json .
              rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)
              l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
              l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' combined.json)

              L1_BRIDGE_ADDR=$l1_bridge_address
              L2_BRIDGE_ADDR=$l2_bridge_address


      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N   V A L I D I U M   S U C C E S S F U L L               ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝'
      echo "======================================================================================================================="
      sleep 10

      prev_aglr_readrpc=$(kurtosis service inspect cdk agglayer --output json | jq -r '.ports["aglr-readrpc"].number')
     

      echo '╔══════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   R U N N I N G   U P G R A D E   F O R   A G G L A Y E R   F R O M   S U P L I E D   T A G      ║'
      echo '╚══════════════════════════════════════════════════════════════════════════════════════════════════╝'

      prev_aglr_readrpc=$(kurtosis service inspect cdk agglayer --output json | jq -r '.ports["aglr-readrpc"].number')

      kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer \
        --image "$FROM_IMAGE" \
        --ports aglr-readrpc=9090,prometheus=9092

      sleep 10

      kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer-prover \
        --image "$FROM_IMAGE" \
        --ports api=4445,prometheus=9093 


      echo "C O N F I R M I N G   R U N N I N G  A G G L A Y E R   F R O M    S U P P L I E D   B A S E   V E R S I O N:  $FROM_TAG "
      echo "========================================================================================================================"
      kurtosis service inspect cdk agglayer --output json
      echo "========================================================================================================================"

      sleep 15

      prev_aglr_readrpc=$(kurtosis service inspect cdk agglayer --output json | jq -r '.ports["aglr-readrpc"].number')

      kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer \
        --image "$TO_IMAGE" \
        --ports aglr-readrpc="$prev_aglr_readrpc",prometheus=9092

      sleep 10

      kurtosis service update \
        "$kurtosis_enclave_name" \
        agglayer-prover \
        --image "$TO_IMAGE" \
        --ports api=4445,prometheus=9093 

      prev_aglr_readrpc=$(kurtosis service inspect cdk agglayer --output json | jq -r '.ports["aglr-readrpc"].number')

      echo "UPGRADED: C O N F I R M I N G   R U N N I N G  A G G L A Y E R   F R O M    S U P P L I E D   T A R G E T   V E R S I O N:  $TO_TAG "
      echo "======================================================================================================================================================"
      kurtosis service inspect cdk agglayer --output json
      echo "======================================================================================================================================================"

      echo '╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║     🎉 💃💃💃💃💃   U P G R A D I N G    A G G L A Y E R   T O  T A R G E T   V E R S I O N  S U C C E S S F U L L 🎉 💃💃💃💃💃                   ║'
      echo '╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝'

      echo "======================================================================================================================================================"
      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N    R O L L U P                                 ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════╝'


      kurtosis run \
              --enclave "$kurtosis_enclave_name" \
              --args-file ./initial-cdk-erigon-rollup.yml \
              "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"  
      
      

      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N   R O L L U P   S U C C E S S F U L L                   ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝'
      echo "====================================================================================================================================="
      sleep 10

      echo "====================================================================================================================================="
      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N    P E R S I M I S T I C  P R O O F (P P)      ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════╝'

      Spin up cdk-erigon pp
      kurtosis run \
              --enclave "$kurtosis_enclave_name" \
              --args-file ./initial-cdk-erigon-pp.yml \
              "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"


              contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
              contracts_container_name=contracts-001--$contracts_uuid

              # Get the deployment details
              docker cp $contracts_container_name:/opt/zkevm/combined.json .
              rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)
              l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
              l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' combined.json)

              L1_BRIDGE_ADDR=$l1_bridge_address
              L2_BRIDGE_ADDR=$l2_bridge_address


      echo '╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N   P E R S I M I S T I C  P R O O F (P P)   S U C C E S S F U L L               ║'
      echo '╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝'
      echo "============================================================================================================================================="
      sleep 10

fi