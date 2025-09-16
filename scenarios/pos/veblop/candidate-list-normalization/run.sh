#!/bin/env bash

# This scenario checks that the selected producers list is correctly normalized.
# The list should not contain empty entries or duplicates and should have at least 1 entry and at most 3 entries.

set -e

enclave_name="pos-candidate-list-normalization"
kurtosis_pos_tag="test/bad-genesis-selected-producers"
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

# Compare selected producers of the first span between genesis and CL API.
# The genesis selected producers is made of empty entries and duplicates. The list also has more than 3 entries.
# The CL API selected producers should have been normalized to contain at most 3 unique entries.
err_found=0

# Genesis selected producers
genesis_selected_producers=$(kurtosis files inspect pos-candidate-list-normalization l2-cl-genesis genesis.json | jq '.app_state.bor.spans[0].selected_producers')
echo "Selected producers set in the genesis: $genesis_selected_producers"

size=$(jq 'length' <<<"$genesis_selected_producers")
echo "Size: $size"

empty_entries=$(jq 'map(select(. == {})) | length' <<<"$genesis_selected_producers")
echo "Empty entries: $empty_entries"

duplicate_entries=$(jq 'group_by(.) | map(select(length > 1) | {value: .[0], count: length}) | length' <<<"$genesis_selected_producers")
echo "Duplicate entries: $duplicate_entries"

# CL API selected producers
l2_cl_api_url=$(kurtosis port print "$enclave_name" l2-cl-1-heimdall-v2-bor-validator http)
cl_api_selected_producers=$(curl -s $l2_cl_api_url/bor/spans/1 | jq -r '.span.selected_producers')
echo "Selected producers from the CL API: $cl_api_selected_producers"

size=$(jq 'length' <<<"$cl_api_selected_producers")
echo "Size: $size"
if [[ $size -lt 1 ]]; then
  echo "Error: Expected at least 1 producer in the first span but got $size"
  err_found=1
fi
if [[ $size -gt 3 ]]; then
  echo "Error: Expected at most 3 producers in the first span but got $size"
  err_found=1
fi

empty_entries=$(jq 'map(select(. == {})) | length' <<<"$cl_api_selected_producers")
echo "Empty entries: $empty_entries"
if [[ $empty_entries -ne 0 ]]; then
  echo "Error: Expected zero empty entries in the first span but got $empty_entries"
  err_found=1
fi

duplicate_entries=$(jq 'group_by(.) | map(select(length > 1) | {value: .[0], count: length}) | length' <<<"$cl_api_selected_producers")
echo "Duplicate entries: $duplicate_entries"
if [[ $duplicate_entries -ne 0 ]]; then
  echo "Error: Expected zero duplicate entries in the first span but got $duplicate_entries"
  err_found=1
fi

if [[ "$err_found" -ne 0 ]]; then
  echo "Error: Selected producers list has not been normalized correctly"
  exit 1
fi
echo "Selected producers list has been normalized correctly"

