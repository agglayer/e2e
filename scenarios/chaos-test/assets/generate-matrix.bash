#!/bin/bash

# Check if PICT and jq are installed
if ! command -v pict &> /dev/null; then
    echo "Error: pict is required. Please install pict."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Please install jq."
    exit 1
fi

# List of container names to exclude
EXCLUDE_CONTAINERS=("kurtosis-" "validator-key-generation-cl-validator-keystore" "test-runner" "contracts-001")

# Get list of running container names, excluding specified ones, and join with commas
CONTAINERS=$(docker ps --format '{{.Names}}' | grep -v -E "$(IFS="|"; echo "${EXCLUDE_CONTAINERS[*]}")" | tr '\n' ',' | sed 's/,$//')

if [[ -z "$CONTAINERS" ]]; then
    echo "No running containers found after filtering!"
    exit 1
fi

# Create PICT model file
PICT_MODEL="chaos_test_model.pict"
{
    echo "container: $CONTAINERS"
    echo "percent: 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90"
    echo "probability: 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9"
    echo "rate: 50kbit, 100kbit, 150kbit, 200kbit, 250kbit, 300kbit, 350kbit, 400kbit, 450kbit, 500kbit, 550kbit, 600kbit, 650kbit, 700kbit, 750kbit, 800kbit, 850kbit, 900kbit"
    echo "jitter: 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150"
} > "$PICT_MODEL"

# Generate test matrix with PICT and format as JSON
pict "$PICT_MODEL" /r /o:1 | awk 'BEGIN {FS="\t"; print "["} NR>1 {if (NR>2) print ","; print "  {"; print "    \"container\": \"" $1 "\","; print "    \"percent\": " $2 ","; print "    \"probability\": " $3 ","; print "    \"rate\": \"" $4 "\","; print "    \"jitter\": " $5; print "  }"} END {print "]"}' > test_matrix.json

echo "Test matrix generated at test_matrix.json with ${#CONTAINERS[@]} containers."