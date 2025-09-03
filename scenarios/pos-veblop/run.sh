#!/bin/env bash
set -e

enclave_name="pos-veblop"
bor_tag="0fe4b0d" # develop - 2025/08/29
heimdallv2_tag="0d27dfc" # develop - 2025/09/01


# Default environment file
ENV_FILE=".env.default"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Load environment variables from file
if [[ -f "${ENV_FILE}" ]]; then
  echo "Loading environment variables from ${ENV_FILE}"
  source "${ENV_FILE}"
else
  echo "Error: Environment file ${ENV_FILE} not found"
  exit 1
fi

# Checking environment variables.
if [[ -z "${ARGS_FILE}" ]]; then
  echo "Error: ARGS_FILE environment variable is not set"
  exit 1
fi
if [[ -z "${SKIP_DEPLOYMENT}" ]]; then
  echo "Warning: SKIP_DEPLOYMENT environment variable is not set"
fi
if [[ -z "${SKIP_TESTS}" ]]; then
  echo "Warning: SKIP_TESTS environment variable is not set"
fi


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
  kurtosis run --enclave "$enclave_name" --args-file "$ARGS_FILE" github.com/0xPolygon/kurtosis-pos@d7102e27da39c91bc19540ff45a76fab392dbcca
else
  echo "🚫 Skipping deployment as requested"
fi


# Run veblop tests
if [[ "$SKIP_TESTS" != "true" ]]; then
  # Wait for veblop hard fork to be enabled (block 256)
  l2_rpc_url=$(kurtosis port print "$enclave_name" "l2-el-1-bor-heimdall-v2-validator" rpc)
  block_number=$(cast block-number --rpc-url "$l2_rpc_url")
  echo "Waiting for block 256..."
  echo "Block number: $block_number"
  while [[ "$block_number" -lt 270 ]]; do
    sleep 5
    block_number=$(cast block-number --rpc-url "$l2_rpc_url")
    echo "Block number: $block_number"
  done
  echo "✅ VeBLoP hardfork is now enabled!"

  echo "Running veblop tests..."
  cd ../..
  export ENCLAVE_NAME="$enclave_name"
  bats tests/pos/veblop.bats
  if [[ $? -ne 0 ]]; then
    echo "❌ Tests failed"
    exit 1
  fi
  echo "✅ Tests passed"
else
  echo "🚫 Skipping tests as requested"
fi
