#!/bin/bash

# List of container names to exclude
EXCLUDE_CONTAINERS=("kurtosis-" "validator-key-generation-cl-validator-keystore" "test-runner" "contracts-001")

# Create temporary file to store container mappings as JSON
CONTAINER_MAP_FILE="./container_mappings.json"
echo "[]" > "$CONTAINER_MAP_FILE"

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

# Create JSON mapping file
echo "[" > "$CONTAINER_MAP_FILE"
for i in "${!CONTAINER_MAPPINGS[@]}"; do
    echo "  ${CONTAINER_MAPPINGS[$i]}" >> "$CONTAINER_MAP_FILE"
    if [[ $i -lt $((${#CONTAINER_MAPPINGS[@]} - 1)) ]]; then
        echo "," >> "$CONTAINER_MAP_FILE"
    else
        echo "" >> "$CONTAINER_MAP_FILE"
    fi
done
echo "]" >> "$CONTAINER_MAP_FILE"

echo ""
echo "Total containers to stress test: ${#CONTAINERS[@]}"
echo "Container mappings saved to: $CONTAINER_MAP_FILE"

# Display the JSON content
echo "Container mappings:"
cat "$CONTAINER_MAP_FILE" | jq '.'
