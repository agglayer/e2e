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
#   [1]             optional: perform upgrade from kurtosis base image (either 1(kurtosis base image) or 2(base image from cli))
#   [true]          optional: perform downgrade back to <from-tag>
# Exit immediately if no args provided
if [[ $# -lt 2 ]]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 <from-tag> <to-tag> [true]"
  exit 1
fi

FROM_TAG="$1"
TO_TAG="$2"
OPTION="$3"
TEST_DOWNGRADE="${4:-false}"

# Compose full image references
IMAGE_BASE="ghcr.io/agglayer/agglayer"
FROM_IMAGE="${IMAGE_BASE}:${FROM_TAG}"
TO_IMAGE="${IMAGE_BASE}:${TO_TAG}"

# checks if the user is requesting for downgrade
if [[ "$TEST_DOWNGRADE" == "true" ]]; then
  echo "================= Downgrading back to $TO_TAG ==========================="
  sed -i "s#^FROM_IMAGE=.*#FROM_IMAGE=$FROM_IMAGE#" .env
  sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env
  ./run-service-downgrade.sh

else



#Update the image 
sed -i "s#^FROM_IMAGE=.*#FROM_IMAGE=$FROM_IMAGE#" .env
sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env

# Immediately set AGGLAYER_IMAGE to FROM_IMAGE
echo "Setting initial Agglayer image to $FROM_IMAGE"
export FROM_IMAGE="$FROM_IMAGE"
export TO_IMAGE="$TO_IMAGE"
# -----------------------------------------------------------------------------
# Phase 1: Tear down previous Docker Compose deployment
# -----------------------------------------------------------------------------
echo "=====================================Shutting down existing Docker Compose containers...============================="
docker compose down

# -----------------------------------------------------------------------------
# Phase 2: Bootstrap rollups with Agglayer $FROM_TAG
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


echo '╔═══════════════════════════════════════════════════════════════╗'
echo '║   A T T A C H I N G    C D K   E R I G O N   V A L I D I U M  ║'
echo '╚═══════════════════════════════════════════════════════════════╝'
kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-validium.yml "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"
# kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-rollup.yml    "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"
# kurtosis run --enclave "$ENCLAVE_NAME" --args-file ./initial-cdk-erigon-pp.yml        "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_PACKAGE_HASH"




echo "=================================================================================================================================="

    if [[ "$OPTION" == "c" ]]; then
          echo '╔════════════════════════════════════════════════════════════════════════╗'
          echo '║   R U N N I N G   U P D A T E   F R O M   C L I  B A S E   I M A G E   ║'
          echo '╚════════════════════════════════════════════════════════════════════════╝'
          # -----------------------------------------------------------------------------
          # Phase 3: Switch to FROM_IMAGE
          # -----------------------------------------------------------------------------
          echo "=========================================Booting up Agglayer with $FROM_IMAGE ========================================="
          echo "Running Phase 3 upgrade..."

          sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$FROM_IMAGE#" .env
          if ./run-service-update.sh; then
            echo "Phase 3 upgrade succeeded"
          else
            echo "Phase 3 upgrade failed"
            exit 1
          fi

          sleep 200
          # -------------------------------------------------------------------------------------------------------------------------------
          # Phase 4: Upgrade to TO_IMAGE
          # -------------------------------------------------------------------------------------------------------------------------------
          echo "=======================================Upgrading Agglayer from $FROM_IMAGE → $TO_IMAGE====================================="
          echo "Running Phase 4 upgrade..."
          sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env
          if ./run-service-update.sh; then
            echo "Phase 4 upgrade succeeded"
          else
            echo "Phase 4 upgrade failed"
            exit 1
          fi

    else
          echo '╔══════════════════════════════════════════════════════════════════════════════════╗'
          echo '║   R U N N I N G   U P D A T E   F R O M   K U R T O S I S  B A S E   I M A G E   ║'
          echo '╚══════════════════════════════════════════════════════════════════════════════════╝'
          # ------------------------------------------------------------------------------------------------------------------------------
          # Phase 4: Upgrade to TO_IMAGE
          # ------------------------------------------------------------------------------------------------------------------------------
          echo "=======================================Upgrading Agglayer from $FROM_IMAGE → $TO_IMAGE===----============================"
          echo "Running Phase 4 upgrade..."
          sed -i "s#^TO_IMAGE=.*#TO_IMAGE=$TO_IMAGE#" .env
          if ./run-service-update.sh; then
            echo "Phase 4 upgrade succeeded"
          else
            echo "Phase 4 upgrade failed"
            exit 1
          fi
    fi

echo "======================================================================================================================================"

fi



