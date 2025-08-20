#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
}

function get_current_block_producer() {
  next_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  current_span_id=$(($(echo "$next_span" | jq -r .span.id) - 1))
  current_span=$(curl -s "${L2_CL_API_URL}/bor/spans/${current_span_id}")

  # Double-check that the current block number is included in the current span.
  # block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  # start_block=$(echo "${span}" | jq -r .span.start_block)
  # end_block=$(echo "${span}" | jq -r .span.end_block)
  # if [[ "${start_block}" -le "${block_number}" && "${end_block}" -ge "${block_number}" ]]; then
  #   echo "Block number ${block_number} is within span ${span_id}."
  # else
  #   echo "Block number ${block_number} is NOT within span ${span_id}."
  #   exit 1
  # fi

  block_producer_id=$(echo "${current_span}" | jq -r '.span.selected_producers[0].val_id')
  block_producer="l2-el-${block_producer_id}-bor-heimdall-v2-validator"
  echo "${block_producer}"
}

# bats test_tags=veblop
@test "stop the current block producer mid-span" {
  # Stop the current block producer.
  read block_producer < <(get_current_block_producer)
  kurtosis service stop "${ENCLAVE_NAME}" "${block_producer}"
  echo "Block producer stopped: ${block_producer}" >&3

  # Update the rpc and api urls if the first validator was stopped.
  if [[ "${block_producer}" == "l2-el-1-bor-heimdall-v2-validator" ]]; then
    export L2_RPC_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-el-2-bor-heimdall-v2-validator" rpc)
    export L2_CL_API_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-cl-2-heimdall-v2-bor-validator" http)
  fi

  # Wait until the chain progresses by at least 10 blocks.
  echo "Last block number before stopping producer: ${last_block_number}" >&3
  current_block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  while (( current_block_number <= last_block_number + 10 )); do
    echo "Waiting for chain to progress... Current block: ${current_block_number}" >&3
    sleep 2
    current_block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  done
  echo "Chain has progressed. Current block: ${current_block_number}" >&3

  # Make sure another block producer is selected.
  read new_block_producer < <(get_current_block_producer)
  if [[ "${new_block_producer}" != "${block_producer}" ]]; then
    echo "New block producer: ${new_block_producer}" >&3
  else
    echo "Block producer did not change as expected." >&3
    exit 1
  fi
}