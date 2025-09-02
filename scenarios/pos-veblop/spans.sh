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

# First collect all span data
declare -A spans
declare -A span_status

for ((span_id=1; span_id<=latest_span_id; span_id++)); do
  span_data=$(curl -s "$cl_api_url/bor/spans/$span_id")
  if [[ $? -eq 0 && "$span_data" != *"error"* ]]; then
    spans[$span_id]="$span_data"
  fi
done

# Analyze spans in chronological order to determine status
for ((span_id=1; span_id<=latest_span_id; span_id++)); do
  if [[ -n "${spans[$span_id]}" ]]; then
    span_data="${spans[$span_id]}"
    start_block=$(echo "$span_data" | jq -r '.span.start_block')

    span_status[$span_id]="Normal"

    # Check if this span should follow the previous one
    if [[ $span_id -gt 1 && -n "${spans[$((span_id-1))]}" ]]; then
      prev_span_data="${spans[$((span_id-1))]}"
      prev_end_block=$(echo "$prev_span_data" | jq -r '.span.end_block')
      expected_start=$((prev_end_block + 1))

      # If this span starts before where it should, it means there was an overlap
      # which indicates this span was created due to producer rotation (skipped original)
      if [[ $start_block -lt $expected_start ]]; then
        span_status[$span_id]="Skipped"
      fi
    fi
  fi
done

# Display results in reverse order (latest first)
for ((span_id=latest_span_id; span_id>=1; span_id--)); do
  if [[ -n "${spans[$span_id]}" ]]; then
    span_data="${spans[$span_id]}"
    id=$(echo "$span_data" | jq -r '.span.id')
    start_block=$(echo "$span_data" | jq -r '.span.start_block')
    end_block=$(echo "$span_data" | jq -r '.span.end_block')
    block_count=$((end_block - start_block + 1))
    producers=$(echo "$span_data" | jq -r '.span.selected_producers[].val_id' | tr '\n' ',' | sed 's/,$//')
    status="${span_status[$span_id]}"

    printf "%-3s | %-11s | %-9s | %-11s | %-18s | %s\n" "$id" "$start_block" "$end_block" "$block_count" "$producers" "$status"
  else
    echo "Error fetching span $span_id"
  fi
done
