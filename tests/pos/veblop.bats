#!/usr/bin/env bats
# bats test_tags=pos

function is_veblop_enabled() {
  local block_number
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  [[ $block_number -gt 270 ]]
}

function get_current_validator_id() {
  # Get the latest span.
  local latest_span
  latest_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  local latest_span_id
  latest_span_id=$(echo "$latest_span" | jq -r '.span.id')
  if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
    echo "Error: Could not retrieve latest span id" >&2
    return 1
  fi

  # Get the current span (latest - 1).
  local current_span_id=$((latest_span_id - 1))
  local current_span
  current_span=$(curl -s "${L2_CL_API_URL}/bor/spans/${current_span_id}")
  if [[ -z "$current_span" || "$current_span" == "null" ]]; then
    echo "Error: Could not retrieve current span" >&2
    return 1
  fi

  # Extract the validator id.
  local validator_id
  validator_id=$(echo "$current_span" | jq -r '.span.selected_producers[0].val_id')
  if [[ -z "$validator_id" || "$validator_id" == "null" ]]; then
    echo "Error: Could not retrieve validator id" >&2
    return 1
  fi

  echo "$validator_id"
}

function get_reorg_count() {
  l2_metrics_url="$1"
  local reorg_count
  reorg_count=$(curl -s "$l2_metrics_url/debug/metrics/prometheus" | grep -e "^chain_reorg_executes" | awk '{print $2}')
  if [[ -z "$reorg_count" || "$reorg_count" == "null" ]]; then
    echo "Error: Could not retrieve reorg count" >&2
    return 1
  fi
  echo "$reorg_count"
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

# bats test_tags=veblop
@test "isolate the current block producer mid-span to trigger a producer rotation" {
  # Get the current validator id.
  validator_id=$(get_current_validator_id)
  if [[ $? -ne 0 ]]; then
    echo "Failed to get current validator id"
    exit 1
  fi
  echo "Current block producer validator id: $validator_id"

  # Get the current block number.
  block_number=$(cast block-number --rpc-url "$L2_RPC_URL")
  echo "Block number: $block_number"

  # Get the reorg count from the first rpc node.
  # Note: We assume the devnet contains at least three validator nodes and one rpc.
  rpc_node=$(docker ps --format '{{.Names}}' | grep "^l2-el-.*-bor-heimdall-v2-rpc" | head -n 1 | sed 's/--.*$//')
  l2_metrics_url=$(kurtosis port print "$ENCLAVE_NAME" "$rpc_node" metrics)
  if [[ -z "$l2_metrics_url" ]]; then
    echo "Error: Could not retrieve L2 metrics url" >&2
    exit 1
  fi

  initial_reorg_count=$(get_reorg_count "$l2_metrics_url")
  echo "Initial reorg count: $initial_reorg_count"

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

  # Get the reorg count.
  final_reorg_count=$(get_reorg_count "$l2_metrics_url")
  echo "Final reorg count: $final_reorg_count"

  if [[ $final_reorg_count -ne $initial_reorg_count ]]; then
    echo "❌ Detected reorg on rpc node ($rpc_node) during producer rotation"
    exit 1
  fi
}

# bats test_tags=veblop
@test "enforce minimum one and maximum three selected producers per span" {
  # Get the latest span.
  latest_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  latest_span_id=$(echo "$latest_span" | jq -r '.span.id')
  if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
    echo "Error: Could not retrieve latest span id"
    return 1
  fi

  # Iterate through all the spans and check the number of producers.
  for ((span_id=1; span_id<=latest_span_id; span_id++)); do
    producer_count=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}" | jq -r '.span.selected_producers | length')
    echo "Span $span_id: $producer_count producer(s)"
    if [[ "$producer_count" -lt 1 ]]; then
      echo "Error: No producer found for span $span_id"
      exit 1
    fi
    if [[ "$producer_count" -gt 3 ]]; then
      echo "Error: More than 3 selected producers for span $span_id"
      exit 1
    fi
  done
}

function get_block_author() {
  block_number="$1"
  local block_number_hex
  block_number_hex=$(printf "0x%x" "$block_number")
  cast rpc bor_getAuthor "$block_number_hex" --rpc-url "$L2_RPC_URL"
}

# bats test_tags=equal-slot-distribution
@test "enforce equal slot distribution between block producers" {
  # This invariant won't be enforced if there have been producer rotations.

  # Get the latest span.
  latest_span=$(curl -s "${L2_CL_API_URL}/bor/spans/latest")
  latest_span_id=$(echo "$latest_span" | jq -r '.span.id')
  if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
    echo "Error: Could not retrieve latest span id"
    return 1
  fi

  # Iterate through all the spans and count the number of spans by producer.
  declare -A span_count
  total_spans=0
  for ((span_id=1; span_id<=latest_span_id; span_id++)); do
    producer=$(curl -s "${L2_CL_API_URL}/bor/spans/${span_id}" | jq -r '.span.selected_producers[0].signer')
    span_count["$producer"]=$((${span_count["$producer"]:-0} + 1))
    total_spans=$((total_spans + 1))
  done

  # Print slot distribution by producer.
  echo "Slot distribution by producer:"
  for producer in "${!span_count[@]}"; do
    echo "- Producer $producer: ${span_count[$producer]} blocks"
  done

  num_producers=${#span_count[@]}
  expected_spans_per_producer=$((total_spans / num_producers))
  echo "Total spans: $total_spans"
  echo "Number of producers: $num_producers"
  echo "Expected spans per producer: ~$expected_spans_per_producer"

  # Check if the distribution is reasonably equal
  tolerance=1  # ±1 span
  for producer in "${!span_count[@]}"; do
    count=${span_count[$producer]}
    diff=$((count - expected_spans_per_producer))
    abs_diff=${diff#-}  # Remove negative sign for absolute value
    if ((abs_diff > tolerance)); then
      echo "❌ Unequal distribution: Producer $producer has $count spans (expected ~$expected_spans_per_producer ±$tolerance)"
      exit 1
    fi
  done
}

# bats test_tags=equal-slot-distribution
@test "enforce equal block distribution between block producers" {
  # This test usually takes around 30/40 seconds to run.
  # This invariant won't be enforced if there have been producer rotations.

  # Get the current block number.
  block_number=$(cast block-number --rpc-url "$L2_RPC_URL")
  echo "Block number: $block_number"

  # Iterate through the last thousand blocks and count the number of blocks by producer.
  declare -A block_count
  total_blocks=0
  for ((i=block_number-999; i<=block_number; i++)); do
    producer=$(get_block_author "$i")
    block_count["$producer"]=$((${block_count["$producer"]:-0} + 1))
    total_blocks=$((total_blocks + 1))
  done

  # Print block distribution by producer.
  echo "Block distribution by producer:"
  for producer in "${!block_count[@]}"; do
    echo "- Producer $producer: ${block_count[$producer]} blocks"
  done

  num_producers=${#block_count[@]}
  expected_blocks_per_producer=$((total_blocks / num_producers))
  echo "Total blocks: $total_blocks"
  echo "Number of producers: $num_producers"
  echo "Expected blocks per producer: ~$expected_blocks_per_producer"

  # Check if the distribution is reasonably equal
  tolerance=128  # ±1 span (128 blocks)
  for producer in "${!block_count[@]}"; do
    count=${block_count[$producer]}
    diff=$((count - expected_blocks_per_producer))
    abs_diff=${diff#-}  # Remove negative sign for absolute value
    if ((abs_diff > tolerance)); then
      echo "❌ Unequal distribution: Producer $producer has $count blocks (expected ~$expected_blocks_per_producer ±$tolerance)"
      exit 1
    fi
  done
}
