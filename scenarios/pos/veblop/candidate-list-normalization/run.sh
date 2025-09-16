#!/bin/env bash
set -e

# Define scenario specific variables
enclave_name="pos-candidate-list-normalization"
kurtosis_pos_tag="stateless"
bor_tag="e3c09a2" # develop - 2025/09/09
heimdallv2_tag="82ead2c" # develop - 2025/09/05

# Load common functions
source ../common.sh

# Build local images if needed
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/bor:$bor_tag"; then
  build_bor_image "$bor_tag"
fi

if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/heimdall-v2:$heimdallv2_tag"; then
  build_heimdallv2_image "$heimdallv2_tag"
fi

# Clone kurtosis-pos repository
git clone https://github.com/0xPolygon/kurtosis-pos.git
pushd kurtosis-pos || exit 1
git checkout "$kurtosis_pos_tag"

# Modify the producer vote list to include duplicates and empty entries.
# The list also contains more than the three maximum expected entries.
app_toml_path="static_files/cl/heimdall_v2/app.toml"
tomlq -t '.custom.producer_votes="1,1,1,,,,,,2,3,4,5,5,,,6,7,8,8,9,,10,,"' "$app_toml_path" > "${app_toml_path}.tmp"
mv "${app_toml_path}.tmp" "$app_toml_path"

# Spin up the network
kurtosis run --enclave "$enclave_name" --args-file ../params.yml .

# Wait for Veblop hardfork to be enabled
l2_rpc_url=$(kurtosis port print "$enclave_name" "l2-el-1-bor-heimdall-v2-validator" rpc)
wait_for_veblop_hf "$l2_rpc_url"

# TODO: Run the candidate list normalization test
# Make sure the devnet is running and the producer vote list has been normalized.
