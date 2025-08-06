#!/usr/bin/env bash
set -e
source ../common/load-env.sh
load_env

ENCLAVE="$ENCLAVE_NAME"
FROM_IMAGE="$FROM_IMAGE"
TO_IMAGE="$TO_IMAGE"

echo "$ENCLAVE"
echo "$FROM_IMAGE"
echo "$TO_IMAGE"



export FROM_IMAGE="$FROM_IMAGE"
export TO_IMAGE="$TO_IMAGE"

if [ -z "$FROM_IMAGE" ] || [ -z "$TO_IMAGE" ]; then
  echo "Usage: $0 <from-image> <to-image>"
  exit 1
fi

sleep 60



# 2) Once it’s healthy, update in place to your "to" tag
echo " downgrading agglayer-prover image to the target image: $TO_IMAGE …"
kurtosis service update \
  "$ENCLAVE" \
  agglayer-prover \
  --image "$TO_IMAGE" \
  --ports api=4445,prometheus=9093 \


sleep 120


echo " downgrading agglayer image to the target image: $TO_IMAGE …"
kurtosis service update \
  "$ENCLAVE" \
  agglayer \
  --image "$TO_IMAGE" \
  --ports aglr-readrpc=9090,prometheus=9092,aglr-grpc=9089,aglr-admin=9091

# 3) Verify
echo " agglayer now running:"

