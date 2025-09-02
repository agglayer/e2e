#!/usr/bin/env bats
# bats test_tags=pos

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "../../core/helpers/scripts/eventually.bash"
  pos_setup

  # Skip veblop tests if not enabled.
  if ! is_veblop_enabled; then
    echo "Veblop hardfork is not enabled (block number <= 256). Aborting tests."
    exit 1
  fi
}

function is_veblop_enabled() {
  local block_number
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  [[ $block_number -gt 270 ]]
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
# @test "stop the current block producer mid-span" {
#   # Right after the primary producer stops, there should be a new span with a different producer.
#   # We should observe the following log in heimdall: "Updating latest span due to different author".
#   # - The chain should not halt.
#   # - There should not be any reorgs.

#   # Get the current span id.
#   span_id=$(get_current_span_id)

#   # Check that the span is not ending soon.
#   span=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}")
#   span_end_block=$(echo "${span}" | jq -r '.span.end_block')
#   block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
#   if [[ $((block_number + 5)) -ge "${span_end_block}" ]]; then
#     echo "Current span is ending soon or has already ended. Aborting test."
#     exit 1
#   fi
#   echo "Block number: ${block_number}"
#   echo "Span id: ${span_id}"
#   echo "Span end block: ${span_end_block}"

#   # Stop the current block producer.
#   block_producer_id=$(get_current_block_producer_id "${span_id}")
#   echo "Stopping block producer id ${block_producer_id}..."
#   kurtosis service stop "${ENCLAVE_NAME}" "l2-cl-${block_producer_id}-heimdall-v2-bor-validator"
#   kurtosis service stop "${ENCLAVE_NAME}" "l2-el-${block_producer_id}-bor-heimdall-v2-validator"
#   echo "Block producer id ${block_producer_id} stopped"

#   # Update the rpc and api urls if the first validator was stopped.
#   if [[ "${block_producer_id}" == "1" ]]; then
#     export L2_RPC_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-el-2-bor-heimdall-v2-validator" rpc)
#     export L2_CL_API_URL=$(kurtosis port print "${ENCLAVE_NAME}" "l2-cl-2-heimdall-v2-bor-validator" http)
#   fi

#   # Wait until the chain progresses by at least 30 blocks.
#   # NOTE: We could wait for less blocks maybe?
#   echo "Waiting for chain to progress..."
#   assert_command_eventually_greater_than "cast block-number --rpc-url ${L2_RPC_URL}" $((block_number + 30)) "180" "10"

#   # TODO: Monitor how heimdall elects the next block producer.
# }

### test

function isolate_container_from_el_nodes() {
  node_name="$1"
  node_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node_name")

  # Create a list that includes all the el nodes except the el node we want to isolate
  target_flags=()
  for c in $(docker ps --format "{{.Names}}" | grep "^l2-el"); do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
    if [[ -n "$ip" && "$ip" != "$node_ip" ]]; then
      target_flags+=(--target "${ip}/32")
    fi
  done

  # Isolate the node using pumba
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gaiaadm/pumba:0.10.1 netem \
    "$target_flags" \
    --tc-image "gaiadocker/iproute2" \
    --duration "15s" \
    --interface "eth0" \
    delay --time 6000 --jitter 1000 "$node_name"
}

@test "stop the current block producer mid-span by isolating the producer's el node from other el nodes" {
  # Get latest span id
  latest_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  latest_span_id=$(echo "$latest_span" | jq -r '.span.id')
  if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
    echo "Error: Could not retrieve latest span id"
    exit 1
  fi
  echo "Latest span id: $latest_span_id"

  # Get the current span
  current_span_id=$((latest_span_id - 1))
  current_span=$(curl -s "${L2_CL_API_URL}/bor/spans/${current_span_id}")
  if [[ -z "$current_span" || "$current_span" == "null" ]]; then
    echo "Error: Could not retrieve current span"
    exit 1
  fi
  echo "Current span id: $current_span_id"

  # Extract signer and validator id
  signer=$(echo "$current_span" | jq -r '.span.selected_producers[0].signer')
  validator_id=$(echo "$current_span" | jq -r --arg signer "$signer" \
    '.span.validator_set.validators[] | select(.signer | ascii_downcase == ($signer | ascii_downcase)) | .val_id')
  if [[ -z "$validator_id" || "$validator_id" == "null" ]]; then
    echo "Error: Could not retrieve validator id"
    exit 1
  fi
  echo "Current producer signer address: $signer"
  echo "Corresponding validator id: $validator_id"

  # Isolate the current block producer with network delays
  echo "Isolating the current block producer with network delays..."
  container_name=$(docker ps --format '{{.Names}}' | grep "^l2-el-${validator_id}-bor-heimdall-v2-validator--")
  isolate_container_from_el_nodes "$container_name"
  echo "Container isolated"
}