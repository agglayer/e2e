#!/usr/bin/env bash
# shellcheck disable=SC2154

# =============================================================================
# Benchmark / timing helpers for the lxly bridge test suite
# =============================================================================
#
# These helpers add latency + throughput instrumentation on top of the bridge
# test harness so runs can be used as Agglayer benchmarks.
#
# Two tiers of measurement:
#
#   Tier 1 (always on) - per-scenario wall-clock latency:
#     * bridge_ms : time to submit the deposit and obtain a deposit count
#     * claim_ms  : time spent waiting for the deposit to become claimable and
#                   claiming it (polycli --wait polls the bridge service, so this
#                   is gated by Agglayer certificate settlement + GER injection)
#     * e2e_ms    : deposit submission -> claim confirmed (cross-chain finality)
#     Emitted to <output_dir>/latencies.csv by _collect_and_report_results.
#
#   Tier 2 (opt-in) - certificate settlement heights from Agglayer:
#     Enabled by exporting AGGLAYER_RPC_URL (or a per-network
#     <PREFIX>_AGGLAYER_RPC_URL, e.g. BALI_NETWORK_65_AGGLAYER_RPC_URL). When
#     set, the run records each L2 network's latest settled certificate height
#     and epoch before and after the batch, so you can derive certificates
#     settled during the run and the epoch cadence. When unset, the snapshot is
#     skipped with a single informational log line (never a silent no-op).
# =============================================================================

# Current time in epoch milliseconds.
_now_ms() {
    date +%s%3N
}

# Milliseconds elapsed between two _now_ms readings; empty if either is missing.
_elapsed_ms() {
    local start="$1" end="$2"
    [[ -n "$start" && -n "$end" ]] || return 0
    echo $(( end - start ))
}

# Resolve the Agglayer read-RPC URL for a logical network id.
# Precedence: per-network <PREFIX>_AGGLAYER_RPC_URL, then global AGGLAYER_RPC_URL.
# Echoes an empty string when none is configured.
_agglayer_rpc_url() {
    local network_id="$1"
    local prefix="${NETWORK_ID_TO_PREFIX[$network_id]:-}"
    if [[ -n "$prefix" ]]; then
        local var="${prefix}_AGGLAYER_RPC_URL"
        if [[ -n "${!var:-}" ]]; then
            echo "${!var}"
            return 0
        fi
    fi
    echo "${AGGLAYER_RPC_URL:-}"
}

# Global store for settlement snapshots, keyed "<phase>_<network>" -> settled height.
declare -gA AGGLAYER_SETTLED_HEIGHTS=()

# Snapshot each unique non-L1 network's latest settled certificate height from
# Agglayer's interop RPC into AGGLAYER_SETTLED_HEIGHTS (in-memory, no file).
# No-op (with one log line) when no Agglayer RPC URL is configured.
#
# Usage: _agglayer_settlement_snapshot <scenarios_file> <phase>   (phase: start|end)
_agglayer_settlement_snapshot() {
    local scenarios_file="$1"
    local phase="$2"

    local unique_networks captured_any=false
    unique_networks=$(jq -r '.[].FromNetwork, .[].ToNetwork' "$scenarios_file" | sort -u)

    while IFS= read -r network_id; do
        [[ -n "$network_id" && "$network_id" != "0" ]] || continue

        local rpc_url
        rpc_url=$(_agglayer_rpc_url "$network_id")
        [[ -n "$rpc_url" ]] || continue
        captured_any=true

        local rollup_id height
        rollup_id=$(_get_network_config "$network_id" "network_id" 2>/dev/null || echo "$network_id")
        height=$(cast rpc --rpc-url "$rpc_url" interop_getLatestSettledCertificateHeader "$rollup_id" 2>/dev/null | jq -r '.height // empty' 2>/dev/null || echo "")
        AGGLAYER_SETTLED_HEIGHTS["${phase}_${network_id}"]="${height:-NA}"
    done <<< "$unique_networks"

    if ! $captured_any; then
        _log_file_descriptor "3" "ℹ️  Agglayer settlement metrics disabled (set AGGLAYER_RPC_URL or <PREFIX>_AGGLAYER_RPC_URL to record certificate settlement)."
    fi
}

# Print certificates settled during the run (end minus start settled height) per
# network, to fd 3. Emits nothing when Tier 2 was disabled or a baseline is missing.
_agglayer_settlement_report() {
    local key net start end printed=false
    for key in "${!AGGLAYER_SETTLED_HEIGHTS[@]}"; do
        [[ "$key" == start_* ]] || continue
        net="${key#start_}"
        start="${AGGLAYER_SETTLED_HEIGHTS[start_${net}]}"
        end="${AGGLAYER_SETTLED_HEIGHTS[end_${net}]:-NA}"
        [[ "$start" != "NA" && "$end" != "NA" ]] || continue
        if ! $printed; then
            _log_file_descriptor "3" "Certificates settled during run (Agglayer):"
            printed=true
        fi
        _log_file_descriptor "3" "  network ${net}: settled height ${start} -> ${end} (+$((end - start)))"
    done
}

# Print latency percentiles for a numeric column of a CSV (nearest-rank, mawk-safe).
# Usage: _latency_percentiles <csv> <column_name>
_latency_percentiles() {
    local csv="$1"
    local col="$2"
    [[ -s "$csv" ]] || { echo "n=0 (no data)"; return 0; }

    local values
    values=$(awk -F, -v col="$col" '
        NR==1 { for (i=1;i<=NF;i++) if ($i==col) c=i; next }
        c && $c ~ /^[0-9]+$/ { print $c }
    ' "$csv" | sort -n)

    if [[ -z "$values" ]]; then
        echo "n=0 (no timed samples for $col)"
        return 0
    fi

    echo "$values" | awk '
        { a[n++]=$1; s+=$1 }
        END {
            p50=a[int(0.50*(n-1))]; p90=a[int(0.90*(n-1))]; p99=a[int(0.99*(n-1))]
            printf "n=%d min=%dms p50=%dms p90=%dms p99=%dms max=%dms mean=%dms\n", n, a[0], p50, p90, p99, a[n-1], s/n
        }'
}
