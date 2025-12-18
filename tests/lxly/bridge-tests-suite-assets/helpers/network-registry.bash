#!/usr/bin/env bash
# Network Registry - Auto-discovery and centralized network configuration
# This eliminates the need to manually update _initialize_network_config for each new network

# Global associative arrays for network configuration
declare -gA NETWORK_REGISTRY=()
declare -gA NETWORK_ID_TO_PREFIX=()
declare -gA NETWORK_PREFIX_TO_ID=()

# Cache for derived values
declare -gA DERIVED_NETWORK_ID_CACHE=()
declare -gA DERIVED_ETH_ADDRESS_CACHE=()

# Auto-discover networks from environment variables
# Supports patterns like:
#   - BALI_NETWORK_68_RPC_URL -> discovers network ID 68 for bali environment
#   - CARDONA_NETWORK_52_RPC_URL -> discovers network ID 52 for cardona environment
#   - SPEC_NETWORK_1_RPC_URL -> discovers network ID 1 for spec environment
#   - SEPOLIA_RPC_URL -> discovers network ID 0 (L1)
_auto_discover_networks() {
    local env_name="${NETWORK_ENVIRONMENT:-kurtosis}"
    
    _log_network_registry "Auto-discovering networks for environment: $env_name"
    
    # Clear existing registry
    NETWORK_REGISTRY=()
    NETWORK_ID_TO_PREFIX=()
    NETWORK_PREFIX_TO_ID=()
    
    # Discover L1 network (Sepolia) - always network ID 0
    if [[ -n "${SEPOLIA_RPC_URL:-}" ]]; then
        _register_discovered_network "0" "sepolia" "SEPOLIA"
    fi
    
    # Auto-discover L2 networks based on environment
    case "$env_name" in
        "bali")
            _discover_networks_by_pattern "BALI_NETWORK_" "bali"
            ;;
        "cardona")
            _discover_networks_by_pattern "CARDONA_NETWORK_" "cardona"
            ;;
        "spec")
            _discover_networks_by_pattern "SPEC_NETWORK_" "spec"
            ;;
        "kurtosis")
            _discover_kurtosis_networks
            ;;
        *)
            _log_network_registry "Warning: Unknown environment '$env_name', attempting pattern-based discovery"
            # Try to discover from any available pattern
            _discover_networks_by_pattern "BALI_NETWORK_" "bali"
            _discover_networks_by_pattern "CARDONA_NETWORK_" "cardona"
            _discover_networks_by_pattern "SPEC_NETWORK_" "spec"
            ;;
    esac
    
    _log_network_registry "Network discovery complete. Found ${#NETWORK_ID_TO_PREFIX[@]} networks."
    _dump_network_registry
}

# Discover networks matching a specific pattern
# Pattern format: PREFIX_NETWORK_ID_SUFFIX
# Example: BALI_NETWORK_68_RPC_URL -> network ID 68
_discover_networks_by_pattern() {
    local pattern_prefix="$1"  # e.g., "BALI_NETWORK_"
    local env_type="$2"         # e.g., "bali"
    
    # Get all environment variables matching the pattern
    local var_names
    var_names=$(compgen -v | grep "^${pattern_prefix}[0-9]\+_RPC_URL$" || true)
    
    for var_name in $var_names; do
        # Extract network ID from variable name
        # e.g., BALI_NETWORK_68_RPC_URL -> 68
        local network_id
        network_id=$(echo "$var_name" | sed -E "s/^${pattern_prefix}([0-9]+)_RPC_URL$/\1/")
        
        if [[ -n "$network_id" && "$network_id" =~ ^[0-9]+$ ]]; then
            local network_prefix="${pattern_prefix}${network_id}"
            local network_name="${env_type}_${network_id}"
            
            _register_discovered_network "$network_id" "$network_name" "$network_prefix"
        fi
    done
}

# Discover Kurtosis networks (special case with different naming convention)
_discover_kurtosis_networks() {
    # Kurtosis L1
    if [[ -n "${KURTOSIS_L1_RPC_URL:-}" ]]; then
        _register_discovered_network "0" "kurtosis_l1" "KURTOSIS_L1"
    fi
    
    # Kurtosis L2 networks
    for i in 1 2 3 4 5; do
        local var_name="KURTOSIS_NETWORK_${i}_RPC_URL"
        if [[ -n "${!var_name:-}" ]]; then
            _register_discovered_network "$i" "kurtosis_network_$i" "KURTOSIS_NETWORK_${i}"
        fi
    done
}

# Register a discovered network
_register_discovered_network() {
    local network_id="$1"
    local network_name="$2"
    local env_prefix="$3"  # e.g., "BALI_NETWORK_68" or "SEPOLIA"
    
    # Store mappings
    NETWORK_ID_TO_PREFIX["$network_id"]="$env_prefix"
    NETWORK_PREFIX_TO_ID["$env_prefix"]="$network_id"
    
    # Build network configuration entry
    local rpc_url_var="${env_prefix}_RPC_URL"
    local bridge_addr_var="${env_prefix}_BRIDGE_ADDR"
    local private_key_var="${env_prefix}_PRIVATE_KEY"
    local bridge_service_var="${env_prefix}_BRIDGE_SERVICE_URL"
    
    NETWORK_REGISTRY["${network_id}_name"]="$network_name"
    NETWORK_REGISTRY["${network_id}_prefix"]="$env_prefix"
    NETWORK_REGISTRY["${network_id}_rpc_url"]="${!rpc_url_var:-}"
    NETWORK_REGISTRY["${network_id}_bridge_addr"]="${!bridge_addr_var:-}"
    NETWORK_REGISTRY["${network_id}_private_key"]="${!private_key_var:-}"
    NETWORK_REGISTRY["${network_id}_bridge_service_url"]="${!bridge_service_var:-}"
    
    _log_network_registry "Registered network ID=$network_id name=$network_name prefix=$env_prefix"
}

# Get network configuration by ID
_get_network_config() {
    local network_id="$1"
    local config_type="$2"  # rpc_url, bridge_addr, private_key, bridge_service_url, network_id, eth_address
    
    # Lazy initialization
    if [[ ${#NETWORK_REGISTRY[@]} -eq 0 ]]; then
        _auto_discover_networks
    fi
    
    # Handle derived values
    case "$config_type" in
        "network_id")
            # Check cache first
            if [[ -n "${DERIVED_NETWORK_ID_CACHE[$network_id]:-}" ]]; then
                echo "${DERIVED_NETWORK_ID_CACHE[$network_id]}"
                return 0
            fi
            
            # Try to derive from bridge contract
            local rpc_url="${NETWORK_REGISTRY[${network_id}_rpc_url]:-}"
            local bridge_addr="${NETWORK_REGISTRY[${network_id}_bridge_addr]:-}"
            
            if [[ -n "$rpc_url" && -n "$bridge_addr" ]]; then
                local derived_id
                if derived_id=$(cast call --rpc-url "$rpc_url" "$bridge_addr" 'networkID()(uint32)' 2>/dev/null); then
                    DERIVED_NETWORK_ID_CACHE["$network_id"]="$derived_id"
                    echo "$derived_id"
                    return 0
                fi
            fi
            
            # Fallback: return the provided network_id
            DERIVED_NETWORK_ID_CACHE["$network_id"]="$network_id"
            echo "$network_id"
            return 0
            ;;
            
        "eth_address")
            # Check cache first
            local cache_key="${network_id}_eth"
            if [[ -n "${DERIVED_ETH_ADDRESS_CACHE[$cache_key]:-}" ]]; then
                echo "${DERIVED_ETH_ADDRESS_CACHE[$cache_key]}"
                return 0
            fi
            
            # Derive from private key
            local private_key="${NETWORK_REGISTRY[${network_id}_private_key]:-}"
            
            if [[ -n "$private_key" ]]; then
                local derived_address
                if derived_address=$(cast wallet address --private-key "$private_key" 2>/dev/null); then
                    DERIVED_ETH_ADDRESS_CACHE["$cache_key"]="$derived_address"
                    echo "$derived_address"
                    return 0
                fi
            fi
            
            _log_network_registry "Error: Could not derive eth_address for network $network_id"
            return 1
            ;;
            
        *)
            # Direct registry lookup
            local value="${NETWORK_REGISTRY[${network_id}_${config_type}]:-}"
            if [[ -n "$value" ]]; then
                echo "$value"
                return 0
            fi
            
            _log_network_registry "Error: Configuration '$config_type' not found for network $network_id"
            return 1
            ;;
    esac
}

# Get all registered network IDs
_get_all_network_ids() {
    # Lazy initialization
    if [[ ${#NETWORK_REGISTRY[@]} -eq 0 ]]; then
        _auto_discover_networks
    fi
    
    # Extract unique network IDs from NETWORK_ID_TO_PREFIX
    printf '%s\n' "${!NETWORK_ID_TO_PREFIX[@]}" | sort -n
}

# Check if a network ID is registered
_is_network_registered() {
    local network_id="$1"
    
    # Lazy initialization
    if [[ ${#NETWORK_REGISTRY[@]} -eq 0 ]]; then
        _auto_discover_networks
    fi
    
    [[ -n "${NETWORK_ID_TO_PREFIX[$network_id]:-}" ]]
}

# Logging helper for network registry
_log_network_registry() {
    local message="$1"
    if [[ "${DEBUG_NETWORK_REGISTRY:-false}" == "true" ]]; then
        echo "[Network Registry] $message" >&3
    fi
}

# Debug: Dump entire network registry
_dump_network_registry() {
    if [[ "${DEBUG_NETWORK_REGISTRY:-false}" != "true" ]]; then
        return
    fi
    
    echo "[Network Registry] ===== NETWORK REGISTRY DUMP =====" >&3
    echo "[Network Registry] Discovered Networks:" >&3
    for net_id in $(printf '%s\n' "${!NETWORK_ID_TO_PREFIX[@]}" | sort -n); do
        local prefix="${NETWORK_ID_TO_PREFIX[$net_id]}"
        local name="${NETWORK_REGISTRY[${net_id}_name]:-}"
        local rpc="${NETWORK_REGISTRY[${net_id}_rpc_url]:-}"
        echo "[Network Registry]   ID=$net_id, Name=$name, Prefix=$prefix, RPC=${rpc:0:30}..." >&3
    done
    echo "[Network Registry] ===================================" >&3
}

# Initialize network registry on source
_auto_discover_networks
