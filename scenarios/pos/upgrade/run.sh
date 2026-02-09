#!/bin/env bash
set -e
source ../../common/load-env.sh
load_env

# Gradual upgrade of bor/heimdall nodes in kurtosis-pos devnet

get_block_producer_id() {
    cl_api_url=$(kurtosis port print "$ENCLAVE_NAME" l2-cl-1-heimdall-v2-bor-validator http)
    next_span_id=$(curl -s "${cl_api_url}/bor/spans/latest" | jq -r '.span.id')
    current_span_id=$((next_span_id - 1))
    producer_id=$(curl -s "${cl_api_url}/bor/spans/$((current_span_id))" | jq -r '.span.selected_producers[0].val_id')
    echo "$producer_id"
}

get_block_producer_address() {
    cl_api_url=$(kurtosis port print "$ENCLAVE_NAME" l2-cl-1-heimdall-v2-bor-validator http)
    next_span_id=$(curl -s "${cl_api_url}/bor/spans/latest" | jq -r '.span.id')
    current_span_id=$((next_span_id - 1))
    producer_address=$(curl -s "${cl_api_url}/bor/spans/$((current_span_id))" | jq -r '.span.selected_producers[0].signer')
    echo "$producer_address"
}

query_rpc_nodes() {
    docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' \
        | grep 'l2-el' \
        | while read -r container; do
            ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "kt-'$ENCLAVE_NAME'").IPAddress}}' "$container")
            echo -n "$container: "
            cast bn --rpc-url "http://$ip:8545"
            done
}

trigger_graceful_span_rotation() {
    # Get the current block producer's service name and address
    producer_service=$(kurtosis enclave inspect "$ENCLAVE_NAME" | grep RUNNING | grep l2-cl-$block_producer_id | awk '{print $2}' | head -n 1)
    producer_address=$(get_block_producer_address)

    # Calculate downtime window timestamps (UTC Unix timestamps)
    # In devnet: 1s block time, 16 blocks per sprint, 8 sprints per span = 128s (~2min) per span
    # Set downtime window to catch the next span rotation (slightly more than one span)
    current_time_plus_30s=$(date -u -d '+30 seconds' '+%s')
    current_time_plus_150s=$(date -u -d '+150 seconds' '+%s')

    # Submit downtime transaction to trigger graceful rotation
    kurtosis service exec $ENCLAVE_NAME $producer_service \
        "heimdalld tx bor producer-downtime --producer-address $producer_address --home /etc/heimdall --start-timestamp-utc $current_time_plus_30s --end-timestamp-utc $current_time_plus_150s"
}

wait_for_producer_rotation() {
    original_producer_id="$1"
    if [[ -z "$original_producer_id" ]]; then
        echo "Original producer ID is required"
        return 1
    fi

    echo "Waiting for block producer rotation from ID $original_producer_id..."
    max_wait_seconds=300  # 5 minutes max wait (enough for multiple span rotations)
    check_interval=10  # Check every 10 seconds
    elapsed=0
    while [[ $elapsed -lt $max_wait_seconds ]]; do
        current_producer_id=$(get_block_producer_id)
        echo "Current producer: $current_producer_id"
        if [[ "$current_producer_id" != "$original_producer_id" ]]; then
            echo "Block producer rotated!"
            return 0
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo "Block producer did not rotate after ${max_wait_seconds}s"
    return 1
}

upgrade_el_node() {
    container="$1"
    if [[ -z "$container" ]]; then
        echo "Container is required for upgrade"
        exit 1
    fi
    service=${container%%--*} # l2-el-1-bor-heimdall-v2-validator
    type=$(echo $service | cut -d'-' -f4) # bor or erigon
    echo "Upgrading $type service: $service"

    # Stop the kurtosis service
    echo "[$service] Stopping kurtosis service"
    kurtosis service stop "$ENCLAVE_NAME" $service

    # Extract the data and configuration from the old container
    echo "[$service] Extracting service data and configuration"
    container_details=$(docker inspect $container)
    data_dir=$(echo $container_details | jq -r ".[0].Mounts[] | select(.Destination == \"/var/lib/$type\") | .Source")
    etc_dir=$(echo $container_details | jq -r ".[0].Mounts[] | select(.Destination == \"/etc/$type\") | .Source")

    mkdir -p ./tmp/$service
    sudo cp -r $data_dir ./tmp/$service/${type}_data
    sudo chmod -R 777 ./tmp/$service/${type}_data

    sudo cp -r $etc_dir ./tmp/$service/${type}_etc
    sudo chmod -R 777 ./tmp/$service/${type}_etc

    # Start a new container with the new image and the same data, in the same docker network
    image=""
    cmd=""
    extra_args=""
    if [[ "$type" == "bor" ]]; then
        # Extract scripts from the old container
        scripts_dir=$(echo $container_details | jq -r '.[0].Mounts[] | select(.Destination == "/usr/local/share") | .Source')
        sudo cp -r $scripts_dir ./tmp/$service/${type}_scripts
        sudo chmod -R 777 ./tmp/$service/${type}_scripts

        image="$new_bor_image"
        cmd="/usr/local/share/container-proc-manager.sh bor server --config /etc/bor/config.toml"
        extra_args="--volume ./tmp/$service/${type}_scripts:/usr/local/share"
    elif [[ "$type" == "erigon" ]]; then
        image="$new_erigon_image"
        cmd="while ! erigon --config /etc/erigon/config.toml; do echo -e '\n❌ Erigon failed to start. Retrying in five seconds...\n'; sleep 5; done"
    else
        echo "Unknown EL type for service $service, expected 'bor' or 'erigon'"
        exit 1
    fi

    echo "[$service] Starting new container $service with image: $image"
    docker run \
        --interactive \
        --detach \
        --tty \
        --name $service \
        --network kt-$ENCLAVE_NAME \
        --volume ./tmp/$service/${type}_data:/var/lib/$type \
        --volume ./tmp/$service/${type}_etc:/etc/$type \
        $extra_args \
        --entrypoint sh \
        "$image" \
        -c "$cmd"
}

# Validate environment variables
if [[ -z "$ENCLAVE_NAME" ]]; then
    echo "ENCLAVE_NAME environment variable is not set."
    exit 1
fi

if [[ -z "$KURTOSIS_POS_VERSION" ]]; then
    echo "KURTOSIS_POS_VERSION environment variable is not set."
    exit 1
fi

if [[ -z "$NEW_BOR_IMAGE" ]]; then
    echo "NEW_BOR_IMAGE environment variable is not set."
    exit 1
fi
new_bor_image="$NEW_BOR_IMAGE"
docker pull "$new_bor_image"

if [[ -z "$NEW_ERIGON_IMAGE" ]]; then
    echo "NEW_ERIGON_IMAGE environment variable is not set."
    exit 1
fi
new_erigon_image="$NEW_ERIGON_IMAGE"
docker pull "$new_erigon_image"

# Check if running as root/sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo or as root"
   exit 1
fi

# Check if the enclave already exists
if kurtosis enclave inspect "$ENCLAVE_NAME" &>/dev/null; then
    echo "The kurtosis enclave '$ENCLAVE_NAME' already exists."
    echo "Please remove it before running this script:"
    echo "kurtosis enclave rm --force $ENCLAVE_NAME"
    exit 1
fi

# Check for orphaned containers from previous runs
# These are manually created containers that may remain after 'kurtosis enclave rm'
orphaned_containers=$(docker ps --all --format '{{.Names}}' | grep -E "^l2-(e|c)l-.*-.*-" || true)
if [[ -n "$orphaned_containers" ]]; then
    echo "Found orphaned containers from a previous run:"
    echo "$orphaned_containers"
    echo "Please remove them before running this script:"
    echo "docker ps --all --format '{{.Names}}' | grep -E '^l2-(e|c)l-.*-.*-' | xargs docker rm --force"
    exit 1
fi

# Clean up temporary directories from previous runs
rm -rf ./tmp
mkdir -p ./tmp

# Add foundry to PATH for sudo execution
export PATH="$PATH:/home/$SUDO_USER/.foundry/bin"

# Deploy the devnet - it might take a few minutes
if [[ ! -d "./kurtosis-pos" ]]; then
    git clone https://github.com/0xPolygon/kurtosis-pos.git
fi
pushd ./kurtosis-pos || exit 1
git checkout "$KURTOSIS_POS_VERSION"
kurtosis run --enclave "$ENCLAVE_NAME" --args-file ../params.yml .

# Validate blocks production across all nodes
.github/actions/monitor/blocks.sh
popd || exit 1

# Get the block producer
block_producer_id=$(get_block_producer_id)
echo "Current block producer ID: $block_producer_id"

# Collect L2 EL nodes to upgrade, excluding the current block producer
containers=()
while IFS= read -r container; do
    containers+=("$container")
done < <(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' \
    | grep "l2-el" \
    | grep -v "l2-el-$block_producer_id-")

echo "Upgrading L2 EL nodes"
for container in "${containers[@]}"; do
    upgrade_el_node "$container" &
done
wait

# Add small delay to allow nodes to start up before querying
sleep 30

# Query RPC nodes
echo "Querying RPC nodes"
query_rpc_node

# Trigger a graceful span rotation
# It will put the block producer in downtime state to do the rotation
# This rotation is considered graceful as it is handled from the consensus
# However, it might take more time than forcing a rotation by shutting down the node
echo "Triggering a graceful span rotation"
trigger_graceful_span_rotation
wait_for_producer_rotation "$block_producer_id"

# TODO: Upgrade the block producer
echo "Upgrading the old block producer"
container=$(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep "l2-el-$block_producer_id-")
upgrade_el_node "$container"

# Query RPC nodes
echo "Querying RPC nodes"
query_rpc_nodes
    