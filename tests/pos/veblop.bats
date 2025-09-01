#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Skip veblop tests if not enabled.
  is_veblop_enabled || exit 1
}

function is_veblop_enabled() {
  local block_number
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  [[ $block_number -gt 256 ]]
}

function get_current_span_id() {
  next_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  current_span_id=$(($(echo "$next_span" | jq -r .span.id) - 1))
  echo "${current_span_id}"
}

function get_current_block_producer_id() {
  span_id="$1"
  span=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}")
  block_producer_id=$(echo "${span}" | jq -r '.span.selected_producers[0].val_id')
  echo "${block_producer_id}"
}

# bats test_tags=veblop
@test "stop the current block producer mid-span" {
  # Right after the primary producer stops, there should be a new span with a different producer.
  # We should observe the following log in heimdall: "Updating latest span due to different author".
  # - The chain should not halt.
  # - There should not be any reorgs.

  # Get the current span id.
  span_id=$(get_current_span_id)

  # Check that the span is not ending soon.
  span=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}")
  span_end_block=$(echo "${span}" | jq -r '.span.end_block')
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  if [[ $((block_number + 5)) -ge "${span_end_block}" ]]; then
    echo "Current span is ending soon or has already ended. Aborting test."
    exit 0
  fi

  # Stop the current block producer.
  block_producer_id=$(get_current_block_producer_id "${span_id}")
  kurtosis service stop "${ENCLAVE_NAME}" "l2-cl-${block_producer_id}-heimdall-v2-bor-validator"
  kurtosis service stop "${ENCLAVE_NAME}" "l2-el-${block_producer_id}-bor-heimdall-v2-validator"
  echo "Block producer id ${block_producer_id} stopped"

  # Update the rpc and api urls if the first validator was stopped.
  if [[ "${block_producer_id}" == "1" ]]; then
    export L2_RPC_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-el-2-bor-heimdall-v2-validator" rpc)
    export L2_CL_API_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-cl-2-heimdall-v2-bor-validator" http)
  fi

  # Wait until the chain progresses by at least 30 blocks.
  # NOTE: We could wait for less blocks maybe?
  echo "Waiting for chain to progress..."
  assert_command_eventually_greater_than "cast block-number --rpc-url ${L2_RPC_URL}" $((block_number + 30)) "180" "10"

  # TODO: Monitor how heimdall elects the next block producer.
}