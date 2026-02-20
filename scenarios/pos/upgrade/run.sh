#!/bin/env bash
set -e
source ../../common/log.sh
source ../../common/load-env.sh
load_env

# Gradual upgrade of bor/heimdall nodes in kurtosis-pos devnet.
# This script is exclusively about L2 nodes.

##############################################################################
# UTILITY FUNCTIONS
##############################################################################
list_nodes() {
	docker ps \
		--filter "network=$docker_network_name" \
		--filter "name=l2-cl" \
		--filter "name=l2-el" \
		--format "table {{.Names}}\t{{.Image}}\t{{.Status}}" |
		grep -v rabbitmq |
		(
			sed -u 1q
			sort -V
		)
}

query_rpc_nodes() {
	local host_port block_number
	docker ps --filter "network=$docker_network_name" --filter "name=l2-el" --format '{{.Names}}' |
		while read -r container; do
			host_port=$(docker port "$container" 8545 | head -1 | sed 's/0.0.0.0/127.0.0.1/')
			if [[ -n "$host_port" ]]; then
				block_number=$(cast bn --rpc-url "http://$host_port")
				echo -n "$container: $block_number"
			else
				echo "$container: no published port"
			fi
		done
}

get_block_producer_id() {
	# Get current block number.
	local el_rpc_url block_number
	el_rpc_url=$(get_any_el_rpc_url)
	block_number=$(cast bn --rpc-url "$el_rpc_url")

	# Get latest span ID.
	local cl_api_url latest_span_id
	cl_api_url=$(get_any_cl_api_url)
	latest_span_id=$(curl -s "${cl_api_url}/bor/spans/latest" | jq -r '.span.id')
	log_info "Current block: $block_number, latest span ID: $latest_span_id" >&2

	# Walk backwards from latest span to find the one containing the current block.
	local span_id span span_start span_end producer_id
	for ((span_id = latest_span_id; span_id >= 0; span_id--)); do
		span=$(curl -s "${cl_api_url}/bor/spans/${span_id}" | jq -r '.span')
		span_start=$(echo "$span" | jq -r '.start_block')
		span_end=$(echo "$span" | jq -r '.end_block')
		if [[ "$block_number" -ge "$span_start" ]] && [[ "$block_number" -le "$span_end" ]]; then
			producer_id=$(echo "$span" | jq -r '.selected_producers[0].val_id')
			log_info "Block $block_number is in span $span_id ($span_start-$span_end), producer val_id: $producer_id" >&2
			echo "$producer_id"
			return 0
		fi
	done
	log_error "No span found containing block $block_number" >&2
	return 1
}

wait_for_devnet_to_reach_block() {
	local target_block="$1"
	if [[ -z "$target_block" ]]; then
		log_error "Target block number is required"
		return 1
	fi

	# Get EL services.
	el_services=$(kurtosis enclave inspect "$ENCLAVE_NAME" | awk '/l2-el/ && /RUNNING/ {print $2}')

	# Wait for all EL nodes to reach the target block.
	local num_steps=50 all_ready=true step
	for step in $(seq 1 "${num_steps}"); do
		log_info "Check ${step}/${num_steps}"
		while IFS= read -r service; do
			local rpc_url=$(kurtosis port print "$ENCLAVE_NAME" "$service" rpc)
			local block_number=$(cast bn --rpc-url "$rpc_url")
			local status="OK"
			if [[ "$block_number" -lt "$target_block" ]]; then
				status="NOT READY"
				all_ready=false
			fi
			log_info "- $service: $block_number / $target_block - $status"
		done <<<"$el_services"

		if $all_ready; then
			log_info "All EL nodes reached block $target_block"
			return 0
		fi
	done
	log_error "Not all EL nodes reached block $target_block after $num_steps steps"
	return 1
}

wait_for_producer_rotation() {
	local original_bp_id="$1"
	if [[ -z "$original_bp_id" ]]; then
		log_error "Original block producer ID is required"
		return 1
	fi

	log_info "Waiting for block producer rotation"
	local max_wait_seconds=300 # Five minutes should be enough for multiple span rotations.
	local check_interval_seconds=10
	local elapsed=0
	while [[ $elapsed -lt $max_wait_seconds ]]; do
		local bp_id=$(get_block_producer_id)
		log_info "Block producer ID: $bp_id"
		if [[ "$bp_id" != "$original_bp_id" ]]; then
			log_info "Block producer rotated!"
			return 0
		fi
		log_info "Block producer has not rotated, retrying in ${check_interval_seconds}s..."
		sleep "$check_interval_seconds"
		elapsed=$((elapsed + check_interval_seconds))
	done

	log_error "Block producer did not rotate after ${max_wait_seconds}s"
	return 1
}

##############################################################################
# SERVICE DISCOVERY FUNCTIONS
##############################################################################
get_any_cl_api_url() {
	local containers
	cl_containers=$(docker ps --filter "network=$docker_network_name" --filter "name=l2-cl" --format '{{.Names}}' | grep -v 'rabbitmq')
	if [[ -z "$cl_containers" ]]; then
		log_error "No L2 CL containers available" >&2
		return 1
	fi

	local container host_port url
	for container in $cl_containers; do
		host_port=$(docker port "$container" 1317 2>/dev/null | head -1 | sed 's/0.0.0.0/127.0.0.1/')
		if [[ -n "$host_port" ]]; then
			url="http://$host_port"
			# Liveness check.
			if curl -sf "${url}/bor/spans/latest" &>/dev/null; then
				echo "$url"
				return 0
			fi
		fi
	done
	return 1
}

get_any_el_rpc_url() {
	local containers
	el_containers=$(docker ps --filter "network=$docker_network_name" --filter "name=l2-el" --format '{{.Names}}')
	if [[ -z "$el_containers" ]]; then
		log_error "No L2 EL containers available" >&2
		return 1
	fi

	local container host_port url
	for container in $el_containers; do
		host_port=$(docker port "$container" 8545 2>/dev/null | head -1 | sed 's/0.0.0.0/127.0.0.1/')
		if [[ -n "$host_port" ]]; then
			url="http://$host_port"
			# Liveness check.
			if cast bn --rpc-url "$url" &>/dev/null; then
				echo "$url"
				return 0
			fi
		fi
	done
	return 1
}

##############################################################################
# UPGRADE FUNCTIONS
##############################################################################
upgrade_cl_node() {
	local container="$1"
	if [[ -z "$container" ]]; then
		log_error "Container is required for upgrade"
		exit 1
	fi
	local service=${container%%--*} # l2-cl-1-heimdall-v2-bor-validator
	log_info "Upgrading CL service: $service"

	# Stop the kurtosis service and wait for it to fully stop.
	log_info "Stopping kurtosis service"
	kurtosis service stop "$ENCLAVE_NAME" "$service"
	docker wait "$container"
	docker network disconnect "$docker_network_name" "$container"
	log_info "Service stopped"

	# Extract the data and configuration from the old container.
	log_info "Extracting service data and configuration"
	mkdir -p "./tmp/$service"
	docker cp "$container":/var/lib/heimdall "./tmp/$service/${type}_data"
	docker cp "$container":/etc/heimdall/config "./tmp/$service/${type}_etc_config"
	docker cp "$container":/etc/heimdall/data "./tmp/$service/${type}_etc_data"
	docker cp "$container":/usr/local/share "./tmp/$service/${type}_scripts"
	chmod -R 777 "./tmp/$service/"

	# Start a new container with the new image and the same data, in the same docker network.
	# TODO: Consider removing the retry loop. It was added for transient Docker daemon issues,
	# but most failures (bad image, missing config) are not transient and retrying won't help.
	log_info "Starting new container with image: $NEW_HEIMDALL_V2_IMAGE"
	local max_attempts=3 check_interval_seconds=3 attempt
	for ((attempt = 1; attempt <= max_attempts; attempt++)); do
		if docker run \
			--detach \
			--name "$service" \
			--network "$docker_network_name" \
			--publish 0:1317 \
			--publish 0:26657 \
			--volume "./tmp/$service/${type}_data:/var/lib/heimdall" \
			--volume "./tmp/$service/${type}_etc_config:/etc/heimdall/config" \
			--volume "./tmp/$service/${type}_etc_data:/etc/heimdall/data" \
			--volume "./tmp/$service/${type}_scripts:/usr/local/share" \
			--entrypoint sh \
			"$NEW_HEIMDALL_V2_IMAGE" \
			-c "/usr/local/share/container-proc-manager.sh heimdalld start --all --bridge --home /etc/heimdall --log_no_color --rest-server"; then
			break
		fi
		if [[ "$attempt" -eq "$max_attempts" ]]; then
			log_error "Failed to start new container after $max_attempts attempts"
			exit 1
		fi
		log_info "Attempt $attempt failed, retrying in ${check_interval_seconds}s..."
		docker rm -f "$service" || true
		sleep "$check_interval_seconds"
	done
}

upgrade_el_node() {
	local container="$1"
	if [[ -z "$container" ]]; then
		log_error "Container is required for upgrade"
		exit 1
	fi
	local service=${container%%--*} # l2-el-1-bor-heimdall-v2-validator
	local type=$(echo "$service" | cut -d'-' -f4) # bor or erigon
	log_info "Upgrading EL service: $service"

	# Stop the kurtosis service and wait for it to fully stop.
	log_info "Stopping kurtosis service"
	kurtosis service stop "$ENCLAVE_NAME" "$service"
	docker wait "$container"
	docker network disconnect "$docker_network_name" "$container"
	log_info "Service stopped"

	# Extract the data and configuration from the old container.
	log_info "Extracting service data and configuration"
	mkdir -p "./tmp/$service"
	docker cp "$container":/var/lib/"$type" "./tmp/$service/${type}_data"
	docker cp "$container":/etc/"$type" "./tmp/$service/${type}_etc"
	if [[ "$type" == "bor" ]]; then
		docker cp "$container":/usr/local/share "./tmp/$service/${type}_scripts"
	fi
	chmod -R 777 "./tmp/$service/"

	# Start a new container with the new image and the same data, in the same docker network.
	# TODO: Consider removing the retry loop. It was added for transient Docker daemon issues,
	# but most failures (bad image, missing config) are not transient and retrying won't help.
	local image cmd extra_args
	if [[ "$type" == "bor" ]]; then
		image="$NEW_BOR_IMAGE"
		cmd="/usr/local/share/container-proc-manager.sh bor server --config /etc/bor/config.toml"
		extra_args="--volume ./tmp/$service/${type}_scripts:/usr/local/share"
	elif [[ "$type" == "erigon" ]]; then
		image="$NEW_ERIGON_IMAGE"
		cmd="while ! erigon --config /etc/erigon/config.toml; do echo -e '\n❌ Erigon failed to start. Retrying in five seconds...\n'; sleep 5; done"
	else
		log_error "Unknown EL type for service $service, expected 'bor' or 'erigon'"
		exit 1
	fi

	log_info "Starting new container with image: $image"
	local max_attempts=3 check_interval_seconds=3 attempt
	for ((attempt = 1; attempt <= max_attempts; attempt++)); do
		if docker run \
			--detach \
			--name "$service" \
			--network "$docker_network_name" \
			--publish 0:8545 \
			--volume "./tmp/$service/${type}_data:/var/lib/$type" \
			--volume "./tmp/$service/${type}_etc:/etc/$type" \
			$extra_args \
			--entrypoint sh \
			"$image" \
			-c "$cmd"; then
			break
		fi
		if [[ "$attempt" -eq "$max_attempts" ]]; then
			log_error "Failed to start new container after $max_attempts attempts"
			exit 1
		fi
		log_info "Attempt $attempt failed, retrying in ${check_interval_seconds}s..."
		docker rm -f "$service" || true
		sleep "$check_interval_seconds"
	done
}

##############################################################################
# MAIN WORKFLOW
##############################################################################

if [[ -z "$ENCLAVE_NAME" ]]; then
	log_error "ENCLAVE_NAME environment variable is not set."
	exit 1
fi
log_info "Using enclave name: $ENCLAVE_NAME"

docker_network_name="kt-$ENCLAVE_NAME"
log_info "Using Docker network name: $docker_network_name"

# Check if running as root/sudo.
# TODO: Check if this is still necessary.
if [[ $EUID -ne 0 ]]; then
	log_error "This script must be run with sudo or as root"
	exit 1
fi

# Add foundry to PATH for sudo execution.
export PATH="$PATH:/home/$SUDO_USER/.foundry/bin"

# Check if the enclave already exists.
if kurtosis enclave inspect "$ENCLAVE_NAME" &>/dev/null; then
	log_error "The kurtosis enclave '$ENCLAVE_NAME' already exists."
	log_error "Please remove it before running this script:"
	log_error "kurtosis enclave rm --force $ENCLAVE_NAME"
	exit 1
fi

# Check for orphaned containers from previous runs.
# These are manually created containers that may remain after 'kurtosis enclave rm'.
orphaned_containers=$(docker ps --all --filter "name=l2-cl" --filter "name=l2-el" --format '{{.Names}}' | grep -v rabbitmq || true)
if [[ -n "$orphaned_containers" ]]; then
	log_error "Found orphaned containers from a previous run:"
	log_error "$orphaned_containers"
	log_error "Please remove them before running this script:"
	log_error "docker ps --all --filter 'name=l2-cl' --filter 'name=l2-el' --format '{{.Names}}' | grep -v rabbitmq | xargs docker rm --force"
	exit 1
fi

# Kurtosis-pos package version.
if [[ -z "$KURTOSIS_POS_VERSION" ]]; then
	log_error "KURTOSIS_POS_VERSION environment variable is not set."
	exit 1
fi
log_info "Using kurtosis-pos version: $KURTOSIS_POS_VERSION"

# New heimdall-v2 image.
if [[ -z "$NEW_HEIMDALL_V2_IMAGE" ]]; then
	log_error "NEW_HEIMDALL_V2_IMAGE environment variable is not set."
	exit 1
fi
log_info "Using new heimdall-v2 image: $NEW_HEIMDALL_V2_IMAGE"
if ! docker image inspect "$NEW_HEIMDALL_V2_IMAGE" &>/dev/null; then
	docker pull "$NEW_HEIMDALL_V2_IMAGE"
fi

# New bor image.
if [[ -z "$NEW_BOR_IMAGE" ]]; then
	log_error "NEW_BOR_IMAGE environment variable is not set."
	exit 1
fi
log_info "Using new bor image: $NEW_BOR_IMAGE"
if ! docker image inspect "$NEW_BOR_IMAGE" &>/dev/null; then
	docker pull "$NEW_BOR_IMAGE"
fi

# New erigon image.
if [[ -z "$NEW_ERIGON_IMAGE" ]]; then
	log_error "NEW_ERIGON_IMAGE environment variable is not set."
	exit 1
fi
log_info "Using new erigon image: $NEW_ERIGON_IMAGE"
if ! docker image inspect "$NEW_ERIGON_IMAGE" &>/dev/null; then
	docker pull "$NEW_ERIGON_IMAGE"
fi

# Clean up temporary directories from previous runs.
rm -rf ./tmp
mkdir -p ./tmp

# Deploy the devnet.
log_info "Deploying the devnet, this may take a few minutes..."
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kurtosis run \
	--enclave "$ENCLAVE_NAME" \
	--args-file "$script_dir/params.yml" \
	github.com/0xPolygon/kurtosis-pos@"$KURTOSIS_POS_VERSION"
list_nodes

# Wait for the devnet to reach the Rio HF block number.
rio_fork_block=${RIO_FORK_BLOCK:-128}
wait_for_devnet_to_reach_block "$rio_fork_block"

# Get the block producer.
block_producer_id=$(get_block_producer_id)
log_info "Current block producer ID: $block_producer_id"

# Collect CL and EL containers to upgrade, excluding the current block producer.
cl_containers=()
while IFS= read -r container; do
	cl_containers+=("$container")
done < <(docker ps --filter "network=$docker_network_name" --format '{{.Names}}' |
	grep "l2-cl" |
	grep -v "rabbitmq" |
	grep -v "l2-cl-$block_producer_id-" |
	sort -V)

el_containers=()
while IFS= read -r container; do
	el_containers+=("$container")
done < <(docker ps --filter "network=$docker_network_name" --format '{{.Names}}' |
	grep "l2-el" |
	grep -v "l2-el-$block_producer_id-" |
	sort -V)

# Upgrade CL nodes one by one, then EL nodes one by one.
log_info "Upgrading ${#cl_containers[@]} CL nodes sequentially (excluding block producer $block_producer_id)"
for i in "${!cl_containers[@]}"; do
	log_info "CL node $((i + 1))/${#cl_containers[@]}: ${cl_containers[$i]}"
	upgrade_cl_node "${cl_containers[$i]}"
	log_info "CL node $((i + 1))/${#cl_containers[@]} done"
	sleep 2
done

log_info "Upgrading ${#el_containers[@]} EL nodes sequentially (excluding block producer $block_producer_id)"
for i in "${!el_containers[@]}"; do
	log_info "EL node $((i + 1))/${#el_containers[@]}: ${el_containers[$i]}"
	upgrade_el_node "${el_containers[$i]}"
	log_info "EL node $((i + 1))/${#el_containers[@]} done"
	sleep 2
done

log_info "All non-producer nodes upgraded, waiting for block producer rotation before upgrading producer $block_producer_id"

sleep 10

# Query RPC nodes.
log_info "Querying RPC nodes"
query_rpc_nodes

# Wait for natural span rotation.
# In devnet: 1s block time, 16 blocks per sprint, 8 sprints per span = 128s (~2min) per span.
# Once an upgraded validator takes over as block producer, we can safely upgrade the old one.
wait_for_producer_rotation "$block_producer_id"

# Upgrade the old block producer.
log_info "Upgrading the old block producer"
cl_container=$(docker ps --filter "network=$docker_network_name" --format '{{.Names}}' | grep "l2-cl-$block_producer_id-" | grep -v "rabbitmq")
if [[ -z "$cl_container" ]]; then
	log_error "Could not find CL container for old block producer ID $block_producer_id"
	exit 1
fi
el_container=$(docker ps --filter "network=$docker_network_name" --format '{{.Names}}' | grep "l2-el-$block_producer_id-")
if [[ -z "$el_container" ]]; then
	log_error "Could not find EL container for old block producer ID $block_producer_id"
	exit 1
fi
upgrade_cl_node "$cl_container"
upgrade_el_node "$el_container"
list_nodes

# Add small delay to allow the node to start up before querying.
sleep 15

# Query RPC nodes.
log_info "Querying RPC nodes"
query_rpc_nodes
