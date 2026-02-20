#!/bin/env bash
set -e
source ../../common/log.sh
source ../../common/load-env.sh
load_env

# Gradual upgrade of bor/heimdall nodes in kurtosis-pos devnet
get_l2_containers() {
	docker ps \
		--filter "network=kt-$ENCLAVE_NAME" \
		--filter "name=l2" \
		--format "table {{.Names}}\t{{.Image}}\t{{.Status}}" |
		grep -v rabbitmq |
		(
			sed -u 1q
			sort -V
		)
}

# Get any available CL API URL (works for both kurtosis-managed and upgraded containers).
get_any_cl_api_url() {
	local container host_port
	for container in $(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep 'l2-cl' | grep -v 'rabbitmq'); do
		host_port=$(docker port "$container" 1317 2>/dev/null | head -1 | sed 's/0.0.0.0/127.0.0.1/')
		if [[ -n "$host_port" ]]; then
			echo "http://$host_port"
			return 0
		fi
	done
	return 1
}

# Get the block producer val_id for the current span.
# Fetches the current block number from an EL node, then walks spans backwards
# from latest to find the span containing that block.
get_block_producer_id() {
	local el_rpc_url block_number cl_api_url latest_span_id span_start span_end span_id producer_id
	el_rpc_url=$(get_any_el_rpc_url) || {
		echo "No EL RPC URL available" >&2
		return 1
	}
	block_number=$(cast bn --rpc-url "$el_rpc_url" 2>/dev/null) || {
		echo "Failed to get block number from $el_rpc_url" >&2
		return 1
	}
	cl_api_url=$(get_any_cl_api_url) || {
		echo "No CL API URL available" >&2
		return 1
	}
	latest_span_id=$(curl -s "${cl_api_url}/bor/spans/latest" | jq -r '.span.id')
	echo "Current block: $block_number, latest span ID: $latest_span_id" >&2

	# Walk backwards from latest span to find the one containing the current block
	for ((span_id = latest_span_id; span_id >= 0; span_id--)); do
		span_start=$(curl -s "${cl_api_url}/bor/spans/${span_id}" | jq -r '.span.start_block')
		span_end=$(curl -s "${cl_api_url}/bor/spans/${span_id}" | jq -r '.span.end_block')
		if [[ "$block_number" -ge "$span_start" ]] && [[ "$block_number" -le "$span_end" ]]; then
			producer_id=$(curl -s "${cl_api_url}/bor/spans/${span_id}" | jq -r '.span.selected_producers[0].val_id')
			echo "Block $block_number is in span $span_id ($span_start-$span_end), producer val_id: $producer_id" >&2
			echo "$producer_id"
			return 0
		fi
	done

	echo "No span found containing block $block_number" >&2
	return 1
}

# Get any available EL RPC URL (works for both kurtosis-managed and upgraded containers).
get_any_el_rpc_url() {
	local container host_port url
	for container in $(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep 'l2-el'); do
		host_port=$(docker port "$container" 8545 2>/dev/null | head -1 | sed 's/0.0.0.0/127.0.0.1/')
		if [[ -n "$host_port" ]]; then
			url="http://$host_port"
			if cast bn --rpc-url "$url" &>/dev/null; then
				echo "$url"
				return 0
			fi
		fi
	done
	return 1
}

upgrade_cl_node() {
	container="$1"
	if [[ -z "$container" ]]; then
		log_error "Container is required for upgrade"
		exit 1
	fi
	service=${container%%--*} # l2-cl-1-heimdall-v2-bor-validator
	log_info "Upgrading heimdall service: $service"

	# Stop the kurtosis service and wait for it to fully stop
	log_info "[$service] Stopping kurtosis service"
	kurtosis service stop "$ENCLAVE_NAME" "$service" || {
		log_error "[$service] Failed to stop kurtosis service"
		exit 1
	}
	docker wait "$container" &>/dev/null || true
	log_info "[$service] Container stopped"

	# Extract the data and configuration from the old container
	log_info "[$service] Extracting service data and configuration"
	mkdir -p "./tmp/$service"
	docker cp "$container":/var/lib/heimdall "./tmp/$service/${type}_data" || {
		log_error "[$service] Failed to copy /var/lib/heimdall"
		exit 1
	}
	docker cp "$container":/etc/heimdall/config "./tmp/$service/${type}_etc_config" || {
		log_error "[$service] Failed to copy /etc/heimdall/config"
		exit 1
	}
	docker cp "$container":/etc/heimdall/data "./tmp/$service/${type}_etc_data" || {
		log_error "[$service] Failed to copy /etc/heimdall/data"
		exit 1
	}
	docker cp "$container":/usr/local/share "./tmp/$service/${type}_scripts" || {
		log_error "[$service] Failed to copy /usr/local/share"
		exit 1
	}
	chmod -R 777 "./tmp/$service/"

	docker network disconnect "kt-$ENCLAVE_NAME" "$container" || log_error "[$service] Failed to disconnect old container from network"
	sleep 1

	# Start a new container with the new image and the same data, in the same docker network
	image="$new_heimdall_v2_image"
	log_info "[$service] Starting new container with image: $image"
	for attempt in 1 2 3; do
		if docker run \
			--detach \
			--name "$service" \
			--network "kt-$ENCLAVE_NAME" \
			--publish 0:1317 \
			--publish 0:26657 \
			--volume "./tmp/$service/${type}_data:/var/lib/heimdall" \
			--volume "./tmp/$service/${type}_etc_config:/etc/heimdall/config" \
			--volume "./tmp/$service/${type}_etc_data:/etc/heimdall/data" \
			--volume "./tmp/$service/${type}_scripts:/usr/local/share" \
			--entrypoint sh \
			"$image" \
			-c "/usr/local/share/container-proc-manager.sh heimdalld start --all --bridge --home /etc/heimdall --log_no_color --rest-server"; then
			break
		fi
		log_info "[$service] Attempt $attempt failed, retrying in 3s..."
		docker rm -f "$service" 2>/dev/null || true
		sleep 3
		if [[ "$attempt" -eq 3 ]]; then
			log_error "[$service] Failed to start new container after 3 attempts"
			exit 1
		fi
	done
}

upgrade_el_node() {
	container="$1"
	if [[ -z "$container" ]]; then
		log_error "Container is required for upgrade"
		exit 1
	fi
	service=${container%%--*}               # l2-el-1-bor-heimdall-v2-validator
	type=$(echo "$service" | cut -d'-' -f4) # bor or erigon
	log_info "Upgrading $type service: $service"

	# Stop the kurtosis service and wait for it to fully stop
	log_info "[$service] Stopping kurtosis service"
	kurtosis service stop "$ENCLAVE_NAME" "$service" || {
		log_error "[$service] Failed to stop kurtosis service"
		exit 1
	}
	docker wait "$container" &>/dev/null || true
	log_info "[$service] Container stopped"

	# Extract the data and configuration from the old container
	log_info "[$service] Extracting service data and configuration"
	mkdir -p "./tmp/$service"
	docker cp "$container":/var/lib/"$type" "./tmp/$service/${type}_data" || {
		log_error "[$service] Failed to copy /var/lib/$type"
		exit 1
	}
	docker cp "$container":/etc/"$type" "./tmp/$service/${type}_etc" || {
		log_error "[$service] Failed to copy /etc/$type"
		exit 1
	}
	if [[ "$type" == "bor" ]]; then
		docker cp "$container":/usr/local/share "./tmp/$service/${type}_scripts" || {
			log_error "[$service] Failed to copy /usr/local/share"
			exit 1
		}
	fi
	chmod -R 777 "./tmp/$service/"

	docker network disconnect "kt-$ENCLAVE_NAME" "$container" || log_error "[$service] Failed to disconnect old container from network"
	sleep 1

	# Start a new container with the new image and the same data, in the same docker network
	image=""
	cmd=""
	extra_args=""
	if [[ "$type" == "bor" ]]; then
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

	log_info "[$service] Starting new container with image: $image"
	for attempt in 1 2 3; do
		if docker run \
			--detach \
			--name "$service" \
			--network "kt-$ENCLAVE_NAME" \
			--publish 0:8545 \
			--volume "./tmp/$service/${type}_data:/var/lib/$type" \
			--volume "./tmp/$service/${type}_etc:/etc/$type" \
			$extra_args \
			--entrypoint sh \
			"$image" \
			-c "$cmd"; then
			break
		fi
		log_info "[$service] Attempt $attempt failed, retrying in 3s..."
		docker rm -f "$service" 2>/dev/null || true
		sleep 3
		if [[ "$attempt" -eq 3 ]]; then
			log_error "[$service] Failed to start new container after 3 attempts"
			exit 1
		fi
	done
}

query_rpc_nodes() {
	docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' |
		grep 'l2-el' |
		while read -r container; do
			host_port=$(docker port "$container" 8545 2>/dev/null | head -1 | sed 's/0.0.0.0/127.0.0.1/')
			if [[ -n "$host_port" ]]; then
				echo -n "$container: "
				cast bn --rpc-url "http://$host_port" 2>/dev/null || echo "N/A"
			else
				echo "$container: no published port"
			fi
		done
}

wait_for_producer_rotation() {
	original_producer_id="$1"
	if [[ -z "$original_producer_id" ]]; then
		log_error "Original producer ID is required"
		return 1
	fi

	log_info "Waiting for block producer rotation..."
	max_wait_seconds=300 # 5 minutes max wait (enough for multiple span rotations)
	check_interval=10    # Check every 10 seconds
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
if ! docker image inspect "$new_heimdall_v2_image" &>/dev/null; then
	docker pull "$new_heimdall_v2_image"
fi

if [[ -z "$NEW_BOR_IMAGE" ]]; then
	log_error "NEW_BOR_IMAGE environment variable is not set."
	exit 1
fi
log_info "Using new bor image: $NEW_BOR_IMAGE"
new_bor_image="$NEW_BOR_IMAGE"
if ! docker image inspect "$new_bor_image" &>/dev/null; then
	docker pull "$new_bor_image"
fi

if [[ -z "$NEW_ERIGON_IMAGE" ]]; then
	log_error "NEW_ERIGON_IMAGE environment variable is not set."
	exit 1
fi
log_info "Using new erigon image: $NEW_ERIGON_IMAGE"
new_erigon_image="$NEW_ERIGON_IMAGE"
if ! docker image inspect "$new_erigon_image" &>/dev/null; then
	docker pull "$new_erigon_image"
fi

# Clean up temporary directories from previous runs
rm -rf ./tmp
mkdir -p ./tmp

# Add foundry to PATH for sudo execution
export PATH="$PATH:/home/$SUDO_USER/.foundry/bin"

# Deploy the devnet - it might take a few minutes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "./kurtosis-pos" ]]; then
	git clone https://github.com/0xPolygon/kurtosis-pos.git
fi
pushd ./kurtosis-pos || exit 1
git checkout main
git pull || log_info "git pull failed (likely running locally under sudo), continuing with local state"
git checkout "$KURTOSIS_POS_VERSION"
kurtosis run --enclave "$ENCLAVE_NAME" --args-file "$SCRIPT_DIR/params.yml" .

# Display L2 containers
get_l2_containers
popd || exit 1

# Wait for all EL nodes to reach the target block (Rio HF activation)
# Uses kurtosis port print since containers are still kurtosis-managed at this point
RIO_HF="${RIO_HF:-128}"
RIO_HF_TIMEOUT="${RIO_HF_TIMEOUT:-300}"
log_info "Waiting for all EL nodes to reach block $RIO_HF (timeout: ${RIO_HF_TIMEOUT}s)"

# Collect EL service names from kurtosis
el_services=$(kurtosis enclave inspect "$ENCLAVE_NAME" | awk '/l2-el/ && /RUNNING/ {print $2}')

end_time=$(($(date +%s) + RIO_HF_TIMEOUT))
while true; do
	all_ready=true
	while IFS= read -r service; do
		[[ -z "$service" ]] && continue
		rpc_url=$(kurtosis port print "$ENCLAVE_NAME" "$service" rpc 2>/dev/null || echo "")
		if [[ -z "$rpc_url" ]]; then
			all_ready=false
			continue
		fi
		bn=$(cast bn --rpc-url "$rpc_url" 2>/dev/null || echo "0")
		if [[ "$bn" -lt "$RIO_HF" ]]; then
			all_ready=false
		fi
	done <<<"$el_services"

	if $all_ready; then
		log_info "All EL nodes reached block $RIO_HF"
		break
	fi

	if [[ $(date +%s) -ge $end_time ]]; then
		log_error "Timeout waiting for block $RIO_HF. Current block heights:"
		while IFS= read -r service; do
			[[ -z "$service" ]] && continue
			rpc_url=$(kurtosis port print "$ENCLAVE_NAME" "$service" rpc 2>/dev/null || echo "")
			bn=$(cast bn --rpc-url "$rpc_url" 2>/dev/null || echo "N/A")
			log_error "  $service: $bn"
		done <<<"$el_services"
		exit 1
	fi

	sleep 5
done

# Get the block producer
block_producer_id=$(get_block_producer_id)
log_info "Current block producer ID: $block_producer_id"

# Collect CL and EL containers to upgrade, excluding the current block producer
cl_containers=()
while IFS= read -r container; do
	cl_containers+=("$container")
done < <(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' |
	grep "l2-cl" |
	grep -v "rabbitmq" |
	grep -v "l2-cl-$block_producer_id-" |
	sort -V)

el_containers=()
while IFS= read -r container; do
	el_containers+=("$container")
done < <(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' |
	grep "l2-el" |
	grep -v "l2-el-$block_producer_id-" |
	sort -V)

# Upgrade CL nodes one by one, then EL nodes one by one
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

# Query RPC nodes
log_info "Querying RPC nodes"
query_rpc_nodes

# Wait for natural span rotation
# In devnet: 1s block time, 16 blocks per sprint, 8 sprints per span = 128s (~2min) per span
# Once an upgraded validator takes over as block producer, we can safely upgrade the old one
wait_for_producer_rotation "$block_producer_id"

# Upgrade the old block producer
log_info "Upgrading the old block producer"
cl_container=$(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep "l2-cl-$block_producer_id-" | grep -v "rabbitmq")
if [[ -z "$cl_container" ]]; then
	log_error "Could not find CL container for old block producer ID $block_producer_id"
	exit 1
fi
el_container=$(docker ps --filter "network=kt-$ENCLAVE_NAME" --format '{{.Names}}' | grep "l2-el-$block_producer_id-")
if [[ -z "$el_container" ]]; then
	log_error "Could not find EL container for old block producer ID $block_producer_id"
	exit 1
fi
upgrade_cl_node "$cl_container"
upgrade_el_node "$el_container"

# Display L2 containers
get_l2_containers

# Add small delay to allow the node to start up before querying
sleep 15

# Query RPC nodes
log_info "Querying RPC nodes"
query_rpc_nodes
