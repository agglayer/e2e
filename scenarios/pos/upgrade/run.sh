#!/bin/env bash
set -e
source ../../common/log.sh
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

upgrade_cl_node() {
    container="$1"
    if [[ -z "$container" ]]; then
        log_error "Container is required for upgrade"
        exit 1
    fi
    service=${container%%--*} # l2-cl-1-heimdall-v2-bor-validator
    type=$(echo $service | cut -d'-' -f4)
    log_info "Upgrading $type service: $service"

    # Stop the kurtosis service
    log_info "[$service] Stopping kurtosis service"
    kurtosis service stop "$ENCLAVE_NAME" $service

    # Extract the data and configuration from the old container
    log_info "[$service] Extracting service data and configuration"
    container_details=$(docker inspect $container)
    data_dir=$(echo $container_details | jq -r ".[0].Mounts[] | select(.Destination == \"/var/lib/$type\") | .Source")
    etc_config_dir=$(echo $container_details | jq -r ".[0].Mounts[] | select(.Destination == \"/etc/$type/config\") | .Source")
    scripts_dir=$(echo $container_details | jq -r '.[0].Mounts[] | select(.Destination == "/usr/local/share") | .Source')

    mkdir -p ./tmp/$service
    sudo cp -r $data_dir ./tmp/$service/${type}_data
    sudo chmod -R 777 ./tmp/$service/${type}_data

    sudo cp -r $etc_config_dir ./tmp/$service/${type}_etc_config
    sudo chmod -R 777 ./tmp/$service/${type}_etc_config

    sudo cp -r $scripts_dir ./tmp/$service/${type}_scripts
    sudo chmod -R 777 ./tmp/$service/${type}_scripts

    # Start a new container with the new image and the same data, in the same docker network
    image="$new_heimdall_v2_image"
    log_info "[$service] Starting new container $service with image: $image"
    docker run \
        --interactive \
        --detach \
        --tty \
        --name $service \
        --network kt-$ENCLAVE_NAME \
        --volume ./tmp/$service/${type}_data:/var/lib/$type \
        --volume ./tmp/$service/${type}_etc_config:/etc/$type/config \
        --volume ./tmp/$service/${type}_scripts:/usr/local/share \
        --entrypoint sh \
        "$image" \
        -c "/usr/local/share/container-proc-manager.sh heimdalld start --all --bridge --home /etc/heimdall --log_no_color --rest-server"
}

upgrade_el_node() {
    container="$1"
    if [[ -z "$container" ]]; then
        log_error "Container is required for upgrade"
        exit 1
    fi
    service=${container%%--*} # l2-el-1-bor-heimdall-v2-validator
    type=$(echo $service | cut -d'-' -f4) # bor or erigon
    log_info "Upgrading $type service: $service"

    # Stop the kurtosis service
    log_info "[$service] Stopping kurtosis service"
    kurtosis service stop "$ENCLAVE_NAME" $service

    # Extract the data and configuration from the old container
    log_info "[$service] Extracting service data and configuration"
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
        log_error "Unknown EL type for service $service, expected 'bor' or 'erigon'"
        exit 1
    fi

    log_info "[$service] Starting new container $service with image: $image"
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

query_rpc_nodes() {
    docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' \
        | grep 'l2-el' \
        | while read -r container; do
            ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "kt-'$ENCLAVE_NAME'").IPAddress}}' "$container")
            echo -n "$container: "
            cast bn --rpc-url "http://$ip:8545"
            done
}

trigger_producer_downtime() {
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
        log_error "Original producer ID is required"
        return 1
    fi

    log_info "Waiting for block producer rotation..."
    max_wait_seconds=300  # 5 minutes max wait (enough for multiple span rotations)
    check_interval=10  # Check every 10 seconds
    elapsed=0
    while [[ $elapsed -lt $max_wait_seconds ]]; do
        current_producer_id=$(get_block_producer_id)
        log_info "Current producer: $current_producer_id"
        if [[ "$current_producer_id" != "$original_producer_id" ]]; then
            log_info "Block producer rotated!"
            return 0
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_error "Block producer did not rotate after ${max_wait_seconds}s"
    return 1
}

# Validate environment variables
if [[ -z "$ENCLAVE_NAME" ]]; then
    log_error "ENCLAVE_NAME environment variable is not set."
    exit 1
fi
log_info "Using enclave name: $ENCLAVE_NAME"

if [[ -z "$KURTOSIS_POS_VERSION" ]]; then
    log_error "KURTOSIS_POS_VERSION environment variable is not set."
    exit 1
fi
log_info "Using kurtosis-pos version: $KURTOSIS_POS_VERSION"

if [[ -z "$NEW_HEIMDALL_V2_IMAGE" ]]; then
    log_error "NEW_HEIMDALL_V2_IMAGE environment variable is not set."
    exit 1
fi
log_info "Using new heimdall-v2 image: $NEW_HEIMDALL_V2_IMAGE"
new_heimdall_v2_image="$NEW_HEIMDALL_V2_IMAGE"
docker pull "$new_heimdall_v2_image"

if [[ -z "$NEW_BOR_IMAGE" ]]; then
    log_error "NEW_BOR_IMAGE environment variable is not set."
    exit 1
fi
log_info "Using new bor image: $NEW_BOR_IMAGE"
new_bor_image="$NEW_BOR_IMAGE"
docker pull "$new_bor_image"

if [[ -z "$NEW_ERIGON_IMAGE" ]]; then
    log_error "NEW_ERIGON_IMAGE environment variable is not set."
    exit 1
fi
log_info "Using new erigon image: $NEW_ERIGON_IMAGE"
new_erigon_image="$NEW_ERIGON_IMAGE"
docker pull "$new_erigon_image"

# Check if running as root/sudo
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run with sudo or as root"
   exit 1
fi

# Check if the enclave already exists
if kurtosis enclave inspect "$ENCLAVE_NAME" &>/dev/null; then
    log_error "The kurtosis enclave '$ENCLAVE_NAME' already exists."
    log_error "Please remove it before running this script:"
    log_error "kurtosis enclave rm --force $ENCLAVE_NAME"
    exit 1
fi

# Check for orphaned containers from previous runs
# These are manually created containers that may remain after 'kurtosis enclave rm'
orphaned_containers=$(docker ps --all --format '{{.Names}}' | grep -E "^l2-(e|c)l-.*-.*-" || true)
if [[ -n "$orphaned_containers" ]]; then
    log_error "Found orphaned containers from a previous run:"
    log_error "$orphaned_containers"
    log_error "Please remove them before running this script:"
    log_error "docker ps --all --format '{{.Names}}' | grep -E '^l2-(e|c)l-.*-.*-' | xargs docker rm --force"
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
log_info "Current block producer ID: $block_producer_id"

# Collect L2 nodes to upgrade, excluding the current block producer
cl_containers=()
while IFS= read -r container; do
    cl_containers+=("$container")
done < <(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' \
    | grep "l2-cl" \
    | grep -v "l2-cl-$block_producer_id-")
if [[ ${#cl_containers[@]} -eq 0 ]]; then
    log_info "No CL containers found to upgrade (excluding block producer)"
fi


el_containers=()
while IFS= read -r container; do
    el_containers+=("$container")
done < <(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' \
    | grep "l2-el" \
    | grep -v "l2-el-$block_producer_id-")
if [[ ${#el_containers[@]} -eq 0 ]]; then
    log_info "No EL containers found to upgrade (excluding block producer)"
fi

log_info "Upgrading L2 nodes"
for container in "${cl_containers[@]}"; do
    upgrade_cl_node "$container" &
done
for container in "${el_containers[@]}"; do
    upgrade_el_node "$container" &
done
wait

# Add small delay to allow nodes to start up before querying
sleep 30

# Query RPC nodes
log_info "Querying RPC nodes"
query_rpc_nodes

# Trigger a graceful span rotation
# It will put the block producer in downtime state to do the rotation
# This rotation is considered graceful as it is handled from the consensus
# However, it might take more time than forcing a rotation by shutting down the node
log_info "Triggering a graceful span rotation"
trigger_producer_downtime
wait_for_producer_rotation "$block_producer_id"

# Upgrade the old block producer
log_info "Upgrading the old block producer"
cl_container=$(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep "l2-cl-$block_producer_id-")
if [[ -z "$cl_container" ]]; then
    log_error "Could not find CL container for old block producer ID $block_producer_id"
    exit 1
fi
el_container=$(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep "l2-el-$block_producer_id-")
if [[ -z "$el_container" ]]; then
    log_error "Could not find EL container for old block producer ID $block_producer_id"
    exit 1
fi
upgrade_cl_node "$cl_container" &
upgrade_el_node "$el_container" &
wait

# Query RPC nodes
log_info "Querying RPC nodes"
query_rpc_nodes
    