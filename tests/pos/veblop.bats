#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
}

# bats test_tags=veblop
@test "stop the current block producer mid-span" {
  # Get current span.
  next_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  span_id=$(($(echo "$next_span" | jq -r .span.id) - 1))
  span=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}")

  # Double-check that the current block number is included in the current span.
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  start_block=$(echo "${span}" | jq -r .span.start_block)
  end_block=$(echo "${span}" | jq -r .span.end_block)
  if [[ "${start_block}" -le "${block_number}" && "${end_block}" -ge "${block_number}" ]]; then
    echo "Block number ${block_number} is within span ${span_id}."
  else
    echo "Block number ${block_number} is NOT within span ${span_id}."
    exit 1
  fi

  # Stop the current block producer.
  block_producer_id=$(echo "${span}" | jq -r '.span.selected_producers[0].val_id')
  kurtosis service stop "${ENCLAVE_NAME}" "l2-el-${block_producer_id}-bor-heimdall-v2-validator"

  # TODO: Make sure the chain is not halted.
  # TODO: Make sure another block producer is selected.
}