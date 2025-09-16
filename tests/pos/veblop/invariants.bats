#!/usr/bin/env bats

function get_block_author() {
  block_number="$1"
  local block_number_hex
  block_number_hex=$(printf "0x%x" "$block_number")
  cast rpc bor_getAuthor "$block_number_hex" --rpc-url "$L2_RPC_URL"
}

setup() {
  # Load libraries.
  load "../../core/helpers/pos-setup.bash"
  load "./lib.bash"

  # Initialize POS setup.
  pos_setup

  # Skip veblop tests if not enabled.
  if ! is_veblop_enabled; then
    echo "Veblop hardfork is not enabled (block number <= 256). Aborting tests."
    exit 1
  fi
}

# This test verifies fairness at the consensus layer (CL).
# It counts spans assigned to each producer and checks that the distribution is reasonably equal with a tolerance of ±1 span.
# bats test_tags=fairness
@test "enforce equal slot distribution between block producers at the consensus layer" {
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
      echo "Error: Unequal distribution: Producer $producer has $count spans (expected ~$expected_spans_per_producer ±$tolerance)"
      exit 1
    fi
  done
}

# This test verifies fairness at the execution layer (EL).
# It counts actual produced blocks over the last 1000 blocks and checks that the distribution is reasonably equal with a tolerance of ±128 blocks (±1 span).
# bats test_tags=fairness
@test "enforce equal block distribution between block producers at the execution layer" {
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
    echo "- Producer $producer: ${block_count[$producer]} blocks"
    total_blocks=$((total_blocks + 1))
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
      echo "Error: Unequal distribution: Producer $producer has $count blocks (expected ~$expected_blocks_per_producer ±$tolerance)"
      exit 1
    fi
  done
}

# This test verifies that each span contains at least one and at most three selected producers.
# bats test_tags=sanity
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
