#!/usr/bin/env bats
# bats test_tags=pos

function is_veblop_enabled() {
  local block_number
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  [[ $block_number -gt 270 ]]
}

function isolate_container_from_el_nodes() {
  node_name="$1"
  node_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node_name")

  # Create a list that includes all the el nodes except the el node we want to isolate.
  target_flags=()
  for c in $(docker ps --format "{{.Names}}" | grep "^l2-el"); do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
    if [[ -n "$ip" && "$ip" != "$node_ip" ]]; then
      target_flags+=(--target "${ip}/32")
    fi
  done

  # Isolate the node using pumba.
  # It won't be able to send anything to the other EL nodes for a period of 15 seconds.
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gaiaadm/pumba:0.10.1 netem \
    "${target_flags[@]}" \
    --tc-image "gaiadocker/iproute2" \
    --duration "15s" \
	  --interface "eth0" \
    loss --percent 100 "$node_name"
}

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

@test "isolate the current block producer mid-span to trigger a producer rotation" {
  # Get the latest span.
  latest_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  latest_span_id=$(echo "$latest_span" | jq -r '.span.id')
  if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
    echo "Error: Could not retrieve latest span id"
    exit 1
  fi
  echo "Latest span id: $latest_span_id"

  # Get the current span.
  current_span_id=$((latest_span_id - 1))
  current_span=$(curl -s "${L2_CL_API_URL}/bor/spans/${current_span_id}")
  if [[ -z "$current_span" || "$current_span" == "null" ]]; then
    echo "Error: Could not retrieve current span"
    exit 1
  fi
  echo "Current span id: $current_span_id"

  # Extract the validator id.
  validator_id=$(echo "$current_span" | jq -r '.span.selected_producers[0].val_id')
  if [[ -z "$validator_id" || "$validator_id" == "null" ]]; then
    echo "Error: Could not retrieve validator id"
    exit 1
  fi
  echo "Validator id: $validator_id"

  # Get the current block number.
  block_number=$(cast block-number --rpc-url "$L2_RPC_URL")
  echo "Block number: $block_number"

  # Isolate the current block producer from the rest of the network.
  # The node won't be able to send anything to the other EL nodes for 15 seconds.
  # It should trigger a producer rotation.
  echo "Isolating the current block producer from the rest of the network..."
  echo "Container name: $container_name"
  container_name=$(docker ps --format '{{.Names}}' | grep "^l2-el-${validator_id}-bor-heimdall-v2-validator--")
  isolate_container_from_el_nodes "$container_name"
  echo "Container isolated"

  # Note: We could also shut down the block producer’s EL client, but with the current kurtosis-pos
  # setup this isn’t viable. All nodes are configured as static peers, so when one node stops, the
  # others endlessly attempt to reconnect instead of continuing block production. As a result, the
  # chain becomes stuck.

  # Wait for the chain to progress.
  echo "Waiting for the chain to progress..."
  assert_command_eventually_greater_than "cast block-number --rpc-url $L2_RPC_URL" $((block_number + 50)) "180" "10"

  # Get the current block number.
  block_number=$(cast block-number --rpc-url "$L2_RPC_URL")
  echo "Block number: $block_number"
}