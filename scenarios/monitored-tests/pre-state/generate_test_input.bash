#!/bin/bash

TEST_INPUT_TEMPLATE="test_input_template.json"

_generate_stress_test_input() {
    # List of container names to exclude
    EXCLUDE_CONTAINERS=("kurtosis-" "validator-key-generation-cl-validator-keystore" "test-runner" "contracts-001")

    # Get list of running containers with names and IDs, excluding specified ones
    CONTAINERS=()
    CONTAINER_MAPPINGS=()

    # Read docker ps output and process line by line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            CONTAINER_NAME=$(echo "$line" | awk '{print $1}')
            CONTAINER_ID=$(echo "$line" | awk '{print $2}')
            
            # Add to arrays
            CONTAINERS+=("$CONTAINER_ID")
            CONTAINER_MAPPINGS+=("{\"name\":\"$CONTAINER_NAME\",\"id\":\"$CONTAINER_ID\"}")
                    
            # Directory of docker container cgroups
            CGROUP_DIR="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
            
            # Verify cgroup directory exists
            if [[ -d "$CGROUP_DIR" ]]; then
                continue
            else
                exit 1
            fi
        fi
    done < <(docker ps --format '{{.Names}} {{.ID}}' --no-trunc | grep -v -E "$(IFS="|"; echo "${EXCLUDE_CONTAINERS[*]}")")

    if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
        echo "No running containers found after filtering!"
        exit 1
    fi

    # Prepare JSON array for stress_test
    STRESS_TEST_JSON="["
    for i in "${!CONTAINER_MAPPINGS[@]}"; do
        STRESS_TEST_JSON+="${CONTAINER_MAPPINGS[$i]}"
        if [[ $i -lt $((${#CONTAINER_MAPPINGS[@]} - 1)) ]]; then
            STRESS_TEST_JSON+=","
        fi
    done
    STRESS_TEST_JSON+="]"

    # Update the "stress_test" section in test_input_template.json
    jq --argjson stress_test "$STRESS_TEST_JSON" '.stress_test = $stress_test' test_input_template.json > $TEST_INPUT_TEMPLATE.tmp && mv $TEST_INPUT_TEMPLATE.tmp $TEST_INPUT_TEMPLATE

    echo ""
    echo "Total containers to stress test: ${#CONTAINERS[@]}"
    echo "Updated 'stress_test' in: $TEST_INPUT_TEMPLATE"

    # Display the updated JSON content
    echo "Updated 'stress_test' section:"
    jq '.stress_test' $TEST_INPUT_TEMPLATE
}

_generate_chaos_test_input() {
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

    # Generate test matrix with PICT and format as JSON, then update chaos_test section
    CHAOS_JSON=$(pict "$PICT_MODEL" /r /o:1 | awk 'BEGIN {FS="\t"; print "["} NR>1 {if (NR>2) print ","; print "  {"; print "    \"container\": \"" $1 "\","; print "    \"percent\": " $2 ","; print "    \"probability\": " $3 ","; print "    \"rate\": \"" $4 "\","; print "    \"jitter\": " $5; print "  }"} END {print "]"}')

    jq --argjson chaos_test "$CHAOS_JSON" '.chaos_test = $chaos_test' test_input_template.json > $TEST_INPUT_TEMPLATE.tmp && mv $TEST_INPUT_TEMPLATE.tmp $TEST_INPUT_TEMPLATE

    echo "Updated 'chaos_test' in: $TEST_INPUT_TEMPLATE"
    echo "Updated 'chaos_test' section:"
    jq '.chaos_test' $TEST_INPUT_TEMPLATE
}

# Call the functions
_generate_stress_test_input
_generate_chaos_test_input

# Remove PICT model file after test
PICT_MODEL="chaos_test_model.pict"
if [[ -f "$PICT_MODEL" ]]; then
    rm "$PICT_MODEL"
fi
