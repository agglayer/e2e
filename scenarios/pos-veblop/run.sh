#!/bin/env bash
set -e

source ../common/load-env.sh
load_env

enclave_name="pos-veblop"
bor_tag="0fe4b0d"
heimdallv2_tag="0d27dfc"

# Spin up the network
if [[ "$SKIP_DEPLOYMENT" != "true" ]]; then
  # Build local images
  if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/bor:$bor_tag"; then
    echo "Building bor:$bor_tag..."
    git clone --branch develop https://github.com/0xPolygon/bor
    pushd bor
    git checkout "$bor_tag"
    docker build -t "local/bor:$bor_tag" .
    popd
  fi

  if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "local/heimdall-v2:$heimdallv2_tag"; then
    echo "Building heimdall-v2:$heimdallv2_tag..."
    git clone --branch develop https://github.com/0xPolygon/heimdall-v2
    pushd heimdall-v2
    git checkout "$heimdallv2_tag"
    docker build -t "local/heimdall-v2:$heimdallv2_tag" .
    popd
  fi

  echo "Deploying the kurtosis enclave..."
  kurtosis run --enclave "$enclave_name" --args-file params.yml github.com/0xPolygon/kurtosis-pos@d7102e27da39c91bc19540ff45a76fab392dbcca
else
  echo "Skipping deployment as requested"
fi

# Wait for veblop hard fork to be enabled (block 256)
l2_rpc_url=$(kurtosis port print "$enclave_name" "l2-el-1-bor-heimdall-v2-validator" rpc)
block_number=0
while [[ "$block_number" -lt 270 ]]; do
  echo "Waiting for block 270... Current: $block_number"
  sleep 5
  block_number=$(cast block-number --rpc-url "$l2_rpc_url")
done
echo "VeBLoP hardfork is now enabled (block number: $block_number)"

# Run veblop tests
if [[ "$SKIP_TESTS" != "true" ]]; then
  echo "Running veblop tests..."
  cd ../..
  export KURTOSIS_ENCLAVE_NAME="$enclave_name"
  bats tests/pos/veblop.bats
  if [[ $? -ne 0 ]]; then
    echo "❌ Tests failed"
    exit 1
  fi
  echo "✅ Tests passed"
else
  echo "Skipping tests as requested"
fi
