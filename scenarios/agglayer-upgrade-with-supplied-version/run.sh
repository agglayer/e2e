#!/bin/env bash
set -e


# ----------------------------------------------------------------------
# Function: Adds rollup RPCs to agglayer and restarts the service
# ----------------------------------------------------------------------
add_rollup_rpc_to_agglayer() {
    echo "Updating agglayer config..."

    kurtosis service exec cdk agglayer '
      set -eu
      file=/etc/zkevm/agglayer-config.toml
      if ! grep -q "2 = http://cdk-erigon-rpc-002:8123" "$file"; then
          sed -i "/1 = \"http:\/\/cdk-erigon-rpc-001:8123\"/a 2 = \"http://cdk-erigon-rpc-002:8123\"" "$file"
          sed -i "/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"/a 3 = \"http://cdk-erigon-rpc-003:8123\"" "$file"
      fi
    '

    echo "Restarting agglayer..."
    kurtosis service stop cdk agglayer
    kurtosis service start cdk agglayer

    echo "Done."
}



# -----------------------------------------------------------------------------------------------------------------
# Function: to verify deployment by checking for events  VerifyBatchesTrustedAggregator in the contract deployments
# ------------------------------------------------------------------------------------------------------------------
run_verification_in_container() (
  set -euo pipefail
  set -o pipefail

  SERVICE_NAME="${1:?Usage: run_verification_in_container <SERVICE_NAME> [LOCAL_SCRIPT] [RPC_URL]}"
  LOCAL_SCRIPT="${2:-./check_verification.sh}"
  RPC_URL="${3:-http://el-1-geth-lighthouse:8545}"

  LOG_DIR="${LOG_DIR:-./logs}"
  mkdir -p "$LOG_DIR"
  LOG_FILE="${LOG_DIR}/${SERVICE_NAME}.log"

  START_TS="$(date -Is)" # current timestamp
  echo "[START  ${START_TS}] ${SERVICE_NAME}"

  # Find the kurtosis container for the service 
  # It finds  the most recent container whose name starts with ${SERVICE_NAME}-- and stores its name in CONTAINER
  CONTAINER="$(docker ps -a --format '{{.Names}}' | grep -E "^${SERVICE_NAME}--" | head -n1 || true)"

  # Run and stream output to both terminal and log
  {
    echo "---- ${START_TS} BEGIN ${SERVICE_NAME} ----"
    # checks if no service was found and exits
    if [[ -z "${CONTAINER}" ]]; then
      echo "No container found matching \"${SERVICE_NAME}--*\"" >&2
      echo "---- $(date -Is) END ${SERVICE_NAME} rc=127 ----"
      exit 127
    fi

    # continues execution if service was found
    echo "Using container: ${CONTAINER}"

    # Copy local script into the container
    REMOTE_SCRIPT="/tmp/check_verification.sh"
    echo "Copying ${LOCAL_SCRIPT} -> ${CONTAINER}:${REMOTE_SCRIPT}"
    docker cp "${LOCAL_SCRIPT}" "${CONTAINER}:${REMOTE_SCRIPT}"

    # Patch placeholders from combined.json and execute
    docker exec -e RPC_URL="${RPC_URL}" "${CONTAINER}" bash -lc '
      set -euo pipefail
      FILE=/opt/zkevm/combined.json
      [[ -f "$FILE" ]] || { echo "Missing $FILE"; exit 1; }

      if command -v jq >/dev/null 2>&1; then
        ROLLUP_MANAGER=$(jq -r ".polygonRollupManagerAddress" "$FILE")
      else
        ROLLUP_MANAGER=$(grep -oP "\"polygonRollupManagerAddress\"\\s*:\\s*\"\\K0x[0-9a-fA-F]+" "$FILE")
      fi

      [[ -n "$ROLLUP_MANAGER" ]] || { echo "Could not parse polygonRollupManagerAddress"; exit 1; }


      echo "ROLLUP_MANAGER=$ROLLUP_MANAGER"

      sed -i "s|__ROLLUP_MANAGER__|$ROLLUP_MANAGER|g" "'"$REMOTE_SCRIPT"'"
      chmod +x "'"$REMOTE_SCRIPT"'"
      "'"$REMOTE_SCRIPT"'"
    '
    RC=$? # saves exits status of prev execution
    echo "---- $(date -Is) END ${SERVICE_NAME} rc=${RC} ----"
    exit $RC
  } 2>&1 | tee -a "$LOG_FILE". # stdout & stderr from the prev cmd, pipes it & appends to log file shows also on terminal.

  # Preserve the exit code of the block (left side of the pipe)
  RC=${PIPESTATUS[0]} # captures the exit code of the first command in the pipeline
  END_TS="$(date -Is)"
  if [[ $RC -eq 0 ]]; then
    echo "[FINISH ${END_TS}] ${SERVICE_NAME} ✅ (rc=0) | log: ${LOG_FILE}"
  elif [[ $RC -eq 2 ]]; then
    echo "[FINISH ${END_TS}] ${SERVICE_NAME} ⚠️  No verification events (rc=2) | log: ${LOG_FILE}"
  else
    echo "[FINISH ${END_TS}] ${SERVICE_NAME} ❌ (rc=${RC}) | log: ${LOG_FILE}"
  fi
  exit $RC
)


# ----------------------------------------------------------------------
# Load environment
# ----------------------------------------------------------------------
if [[ -f ../common/load-env.sh ]]; then
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


# ------------------------------------------------------------------------------
# CLI Arguments
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
    echo "Downgrade tags match previous upgrade."
  else
    echo "Downgrade tag mismatch!"
    echo "Expected FROM_TAG=$PREV_TO_TAG, TO_TAG=$PREV_FROM_TAG"
    echo "Got      FROM_TAG=$FROM_TAG, TO_TAG=$TO_TAG"
    exit 1
  fi
fi

# Compose full image references
IMAGE_BASE="ghcr.io/agglayer/agglayer"
FROM_IMAGE="${IMAGE_BASE}:${FROM_TAG}"
TO_IMAGE="${IMAGE_BASE}:${TO_TAG}"




sed -i "s#^FROM_TAG=.*#FROM_TAG=$FROM_TAG#" .env
sed -i "s#^TO_TAG=.*#TO_TAG=$TO_TAG#" .env


KURTOSIS_HASH="$KURTOSIS_PACKAGE_HASH"
KURTOSIS_ENCLAVE_NAME="$ENCLAVE_NAME"



echo ":-kurtosis hash:= $KURTOSIS_HASH"
echo ":-enclave name:= $KURTOSIS_ENCLAVE_NAME"
echo ":-from image:= $FROM_IMAGE"
echo ":-to image:= $TO_IMAGE"
echo ":-from tag:= $FROM_TAG"
echo ":-to tag:= $TO_TAG"
echo ":-action:= $ACTION"



# Create a yml files with a real SP1 keys if needed
yq -y --arg sp1key "$SP1_NETWORK_KEY" --arg newImage "$FROM_IMAGE" '
  .args.agglayer_prover_sp1_key = $sp1key |
  .args.agglayer_image = $newImage
' ./assets/cdk-erigon-validium.yml > initial-cdk-erigon-validium.yml

yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.agglayer_prover_sp1_key = $sp1key
' ./assets/cdk-erigon-rollup.yml > initial-cdk-erigon-rollup.yml


yq -y --arg sp1key "$SP1_NETWORK_KEY" '
.args.agglayer_prover_sp1_key = $sp1key
' ./assets/cdk-erigon-rollup-003.yml > initial-cdk-erigon-rollup-003.yml




# checks if the user is requesting for downgrade
if [[ "$ACTION" == "downgrade" ]]; then

      # check if there is a running enclave
      ENCLAVE_EXIST=$(kurtosis enclave ls | awk '$3 == "RUNNING" {print $2; exit}')
      if [[ "$ENCLAVE_EXIST" != "$KURTOSIS_ENCLAVE_NAME" ]]; then
          echo "Enclave name is not $KURTOSIS_ENCLAVE_NAME. Exiting...OR No Running enclave "
          exit 1
      fi
      
      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   R U N N I N G   D O W N G R A D E   F O R   A G G L A Y E R   F R O M   S U P L I E D   T A G       ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝'

    

      TO_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)
      kurtosis service inspect cdk agglayer --output json \
        | jq --arg img "$TO_IMAGE" '.image = $img' > "$TO_IMAGE_SERVICE_CONFIG_FILE"
     
      echo $TO_IMAGE_SERVICE_CONFIG_FILE
      cat "$TO_IMAGE_SERVICE_CONFIG_FILE"

      kurtosis service rm "$KURTOSIS_ENCLAVE_NAME" agglayer
      kurtosis service add cdk agglayer --json-service-config "$TO_IMAGE_SERVICE_CONFIG_FILE"
      rm  "$TO_IMAGE_SERVICE_CONFIG_FILE"


     

      TO_PROVER_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)
      kurtosis service inspect cdk agglayer-prover --output json \
        | jq --arg img "$TO_IMAGE" '.image = $img' > "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"
      kurtosis service add cdk agglayer-prover --json-service-config "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"
       rm  "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"



      echo "D O W N G R A D E D: C O N F I R M I N G   R U N N I N G  A G G L A Y E R   W I T H   T A R G E T   D O W N G R A D E   V E R S I O N:  $TO_TAG "
      echo "=========================================================================================================================================="
      kurtosis service inspect cdk agglayer --output json
      echo "=========================================================================================================================================="


      echo '╔════════════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      D O W N G R A D I N G    A G G L A Y E R   S U C C E S S F U L L                                      ║'
      echo '╚════════════════════════════════════════════════════════════════════════════════════════════════════════════╝'

      echo " Running Updating Agglayer with Rollup ERIGON ROLLUP RPC NODE"
      add_rollup_rpc_to_agglayer

else
      echo '╔═══════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N   V A L I D I U M  ║'
      echo '╚═══════════════════════════════════════════════════════════════╝'


      kurtosis run \
              --enclave "$KURTOSIS_ENCLAVE_NAME" \
              --args-file ./initial-cdk-erigon-validium.yml \
              "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_HASH"
      

      echo '╔══════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N   V A L I D I U M   S U C C E S S F U L L      ║'
      echo '╚══════════════════════════════════════════════════════════════════════════════════════════════╝'
      


      echo '╔══════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║   R U N N I N G   U P G R A D E   F O R   A G G L A Y E R   F R O M   S U P L I E D   T A G      ║'
      echo '╚══════════════════════════════════════════════════════════════════════════════════════════════════╝'

  

      echo "==================== R U N N I N G   K U R T O S I S  W I T H    A G G L A Y E R   F R O M   I M A G E:  $FROM_IMAGE ============"
      # 1. Create a temporary file  to hold the config json of the current kurtosis base image
      FROM_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)

      # 2. Dump the inspected JSON, update the image, and save to the temp file
      kurtosis service inspect cdk agglayer --output json \
        | jq --arg img "$FROM_IMAGE" '.image = $img' > "$FROM_IMAGE_SERVICE_CONFIG_FILE"
     
      echo $FROM_IMAGE_SERVICE_CONFIG_FILE
      cat "$FROM_IMAGE_SERVICE_CONFIG_FILE"

      kurtosis service rm "$KURTOSIS_ENCLAVE_NAME" agglayer
      kurtosis service add cdk agglayer --json-service-config "$FROM_IMAGE_SERVICE_CONFIG_FILE"

      rm  "$FROM_IMAGE_SERVICE_CONFIG_FILE"



      FROM_PROVER_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)
      echo "AGGLAYER - PROVER CONFIG JSON"
      kurtosis service inspect cdk agglayer-prover --output json \
        | jq --arg img "$FROM_IMAGE" '.image = $img' > "$FROM_PROVER_IMAGE_SERVICE_CONFIG_FILE"
      kurtosis service add cdk agglayer-prover --json-service-config "$FROM_PROVER_IMAGE_SERVICE_CONFIG_FILE"
       rm  "$FROM_PROVER_IMAGE_SERVICE_CONFIG_FILE"

      
     
      echo "==================== R U N N I N G   K U R T O S I S   W I T H    A G G L A Y E R   T O   I M A G E:  $TO_IMAGE ================="
      # 1. Create a temporary file  to hold the config json of the current service
      TO_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)

      # 2. Dump the inspected JSON, update the image, and save to the temp file
      kurtosis service inspect cdk agglayer --output json \
        | jq --arg img "$TO_IMAGE" '.image = $img' > "$TO_IMAGE_SERVICE_CONFIG_FILE"
     
      echo $TO_IMAGE_SERVICE_CONFIG_FILE
      cat "$TO_IMAGE_SERVICE_CONFIG_FILE"

      kurtosis service rm "$KURTOSIS_ENCLAVE_NAME" agglayer
      kurtosis service add cdk agglayer --json-service-config "$TO_IMAGE_SERVICE_CONFIG_FILE"

      rm  "$TO_IMAGE_SERVICE_CONFIG_FILE"


      TO_PROVER_IMAGE_SERVICE_CONFIG_FILE=$(mktemp)
      kurtosis service inspect cdk agglayer-prover --output json \
        | jq --arg img "$TO_IMAGE" '.image = $img' > "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"
      kurtosis service add cdk agglayer-prover --json-service-config "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"
       rm  "$TO_PROVER_IMAGE_SERVICE_CONFIG_FILE"

    

      echo "C O N F I R M I N G   R U N N I N G  A G G L A Y E R   F R O M    S U P P L I E D   B A S E   V E R S I O N:  $TO_TAG "
      echo "========================================================================================================================"
      kurtosis service inspect cdk agglayer --output json
      echo "========================================================================================================================"

     

      echo '╔══════════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║        U P G R A D I N G    A G G L A Y E R   T O  T A R G E T   V E R S I O N  S U C C E S S F U L L    ║'
      echo '╚══════════════════════════════════════════════════════════════════════════════════════════════════════════╝'



      

      echo '╔═════════════════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N    R O L L U P   T W O       ║'
      echo '╚═════════════════════════════════════════════════════════════════════════╝'


      kurtosis run \
              --enclave "$KURTOSIS_ENCLAVE_NAME" \
              --args-file ./initial-cdk-erigon-rollup.yml \
              "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_HASH"  
      
      

      echo '╔═════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N   R O L L U P   S U C C E S S F U L L     ║'
      echo '╚═════════════════════════════════════════════════════════════════════════════════════════╝'
  


      echo '╔═════════════════════════════════════════════════════════════════════════════╗'
      echo '║   A T T A C H I N G    C D K   E R I G O N    R O L L U P   T H R E E       ║'
      echo '╚═════════════════════════════════════════════════════════════════════════════╝'


      kurtosis run \
              --enclave "$KURTOSIS_ENCLAVE_NAME" \
              --args-file ./initial-cdk-erigon-rollup-003.yml \
              "github.com/0xPolygon/kurtosis-cdk@$KURTOSIS_HASH"  
      
      

      echo '╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗'
      echo '║      A T T A C H I N G    C D K   E R I G O N     R O L L U P   T H R E E   S U C C E S S F U L L     ║'
      echo '╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝'



      echo "Modifying agglayer configuration to include new rollup"
      add_rollup_rpc_to_agglayer



      # live countdown for 3 minutes
      for ((s=180; s>0; s--)); do
        printf "\rWaiting 3 min to verify deployment - will execute VerifyBatchesTrustedAggregator event… %02d:%02d" $((s/60)) $((s%60))
        sleep 1
      done
      printf "\r✓ done.          \n"

      for n in 001 002 003; do
        run_verification_in_container "contracts-$n" || true
      done
fi



