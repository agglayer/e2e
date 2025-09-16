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

# TODO: Check that producer rotation iterates through all qualified candidates in a deterministic order.
