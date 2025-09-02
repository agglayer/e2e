#!/bin/env bash
set -e

enclave_name="pos-veblop"

# Spin up the network
kurtosis run --enclave "$enclave_name" --args-file params.yml github.com/0xPolygon/kurtosis-pos@v1.1.7

echo ' __     _______ ____  _     ___  ____  '
echo ' \ \   / / ____| __ )| |   / _ \|  _ \ '
echo '  \ \ / /|  _| |  _ \| |  | | | | |_) |'
echo '   \ V / | |___| |_) | |__| |_| |  __/ '
echo '    \_/  |_____|____/|_____\___/|_|    '

# Wait for veblop hard fork to be enabled (block 256)
block_number=0
while [[ "$block_number" -lt 270 ]]; do
  echo "Waiting for block 270... Current: $block_number"
  sleep 5
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
done
echo "VeBLoP hardfork is now enabled"

# Run veblop tests
cd ../..
export KURTOSIS_ENCLAVE_NAME="$enclave_name"
bats tests/pos/veblop.bats
if [[ $? -ne 0 ]]; then
  echo "❌ Tests failed"
  exit 1
fi
echo "✅ Tests passed"
