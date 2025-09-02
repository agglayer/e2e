#!/bin/env bash
set -e

enclave_name="pos-veblop"

# Get the CL API URL
cl_api_url=$(kurtosis port print "$enclave_name" l2-cl-1-heimdall-v2-bor-validator http 2>&1)
if [[ $cl_api_url == *"Error"* ]]; then
  cl_api_url=$(kurtosis port print "$enclave_name" l2-cl-2-heimdall-v2-bor-validator http 2>&1)
  if [[ $cl_api_url == *"Error"* ]]; then
    cl_api_url=$(kurtosis port print "$enclave_name" l2-cl-3-heimdall-v2-bor-validator http 2>&1)
    if [[ $cl_api_url == *"Error"* ]]; then
      echo "Error: Could not get CL API URL"
      exit 1
    fi
  fi
fi
echo "CL API URL: $cl_api_url"

# Get the latest span ID
latest_span_id=$(curl -s "$cl_api_url/bor/spans/latest" | jq -r '.span.id')
if [[ -z "$latest_span_id" || "$latest_span_id" == "null" ]]; then
  echo "Error: Could not retrieve latest span ID"
  exit 1
fi
echo "Latest span id: $latest_span_id"
echo "Fetching all spans from 1 to $latest_span_id..."
echo

# Fetch all spans from 1 to latest
echo "ID | Start Block | End Block | Block Count | Selected Producers | Status"
echo "---|-------------|-----------|-------------|--------------------|---------"

# Variables to track previous span for continuity check
prev_start_block=""
prev_end_block=""

for ((span_id=latest_span_id; span_id>=1; span_id--)); do
  span_data=$(curl -s "$cl_api_url/bor/spans/$span_id")

  if [[ $? -eq 0 && "$span_data" != *"error"* ]]; then
    id=$(echo "$span_data" | jq -r '.span.id')
    start_block=$(echo "$span_data" | jq -r '.span.start_block')
    end_block=$(echo "$span_data" | jq -r '.span.end_block')

    # Calculate the number of blocks in the span
    block_count=$((end_block - start_block + 1))

    # Get selected producers IDs as a comma-separated list
    producers=$(echo "$span_data" | jq -r '.span.selected_producers[].val_id' | tr '\n' ',' | sed 's/,$//')

    # Determine span status (continuous or producer rotated)
    status="Normal"
    if [[ -n "$prev_start_block" ]]; then
      # Check if this span is continuous with the previous one
      expected_next_start=$((end_block + 1))
      if [[ "$prev_start_block" -ne "$expected_next_start" ]]; then
        status="Producer Rotated"
      fi
    fi

    printf "%-3s | %-11s | %-9s | %-11s | %-18s | %s\n" "$id" "$start_block" "$end_block" "$block_count" "$producers" "$status"

    # Store current span info for next iteration
    prev_start_block="$start_block"
    prev_end_block="$end_block"
  else
    echo "Error fetching span $span_id"
  fi
done
