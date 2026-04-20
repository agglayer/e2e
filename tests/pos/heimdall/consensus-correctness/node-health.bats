#!/usr/bin/env bats
# bats file_tags=heimdall,node,health,correctness

# Heimdall Node Health
# ====================
# This suite verifies the basic operational health of the Heimdall node:
#   - The node reports a valid, non-empty chain ID
#   - The node is fully synced with the network (not catching up)
#   - The current block height is a positive integer
#   - The node has at least one connected peer
#
# These checks confirm the node is participating in the network as expected
# and serving correct state information.
#
# REQUIREMENTS:
#   - A Kurtosis Polygon PoS enclave is running (default name: "pos")
#   - CometBFT RPC reachable at L2_CL_RPC_URL (resolved automatically)
#   - Heimdall REST API reachable at L2_CL_API_URL (for secondary checks)
#   - Node has been running long enough to be synced
#
# RUN: bats tests/pos/heimdall/consensus-correctness/node-health.bats

# ─────────────────────────────────────────────────────────────────────────────
# File-level setup (runs once before all tests)
# ─────────────────────────────────────────────────────────────────────────────

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Resolve the CometBFT JSON-RPC URL.  It is exposed on a different port
    # from the Cosmos REST API (L2_CL_API_URL).  Try kurtosis first, then
    # fall back to replacing the REST port (1317) with the CometBFT default
    # (26657).
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            export L2_CL_RPC_URL="${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi
    echo "L2_CL_RPC_URL=${L2_CL_RPC_URL}" >&3

    # Probe availability via the CometBFT RPC /status endpoint.
    local probe
    probe=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null \
        | jq -r '.result.node_info.network // empty' 2>/dev/null || true)

    if [[ -z "${probe}" ]]; then
        echo "WARNING: CometBFT RPC status endpoint not reachable at ${L2_CL_RPC_URL} — all node health tests will be skipped." >&3
        echo "1" > "${BATS_FILE_TMPDIR}/heimdall_health_unavailable"
    else
        echo "CometBFT RPC status reachable; chain_id=${probe}" >&3
        echo "0" > "${BATS_FILE_TMPDIR}/heimdall_health_unavailable"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-test setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    # Re-derive L2_CL_RPC_URL so it is available in every test subshell.
    if [[ -z "${L2_CL_RPC_URL:-}" ]]; then
        local rpc_port
        if rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" \
                "l2-cl-1-heimdall-v2-bor-validator" rpc 2>/dev/null); then
            export L2_CL_RPC_URL="${rpc_port}"
        else
            export L2_CL_RPC_URL="${L2_CL_API_URL/:1317/:26657}"
        fi
    fi

    if [[ "$(cat "${BATS_FILE_TMPDIR}/heimdall_health_unavailable" 2>/dev/null)" != "0" ]]; then
        skip "CometBFT RPC status endpoint not reachable at ${L2_CL_RPC_URL}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the raw JSON from the CometBFT /status endpoint.
# Prints the raw JSON on stdout, or returns 1 on failure.
_get_status() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/status" 2>/dev/null || true)
    if [[ -z "${raw}" || "${raw}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${raw}"
}

# Fetch the raw JSON from the Cosmos SDK node_info endpoint.
# Prints the raw JSON on stdout, or returns 1 on failure.
_get_node_info() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_API_URL}/cosmos/base/tendermint/v1beta1/node_info" 2>/dev/null || true)
    if [[ -z "${raw}" || "${raw}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${raw}"
}

# Fetch the raw JSON from the CometBFT /net_info endpoint on the RPC port.
# Prints the raw JSON on stdout, or returns 1 on failure.
_get_net_info() {
    local raw
    raw=$(curl -s -m 30 --connect-timeout 5 \
        "${L2_CL_RPC_URL}/net_info" 2>/dev/null || true)
    if [[ -z "${raw}" || "${raw}" == "null" ]]; then
        return 1
    fi
    printf '%s' "${raw}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

# bats test_tags=node,health,correctness
@test "heimdall node: chain ID is non-empty and consistent across endpoints" {
    # The node must report a valid chain ID from the primary /status endpoint.
    # If the secondary node_info endpoint is also reachable, both must agree —
    # a mismatch indicates a misconfigured or compromised node identity.

    local status_json
    if ! status_json=$(_get_status); then
        fail "Could not fetch status from CometBFT RPC at ${L2_CL_RPC_URL}/status"
    fi

    local chain_id
    chain_id=$(printf '%s' "${status_json}" \
        | jq -r '.result.node_info.network // empty' 2>/dev/null || true)

    if [[ -z "${chain_id}" || "${chain_id}" == "null" ]]; then
        echo "FAIL: /status returned no chain ID in .result.node_info.network" >&2
        return 1
    fi

    echo "  Primary chain ID (from /status): ${chain_id}" >&3

    # Cross-check with the Cosmos SDK node_info endpoint if available.
    local node_info_json
    if node_info_json=$(_get_node_info 2>/dev/null); then
        local chain_id_secondary
        chain_id_secondary=$(printf '%s' "${node_info_json}" \
            | jq -r '.default_node_info.network // empty' 2>/dev/null || true)

        if [[ -n "${chain_id_secondary}" && "${chain_id_secondary}" != "null" ]]; then
            echo "  Secondary chain ID (from /cosmos/base/tendermint/v1beta1/node_info): ${chain_id_secondary}" >&3

            if [[ "${chain_id}" != "${chain_id_secondary}" ]]; then
                echo "FAIL: chain ID mismatch between endpoints:" >&2
                echo "  /status                          → ${chain_id}" >&2
                echo "  /cosmos/base/tendermint/.../node_info → ${chain_id_secondary}" >&2
                return 1
            fi
        else
            echo "  NOTE: secondary node_info endpoint did not return a chain ID — skipping cross-check" >&3
        fi
    else
        echo "  NOTE: secondary node_info endpoint not reachable — skipping cross-check" >&3
    fi

    echo "OK: chain ID = ${chain_id}" >&3
}

# bats test_tags=node,health,correctness
@test "heimdall node: is not catching up (fully synced)" {
    # A node in catch-up mode has not yet reached the network tip.  Any state
    # it serves (validators, spans, checkpoints) may be stale.  All other health
    # invariants are only meaningful once the node is fully synced.

    local status_json
    if ! status_json=$(_get_status); then
        fail "Could not fetch status from CometBFT RPC at ${L2_CL_RPC_URL}/status"
    fi

    local catching_up
    catching_up=$(printf '%s' "${status_json}" \
        | jq -r 'if .result.sync_info | has("catching_up") then .result.sync_info.catching_up | tostring else "missing" end' 2>/dev/null || true)

    if [[ -z "${catching_up}" || "${catching_up}" == "missing" ]]; then
        skip "sync_info.catching_up not found in status response"
    fi

    local height
    height=$(printf '%s' "${status_json}" \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
    # Normalise to integer; default to 0 if missing or non-numeric.
    [[ "${height}" =~ ^[0-9]+$ ]] || height=0

    echo "  catching_up=${catching_up}, height=${height}" >&3

    # jq -r renders JSON booleans as bare true/false strings.
    if [[ "${catching_up}" == "true" ]]; then
        echo "FAIL: node is still catching up (sync_info.catching_up=true) at height ${height}" >&2
        echo "  The node has not yet reached the network tip.  State served by this node" >&2
        echo "  may be stale.  Wait for sync to complete before running further checks." >&2
        return 1
    fi

    echo "OK: node is not catching up, height=${height}" >&3
}

# bats test_tags=node,health,correctness
@test "heimdall node: latest block height is a positive integer" {
    # A height of 0 or a non-numeric value means the node has not yet produced
    # or received any blocks — it cannot be a useful participant in consensus.

    local status_json
    if ! status_json=$(_get_status); then
        fail "Could not fetch status from CometBFT RPC at ${L2_CL_RPC_URL}/status"
    fi

    local height_raw
    height_raw=$(printf '%s' "${status_json}" \
        | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)

    if [[ -z "${height_raw}" || "${height_raw}" == "null" ]]; then
        echo "FAIL: /status did not return .result.sync_info.latest_block_height" >&2
        return 1
    fi

    # Normalise: strip surrounding quotes if present, then convert to decimal.
    # The field is sometimes returned as a JSON string ("1234") rather than an
    # integer (1234) depending on the Heimdall / CometBFT version.
    local height
    height=$(printf '%d' "${height_raw}" 2>/dev/null || true)

    # Validate that the result is a non-empty sequence of digits before any
    # arithmetic comparison.
    if ! [[ "${height}" =~ ^[0-9]+$ ]]; then
        echo "FAIL: latest_block_height '${height_raw}' could not be parsed as an integer" >&2
        return 1
    fi

    if [[ "${height}" -le 0 ]]; then
        echo "FAIL: latest block height is ${height} — node has not produced any blocks yet" >&2
        return 1
    fi

    echo "OK: latest block height = ${height}" >&3
}

# bats test_tags=node,health,peers
@test "heimdall node: has at least one connected peer" {
    # An isolated node with zero peers cannot exchange blocks or votes with the
    # rest of the network.  It will either stall (no new blocks) or fork silently
    # (no way to detect the canonical chain).  At least one peer is the minimum
    # required for any meaningful participation in BFT consensus.

    local net_info_json
    if ! net_info_json=$(_get_net_info 2>/dev/null); then
        skip "CometBFT RPC not reachable at ${L2_CL_RPC_URL}"
    fi

    # Verify we got a real response, not an error page.
    local n_peers_raw
    n_peers_raw=$(printf '%s' "${net_info_json}" \
        | jq -r '.result.n_peers // empty' 2>/dev/null || true)

    if [[ -z "${n_peers_raw}" || "${n_peers_raw}" == "null" ]]; then
        skip "CometBFT RPC not reachable at ${L2_CL_RPC_URL}"
    fi

    # n_peers may be a JSON string ("1") or an integer (1) — normalise to int.
    local n_peers
    if [[ "${n_peers_raw}" =~ ^[0-9]+$ ]]; then
        n_peers="${n_peers_raw}"
    else
        n_peers=$(printf '%d' "${n_peers_raw}" 2>/dev/null || echo "0")
        [[ "${n_peers}" =~ ^[0-9]+$ ]] || n_peers=0
    fi

    echo "  n_peers=${n_peers}" >&3

    if [[ "${n_peers}" -eq 0 ]]; then
        echo "FAIL: node has 0 connected peers — isolated node cannot participate in consensus" >&2
        return 1
    fi

    echo "OK: ${n_peers} peer(s) connected" >&3
}
