#!/bin/env bash
set -euo pipefail
# Load environment

echo "Loading environment variables"
source ../common/load-env.sh
load_env


# ──────────────────────────────────────────────────────────────────────────────
# Usage: ./run.sh <from-tag> <to-tag> [true]
#   <from-tag>      e.g. 0.3.0-rc.21
#   <to-tag>        e.g. 0.3.5
#   [true]          optional: perform downgrade back to <from-tag>
# Exit immediately if no args provided
if [[ $# -lt 2 ]]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 <from-tag> <to-tag> [true]"
  exit 1
fi

FROM_TAG="$1"
TO_TAG="$2"
TEST_DOWNGRADE="${3:-false}"

# Compose full image references
IMAGE_BASE="ghcr.io/agglayer/agglayer"
FROM_IMAGE="${IMAGE_BASE}:${FROM_TAG}"
TO_IMAGE="${IMAGE_BASE}:${TO_TAG}"
AGGLAYER_IMAGE="${IMAGE_BASE}:${TO_TAG}"



# Remove existing docker compose containers if any
docker compose down

# checks if the user is requesting for downgrade
if [[ "$TEST_DOWNGRADE" == "true" ]]; then

echo '╔══════════════════════════════════════════════════════════╗'
echo '║    D O W N G R A D I N G   A G G L A Y E R               ║'
echo '╚══════════════════════════════════════════════════════════╝'

  echo "================= Downgrading back to $TO_TAG ==========================="
  sed -i "s#^FROM_IMAGE=.*#FROM_IMAGE=$FROM_IMAGE#" .env
  sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env
  sed -i "s#^AGGLAYER_IMAGE=.*#AGGLAYER_IMAGE=$TO_IMAGE#" .env
  # ./run-service-downgrade.sh
  docker compose up -d > docker-compose.log 2>&1

else



#Update the image 
sed -i "s#^FROM_IMAGE=.*#FROM_IMAGE=$FROM_IMAGE#" .env
sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env

# Immediately set AGGLAYER_IMAGE to FROM_IMAGE
echo "Setting initial Agglayer image to $FROM_IMAGE"
export FROM_IMAGE="$FROM_IMAGE"
export TO_IMAGE="$TO_IMAGE"


# -----------------------------------------------------------------------------
# Phase 1: Bootstrap rollups with Agglayer $FROM_TAG
# -----------------------------------------------------------------------------
echo "Bootstrapping rollups with Agglayer $FROM_TAG"

yq -y --arg sp1key "$SP1_NETWORK_KEY" \
  '.args.agglayer_prover_sp1_key = $sp1key' \
  ./assets/cdk-erigon-validium.yml > initial-cdk-erigon-validium.yml

yq -y --arg sp1key "$SP1_NETWORK_KEY" \
  '.args.agglayer_prover_sp1_key = $sp1key' \
  ./assets/cdk-erigon-rollup.yml > initial-cdk-erigon-rollup.yml

yq -y --arg sp1key "$SP1_NETWORK_KEY" \
  '.args.agglayer_prover_sp1_key = $sp1key' \
  ./assets/cdk-erigon-pp.yml > initial-cdk-erigon-pp.yml


echo '╔═══════════════════════════════════════════════════════════════════════════════╗'
echo '║        A T T A C H I N G   C D K  E R I G O N  R O L L U P   V A L I D I U M  ║'
echo '╚═══════════════════════════════════════════════════════════════════════════════╝'
kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-validium.yml "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"
# Get the deployment details
contracts_uuid=$(kurtosis enclave inspect --full-uuids $ENCLAVE_NAME | grep contracts-001[^-] | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

echo $contracts_container_name "contract name"
# Get the deployment details
docker cp $contracts_container_name:/opt/zkevm/combined.json .
rollup_manager_address=$(jq -r '.polygonRollupManagerAddress' combined.json)
l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' combined.json)

L1_BRIDGE_ADDR=$l1_bridge_address
L2_BRIDGE_ADDR=$l2_bridge_address
export L1_BRIDGE_ADDR
export L2_BRIDGE_ADDR


echo '╔══════════════════════════════════════════════════════════════════╗'
echo '║        A T T A C H I N G   C D K  E R I G O N  R O L L  U P      ║'
echo '╚══════════════════════════════════════════════════════════════════╝'
# kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-rollup.yml    "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"
# kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-pp.yml        "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"

# -----------------------------------------------------------------------------
# Phase 2: Switch to FROM_IMAGE
# -----------------------------------------------------------------------------
echo "=========================================Booting up Agglayer with $FROM_IMAGE ======================================"
sed -i "s#^AGGLAYER_IMAGE=.*#AGGLAYER_IMAGE=$FROM_IMAGE#" .env
echo "Running Phase 3 upgrade..."
if ./run-service-update.sh; then
  echo "Phase 3 upgrade succeeded"
else
  echo "Phase 3 upgrade failed"
  exit 1
fi

# -----------------------------------------------------------------------------
# Phase 3: Upgrade to TO_IMAGE
# -----------------------------------------------------------------------------


echo '╔══════════════════════════════════════════════════════════╗'
echo '║        U P G R A D I N G   A G G L A Y E R               ║'
echo '╚══════════════════════════════════════════════════════════╝'

echo "=======================================Upgrading Agglayer from $FROM_IMAGE → $TO_IMAGE==============================="
sed -i "s#^AGGLAYER_IMAGE=.*#AGGLAYER_IMAGE=$TO_IMAGE#" .env
echo "Running Phase 4 upgrade..."
docker compose up -d > docker-compose.log 2>&1
echo "Phase 4 upgrade succeeded"

fi



