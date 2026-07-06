#!/usr/bin/env bash
# =============================================================================
# Pre-flight root-wallet funding check for the Standard Bridge Tests suite.
#
# The bridge suite funds one ephemeral wallet per scenario on every network the
# scenarios touch (_setup_ephemeral_accounts_in_bulk in bridge-tests-helper.bash):
#   - 0.1   ETH per account on network 0 (L1 / Sepolia)
#   - 0.001 ETH per account on every other (L2) network
# If the root/funded wallet is short, the run fails partway through and can burn
# the whole job timeout. This script estimates the requirement and stops early
# when the wallet is blatantly underfunded.
#
# It only checks *native* balance: the test ERC20s are minted on demand by the
# root wallet, so no pre-existing token balance is required.
#
# Expects these to already be exported by the caller (same names the network
# registry auto-discovers):
#   NETWORK_ENVIRONMENT                         (bali | cardona | spec)
#   SEPOLIA_RPC_URL / SEPOLIA_PRIVATE_KEY       (network 0 / L1)
#   <ENV>_NETWORK_<id>_RPC_URL / _PRIVATE_KEY   (each L2 network)
#
# Optional:
#   FUNDING_CHECK_MARGIN_PCT   headroom over the raw drip requirement (default 120 = 1.2x)
#
# Exit 0 if every configured network has enough; exit 1 on any UNDERFUNDED/ERROR.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must be set BEFORE sourcing the registry: network-registry.bash runs
# _auto_discover_networks at source time and reads NETWORK_ENVIRONMENT to pick
# the L2 discovery pattern. Setting it afterwards would let discovery run under
# the wrong (kurtosis) default and register only network 0.
NETWORK_ENVIRONMENT="${NETWORK_ENVIRONMENT:-bali}"

# Reuse the existing network registry (_get_network_config, auto-discovery).
# NOTE: safe to source outside bats because its logging only writes to fd 3 when
# DEBUG_NETWORK_REGISTRY=true (which we never set); leave that unset here.
# shellcheck source=network-registry.bash
source "$SCRIPT_DIR/network-registry.bash"

MARGIN_PCT="${FUNDING_CHECK_MARGIN_PCT:-120}"
if ! [[ "$MARGIN_PCT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: FUNDING_CHECK_MARGIN_PCT must be a non-negative integer, got: '$MARGIN_PCT'" >&2
    exit 1
fi

# Per-account native drip, mirroring bridge-tests-helper.bash:624-630.
L1_PER_ACCOUNT_ETHER="0.1"     # network 0
L2_PER_ACCOUNT_ETHER="0.001"   # every other network

# --- Resolve the scenarios file (mirror bridge-tests-suite.bats:32-46) --------
case "$NETWORK_ENVIRONMENT" in
    bali)    suite_file="bali-bridge-tests-suite.json" ;;
    cardona) suite_file="cardona-bridge-tests-suite.json" ;;
    spec)    suite_file="spec-bridge-tests-suite.json" ;;
    *)       suite_file="bali-bridge-tests-suite.json" ;;  # default, as in the suite
esac
scenarios_file="$SCRIPT_DIR/../acts-file-outputs/$suite_file"

if [[ ! -f "$scenarios_file" ]]; then
    echo "ERROR: scenarios file not found: $scenarios_file" >&2
    exit 1
fi

total_scenarios="$(jq '. | length' "$scenarios_file" 2>/dev/null || echo "")"
if ! [[ "$total_scenarios" =~ ^[0-9]+$ ]] || [[ "$total_scenarios" -eq 0 ]]; then
    echo "ERROR: could not read a positive scenario count from $scenarios_file" >&2
    exit 1
fi

unique_networks="$(jq -r '.[].FromNetwork, .[].ToNetwork' "$scenarios_file" 2>/dev/null | grep -v '^null$' | sort -u)"
if [[ -z "$unique_networks" ]]; then
    echo "ERROR: no networks found in scenarios file $scenarios_file (missing From/ToNetwork?)" >&2
    exit 1
fi

echo "========================================================================"
echo " Root wallet funding pre-flight"
echo "   Environment : $NETWORK_ENVIRONMENT"
echo "   Scenarios   : $total_scenarios (one ephemeral wallet funded per scenario)"
echo "   Networks    : $(echo "$unique_networks" | tr '\n' ' ')"
echo "   Margin      : ${MARGIN_PCT}% of the raw drip requirement"
echo "========================================================================"
printf '%-8s %-44s %-16s %-16s %s\n' "Network" "Funding address" "Required(ETH)" "Balance(ETH)" "Status"

# Fetch native balance in ether, with one retry. Echoes the value on success.
_get_balance_ether() {
    local rpc_url="$1" address="$2" out
    if out=$(cast balance --ether --rpc-url "$rpc_url" "$address" 2>/dev/null); then
        echo "$out"; return 0
    fi
    if out=$(cast balance --ether --rpc-url "$rpc_url" "$address" 2>/dev/null); then
        echo "$out"; return 0
    fi
    return 1
}

failures=0

while IFS= read -r network_id; do
    [[ -n "$network_id" ]] || continue

    # Mirror the run's own skip signal (bridge-tests-suite.bats:259-263): a network
    # is funded iff its bridge_addr resolves. If it doesn't, the run skips the
    # network entirely, so it needs no balance here -> SKIP.
    bridge_addr="$(_get_network_config "$network_id" bridge_addr 2>/dev/null || true)"
    if [[ -z "$bridge_addr" ]]; then
        printf '%-8s %-44s %-16s %-16s %s\n' "$network_id" "(not configured)" "-" "-" "SKIP"
        continue
    fi

    # The run WILL fund this network. If rpc/key are missing the run would try and
    # fail (polycli fund aborts setup), so treat that as an ERROR, not a SKIP.
    rpc_url="$(_get_network_config "$network_id" rpc_url 2>/dev/null || true)"
    private_key="$(_get_network_config "$network_id" private_key 2>/dev/null || true)"
    if [[ -z "$rpc_url" || -z "$private_key" ]]; then
        printf '%-8s %-44s %-16s %-16s %s\n' "$network_id" "(missing rpc/key)" "-" "-" "ERROR"
        failures=$((failures + 1))
        continue
    fi

    address="$(cast wallet address --private-key "$private_key" 2>/dev/null || true)"
    if [[ -z "$address" ]]; then
        printf '%-8s %-44s %-16s %-16s %s\n' "$network_id" "(bad private key)" "-" "-" "ERROR"
        failures=$((failures + 1))
        continue
    fi

    if [[ "$network_id" == "0" ]]; then
        per_account="$L1_PER_ACCOUNT_ETHER"
    else
        per_account="$L2_PER_ACCOUNT_ETHER"
    fi

    # required = scenarios * per_account * margin/100 (ether decimals; float math is
    # fine for a blatant-shortfall gate and avoids 64-bit wei overflow).
    required_ether="$(awk -v n="$total_scenarios" -v p="$per_account" -v m="$MARGIN_PCT" \
        'BEGIN { printf "%.6f", n * p * m / 100 }')"

    if ! balance_ether="$(_get_balance_ether "$rpc_url" "$address")"; then
        printf '%-8s %-44s %-16s %-16s %s\n' "$network_id" "$address" "$required_ether" "(query failed)" "ERROR"
        failures=$((failures + 1))
        continue
    fi

    if awk -v b="$balance_ether" -v r="$required_ether" 'BEGIN { exit !(b + 0 < r + 0) }'; then
        status="UNDERFUNDED"
        failures=$((failures + 1))
    else
        status="OK"
    fi
    # Comparison uses full precision above; round only for a tidy table.
    balance_disp="$(awk -v b="$balance_ether" 'BEGIN { printf "%.6f", b + 0 }')"
    printf '%-8s %-44s %-16s %-16s %s\n' "$network_id" "$address" "$required_ether" "$balance_disp" "$status"
done <<< "$unique_networks"

echo "========================================================================"
if [[ "$failures" -gt 0 ]]; then
    echo "FAIL: $failures network(s) are underfunded or unverifiable."
    echo "      Top up the funded wallet(s) or lower FUNDING_CHECK_MARGIN_PCT, then re-run."
    echo "      Required per network = scenarios($total_scenarios) x per-account drip x ${MARGIN_PCT}%"
    echo "      (0.1 ETH/account on network 0, 0.001 ETH/account on L2 networks)."
    echo "      Note: this is a native-drip estimate; the ${MARGIN_PCT}% margin also has to"
    echo "      absorb the funder's own gas (mint/approve/polycli-fund txs)."
    exit 1
fi
echo "OK: all configured networks have sufficient funding."
exit 0
