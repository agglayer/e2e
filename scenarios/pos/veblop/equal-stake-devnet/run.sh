#!/bin/env bash

# This scenario checks that producer rotation iterates through all qualified candidates in a deterministic order.

set -e

enclave_name="pos-equal-stake-devnet"
kurtosis_pos_tag="stateless"
bor_tag="e3c09a2" # develop - 2025/09/09
heimdallv2_tag="82ead2c" # develop - 2025/09/05

# Load common functions
source ../common.sh

# Build local images if needed
build_local_images "$bor_tag" "$heimdallv2_tag"

# Clone the kurtosis-pos repository
git clone https://github.com/0xPolygon/kurtosis-pos.git
pushd kurtosis-pos || exit 1
git checkout "$kurtosis_pos_tag"

# Spin up the network
kurtosis run --enclave "$enclave_name" --args-file ../params.yml .

# Wait for Veblop hardfork to be enabled
l2_rpc_url=$(kurtosis port print "$enclave_name" "l2-el-1-bor-heimdall-v2-validator" rpc)
wait_for_veblop_hf "$l2_rpc_url"

# Wait for at least 6 spans to be created
cl_api_url=$(kurtosis port print "$enclave_name" l2-cl-1-heimdall-v2-bor-validator http)
latest_span_id=$(curl -s "$cl_api_url/bor/spans/latest" | jq -r '.span.id')
if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
  echo "Error: Could not retrieve latest span ID"
  exit 1
fi
spans=$((latest_span_id - 1))

ts=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$ts] Number of spans: $spans"
while [[ "$spans" -lt 7 ]]; do
  sleep 5
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  latest_span_id=$(curl -s "$cl_api_url/bor/spans/latest" | jq -r '.span.id')
  spans=$((latest_span_id - 1))
  echo "[$ts] Number of spans: $spans"
done
echo "At least 6 spans have been created!"

# Get the selected producers for each span
# Check that the order is deterministic (1,2,3,1,2,3,...) since all candidates have the same stake
err_found=0
for ((i=2; i<=7; i++)); do
  expected_producer=$(( ((i-1) % 3 ) + 1 ))
  producer=$(curl -s "$cl_api_url/bor/spans/$i" | jq -r '.span.selected_producers[0].val_id')
  if [[ "$producer" == "$expected_producer" ]]; then
    echo "Span $i: Producer is $producer (expected $expected_producer)"
  else
    echo "Span $i: Producer is $producer (expected $expected_producer)"
    err_found=1
  fi
done

if [[ "$err_found" -ne 0 ]]; then
  echo "Error: Producer rotation did not follow the expected order"
  exit 1
fi
echo "Producer rotation followed the expected order"
