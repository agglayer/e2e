#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup
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
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  span_id=$(get_current_span_id)

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

  # Wait until the chain progresses by at least a full span (128 blocks).
  # TODO: We could wait for less blocks maybe?
  assert_command_eventually_greater_than "cast block-number --rpc-url ${L2_RPC_URL}" $((block_number + 128)) "180" "10"

  # Make sure another block producer is selected.
  new_block_producer_id=$(get_current_block_producer_id "${span_id}")
  if [[ "${new_block_producer_id}" != "${block_producer_id}" ]]; then
    echo "New block producer: ${new_block_producer_id}"
  else
    echo "Block producer did not change as expected."
    exit 1
  fi
}