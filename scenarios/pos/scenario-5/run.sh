#!/bin/env bash
set -e

source ../common.sh

enclave_name="pos-veblop-5"
bor_tag="0fe4b0d" # develop - 2025/08/29
heimdallv2_tag="0d27dfc" # develop - 2025/09/01
kurtosis_pos_tag="7bee88b569cfe566575e674359a7fc105c70169f" # test/10x-stake-first-validator - 2025/09/03

# Build local images if needed
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/bor:$bor_tag"; then
  build_bor_image "$bor_tag"
fi

if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/heimdall-v2:$heimdallv2_tag"; then
  build_heimdallv2_image "$heimdallv2_tag"
fi

# Spin up the network
echo "Deploying the kurtosis enclave..."
kurtosis run --enclave "$enclave_name" --args-file params.yml "github.com/0xPolygon/kurtosis-pos@$kurtosis_pos_tag"

# Wait for veblop hard fork to be enabled (block 256)
l2_rpc_url=$(kurtosis port print "$enclave_name" "l2-el-1-bor-heimdall-v2-validator" rpc)
wait_for_veblop_hf "$l2_rpc_url"

# Run veblop default tests
export ENCLAVE_NAME="$enclave_name"
bats --filter-tags equal-slot-distribution ../../../tests/pos/veblop.bats
