#!/bin/env bash

function build_bor_image() {
  bor_tag="$1"

  echo "Building bor:$bor_tag..."
  git clone --branch develop https://github.com/0xPolygon/bor
  pushd bor || exit 1
  git checkout "$bor_tag"
  docker build -t "local/bor:$bor_tag" .
  popd || exit 1
}

function build_heimdallv2_image() {
  heimdallv2_tag="$1"

  echo "Building heimdall-v2:$heimdallv2_tag..."
  git clone --branch develop https://github.com/0xPolygon/heimdall-v2
  pushd heimdall-v2 || exit 1
  git checkout "$heimdallv2_tag"
  docker build -t "local/heimdall-v2:$heimdallv2_tag" .
  popd || exit 1
}

function wait_for_veblop_hf() {
  l2_rpc_url="$1"

  block_number=$(cast block-number --rpc-url "$l2_rpc_url")
  echo "Waiting for block 256..." # plus some margin, here 20 blocks more
  echo "Block number: $block_number"
  while [[ "$block_number" -lt 276 ]]; do
    sleep 5
    block_number=$(cast block-number --rpc-url "$l2_rpc_url")
    echo "Block number: $block_number"
  done
  echo "✅ VeBLoP hardfork is now enabled!"
}
