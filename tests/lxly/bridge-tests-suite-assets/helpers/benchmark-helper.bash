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

# Snapshot each unique non-L1 network's latest settled certificate height and
# epoch from Agglayer's interop RPC, appending rows to
# <output_dir>/agglayer_settlement.csv with a phase column (start|end).
# No-op (with one log line) when no Agglayer RPC URL is configured.
#
# Usage: _agglayer_settlement_snapshot <scenarios_file> <phase> <output_dir>
_agglayer_settlement_snapshot() {
    local scenarios_file="$1"
    local phase="$2"
    local output_dir="$3"
    local csv="$output_dir/agglayer_settlement.csv"

    if [[ ! -s "$csv" ]]; then
        echo "phase,network,rollup_id,settled_height,epoch_number,captured_ms" > "$csv"
    fi

    local unique_networks
    unique_networks=$(jq -r '.[].FromNetwork, .[].ToNetwork' "$scenarios_file" | sort -u)

    local captured_any=false
    while IFS= read -r network_id; do
        [[ -n "$network_id" && "$network_id" != "0" ]] || continue

        local rpc_url
        rpc_url=$(_agglayer_rpc_url "$network_id")
        [[ -n "$rpc_url" ]] || continue
        captured_any=true

        local rollup_id
        rollup_id=$(_get_network_config "$network_id" "network_id" 2>/dev/null || echo "$network_id")

        local header height epoch
        header=$(cast rpc --rpc-url "$rpc_url" interop_getLatestSettledCertificateHeader "$rollup_id" 2>/dev/null || echo "")
        height=$(echo "$header" | jq -r '.height // empty' 2>/dev/null || echo "")
        epoch=$(echo "$header" | jq -r '.epoch_number // empty' 2>/dev/null || echo "")

        echo "${phase},${network_id},${rollup_id},${height:-NA},${epoch:-NA},$(_now_ms)" >> "$csv"
    done <<< "$unique_networks"

    if ! $captured_any; then
        _log_file_descriptor "3" "ℹ️  Agglayer settlement snapshot ($phase) skipped: export AGGLAYER_RPC_URL (or <PREFIX>_AGGLAYER_RPC_URL) to record certificate settlement heights."
    fi
}

# Print settled-certificate deltas (certs settled during the run) per network,
# comparing the start and end phases in agglayer_settlement.csv. Emits nothing
# when the file only has a header (Tier 2 disabled).
_agglayer_settlement_report() {
    local output_dir="$1"
    local csv="$output_dir/agglayer_settlement.csv"
    [[ -s "$csv" ]] || return 0

    awk -F, '
        NR==1 { next }
        $1=="start" { start[$2]=$4; rid[$2]=$3 }
        $1=="end"   { end[$2]=$4 }
        END {
            printed=0
            for (net in end) {
                if (start[net]=="" || start[net]=="NA" || end[net]=="NA") continue
                if (!printed) { print "Certificates settled during run (Agglayer):"; printed=1 }
                printf "  network %s (rollup %s): settled height %s -> %s (+%d)\n", net, rid[net], start[net], end[net], (end[net]-start[net])
            }
        }'
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
