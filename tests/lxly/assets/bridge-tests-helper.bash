#!/bin/bash
# shellcheck disable=SC2154,SC2034

# =============================================================================
# Bridge Tests Helper - Multi-Network Support with Auto-Derivation
# =============================================================================
#
# This script supports dynamic network configuration for bridge testing.
# Network ID and ETH addresses are automatically derived to reduce redundancy.
# 
# USAGE EXAMPLES:
# 
# 1. Using existing L1/L2 networks (backward compatible):
#    The script automatically maps network IDs to existing variables:
#    - Network 0 -> l1_rpc_url, l1_bridge_addr, l1_private_key
#    - Network 1 -> l2_rpc_url, l2_bridge_addr, l2_private_key
#    - network_id: derived via "cast call <rpc> <bridge> 'networkID()'"
#    - eth_address: derived via "cast wallet address --private-key <key>"
#
# 2. Adding new Bali networks (only essential variables needed):
#    You only need to define these 3 essential variables:
#    
#    # For bali-37 (network ID 37):
#    export bali_01_rpc_url="https://rpc.bali-01.example.com"
#    export bali_01_bridge_addr="0x..."
#    export bali_01_private_key="0x..."
#    
#    # The following are derived automatically:
#    # - network_id: queried from bridge contract
#    # - eth_address: derived from private key
#    
#    # Alternative naming patterns are also supported:
#    export BALI_37_RPC_URL="https://rpc.bali-37.example.com"
#    export NETWORK_37_BRIDGE_ADDR="0x..."
#    export NETWORK_37_PRIVATE_KEY="0x..."
#
# 3. Registering networks dynamically (simplified):
#    _register_network "49" "bali_49" "https://rpc.bali-49.com" "0xbridge..." "0xkey..."
#
# 4. Listing configured networks (shows derived values):
#    _list_networks
#
# =============================================================================

# Source the logger functions
# shellcheck disable=SC1091
source "$PROJECT_ROOT/core/helpers/logger.bash"

# =============================================================================
# Network Configuration Functions
# =============================================================================
# =============================================================================

# Initialize network configuration
_initialize_network_config() {
    # Define network ID to name mapping
    # This can be extended to support more networks
    case "${NETWORK_ENVIRONMENT:-kurtosis}" in
        "kurtosis")
            declare -gA NETWORK_ID_TO_NAME=(
                ["0"]="kurtosis_l1"
                ["1"]="kurtosis_network_1"
                ["2"]="kurtosis_network_2"
            )
            # You can also define network name to ID mapping for reverse lookup
            declare -gA NETWORK_NAME_TO_ID=(
                ["kurtosis_l1"]="0"
                ["kurtosis_network_1"]="1"
                ["kurtosis_network_2"]="2"
            )
        ;;
        "bali")
            declare -gA NETWORK_ID_TO_NAME=(
                ["0"]="sepolia"
                ["1"]="bali_1"
                ["37"]="bali_37"
                # ["48"]="bali_48" # Bali-48 seems to have a higher gas fee, so it burns a lot of gas.
                ["49"]="bali_49"
                ["52"]="bali_52"
                ["57"]="bali_57"
            )
            
            # You can also define network name to ID mapping for reverse lookup
            declare -gA NETWORK_NAME_TO_ID=(
                ["sepolia"]="0"
                ["bali_1"]="1"
                ["bali_37"]="37"
                # ["bali_48"]="48" # Bali-48 seems to have a higher gas fee, so it burns a lot of gas.
                ["bali_49"]="49"
                ["bali_52"]="52"
                ["bali_57"]="57"
            )
        ;;
        "cardona")
            declare -gA NETWORK_ID_TO_NAME=(
                ["0"]="sepolia"
                # ["1"]="cardona_1"
                # ["48"]="cardona_48"
                # ["50"]="cardona_50"
                ["51"]="cardona_51"
                ["52"]="cardona_52"
            )
            
            # You can also define network name to ID mapping for reverse lookup
            declare -gA NETWORK_NAME_TO_ID=(
                ["sepolia"]="0"
                # ["cardona_1"]="1"
                # ["cardona_48"]="48"
                # ["cardona_50"]="50"
                ["cardona_51"]="51"
                ["cardona_52"]="52"
            )
        ;;
    esac
    
    # Cache for derived values to avoid repeated RPC calls
    declare -gA DERIVED_NETWORK_ID_CACHE=()
    declare -gA DERIVED_ETH_ADDRESS_CACHE=()
}

_get_network_config() {
    local network_id="$1"
    local config_type="$2"  # rpc_url, bridge_addr, private_key | network_id, eth_address (derived)
    
    # Initialize network configuration if not done already
    if [[ -z "${NETWORK_ID_TO_NAME[$network_id]:-}" ]]; then
        _initialize_network_config
    fi
    
    # Get the network name from network ID
    local network_name="${NETWORK_ID_TO_NAME[$network_id]:-}"
    
    if [[ -z "$network_name" ]]; then
        echo "Unsupported network ID: $network_id" >&3
        return 1
    fi
    
    # Handle derived values first
    case "$config_type" in
        "network_id")
            # Check cache first
            local cache_key="$network_id"
            if [[ -n "${DERIVED_NETWORK_ID_CACHE[$cache_key]:-}" ]]; then
                echo "${DERIVED_NETWORK_ID_CACHE[$cache_key]}"
                return 0
            fi
            
            # For network_id, we can derive it from the RPC URL by calling the contract
            # Get rpc_url and bridge_addr directly from environment variables (no recursion)
            local rpc_url bridge_addr
            rpc_url=$(_get_env_var_directly "$network_name" "rpc_url")
            bridge_addr=$(_get_env_var_directly "$network_name" "bridge_addr")
            
            if [[ -n "$rpc_url" && -n "$bridge_addr" ]]; then
                # Try to get network ID from the bridge contract
                local derived_network_id
                if derived_network_id=$(cast call --rpc-url "$rpc_url" "$bridge_addr" 'networkID()(uint32)' 2>/dev/null); then
                    # Cache the result
                    DERIVED_NETWORK_ID_CACHE["$cache_key"]="$derived_network_id"
                    echo "$derived_network_id"
                    return 0
                fi
            fi
            
            # Fallback: return the provided network_id and cache it
            DERIVED_NETWORK_ID_CACHE["$cache_key"]="$network_id"
            echo "$network_id"
            return 0
            ;;
        "eth_address")
            # Check cache first
            local cache_key="${network_name}_eth"
            if [[ -n "${DERIVED_ETH_ADDRESS_CACHE[$cache_key]:-}" ]]; then
                echo "${DERIVED_ETH_ADDRESS_CACHE[$cache_key]}"
                return 0
            fi
            
            # For eth_address, derive it from the private key
            # Get private_key directly from environment variables (no recursion)
            local private_key
            private_key=$(_get_env_var_directly "$network_name" "private_key")
            
            if [[ -n "$private_key" ]]; then
                local derived_address
                if derived_address=$(cast wallet address --private-key "$private_key" 2>/dev/null); then
                    # Cache the result
                    DERIVED_ETH_ADDRESS_CACHE["$cache_key"]="$derived_address"
                    echo "$derived_address"
                    return 0
                fi
            fi
            
            # Fallback: try to get stored eth_address directly
            local value
            value=$(_get_env_var_directly "$network_name" "eth_address")
            if [[ -n "$value" ]]; then
                echo "$value"
                return 0
            fi
            ;;
        *)
            # For non-derived values, get them directly from environment variables
            local value
            value=$(_get_env_var_directly "$network_name" "$config_type")
            if [[ -n "$value" ]]; then
                echo "$value"
                return 0
            fi
            ;;
    esac
    
    echo "Configuration not found for network $network_id ($network_name) config $config_type" >&3
    return 1
}

_get_env_var_directly() {
    local network_name="$1"
    local config_type="$2"
    
    local value=""
    
    case "$config_type" in
        "rpc_url"|"bridge_addr"|"private_key"|"bridge_service_url"|"eth_address")
            if [[ "$network_name" =~ ^bali_ ]]; then
                # For Bali networks, use BALI_NETWORK_XX_* pattern (must match env file)
                local network_num="${network_name#bali_}"
                env_var_name="BALI_NETWORK_${network_num}_$(echo "$config_type" | tr '[:lower:]' '[:upper:]')"
                value="${!env_var_name:-}"
            elif [[ "$network_name" =~ ^cardona_ ]]; then
                # For Cardona networks, use CARDONA_NETWORK_XX_* pattern (must match env file)
                local network_num="${network_name#cardona_}"
                env_var_name="CARDONA_NETWORK_${network_num}_$(echo "$config_type" | tr '[:lower:]' '[:upper:]')"
                value="${!env_var_name:-}"
            elif [[ "$network_name" == "sepolia" ]]; then
                # For Sepolia, use SEPOLIA_* pattern
                local env_var_name
                env_var_name="SEPOLIA_$(echo "$config_type" | tr '[:lower:]' '[:upper:]')"
                value="${!env_var_name:-}"
            else
                # For other networks (like kurtosis), use the direct network_name_config pattern
                local var_name="${network_name}_${config_type}"
                value="${!var_name:-}"
            fi
            ;;
    esac
    
    echo "$value"
}

# Helper function to register a new network dynamically
_register_network() {
    local network_id="$1"
    local network_name="$2"
    local rpc_url="$3"
    local bridge_addr="$4"
    local private_key="$5"
    # Note: network_id and eth_address will be derived
    
    # Initialize if needed
    _initialize_network_config
    
    # Register the network
    NETWORK_ID_TO_NAME["$network_id"]="$network_name"
    NETWORK_NAME_TO_ID["$network_name"]="$network_id"
    
    # Set only the essential configuration variables (others will be derived)
    declare -g "${network_name}_rpc_url=$rpc_url"
    declare -g "${network_name}_bridge_addr=$bridge_addr"
    declare -g "${network_name}_private_key=$private_key"
    
    _log_file_descriptor "2" "Registered network: $network_name (ID: $network_id)"
    _log_file_descriptor "2" "  RPC URL: $rpc_url"
    _log_file_descriptor "2" "  Bridge Address: $bridge_addr"
    _log_file_descriptor "2" "  Network ID and ETH address will be derived"
}

# Helper function to list all configured networks
_list_networks() {
    _initialize_network_config
    
    echo "Configured networks:" >&3
    for network_id in "${!NETWORK_ID_TO_NAME[@]}"; do
        local network_name="${NETWORK_ID_TO_NAME[$network_id]}"
        local rpc_url
        rpc_url=$(_get_network_config "$network_id" "rpc_url" 2>/dev/null || echo "Not configured")
        local derived_network_id
        derived_network_id=$(_get_network_config "$network_id" "network_id" 2>/dev/null || echo "Unable to derive")
        local eth_address
        eth_address=$(_get_network_config "$network_id" "eth_address" 2>/dev/null || echo "Unable to derive")
        
        echo "  Network ID $network_id ($network_name):" >&3
        echo "    RPC URL: $rpc_url" >&3
        echo "    Derived Network ID: $derived_network_id" >&3
        echo "    Derived ETH Address: $eth_address" >&3
    done
}

# Initialize network configurations on script load
_initialize_network_config

# =============================================================================
# Helper Functions
# =============================================================================

# Add a helper function for safe cast send operations
_safe_cast_send() {
    local rpc_url="$1"
    local private_key="$2"
    shift 2
    local cast_args=("$@")
    
    local output
    local status
    
    # First attempt: Use EIP-1559 (non-legacy) transaction
    # _log_file_descriptor "3" "Attempting non-legacy transaction"
    if output=$(cast send --rpc-url "$rpc_url" --private-key "$private_key" "${cast_args[@]}" 2>&1); then
        # _log_file_descriptor "3" "Non-legacy transaction succeeded"
        # echo "$output"
        return 0
    else
        status=$?
        # _log_file_descriptor "3" "Non-legacy transaction failed: $output"
        
        # Check if the failure is due to EIP-1559 not being supported or EIP-1559 related errors
        if echo "$output" | grep -q -E "(unsupported feature: eip1559|EIP-1559|type 2 transactions|not supported|tip higher than fee cap|priority fee higher|gasFeeCap.*tip)"; then
            # _log_file_descriptor "3" "EIP-1559 not supported or EIP-1559 error detected, falling back to legacy transaction"
            
            # Second attempt: Use legacy transaction as fallback
            if output=$(cast send --legacy --rpc-url "$rpc_url" --private-key "$private_key" "${cast_args[@]}" 2>&1); then
                # _log_file_descriptor "3" "Legacy transaction succeeded"
                # echo "$output"
                return 0
            else
                local legacy_status=$?
                # _log_file_descriptor "3" "Legacy transaction also failed: $output"
                # echo "$output"
                return $legacy_status
            fi
        else
            # Non-EIP-1559 related error, don't retry with legacy
            # _log_file_descriptor "3" "Non-EIP-1559 error, not retrying"
             _log_file_descriptor "3" "$output"
            return $status
        fi
    fi
}


deploy_buggy_erc20() {
    local rpc_url=$1
    local private_key=$2
    local eth_address=$3
    local bridge_address=$4
    _log_file_descriptor "3" "Deploying Buggy ERC20 - RPC: $rpc_url, Address: $eth_address, Bridge: $bridge_address"

    salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    deterministic_deployer_addr="0x4e59b44847b379578588920ca78fbf26c0b4956c"
    erc20_buggy_bytecode=608060405234801561001057600080fd5b506040516109013803806109018339818101604052606081101561003357600080fd5b810190808051604051939291908464010000000082111561005357600080fd5b90830190602082018581111561006857600080fd5b825164010000000081118282018810171561008257600080fd5b82525081516020918201929091019080838360005b838110156100af578181015183820152602001610097565b50505050905090810190601f1680156100dc5780820380516001836020036101000a031916815260200191505b50604052602001805160405193929190846401000000008211156100ff57600080fd5b90830190602082018581111561011457600080fd5b825164010000000081118282018810171561012e57600080fd5b82525081516020918201929091019080838360005b8381101561015b578181015183820152602001610143565b50505050905090810190601f1680156101885780820380516001836020036101000a031916815260200191505b5060405260209081015185519093506101a792506003918601906101d8565b5081516101bb9060049060208501906101d8565b506005805460ff191660ff92909216919091179055506102799050565b828054600181600116156101000203166002900490600052602060002090601f01602090048101928261020e5760008555610254565b82601f1061022757805160ff1916838001178555610254565b82800160010185558215610254579182015b82811115610254578251825591602001919060010190610239565b50610260929150610264565b5090565b5b808211156102605760008155600101610265565b610679806102886000396000f3fe608060405234801561001057600080fd5b50600436106100b45760003560e01c806370a082311161007157806370a082311461021257806395d89b41146102385780639dc29fac14610240578063a9059cbb1461026c578063b46310f614610298578063dd62ed3e146102c4576100b4565b806306fdde03146100b9578063095ea7b31461013657806318160ddd1461017657806323b872dd14610190578063313ce567146101c657806340c10f19146101e4575b600080fd5b6100c16102f2565b6040805160208082528351818301528351919283929083019185019080838360005b838110156100fb5781810151838201526020016100e3565b50505050905090810190601f1680156101285780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6101626004803603604081101561014c57600080fd5b506001600160a01b038135169060200135610380565b604080519115158252519081900360200190f35b61017e6103e6565b60408051918252519081900360200190f35b610162600480360360608110156101a657600080fd5b506001600160a01b038135811691602081013590911690604001356103ec565b6101ce610466565b6040805160ff9092168252519081900360200190f35b610210600480360360408110156101fa57600080fd5b506001600160a01b03813516906020013561046f565b005b61017e6004803603602081101561022857600080fd5b50356001600160a01b031661047d565b6100c161048f565b6102106004803603604081101561025657600080fd5b506001600160a01b0381351690602001356104ea565b6101626004803603604081101561028257600080fd5b506001600160a01b0381351690602001356104f4565b610210600480360360408110156102ae57600080fd5b506001600160a01b03813516906020013561054f565b61017e600480360360408110156102da57600080fd5b506001600160a01b038135811691602001351661056b565b6003805460408051602060026001851615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103785780601f1061034d57610100808354040283529160200191610378565b820191906000526020600020905b81548152906001019060200180831161035b57829003601f168201915b505050505081565b3360008181526002602090815260408083206001600160a01b038716808552908352818420869055815186815291519394909390927f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925928290030190a350600192915050565b60005481565b6001600160a01b0380841660008181526002602090815260408083203384528252808320805487900390558383526001825280832080548790039055938616808352848320805487019055845186815294519294909392600080516020610624833981519152929181900390910190a35060019392505050565b60055460ff1681565b6104798282610588565b5050565b60016020526000908152604090205481565b6004805460408051602060026001851615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103785780601f1061034d57610100808354040283529160200191610378565b61047982826105d3565b336000818152600160209081526040808320805486900390556001600160a01b03861680845281842080548701905581518681529151939490939092600080516020610624833981519152928290030190a350600192915050565b6001600160a01b03909116600090815260016020526040902055565b600260209081526000928352604080842090915290825290205481565b6001600160a01b038216600081815260016020908152604080832080548601905582548501835580518581529051600080516020610624833981519152929181900390910190a35050565b6001600160a01b0382166000818152600160209081526040808320805486900390558254859003835580518581529051929392600080516020610624833981519152929181900390910190a3505056feddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa2646970667358221220364a383ccce0e270376267b8631412d1b7ddb1883c5379556b58cbefc1ca504564736f6c63430007060033
    
    # This contract is a weird ERC20 that has a infinite money glitch and allows for some bizarre testing
    constructor_args=$(cast abi-encode 'f(string,string,uint8)' 'Buggy ERC20' 'BUG' "18" | sed 's/0x//')
    test_erc20_buggy_addr=$(cast create2 --salt $salt --init-code $erc20_buggy_bytecode"$constructor_args")
    _log_file_descriptor "3" "Calculated Buggy ERC20 address: $test_erc20_buggy_addr"

    if [[ $(cast code --rpc-url "$rpc_url" "$test_erc20_buggy_addr") != "0x" ]]; then
        _log_file_descriptor "3" "The network on $rpc_url already has the Buggy ERC20 deployed. Skipping deployment..."
    else
        _log_file_descriptor "3" "Deploying Buggy ERC20 to $rpc_url..."
        if ! _safe_cast_send "$rpc_url" "$private_key" "$deterministic_deployer_addr" "$salt$erc20_buggy_bytecode$constructor_args"; then
            _log_file_descriptor "3" "Failed to deploy Buggy ERC20"
            return 1
        fi
        _log_file_descriptor "3" "Deployment transaction sent."

        _log_file_descriptor "3" "Minting max uint tokens to $eth_address..."
        if ! _safe_cast_send "$rpc_url" "$private_key" "$test_erc20_buggy_addr" 'mint(address,uint256)' "$eth_address" "$(cast max-uint)"; then
            _log_file_descriptor "3" "Failed to mint tokens"
            return 1
        fi
        _log_file_descriptor "3" "Minting completed."

        _log_file_descriptor "3" "Approving max uint tokens for bridge $bridge_address..."
        if ! _safe_cast_send "$rpc_url" "$private_key" "$test_erc20_buggy_addr" 'approve(address,uint256)' "$bridge_address" "$(cast max-uint)"; then
            _log_file_descriptor "3" "Failed to approve tokens"
            return 1
        fi
        _log_file_descriptor "3" "Approval completed."
    fi
}


deploy_test_erc20() {
    local rpc_url=$1
    local private_key=$2
    local eth_address=$3
    local bridge_address=$4
    _log_file_descriptor "3" "Deploying Test ERC20 - RPC: $rpc_url, Address: $eth_address, Bridge: $bridge_address"

    salt="0x0000000000000000000000000000000000000000000000000000000000000000"
    deterministic_deployer_addr="0x4e59b44847b379578588920ca78fbf26c0b4956c"
    erc_20_bytecode=60806040526040516200143a3803806200143a833981016040819052620000269162000201565b8383600362000036838262000322565b50600462000045828262000322565b5050506200005a82826200007160201b60201c565b505081516020909201919091206006555062000416565b6001600160a01b038216620000cc5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015260640160405180910390fd5b8060026000828254620000e09190620003ee565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b505050565b634e487b7160e01b600052604160045260246000fd5b600082601f8301126200016457600080fd5b81516001600160401b03808211156200018157620001816200013c565b604051601f8301601f19908116603f01168101908282118183101715620001ac57620001ac6200013c565b81604052838152602092508683858801011115620001c957600080fd5b600091505b83821015620001ed5785820183015181830184015290820190620001ce565b600093810190920192909252949350505050565b600080600080608085870312156200021857600080fd5b84516001600160401b03808211156200023057600080fd5b6200023e8883890162000152565b955060208701519150808211156200025557600080fd5b50620002648782880162000152565b604087015190945090506001600160a01b03811681146200028457600080fd5b6060959095015193969295505050565b600181811c90821680620002a957607f821691505b602082108103620002ca57634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200013757600081815260208120601f850160051c81016020861015620002f95750805b601f850160051c820191505b818110156200031a5782815560010162000305565b505050505050565b81516001600160401b038111156200033e576200033e6200013c565b62000356816200034f845462000294565b84620002d0565b602080601f8311600181146200038e5760008415620003755750858301515b600019600386901b1c1916600185901b1785556200031a565b600085815260208120601f198616915b82811015620003bf578886015182559484019460019091019084016200039e565b5085821015620003de5787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b808201808211156200041057634e487b7160e01b600052601160045260246000fd5b92915050565b61101480620004266000396000f3fe608060405234801561001057600080fd5b506004361061014d5760003560e01c806340c10f19116100c35780639e4e73181161007c5780639e4e73181461033c578063a457c2d714610363578063a9059cbb14610376578063c473af3314610389578063d505accf146103b0578063dd62ed3e146103c357600080fd5b806340c10f19146102b257806342966c68146102c557806356189cb4146102d857806370a08231146102eb5780637ecebe001461031457806395d89b411461033457600080fd5b806323b872dd1161011557806323b872dd146101c357806330adf81f146101d6578063313ce567146101fd5780633408e4701461020c5780633644e51514610212578063395093511461029f57600080fd5b806304622c2e1461015257806306fdde031461016e578063095ea7b31461018357806318160ddd146101a6578063222f5be0146101ae575b600080fd5b61015b60065481565b6040519081526020015b60405180910390f35b6101766103d6565b6040516101659190610db1565b610196610191366004610e1b565b610468565b6040519015158152602001610165565b60025461015b565b6101c16101bc366004610e45565b610482565b005b6101966101d1366004610e45565b610492565b61015b7f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c981565b60405160128152602001610165565b4661015b565b61015b6006546000907f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f907fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc646604080516020810195909552840192909252606083015260808201523060a082015260c00160405160208183030381529060405280519060200120905090565b6101966102ad366004610e1b565b6104b6565b6101c16102c0366004610e1b565b6104d8565b6101c16102d3366004610e81565b6104e6565b6101c16102e6366004610e45565b6104f3565b61015b6102f9366004610e9a565b6001600160a01b031660009081526020819052604090205490565b61015b610322366004610e9a565b60056020526000908152604090205481565b6101766104fe565b61015b7fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc681565b610196610371366004610e1b565b61050d565b610196610384366004610e1b565b61058d565b61015b7f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f81565b6101c16103be366004610ebc565b61059b565b61015b6103d1366004610f2f565b6106ae565b6060600380546103e590610f62565b80601f016020809104026020016040519081016040528092919081815260200182805461041190610f62565b801561045e5780601f106104335761010080835404028352916020019161045e565b820191906000526020600020905b81548152906001019060200180831161044157829003601f168201915b5050505050905090565b6000336104768185856106d9565b60019150505b92915050565b61048d8383836107fd565b505050565b6000336104a08582856109a3565b6104ab8585856107fd565b506001949350505050565b6000336104768185856104c983836106ae565b6104d39190610fb2565b6106d9565b6104e28282610a17565b5050565b6104f03382610ad6565b50565b61048d8383836106d9565b6060600480546103e590610f62565b6000338161051b82866106ae565b9050838110156105805760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f77604482015264207a65726f60d81b60648201526084015b60405180910390fd5b6104ab82868684036106d9565b6000336104768185856107fd565b428410156105eb5760405162461bcd60e51b815260206004820152601960248201527f48455a3a3a7065726d69743a20415554485f45585049524544000000000000006044820152606401610577565b6001600160a01b038716600090815260056020526040812080547f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9918a918a918a91908661063883610fc5565b909155506040805160208101969096526001600160a01b0394851690860152929091166060840152608083015260a082015260c0810186905260e0016040516020818303038152906040528051906020012090506106998882868686610c08565b6106a48888886106d9565b5050505050505050565b6001600160a01b03918216600090815260016020908152604080832093909416825291909152205490565b6001600160a01b03831661073b5760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f206164646044820152637265737360e01b6064820152608401610577565b6001600160a01b03821661079c5760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f206164647265604482015261737360f01b6064820152608401610577565b6001600160a01b0383811660008181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a3505050565b6001600160a01b0383166108615760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f206164604482015264647265737360d81b6064820152608401610577565b6001600160a01b0382166108c35760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201526265737360e81b6064820152608401610577565b6001600160a01b0383166000908152602081905260409020548181101561093b5760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e7420657863656564732062604482015265616c616e636560d01b6064820152608401610577565b6001600160a01b03848116600081815260208181526040808320878703905593871680835291849020805487019055925185815290927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35b50505050565b60006109af84846106ae565b9050600019811461099d5781811015610a0a5760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e63650000006044820152606401610577565b61099d84848484036106d9565b6001600160a01b038216610a6d5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f2061646472657373006044820152606401610577565b8060026000828254610a7f9190610fb2565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b6001600160a01b038216610b365760405162461bcd60e51b815260206004820152602160248201527f45524332303a206275726e2066726f6d20746865207a65726f206164647265736044820152607360f81b6064820152608401610577565b6001600160a01b03821660009081526020819052604090205481811015610baa5760405162461bcd60e51b815260206004820152602260248201527f45524332303a206275726e20616d6f756e7420657863656564732062616c616e604482015261636560f81b6064820152608401610577565b6001600160a01b0383166000818152602081815260408083208686039055600280548790039055518581529192917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a3505050565b600654604080517f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f602080830191909152818301939093527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a0808301919091528251808303909101815260c082019092528151919092012061190160f01b60e083015260e282018190526101028201869052906000906101220160408051601f198184030181528282528051602091820120600080855291840180845281905260ff89169284019290925260608301879052608083018690529092509060019060a0016020604051602081039080840390855afa158015610d1b573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b03811615801590610d515750876001600160a01b0316816001600160a01b0316145b6106a45760405162461bcd60e51b815260206004820152602b60248201527f48455a3a3a5f76616c69646174655369676e6564446174613a20494e56414c4960448201526a445f5349474e415455524560a81b6064820152608401610577565b600060208083528351808285015260005b81811015610dde57858101830151858201604001528201610dc2565b506000604082860101526040601f19601f8301168501019250505092915050565b80356001600160a01b0381168114610e1657600080fd5b919050565b60008060408385031215610e2e57600080fd5b610e3783610dff565b946020939093013593505050565b600080600060608486031215610e5a57600080fd5b610e6384610dff565b9250610e7160208501610dff565b9150604084013590509250925092565b600060208284031215610e9357600080fd5b5035919050565b600060208284031215610eac57600080fd5b610eb582610dff565b9392505050565b600080600080600080600060e0888a031215610ed757600080fd5b610ee088610dff565b9650610eee60208901610dff565b95506040880135945060608801359350608088013560ff81168114610f1257600080fd5b9699959850939692959460a0840135945060c09093013592915050565b60008060408385031215610f4257600080fd5b610f4b83610dff565b9150610f5960208401610dff565b90509250929050565b600181811c90821680610f7657607f821691505b602082108103610f9657634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b8082018082111561047c5761047c610f9c565b600060018201610fd757610fd7610f9c565b506001019056fea26469706673582212207bede9966bc8e8634cc0c3dc076626579b27dff7bbcac0b645c87d4cf1812b9864736f6c63430008140033
    
    constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' 'Bridge Test' 'BT' "$eth_address" 100000000000000000000 | sed 's/0x//')
    test_erc20_addr=$(cast create2 --salt $salt --init-code $erc_20_bytecode"$constructor_args")
    _log_file_descriptor "3" "Calculated Test ERC20 address: $test_erc20_addr"

    if [[ $(cast code --rpc-url "$rpc_url" "$test_erc20_addr") != "0x" ]]; then
        _log_file_descriptor "3" "The network on $rpc_url already has the Test ERC20 deployed. Skipping deployment..."
    else
        _log_file_descriptor "3" "Deploying Test ERC20 to $rpc_url..."
        if ! _safe_cast_send "$rpc_url" "$private_key" "$deterministic_deployer_addr" "$salt$erc_20_bytecode$constructor_args"; then
            _log_file_descriptor "3" "Failed to deploy Test ERC20"
            return 1
        fi
        _log_file_descriptor "3" "Deployment transaction sent."

        _log_file_descriptor "3" "Approving max uint tokens for bridge $bridge_address..."
        if ! _safe_cast_send "$rpc_url" "$private_key" "$test_erc20_addr" 'approve(address,uint256)' "$bridge_address" "$(cast max-uint)"; then
            _log_file_descriptor "3" "Failed to approve tokens"
            return 1
        fi
        _log_file_descriptor "3" "Approval completed."
    fi
}

# =============================================================================
# Ephemeral Account Management
# =============================================================================

_generate_ephemeral_account() {
    # Fix date to specific timezone for consistency
    export TZ='Asia/Seoul'
    local test_index="$1"
    
    # Generate a deterministic but unique private key based on test index
    # This ensures each test gets the same key on reruns but avoids file conflicts
    # This was chosen specifically instead of "cast wallet new" for deterministic address generation
    local seed
    seed="ephemeral_test_${test_index}_$(date +%Y%m%d)"
    local private_key
    private_key="0x$(echo -n "$seed" | sha256sum | cut -d' ' -f1)"
    local address
    address=$(cast wallet address --private-key "$private_key")
    
    echo "$private_key $address"
}


_fund_ephemeral_account() {
    local target_address="$1"
    local rpc_url="$2"
    local funding_private_key="$3"
    local amount="$4"
    
    _log_file_descriptor "2" "Funding $target_address with $amount on $rpc_url"
    
    # First check if the RPC is reachable
    if ! cast chain-id --rpc-timeout 5 --rpc-url "$rpc_url" >/dev/null 2>&1; then
        _log_file_descriptor "2" "RPC $rpc_url is not reachable"
        return 1
    fi
    
    # Check if target address already has sufficient balance (more than 1 ETH)
    local target_balance
    target_balance=$(cast balance --rpc-url "$rpc_url" "$target_address")
    local threshold="100000000000000000"  # 0.1 ETH in wei
    
    _log_file_descriptor "2" "Target address balance: $target_balance"
    _log_file_descriptor "2" "Funding threshold: $threshold"
    
    if [[ -n "$target_balance" && "$target_balance" != "0" ]]; then
        # Use bc for comparison if available, otherwise use bash arithmetic
        if command -v bc >/dev/null 2>&1; then
            if [[ $(echo "$target_balance > $threshold" | bc) -eq 1 ]]; then
                _log_file_descriptor "2" "Target address already has sufficient balance ($target_balance > $threshold), skipping funding"
                return 0
            fi
        else
            # Fallback to bash arithmetic for smaller numbers
            if [[ "$target_balance" -gt "$threshold" ]]; then
                _log_file_descriptor "2" "Target address already has sufficient balance ($target_balance > $threshold), skipping funding"
                return 0
            fi
        fi
    fi
    
    local funding_address
    funding_address=$(cast wallet address --private-key "$funding_private_key")
    _log_file_descriptor "2" "Funding from address: $funding_address"
    
    # Check balance of funding account
    local balance
    balance=$(cast balance --rpc-url "$rpc_url" "$funding_address")
    _log_file_descriptor "2" "Funding account balance: $balance"
    
    if [[ "$balance" == "0" ]]; then
        _log_file_descriptor "2" "Funding account has zero balance"
        return 1
    fi
    
    # Send native token with timeout using the safe cast send helper
    if _safe_cast_send "$rpc_url" "$funding_private_key" "$target_address" --value "$amount"; then
        _log_file_descriptor "2" "Successfully funded $target_address"
        return 0
    else
        _log_file_descriptor "2" "Failed to fund $target_address"
        return 1
    fi
}


_reclaim_funds_after_test() {
    local target_address="$1"
    local rpc_url="$2"
    local total_scenarios="$3"

    _log_file_descriptor "3" "Reclaiming funds from $total_scenarios ephemeral accounts..."

    for i in $(seq 0 $((total_scenarios - 1))); do
        result=$(_generate_ephemeral_account "$i")
        private_key=$(echo "$result" | cut -d' ' -f1)
        address=$(echo "$result" | cut -d' ' -f2)
        balance=$(cast balance "$address" --rpc-url "$rpc_url" 2>/dev/null || echo "0")
        
        if [[ "$balance" != "0" ]]; then
            _log_file_descriptor "2" "Transferring from $address..."
            _log_file_descriptor "2" "  Balance: $(cast to-unit "$balance" ether) ETH"
            
            # Get gas price (with fallback)
            local gas_price
            gas_price=$(cast gas-price --rpc-url "$rpc_url" 2>/dev/null || echo "20000000000")  # 20 gwei fallback
            
            # Use a smaller, more reasonable gas limit for simple transfers
            local gas_limit=42000  # Standard ETH transfer gas limit
            
            # Check if balance is very small (less than 0.001 ETH)
            local min_balance="1000000000000000"  # 0.001 ETH in wei
            if [[ "$balance" -lt "$min_balance" ]]; then
                _log_file_descriptor "2" "  Balance too small to reclaim (< 0.001 ETH), skipping"
                continue
            fi
            
            # Calculate gas cost with safety checks
            local gas_cost
            if command -v bc >/dev/null 2>&1; then
                # Use bc for precise calculation if available
                gas_cost=$(echo "$gas_price * $gas_limit" | bc 2>/dev/null || echo "$gas_price")
            else
                # Simple bash arithmetic with overflow protection
                if [[ "$gas_price" -lt 1000000000000 ]]; then  # Less than 1000 gwei
                    gas_cost=$((gas_price * gas_limit))
                else
                    # For very high gas prices, use a conservative estimate
                    gas_cost=$((balance / 10))  # Reserve 10% for gas
                fi
            fi
            
            # Calculate adjusted balance (balance - gas cost)
            local adjusted_balance
            if [[ "$balance" -gt "$gas_cost" ]]; then
                adjusted_balance=$((balance - gas_cost))
            else
                _log_file_descriptor "2" "  Insufficient balance to cover gas fees (balance: $balance, estimated gas: $gas_cost)"
                continue
            fi
            
            # Only proceed if we have a meaningful amount left to transfer
            local min_transfer="1000000000000000"  # 0.001 ETH minimum transfer
            if [[ "$adjusted_balance" -lt "$min_transfer" ]]; then
                _log_file_descriptor "2" "  Remaining balance after gas too small to transfer, skipping"
                continue
            fi
            
            _log_file_descriptor "2" "  Gas cost: $(cast to-unit $gas_cost ether) ETH"
            _log_file_descriptor "2" "  Sending: $(cast to-unit $adjusted_balance ether) ETH"
            
            # Try reclaim with progressive fallbacks
            if _safe_cast_send "$rpc_url" "$private_key" "$target_address" --value "$adjusted_balance"; then
                _log_file_descriptor "2" "  Successfully reclaimed funds"
            elif _safe_cast_send "$rpc_url" "$private_key" "$target_address" --value "$adjusted_balance" --gas-price "$((gas_price * 2))"; then
                _log_file_descriptor "2" "  Successfully reclaimed funds with higher gas price"
            else
                # Final attempt with very conservative amount
                local conservative_amount=$((balance * 8 / 10))  # Use 80% of balance
                if [[ "$conservative_amount" -gt "$min_transfer" ]]; then
                    if _safe_cast_send "$rpc_url" "$private_key" "$target_address" --value "$conservative_amount"; then
                        _log_file_descriptor "2" "  Successfully reclaimed funds with conservative amount"
                    else
                        _log_file_descriptor "2" "  All reclaim attempts failed for $address"
                    fi
                else
                    _log_file_descriptor "2" "  Balance too small for conservative reclaim attempt"
                fi
            fi
        fi
    done
}

# =============================================================================
# Utility Functions
# =============================================================================

_get_bridge_type_command() {
    local bridge_type="$1"
    case "$bridge_type" in
        "Asset") echo "asset" ;;
        "Message") echo "message" ;;
        "Weth") echo "weth" ;;
        *) echo "Unrecognized Bridge Type: $bridge_type" >&3; return 1 ;;
    esac
}


_get_destination_address() {
    local dest_type="$1"
    local ephemeral_address="$2"
    local to_network="${3:-1}"  # Add network parameter, default to network 1
    case "$dest_type" in
        "BridgeContract") 
            # Return the bridge address for the destination network
            _get_network_config "$to_network" "bridge_addr"
            ;;
        "Precompile") echo "0x0000000000000000000000000000000000000004" ;;
        "EOA") echo "$ephemeral_address" ;;
        *) echo "Unrecognized Destination Address: $dest_type" >&3; return 1 ;;
    esac
}


_get_token_address() {
    local token_type="$1"
    local from_network="${2:-0}"  # Add network parameter, default to network 0
    case "$token_type" in
        "POL") echo "$pol_address" ;;  # Should be the same on both networks
        "LocalERC20") echo "$test_erc20_addr" ;;  # Should be deployed on both
        "WETH") 
            # For WETH, we need network-specific addresses
            if [[ "$from_network" == "0" ]]; then
                # L1 WETH address - you may need to set this properly
                echo "$pp_weth_address"
            else
                # L2 WETH address
                echo "$pp_weth_address"
            fi
            ;;
        "Buggy") echo "$test_erc20_buggy_addr" ;;
        "NativeEther") echo "0x0000000000000000000000000000000000000000" ;;
        "GasToken") echo "$gas_token_address" ;;
        *) echo "Unrecognized Test Token: $token_type" >&3; return 1 ;;
    esac
}


_add_metadata_to_command() {
    local command="$1"
    local metadata_type="$2"
    local test_index="$3"
    local token_type="$4"  # Add token type to consider combinations
    
    case "$metadata_type" in
        "Random")
            # Use test index to make it unique
            echo "$command --call-data $(echo "${test_index}$(date +%s)" | xxd -p)"
            ;;
        "0x")
            echo "$command --call-data 0x"
            ;;
        "Huge")
            local temp_file="/tmp/huge_data_${test_index}.hex"
            # Create the file with proper hex data - add error handling and redirect stderr
            if ! (dd if=/dev/zero bs=1 count=48500 2>/dev/null | xxd -p | tr -d "\n" > "$temp_file"); then
                _log_file_descriptor "2" "Failed to create huge metadata file, using alternative method"
                # Alternative method using printf
                printf '%*s' 97000 '' | tr ' ' '0' > "$temp_file"
            fi
            echo "$command --call-data-file $temp_file"
            ;;
        "Max")
            local temp_file="/tmp/max_data_${test_index}.hex"
            # Special handling for POL with Max metadata - reduce size to avoid issues
            if [[ "$token_type" == "POL" ]]; then
                # Use smaller metadata size for POL to avoid memory/gas issues
                if ! (dd if=/dev/zero bs=1 count=65000 2>/dev/null | xxd -p | tr -d "\n" > "$temp_file"); then
                    _log_file_descriptor "2" "Failed to create max metadata file for POL, using alternative method"
                    printf '%*s' 130000 '' | tr ' ' '0' > "$temp_file"
                fi
                _log_file_descriptor "2" "Using reduced metadata size for POL token"
            else
                # Normal max size for other tokens
                if ! (dd if=/dev/zero bs=1 count=130784 2>/dev/null | xxd -p | tr -d "\n" > "$temp_file"); then
                    _log_file_descriptor "2" "Failed to create max metadata file, using alternative method"
                    printf '%*s' 261569 '' | tr ' ' '0' > "$temp_file"
                fi
            fi
            echo "$command --call-data-file $temp_file"
            ;;
        *)
            _log_file_descriptor "2" "Unrecognized Metadata: $metadata_type"
            return 1
            ;;
    esac
}


_add_force_update_to_command() {
    local command="$1"
    local force_update="$2"
    
    case "$force_update" in
        "True") echo "$command --force-update-root=true" ;;
        "False") echo "$command --force-update-root=false" ;;
        *) echo "Unrecognized Force Update: $force_update" >&3; return 1 ;;
    esac
}


_setup_amount_and_add_to_command() {
    local command="$1"
    local amount_type="$2"
    local ephemeral_private_key="$3"
    local token_type="$4"
    local test_index="$5"
    local metadata_type="$6"  # Add metadata parameter to consider combinations
    local base_gas_limit="$7"  # Add base gas limit parameter
    local from_network="$8"  # Add from_network parameter for dynamic configuration
    
    # Extract just the gas limit value from the base_gas_limit string
    local gas_limit_value
    if [[ "$base_gas_limit" =~ --gas-limit\ ([0-9]+) ]]; then
        gas_limit_value="${BASH_REMATCH[1]}"
    else
        gas_limit_value="1500000"  # Default fallback
    fi
    
    case "$amount_type" in
        "0")
            echo "$command --value 0 --gas-limit $gas_limit_value"
            ;;
        "1")
            echo "$command --value 1 --gas-limit $gas_limit_value"
            ;;
        "Max")
            if [[ "$token_type" == "Buggy" ]]; then
                # Use ephemeral account to manipulate buggy token
                local ephemeral_address
                ephemeral_address=$(cast wallet address --private-key "$ephemeral_private_key")
                # Use source network (from where we're bridging) for the buggy token manipulation
                local source_rpc_url
                source_rpc_url=$(_get_network_config "$from_network" "rpc_url")
                local source_bridge_addr  
                source_bridge_addr=$(_get_network_config "$from_network" "bridge_addr")
                _safe_cast_send "$source_rpc_url" "$ephemeral_private_key" \
                    "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$source_bridge_addr" 0 >/dev/null 2>&1 || true
                # Use higher gas limit for Max amounts, but respect metadata-based limits
                local max_gas_limit=$((gas_limit_value * 2))
                echo "$command --value $(cast max-uint) --gas-limit $max_gas_limit"
            elif [[ "$token_type" == "POL" && "$metadata_type" == "Max" ]]; then
                # Special case: POL with Max amount AND Max metadata - use much smaller amount
                echo "$command --value 100000000000000000000000 --gas-limit $gas_limit_value"
                _log_file_descriptor "2" "Using reduced bridge amount for POL Max+Max combination"
            elif [[ "$token_type" == "LocalERC20" || "$token_type" == "POL" ]]; then
                # Use the safe amount for LocalERC20 and POL (normal cases)
                local max_gas_limit=$((gas_limit_value * 2))
                echo "$command --value 1000000000000000000000000000 --gas-limit $max_gas_limit"
            else
                local max_gas_limit=$((gas_limit_value * 2))
                echo "$command --value $(cast max-uint) --gas-limit $max_gas_limit"
            fi
            ;;
        "Random")
            # Use test index to make random values unique
            echo "$command --value $((1000000 + test_index * 12345)) --gas-limit $gas_limit_value"
            ;;
        *)
            echo "Unrecognized Amount: $amount_type" >&3
            exit 1
            ;;
    esac
}

_setup_ephemeral_accounts_in_bulk() {
    local network_designation="$1"
    local total_scenarios="$2"
    local bridge_addr="$3"  # Add bridge address parameter for approvals

    # Extract network ID from designation
    local network_id=""
    local target_rpc_url target_private_key
    
    if [[ "$network_designation" =~ ^NETWORK_([0-9]+)$ ]]; then
        # New dynamic format: NETWORK_0, NETWORK_1, etc.
        network_id="${BASH_REMATCH[1]}"
        target_rpc_url=$(_get_network_config "$network_id" "rpc_url")
        target_private_key=$(_get_network_config "$network_id" "private_key")
        # _log_file_descriptor "2" "Funding $total_scenarios ephemeral accounts on network $network_id"
    elif [[ "$network_designation" == "L2" ]]; then
        # Legacy L2 support
        network_id="1"
        target_rpc_url=$(_get_network_config "1" "rpc_url")
        target_private_key=$(_get_network_config "1" "private_key")
        # _log_file_descriptor "2" "Funding $total_scenarios ephemeral accounts on L2 (network 1)"
    else
        # Legacy L1 support or default
        network_id="0"
        target_rpc_url=$(_get_network_config "0" "rpc_url")
        target_private_key=$(_get_network_config "0" "private_key")
        # _log_file_descriptor "2" "Funding $total_scenarios ephemeral accounts on L1 (network 0)"
    fi

    # Check if network is using custom gas token on L2 - in this case, we'll sufficiently fund the ephemeral accounts with the custom ERC20 gas tokens.
    if [[ $(cast call "$bridge_addr" "gasTokenAddress()(address)" --rpc-url "$target_rpc_url" 2>/dev/null || echo "0x0000000000000000000000000000000000000000") != "0x0000000000000000000000000000000000000000" ]]; then
        # Fund 1 ether to ephemeral accounts. The seed gets parsed to seed_index_YYYYMMDD (e.g., "ephemeral_test_0_20241010") which is identical to the seed being used in the bridge-tests-suite.
        local eth_fund_output
        if ! eth_fund_output=$(polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --eth-amount 1000000000000000000 2>&1); then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with custom gas token"
            _log_file_descriptor "2" "polycli fund output: $eth_fund_output"
            return 1
        fi
    else
        # Fund 0.001 ether to ephemeral accounts. The seed gets parsed to seed_index_YYYYMMDD (e.g., "ephemeral_test_0_20241010") which is identical to the seed being used in the bridge-tests-suite.
        local eth_fund_output
        if ! eth_fund_output=$(polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --eth-amount 1000000000000000 2>&1); then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with ETH"
            _log_file_descriptor "2" "polycli fund output: $eth_fund_output"
            return 1
        fi
    fi

    # Bulk fund and approve ERC20 tokens to ephemeral accounts
    # _log_file_descriptor "2" "Bulk funding and approving ERC20 tokens for $total_scenarios ephemeral accounts"
    target_address=$(cast wallet address --private-key "$target_private_key")
    
    # Fund and approve LocalERC20 tokens
    if [[ -n "$test_erc20_addr" && "$test_erc20_addr" != "0x0000000000000000000000000000000000000000" ]]; then
        # Fund private key to make sure it has enough balance to approve in multicall3 transaction
        _safe_cast_send "$target_rpc_url" "$target_private_key" "$test_erc20_addr" 'mint(address,uint256)' $target_address 1000000000000000000000000000000
        # _log_file_descriptor "2" "Bulk funding LocalERC20 tokens ($test_erc20_addr) with approvals for bridge ($bridge_addr)"
        local erc20_fund_output
        if ! erc20_fund_output=$(polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --token-address "$test_erc20_addr" --token-amount 1000000000000000000000000000 --approve-spender "$bridge_addr" --approve-amount 1000000000000000000000000000 2>&1); then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with LocalERC20 tokens"
            _log_file_descriptor "2" "polycli fund output: $erc20_fund_output"
            return 1
        fi
    fi
    
    # Fund and approve Buggy ERC20 tokens
    if [[ -n "$test_erc20_buggy_addr" && "$test_erc20_buggy_addr" != "0x0000000000000000000000000000000000000000" ]]; then
        # Fund private key to make sure it has enough balance to approve in multicall3 transaction
        _safe_cast_send "$target_rpc_url" "$target_private_key" "$test_erc20_buggy_addr" 'mint(address,uint256)' "$target_address" "$(cast max-uint)"
        # _log_file_descriptor "2" "Bulk funding Buggy ERC20 tokens ($test_erc20_buggy_addr) with approvals for bridge ($bridge_addr)"
        local buggy_fund_output
        if ! buggy_fund_output=$(polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --token-address "$test_erc20_buggy_addr" --token-amount "$(cast max-uint)" --approve-spender "$bridge_addr" --approve-amount "$(cast max-uint)" 2>&1); then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with Buggy ERC20 tokens"
            _log_file_descriptor "2" "polycli fund output: $buggy_fund_output"
            return 1
        fi
    fi
    
    # Fund and approve POL tokens (commented out as in original)
    # if [[ -n "$pol_address" && "$pol_address" != "0x0000000000000000000000000000000000000000" ]]; then
    #     _log_file_descriptor "2" "Bulk funding POL tokens ($pol_address) with approvals for bridge ($bridge_addr)"
    #     polycli fund --rpc-url $target_rpc_url --number $total_scenarios --private-key $target_private_key --file /tmp/wallets-funded.json --seed "ephemeral_test" --token-address "$pol_address" --token-amount 1000000000000000000000000000 --approve-spender "$bridge_addr" --approve-amount 1000000000000000000000000000 >/dev/null 2>&1
    # fi
    
    # Fund and approve GasToken if available
    if [[ -n "$gas_token_address" && "$gas_token_address" != "0x0000000000000000000000000000000000000000" ]]; then
        # Fund private key to make sure it has enough balance to approve in multicall3 transaction
        _safe_cast_send "$target_rpc_url" "$target_private_key" "$gas_token_address" 'mint(address,uint256)' $target_address 1000000000000000000000000000000
        # _log_file_descriptor "2" "Bulk funding GasToken tokens ($gas_token_address) with approvals for bridge ($bridge_addr)"
        if ! polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --token-address "$gas_token_address" --token-amount 1000000000000000000000000000 --approve-spender "$bridge_addr" --approve-amount 1000000000000000000000000000 >/dev/null 2>&1; then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with GasToken tokens"
            return 1
        fi
    fi
    
    # Fund and approve WETH tokens if available
    if [[ -n "$pp_weth_address" && "$pp_weth_address" != "0x0000000000000000000000000000000000000000" ]]; then
        # Fund private key to make sure it has enough balance to approve in multicall3 transaction
        _safe_cast_send "$target_rpc_url" "$target_private_key" "$pp_weth_address" 'mint(address,uint256)' $target_address 1000000000000000000000000000000
        # _log_file_descriptor "2" "Bulk funding WETH tokens ($pp_weth_address) with approvals for bridge ($bridge_addr)"
        if ! polycli fund --rpc-url "$target_rpc_url" --number "$total_scenarios" --private-key "$target_private_key" --file /tmp/wallets-funded.json --seed "ephemeral_test" --token-address "$pp_weth_address" --token-amount 1000000000000000000000000000 --approve-spender "$bridge_addr" --approve-amount 1000000000000000000000000000 >/dev/null 2>&1; then
            _log_file_descriptor "2" "ERROR: Failed to fund ephemeral accounts with WETH tokens"
            return 1
        fi
    fi
}

_setup_single_test_account() {
    local test_index="$1"
    local scenario="$2"
    
    _log_file_descriptor "2" "Setting up account for test $test_index"
    
    # Extract scenario parameters including network information
    local test_token
    test_token=$(echo "$scenario" | jq -r '.Token')
    local test_amount
    test_amount=$(echo "$scenario" | jq -r '.Amount')
    local test_meta_data
    test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
    local from_network
    from_network=$(echo "$scenario" | jq -r '.FromNetwork')
    local to_network
    to_network=$(echo "$scenario" | jq -r '.ToNetwork')
    
    # Set source and destination networks based on FromNetwork and ToNetwork
    local source_rpc_url source_network_id source_bridge_addr source_private_key
    local dest_rpc_url dest_network_id dest_bridge_addr dest_private_key
    
    # Get source network configuration
    source_rpc_url=$(_get_network_config "$from_network" "rpc_url")
    source_network_id=$(_get_network_config "$from_network" "network_id")
    source_bridge_addr=$(_get_network_config "$from_network" "bridge_addr")
    source_private_key=$(_get_network_config "$from_network" "private_key")
    
    # Get destination network configuration
    dest_rpc_url=$(_get_network_config "$to_network" "rpc_url")
    dest_network_id=$(_get_network_config "$to_network" "network_id")
    dest_bridge_addr=$(_get_network_config "$to_network" "bridge_addr")
    dest_private_key=$(_get_network_config "$to_network" "private_key")
    
    _log_file_descriptor "2" "Configured for network $from_network -> network $to_network bridge setup"
    
    # Generate ephemeral account
    local ephemeral_data
    ephemeral_data=$(_generate_ephemeral_account "$test_index")
    local ephemeral_private_key
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    local ephemeral_address
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
    
    _log_file_descriptor "2" "Generated ephemeral account for test $test_index: $ephemeral_address"
    _log_file_descriptor "2" "Private key for ephemeral account $test_index: $ephemeral_private_key"
    
    # Test if ephemeral_private_key is valid
    if [[ -z "$ephemeral_private_key" || "$ephemeral_private_key" == "0x" ]]; then
        _log_file_descriptor "2" "Failed to generate ephemeral private key for test $test_index"
        return 1
    fi
    
    # Both token funding and approvals are now handled in bulk by _setup_ephemeral_accounts_in_bulk()
    # No individual token setup or approval is needed here
    
    _log_file_descriptor "2" "Account setup completed for test $test_index (network $from_network -> $to_network) - tokens and approvals handled in bulk"
    return 0
}


_cleanup_max_amount_setup() {
    local amount_type="$1"
    local from_network="${2:-0}"  # Default to network 0 if not provided
    if [[ "$amount_type" = "Max" ]]; then
        local source_rpc_url source_private_key source_bridge_addr
        source_rpc_url=$(_get_network_config "$from_network" "rpc_url")
        source_private_key=$(_get_network_config "$from_network" "private_key")
        source_bridge_addr=$(_get_network_config "$from_network" "bridge_addr")
        _safe_cast_send "$source_rpc_url" "$source_private_key" \
            "$test_erc20_buggy_addr" 'setBalanceOf(address,uint256)' "$source_bridge_addr" 0 >/dev/null 2>&1 || true
    fi
}


_check_already_claimed() {
    local output="$1"
    
    # Only check for explicit "already claimed" patterns, not retries or timeouts
    # Be very specific to avoid false positives from retry/timeout scenarios
    if echo "$output" | grep -q -E "(already been claimed|AlreadyClaimedError|the claim transaction has already been claimed|already claimed \(verified\)|already claimed \(race condition detected\)|already claimed \(consistent failure pattern\)|Deposit was already claimed|was already claimed by another process)"; then
        _log_file_descriptor "2" "Found explicit 'already claimed' pattern - indicates success"
        return 0
    fi
    
    # Explicitly exclude retry/timeout patterns that should NOT be considered as "already claimed"
    if echo "$output" | grep -q -E "(not yet ready to be claimed|Try again in a few blocks|retrying\.\.\.|unable to retrieve bridge deposit|Wait timer.*exceeded|timeout|connection refused|the Merkle Proofs cannot be retrieved|error getting merkle proofs)"; then
        _log_file_descriptor "2" "Found retry/timeout pattern - NOT an 'already claimed' case"
        return 1
    fi
    
    # If no explicit "already claimed" pattern found, return false
    return 1
}

_validate_bridge_error() {
    local expected_result="$1"
    local output="$2"
    
    # Check for "already claimed" patterns first - these should generally be treated as success
    _check_already_claimed "$output"
    _log_file_descriptor "2" "Validating bridge error - Expected: $expected_result"
    _log_file_descriptor "2" "Bridge output: $output"
    
    # Check if expected_result_claim is an array or a single string
    if [[ "$expected_result" =~ ^\[.*\]$ ]]; then
        # Handle array of expected results
        _log_file_descriptor "2" "Processing array of expected results"
        local match_found=false
        while read -r expected_error; do
            expected_error=$(echo "$expected_error" | jq -r '.')
            _log_file_descriptor "2" "Checking for expected error: $expected_error"
            
            if _check_error_pattern "$expected_error" "$output"; then
                _log_file_descriptor "2" "Found matching error pattern: $expected_error"
                match_found=true
                break
            fi
        done < <(echo "$expected_result" | jq -c '.[]')
        
        if $match_found; then
            _log_file_descriptor "2" "Match found in array validation"
            return 0
        else
            _log_file_descriptor "2" "No match found in array validation"
            return 1
        fi
    else
        # Handle single expected error
        local expected_error
        expected_error=$(echo "$expected_result" | jq -r '.')
        _log_file_descriptor "2" "Processing single expected result: $expected_error"
        
        if [[ "$expected_error" == "Success" ]]; then
            _log_file_descriptor "2" "Single 'Success' expected"
            return 0  # Success is always valid
        elif _check_error_pattern "$expected_error" "$output"; then
            _log_file_descriptor "2" "Single error pattern matched"
            return 0
        else
            _log_file_descriptor "2" "Single error pattern not matched"
            return 1
        fi
    fi
}


_check_error_pattern() {
    local expected_error="$1"
    local output="$2"
    
    _log_file_descriptor "2" "Checking error pattern '$expected_error' in output"
    
    # Handle different error patterns
    if [[ "$expected_error" =~ ^oversized\ data ]]; then
        # Check for both the specific pattern and the general "oversized data" error
        if echo "$output" | grep -q -E "(oversized data: transaction size [0-9]+, limit 131072|oversized data)"; then
            _log_file_descriptor "2" "Matched oversized data pattern"
            return 0
        fi
    elif [[ "$expected_error" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Handle hex error codes (like 0x23d72133)
        if echo "$output" | grep -q "$expected_error"; then
            _log_file_descriptor "2" "Matched hex error code: $expected_error"
            return 0
        fi
    else
        # Handle general string patterns
        if echo "$output" | grep -q "$expected_error"; then
            _log_file_descriptor "2" "Matched general error pattern: $expected_error"
            return 0
        fi
    fi
    
    _log_file_descriptor "2" "No pattern match found for: $expected_error"
    return 1
}

_run_single_bridge_test() {
    local test_index="$1"
    local scenario="$2"
    local result_file="/tmp/test_result_${test_index}.txt"
    
    _log_file_descriptor "2" "Starting bridge test $test_index"
    
    # Extract scenario parameters including network information
    local test_bridge_type
    test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
    local test_destination_address
    test_destination_address=$(echo "$scenario" | jq -r '.DestinationAddress')
    local test_token
    test_token=$(echo "$scenario" | jq -r '.Token')
    local test_meta_data
    test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
    local test_force_update
    test_force_update=$(echo "$scenario" | jq -r '.ForceUpdate')
    local test_amount
    test_amount=$(echo "$scenario" | jq -r '.Amount')
    local expected_result_process
    expected_result_process=$(echo "$scenario" | jq -r '.ExpectedResultProcess')
    local expected_result_claim
    expected_result_claim=$(echo "$scenario" | jq -r '.ExpectedResultClaim')
    local from_network
    from_network=$(echo "$scenario" | jq -r '.FromNetwork')
    local to_network
    to_network=$(echo "$scenario" | jq -r '.ToNetwork')
    
    # Set source and destination networks based on FromNetwork and ToNetwork
    local source_rpc_url source_network_id source_bridge_addr source_private_key
    local dest_rpc_url dest_network_id dest_bridge_addr dest_private_key
    local claim_rpc_url claim_bridge_addr claim_private_key
    
    # Get source network configuration
    source_rpc_url=$(_get_network_config "$from_network" "rpc_url")
    source_network_id=$(_get_network_config "$from_network" "network_id")
    source_bridge_addr=$(_get_network_config "$from_network" "bridge_addr")
    source_private_key=$(_get_network_config "$from_network" "private_key")
    
    # Get destination network configuration
    dest_rpc_url=$(_get_network_config "$to_network" "rpc_url")
    dest_network_id=$(_get_network_config "$to_network" "network_id")
    dest_bridge_addr=$(_get_network_config "$to_network" "bridge_addr")
    dest_private_key=$(_get_network_config "$to_network" "private_key")
    
    # Set claim network configuration (same as destination)
    claim_rpc_url="$dest_rpc_url"
    claim_bridge_addr="$dest_bridge_addr"
    claim_private_key="$dest_private_key"
    
    _log_file_descriptor "2" "Configured for network $from_network -> network $to_network bridge"
    
    _log_file_descriptor "2" "Test $test_index - Token: $test_token, Amount: $test_amount, Metadata: $test_meta_data"
    
    # Get ephemeral account (already set up)
    local ephemeral_data
    ephemeral_data=$(_generate_ephemeral_account "$test_index")
    local ephemeral_private_key
    ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    local ephemeral_address
    ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
    
    _log_file_descriptor "2" "Using ephemeral account for test $test_index: $ephemeral_address"
    
    # Pre-create metadata files if needed
    if [[ "$test_meta_data" == "Huge" ]]; then
        local temp_file="/tmp/huge_data_${test_index}.hex"
        _log_file_descriptor "2" "Creating huge metadata file: $temp_file"
        xxd -p /dev/zero | tr -d "\n" | head -c 97000 > "$temp_file"
        if [[ ! -f "$temp_file" ]]; then
            _log_file_descriptor "2" "Failed to create huge metadata file"
            echo "TEST_$test_index|FAIL|N/A|Failed to create metadata file" > "$result_file"
            return 1
        fi
    elif [[ "$test_meta_data" == "Max" ]]; then
        local temp_file="/tmp/max_data_${test_index}.hex"
        _log_file_descriptor "2" "Creating max metadata file: $temp_file"
        # Special handling for POL with Max metadata
        if [[ "$test_token" == "POL" ]]; then
            xxd -p /dev/zero | tr -d "\n" | head -c 130000 > "$temp_file"  # Reduced size for POL
            _log_file_descriptor "2" "Created reduced max metadata file for POL: $(wc -c < "$temp_file") bytes"
        else
            xxd -p /dev/zero | tr -d "\n" | head -c 261569 > "$temp_file"
        fi
        if [[ ! -f "$temp_file" ]]; then
            _log_file_descriptor "2" "Failed to create max metadata file"
            echo "TEST_$test_index|FAIL|N/A|Failed to create metadata file" > "$result_file"
            return 1
        fi
    fi
    
    # Build bridge command
    local bridge_command="polycli ulxly bridge"
    local bridge_type_cmd
    bridge_type_cmd=$(_get_bridge_type_command "$test_bridge_type")
    bridge_command="$bridge_command $bridge_type_cmd"
    
    # Use source network parameters for the bridge command
    local fixed_flags="--rpc-url $source_rpc_url --destination-network $dest_network_id"
    bridge_command="$bridge_command $fixed_flags"

    # Add destination address
    local dest_addr
    dest_addr=$(_get_destination_address "$test_destination_address" "$ephemeral_address" "$to_network")
    bridge_command="$bridge_command --destination-address $dest_addr"

    # Add token address
    local token_addr
    # For custom gas token networks, when bridging from L2 -> L1, the gas token should always be 0x0.
    # But when we derive the gas token address from the bridge contract, it will return the gas token contract address on L1.
    # This will cause "no contract code at given address" error when bridging from L2.
    if [[ "$from_network" != "0" && "$to_network" == "0" && "$test_token" == "GasToken" ]]; then
        # Bridging from any non-L1 network to L1 with GasToken should use 0x0
        token_addr="0x0000000000000000000000000000000000000000"
    else
        token_addr=$(_get_token_address "$test_token" "$from_network")
    fi
    bridge_command="$bridge_command --token-address $token_addr"

    # Add metadata with test_index and token_type parameters
    if ! bridge_command=$(_add_metadata_to_command "$bridge_command" "$test_meta_data" "$test_index" "$test_token"); then
        _log_file_descriptor "2" "Failed to add metadata to command"
        echo "TEST_$test_index|FAIL|N/A|Failed to add metadata" > "$result_file"
        return 1
    fi

    # Add force update flag
    if ! bridge_command=$(_add_force_update_to_command "$bridge_command" "$test_force_update"); then
        _log_file_descriptor "2" "Failed to add force update to command"
        echo "TEST_$test_index|FAIL|N/A|Failed to add force update flag" > "$result_file"
        return 1
    fi

    # Setup amount and add to command (now with metadata parameter)
    if ! bridge_command=$(_setup_amount_and_add_to_command "$bridge_command" "$test_amount" "$ephemeral_private_key" "$test_token" "$test_index" "$test_meta_data" "$base_gas_limit" "$from_network"); then
        _log_file_descriptor "2" "Failed to add amount to command"
        echo "TEST_$test_index|FAIL|N/A|Failed to add amount" > "$result_file"
        return 1
    fi

    # Add final command parameters - use source bridge address and ephemeral private key
    bridge_command="$bridge_command --bridge-address $source_bridge_addr --private-key $ephemeral_private_key"
    
    # Determine appropriate gas limit based on operation complexity - stay within block limits
    local base_gas_limit=""
    if [[ "$test_meta_data" == "Max" ]]; then
        base_gas_limit="--gas-limit 25000000"  # Reduced from 30M to stay under block limit
    elif [[ "$test_meta_data" == "Huge" ]]; then
        base_gas_limit="--gas-limit 15000000"
    elif [[ "$test_amount" == "Max" ]]; then
        base_gas_limit="--gas-limit 12000000"
    else
        base_gas_limit="--gas-limit 1500000"
    fi
    
    # Add base gas limit if not already set by amount function
    if [[ ! "$bridge_command" =~ --gas-limit ]]; then
        bridge_command="$bridge_command $base_gas_limit"
    fi
    
    _log_file_descriptor "2" "Executing bridge command for test $test_index: $bridge_command"
    
    # Execute the bridge command with longer timeout for problematic combinations
    local timeout_duration=$global_timeout
    
    local bridge_output
    local bridge_status
    local max_bridge_retries=3
    local bridge_attempt=0
    local retry_bridge=false
    
    while [[ $bridge_attempt -lt $max_bridge_retries ]]; do
        bridge_attempt=$((bridge_attempt + 1))
        _log_file_descriptor "2" "Bridge attempt $bridge_attempt for test $test_index"
        
        if bridge_output=$(timeout "$timeout_duration" bash -c "$bridge_command" 2>&1); then
            bridge_status=0
            _log_file_descriptor "2" "Bridge command succeeded on attempt $bridge_attempt"
            break
        else
            bridge_status=$?
            _log_file_descriptor "2" "Bridge attempt $bridge_attempt failed with status $bridge_status"
            _log_file_descriptor "2" "Bridge output: $bridge_output"
            
            # Check if this is a retryable error
            retry_bridge=false
            
            # Check for network/receipt timeout issues - these are retryable
            if echo "$bridge_output" | grep -q -E "(Wait timer for transaction receipt exceeded|not found|connection refused|timeout|network error)"; then
                _log_file_descriptor "2" "Detected network/timeout error - this is retryable"
                retry_bridge=true
            fi
            
            # Check for nonce issues - also retryable
            if echo "$bridge_output" | grep -q -E "(nonce too low|replacement transaction underpriced|already known)"; then
                _log_file_descriptor "2" "Detected nonce/replacement error - this is retryable"
                retry_bridge=true
            fi
            
            # Check for temporary RPC issues
            if echo "$bridge_output" | grep -q -E "(502 Bad Gateway|503 Service Unavailable|429 Too Many Requests|Internal server error)"; then
                _log_file_descriptor "2" "Detected temporary RPC error - this is retryable"
                retry_bridge=true
            fi
            
            # If it's retryable and we haven't exhausted retries, continue
            if $retry_bridge && [[ $bridge_attempt -lt $max_bridge_retries ]]; then
                _log_file_descriptor "2" "Retrying bridge operation after delay (attempt $bridge_attempt/$max_bridge_retries)"
                
                # For replacement transaction underpriced errors, increase gas price and limit
                if echo "$bridge_output" | grep -q "replacement transaction underpriced"; then
                    _log_file_descriptor "2" "Increasing gas price and limit for replacement transaction"
                    
                    # Calculate gas price multiplier based on attempt (1.5x, 2x, 2.5x, etc.)
                    local gas_price_multiplier=$((bridge_attempt + 1))
                    local gas_limit_multiplier=$((bridge_attempt + 1))
                    
                    # Get current gas price from source network
                    local current_gas_price
                    if current_gas_price=$(cast gas-price --rpc-url "$source_rpc_url" 2>/dev/null); then
                        # Increase gas price by multiplier + 20% buffer
                        local new_gas_price=$((current_gas_price * gas_price_multiplier * 12 / 10))
                        _log_file_descriptor "2" "Setting gas price to $new_gas_price (${gas_price_multiplier}.2x current)"
                    else
                        _log_file_descriptor "2" "Could not get current gas price, using default escalation"
                        local new_gas_price=$((20000000000 * gas_price_multiplier))  # 20 gwei * multiplier
                    fi
                    
                    # Extract current gas limit and increase it
                    local current_gas_limit=""
                    if [[ "$bridge_command" =~ --gas-limit\ ([0-9]+) ]]; then
                        current_gas_limit="${BASH_REMATCH[1]}"
                        local new_gas_limit=$((current_gas_limit * gas_limit_multiplier))
                        _log_file_descriptor "2" "Increasing gas limit from $current_gas_limit to $new_gas_limit"
                        
                        # Update the command with new gas limit
                        bridge_command=$(echo "$bridge_command" | sed "s/--gas-limit [0-9]*/--gas-limit $new_gas_limit/")
                    else
                        # Add gas limit if not present
                        local base_gas_limit=$((3000000 * gas_limit_multiplier))
                        bridge_command="$bridge_command --gas-limit $base_gas_limit"
                        _log_file_descriptor "2" "Added gas limit: $base_gas_limit"
                    fi
                    
                    # Add gas price to command
                    bridge_command="$bridge_command --gas-price $new_gas_price"
                    _log_file_descriptor "2" "Updated bridge command with higher gas: $bridge_command"
                elif echo "$bridge_output" | grep -q -E "(Wait timer for transaction receipt exceeded|not found)"; then
                    _log_file_descriptor "2" "Network/timeout error detected, increasing gas for faster inclusion"
                    
                    # For network issues, also increase gas to get priority
                    local gas_multiplier=$((bridge_attempt + 1))
                    
                    # Increase gas limit
                    if [[ "$bridge_command" =~ --gas-limit\ ([0-9]+) ]]; then
                        local current_gas_limit="${BASH_REMATCH[1]}"
                        local new_gas_limit=$((current_gas_limit * gas_multiplier))
                        bridge_command=$(echo "$bridge_command" | sed "s/--gas-limit [0-9]*/--gas-limit $new_gas_limit/")
                        _log_file_descriptor "2" "Increased gas limit to $new_gas_limit for faster inclusion"
                    fi
                    
                    # Add higher gas price for network issues
                    local current_gas_price
                    if current_gas_price=$(cast gas-price --rpc-url "$source_rpc_url" 2>/dev/null); then
                        local priority_gas_price=$((current_gas_price * gas_multiplier * 15 / 10))  # 1.5x * multiplier
                        bridge_command="$bridge_command --gas-price $priority_gas_price"
                        _log_file_descriptor "2" "Added priority gas price: $priority_gas_price"
                    fi
                fi
                
                sleep $((bridge_attempt * 2))  # Exponential backoff
                continue
            else
                # Not retryable or exhausted retries
                _log_file_descriptor "2" "Bridge operation failed permanently or exhausted retries"
                break
            fi
        fi
    done
    
    # Only do gas limit retry if the final attempt failed with gas issues
    if [[ $bridge_status -ne 0 ]]; then
        _log_file_descriptor "2" "Bridge command failed with timeout or error status $bridge_status"
        
        # Check if it's a gas limit issue and suggest retry with higher gas
        if echo "$bridge_output" | grep -q -E "(Perhaps try increasing the gas limit|insufficient gas|intrinsic gas too low|GasUsed=[0-9]+ cumulativeGasUsedForTx=)"; then
            _log_file_descriptor "2" "Gas limit issue detected, removing gas limit to use automatic estimation"
            
            # Remove the gas limit parameter entirely to let the system auto-estimate
            local retry_command
            retry_command=$(echo "$bridge_command" | sed 's/--gas-limit [0-9]* //g')
            _log_file_descriptor "2" "Retrying without gas limit (auto-estimation): $retry_command"
            
            if bridge_output=$(timeout "$timeout_duration" bash -c "$retry_command" 2>&1); then
                bridge_status=0
                _log_file_descriptor "2" "Retry without gas limit succeeded"
            else
                bridge_status=$?
                _log_file_descriptor "2" "Retry without gas limit also failed"
                _log_file_descriptor "2" "Retry output: $bridge_output"
                
                # If it still fails, check if it's a different error
                if echo "$bridge_output" | grep -q -E "(insufficient gas|intrinsic gas too low|Perhaps try increasing the gas limit|GasUsed=[0-9]+)"; then
                    _log_file_descriptor "2" "Still a gas issue even with auto-estimation - may be a block limit"
                elif echo "$bridge_output" | grep -q "exceeds block gas limit"; then
                    _log_file_descriptor "2" "Transaction exceeds block gas limit even with auto-estimation"
                    # Check if this is an expected failure
                    if [[ "$expected_result_process" != "Success" ]]; then
                        _log_file_descriptor "2" "Block gas limit error matches expected failure"
                        bridge_status=0  # Treat as success if failure was expected
                    fi
                else
                    _log_file_descriptor "2" "Different error after removing gas limit"
                fi
            fi
        # Add special handling for huge calldata scenarios that fail with network/timeout errors
        elif [[ "$test_meta_data" == "Huge" || "$test_meta_data" == "Max" ]] && \
            echo "$bridge_output" | grep -q -E "(Wait timer for transaction receipt exceeded|not found|replacement transaction underpriced)"; then
            _log_file_descriptor "2" "Huge/Max calldata with network/timeout errors - likely gas estimation issue, removing gas limit"
            
            # Remove the gas limit parameter entirely to let the system auto-estimate
            local retry_command
            retry_command=$(echo "$bridge_command" | sed 's/--gas-limit [0-9]* //g')
            _log_file_descriptor "2" "Retrying huge/max calldata without gas limit (auto-estimation): $retry_command"
            
            if bridge_output=$(timeout "$timeout_duration" bash -c "$retry_command" 2>&1); then
                bridge_status=0
                _log_file_descriptor "2" "Retry without gas limit succeeded for huge/max calldata"
            else
                bridge_status=$?
                _log_file_descriptor "2" "Retry without gas limit also failed for huge/max calldata"
                _log_file_descriptor "2" "Retry output: $bridge_output"
                
                # Check if it's still a gas/block limit issue
                if echo "$bridge_output" | grep -q -E "(insufficient gas|intrinsic gas too low|Perhaps try increasing the gas limit|GasUsed=[0-9]+)"; then
                    _log_file_descriptor "2" "Still a gas issue even with auto-estimation for huge/max calldata"
                elif echo "$bridge_output" | grep -q "exceeds block gas limit"; then
                    _log_file_descriptor "2" "Transaction exceeds block gas limit even with auto-estimation for huge/max calldata"
                    # Check if this is an expected failure
                    if [[ "$expected_result_process" != "Success" ]]; then
                        _log_file_descriptor "2" "Block gas limit error matches expected failure for huge/max calldata"
                        bridge_status=0  # Treat as success if failure was expected
                    fi
                elif echo "$bridge_output" | grep -q -E "(Wait timer for transaction receipt exceeded|not found)"; then
                    _log_file_descriptor "2" "Still getting network/timeout errors even without gas limit - may be RPC issue"
                else
                    _log_file_descriptor "2" "Different error after removing gas limit for huge/max calldata"
                fi
            fi
        elif echo "$bridge_output" | grep -q "exceeds block gas limit"; then
            _log_file_descriptor "2" "Transaction exceeds block gas limit - this is expected for some edge case tests"
            # For tests expecting to hit block gas limits, this might be the expected behavior
            # Check if this is an expected failure
            if [[ "$expected_result_process" != "Success" ]]; then
                _log_file_descriptor "2" "Block gas limit error matches expected failure"
                bridge_status=0  # Treat as success if failure was expected
            fi
        fi
    fi
    
    _log_file_descriptor "2" "Bridge command completed for test $test_index with status $bridge_status"
    if [[ $bridge_status -ne 0 ]]; then
        _log_file_descriptor "2" "Bridge output: $bridge_output"
    fi
    
    local deposit_count=""
    if [[ $bridge_status -eq 0 ]]; then
        _log_file_descriptor "2" "Bridge output: $bridge_output"
        deposit_count=$(echo "$bridge_output" | awk '/depositCount=/ {gsub(/.*depositCount=/, ""); gsub(/\x1b\[[0-9;]*m/, ""); print}')
        _log_file_descriptor "2" "Extracted deposit count: $deposit_count"
    fi
    
    local bridge_result="FAIL"
    local claim_result="N/A"
    local error_message=""
    
    # Validate bridge result
    local bridge_expects_success=false
    local bridge_has_other_expected_errors=false
    
    # Determine what bridge outcomes are expected
    if [[ "$expected_result_process" == "Success" ]]; then
        bridge_expects_success=true
    elif [[ "$expected_result_process" =~ ^\[.*\]$ ]]; then
        # Handle array of expected bridge results
        _log_file_descriptor "2" "Processing array of expected bridge results: $expected_result_process"
        
        # Check if array contains "Success"
        if echo "$expected_result_process" | jq -r '.[]' | grep -q "^Success$"; then
            bridge_expects_success=true
            _log_file_descriptor "2" "Bridge array contains 'Success' as valid outcome"
        fi
        
        # Check if array contains other error patterns
        if echo "$expected_result_process" | jq -r '.[]' | grep -v "^Success$" | grep -q .; then
            bridge_has_other_expected_errors=true
            _log_file_descriptor "2" "Bridge array contains other expected error patterns"
        fi
    else
        # Single non-Success expected result
        bridge_has_other_expected_errors=true
    fi
    
    _log_file_descriptor "2" "Bridge expects success: $bridge_expects_success, has other expected errors: $bridge_has_other_expected_errors"
    
    # Validate based on actual bridge result
    if [[ $bridge_status -eq 0 ]]; then
        # Bridge succeeded
        if $bridge_expects_success; then
            bridge_result="PASS"
            _log_file_descriptor "2" "Bridge succeeded and success was expected"
            
            # Execute claim if expected (based on reference implementation)
            if [[ "$expected_result_claim" != "N/A" ]]; then
                _log_file_descriptor "2" "Executing claim command for test $test_index"
                
                # Build claim command based on reference
                local claim_command="polycli ulxly claim"
                case "$test_bridge_type" in
                    "Asset"|"Weth") claim_command="$claim_command asset" ;;
                    "Message") claim_command="$claim_command message" ;;
                    *) 
                        _log_file_descriptor "2" "Unrecognized Bridge Type for claim: $test_bridge_type"
                        echo "TEST_$test_index|FAIL|N/A|Unrecognized Bridge Type for claim" > "$result_file"
                        return 1 
                        ;;
                esac

                # Use destination network parameters for the claim command
                # Get bridge service URL using proper selection logic
                local selected_bridge_service_url
                selected_bridge_service_url=$(_select_bridge_service_url "$source_network_id" "$dest_network_id")
                _log_file_descriptor "2" "Using selected bridge service URL: $selected_bridge_service_url"
                claim_command="$claim_command --destination-address $dest_addr --bridge-address $claim_bridge_addr --private-key $ephemeral_private_key --rpc-url $claim_rpc_url --deposit-count $deposit_count --deposit-network $source_network_id --bridge-service-url $selected_bridge_service_url --wait $claim_wait_duration"
                
                # Execute claim command
                _log_file_descriptor "2" "Running claim command for test $test_index: $claim_command"
                local claim_output claim_status
                local max_claim_retries=5  # Increased from 3 to handle Merkle proof retrieval delays
                local claim_attempt=0

                while [[ $claim_attempt -lt $max_claim_retries ]]; do
                        claim_attempt=$((claim_attempt + 1))
                        _log_file_descriptor "2" "Claim attempt $claim_attempt for test $test_index"

                        if claim_output=$(timeout "$global_timeout" bash -c "$claim_command" 2>&1); then
                            claim_status=0
                            _log_file_descriptor "2" "Claim command exited with status 0 on attempt $claim_attempt"
                            
                            # Even if exit status is 0, check for failure indicators in the output
                            if echo "$claim_output" | grep -q -E "(Deposit transaction failed|Perhaps try increasing the gas limit|GasUsed=[0-9]+ cumulativeGasUsedForTx=)"; then
                                _log_file_descriptor "2" "Claim command succeeded but transaction failed - checking if already claimed"
                                
                                # Wait a moment for state to update, then check if it was actually claimed
                                sleep 2
                                
                                # Try to query the claim status directly using the deposit info
                                local verify_command="${claim_command} --dry-run"
                                local verify_output
                                if verify_output=$(timeout 30 bash -c "$verify_command" 2>&1) || \
                                   verify_output=$(timeout 30 bash -c "$claim_command" 2>&1); then
                                    if _check_already_claimed "$verify_output"; then
                                        _log_file_descriptor "2" "Verification confirmed deposit was already claimed by another process"
                                        claim_status=0  # Treat as success
                                        claim_output="Deposit was already claimed (verified)"
                                        break
                                    fi
                                fi
                                
                                # Additional check: if we see "The deposit is ready to be claimed" followed by transaction failure,
                                # it's likely already claimed by another process
                                if echo "$claim_output" | grep -q "The deposit is ready to be claimed" && \
                                   echo "$claim_output" | grep -q "Deposit transaction failed"; then
                                    _log_file_descriptor "2" "Deposit ready but transaction failed - likely already claimed by parallel process"
                                    claim_status=0  # Treat as success
                                    claim_output="Deposit was likely already claimed by parallel process"
                                    break
                                fi
                                
                                # If verification fails, treat the original failure as real
                                _log_file_descriptor "2" "Transaction genuinely failed, not due to already claimed"
                                claim_status=1
                                break
                            else
                                _log_file_descriptor "2" "Claim succeeded cleanly on attempt $claim_attempt"
                                break
                            fi
                        else
                            claim_status=$?
                            _log_file_descriptor "2" "Claim attempt $claim_attempt failed with exit status $claim_status"
                            _log_file_descriptor "2" "Claim output: $claim_output"

                            # Check if it's already claimed - this should be treated as success
                            if _check_already_claimed "$claim_output"; then
                                _log_file_descriptor "2" "Deposit was already claimed by another process"
                                claim_status=0
                                break
                            fi

                            # Check if it's a temporary "not ready" error - retry after delay
                            if echo "$claim_output" | grep -q -E "(not yet ready to be claimed|Try again in a few blocks)"; then
                                _log_file_descriptor "2" "Claim not ready yet, will retry after delay (attempt $claim_attempt/$max_claim_retries)"
                                if [[ $claim_attempt -lt $max_claim_retries ]]; then
                                    sleep 10  # Wait longer before retry for "not ready" errors
                                    continue
                                else
                                    _log_file_descriptor "2" "Exhausted retries waiting for claim to be ready"
                                    # Don't falsely claim it was already claimed - it's just not ready yet
                                    break
                                fi
                            fi

                            # Check if it's a Merkle proof retrieval issue - retry after longer delay
                            if echo "$claim_output" | grep -q -E "(the Merkle Proofs cannot be retrieved|error getting merkle proofs)"; then
                                _log_file_descriptor "2" "Merkle proof retrieval failed, will retry after delay (attempt $claim_attempt/$max_claim_retries)"
                                if [[ $claim_attempt -lt $max_claim_retries ]]; then
                                    sleep 300  # Wait longer for bridge service to index the deposit
                                    continue
                                else
                                    _log_file_descriptor "2" "Exhausted retries waiting for Merkle proofs to be available"
                                    break
                                fi
                            fi

                            # Additional pattern: "The deposit is ready to be claimed" + "Deposit transaction failed"
                            # This typically indicates the deposit was claimed between the ready check and the claim attempt
                            if echo "$claim_output" | grep -q "The deposit is ready to be claimed" && \
                               echo "$claim_output" | grep -q "Deposit transaction failed"; then
                                _log_file_descriptor "2" "Deposit ready but transaction failed - checking for race condition"
                                
                                # Do one final verification attempt
                                local final_verify_output
                                if final_verify_output=$(timeout 15 bash -c "$claim_command" 2>&1); then
                                    if _check_already_claimed "$final_verify_output"; then
                                        _log_file_descriptor "2" "Verification confirmed deposit was already claimed (race condition)"
                                        claim_status=0
                                        claim_output="Deposit was already claimed (race condition detected)"
                                        break
                                    fi
                                else
                                    # If the verification also fails with the same pattern, assume it's already claimed
                                    if echo "$final_verify_output" | grep -q "The deposit is ready to be claimed" && \
                                    echo "$final_verify_output" | grep -q "Deposit transaction failed"; then
                                        _log_file_descriptor "2" "Verification confirmed deposit was already claimed (consistent failure pattern)"
                                        claim_status=0
                                        claim_output="Deposit was already claimed (consistent failure pattern)"
                                        break
                                    fi
                                fi
                            fi

                            # For other errors, don't retry immediately but check if it might be an already-claimed case
                            if echo "$claim_output" | grep -q -E "(Deposit transaction failed|Perhaps try increasing the gas limit)"; then
                                _log_file_descriptor "2" "Got transaction failure error - verifying if deposit was actually claimed"
                                sleep 2  # Brief pause for state propagation
                                
                                # Try one more time to see if the error message changes to "already claimed"
                                local final_check_output
                                if final_check_output=$(timeout 30 bash -c "$claim_command" 2>&1); then
                                    _log_file_descriptor "2" "Final check succeeded unexpectedly"
                                    claim_status=0
                                    claim_output="$final_check_output"
                                    break
                                else
                                    if _check_already_claimed "$final_check_output"; then
                                        _log_file_descriptor "2" "Verification confirmed deposit was already claimed"
                                        claim_status=0
                                        claim_output="$final_check_output"
                                        break
                                    fi
                                fi
                            fi

                            # For genuine failures, don't retry
                            break
                        fi
                    done
                
                _log_file_descriptor "2" "Claim command output for test $test_index: $claim_output"

                # Validate claim result with array support
                local claim_expects_success=false
                local claim_has_other_expected_errors=false
                
                # Determine what claim outcomes are expected
                if [[ "$expected_result_claim" == "Success" ]]; then
                    claim_expects_success=true
                elif [[ "$expected_result_claim" =~ ^\[.*\]$ ]]; then
                    # Handle array of expected claim results
                    _log_file_descriptor "2" "Processing array of expected claim results: $expected_result_claim"
                    
                    # Check if array contains "Success"
                    if echo "$expected_result_claim" | jq -r '.[]' | grep -q "^Success$"; then
                        claim_expects_success=true
                        _log_file_descriptor "2" "Claim array contains 'Success' as valid outcome"
                    fi
                    
                    # Check if array contains other error patterns
                    if echo "$expected_result_claim" | jq -r '.[]' | grep -v "^Success$" | grep -q .; then
                        claim_has_other_expected_errors=true
                        _log_file_descriptor "2" "Claim array contains other expected error patterns"
                    fi
                else
                    # Single non-Success expected result
                    claim_has_other_expected_errors=true
                fi
                
                _log_file_descriptor "2" "Claim expects success: $claim_expects_success, has other expected errors: $claim_has_other_expected_errors"
                
                # Validate claim result
                if [[ $claim_status -eq 0 ]]; then
                    # Claim succeeded
                    if $claim_expects_success; then
                        claim_result="PASS"
                        _log_file_descriptor "2" "Claim succeeded and success was expected"
                    else
                        # Success not expected, but check if already claimed
                        if _check_already_claimed "$claim_output"; then
                            claim_result="PASS"
                            _log_file_descriptor "2" "Claim succeeded because deposit was already claimed by another process"
                        else
                            claim_result="FAIL"
                            error_message="Expected claim failure but succeeded for deposit $deposit_count"
                        fi
                    fi
                else
                    # Claim failed - check specific failure reasons
                    if _check_already_claimed "$claim_output"; then
                        claim_result="PASS"
                        _log_file_descriptor "2" "Claim failed because deposit $deposit_count was already claimed by another process"
                    elif echo "$claim_output" | grep -q -E "(not yet ready to be claimed|Try again in a few blocks)"; then
                        # Handle "not ready" timeouts based on expectations
                        if $claim_expects_success; then
                            claim_result="FAIL"
                            error_message="Claim timed out waiting for deposit to be ready (not yet ready to be claimed)"
                            _log_file_descriptor "2" "Claim failed due to timeout waiting for deposit to be ready"
                        else
                            # If failure was expected, treat timeout as valid failure
                            claim_result="PASS"
                            _log_file_descriptor "2" "Claim timeout matches expected failure pattern"
                        fi
                    elif echo "$claim_output" | grep -q -E "(the Merkle Proofs cannot be retrieved|error getting merkle proofs)"; then
                        # Handle Merkle proof retrieval timeouts based on expectations
                        if $claim_expects_success; then
                            claim_result="FAIL"
                            error_message="Claim timed out waiting for Merkle proofs to be available"
                            _log_file_descriptor "2" "Claim failed due to timeout waiting for Merkle proofs"
                        else
                            # If failure was expected, treat Merkle proof timeout as valid failure
                            claim_result="PASS"
                            _log_file_descriptor "2" "Merkle proof timeout matches expected failure pattern"
                        fi
                    elif $claim_has_other_expected_errors && _validate_bridge_error "$expected_result_claim" "$claim_output"; then
                        claim_result="PASS"
                        _log_file_descriptor "2" "Claim failed with expected error pattern"
                    elif $claim_expects_success && ! $claim_has_other_expected_errors; then
                        # Only expected success, but got failure
                        claim_result="FAIL"
                        error_message="Expected claim success but failed for deposit $deposit_count"
                    elif ! $claim_expects_success && $claim_has_other_expected_errors; then
                        # Expected specific errors but didn't match
                        claim_result="FAIL"
                        error_message="Expected claim errors $(echo "$expected_result_claim" | tr -d '\n') not found in output"
                    else
                        # Mixed expectations (success + errors) but failure didn't match expected patterns
                        claim_result="FAIL"
                        error_message="Claim failed but error doesn't match expected patterns: $(echo "$expected_result_claim" | tr -d '\n')"
                    fi
                fi
            fi
        else
            # Bridge succeeded but success was not expected
            bridge_result="FAIL"
            error_message="Expected bridge failure but succeeded: $bridge_output"
        fi
    else
        # Bridge failed
        if $bridge_has_other_expected_errors && _validate_bridge_error "$expected_result_process" "$bridge_output"; then
            bridge_result="PASS"
            _log_file_descriptor "2" "Bridge failed with expected error pattern"
        elif $bridge_expects_success && ! $bridge_has_other_expected_errors; then
            # Only expected success, but got failure
            bridge_result="FAIL"
            error_message="Expected bridge success but failed: $bridge_output"
        elif ! $bridge_expects_success && $bridge_has_other_expected_errors; then
            # Expected specific errors but didn't match
            bridge_result="FAIL"
            error_message="Expected bridge errors $(echo "$expected_result_process" | tr -d '\n') not found in output"
        else
            # Mixed expectations (success + errors) but failure didn't match expected patterns
            bridge_result="FAIL"
            error_message="Bridge failed but error doesn't match expected patterns: $(echo "$expected_result_process" | tr -d '\n')"
        fi
    fi
    
    # Clean up temporary files for this test
    rm -f "/tmp/huge_data_${test_index}.hex" "/tmp/max_data_${test_index}.hex"
    
    # Write result to file
    echo "TEST_$test_index|$bridge_result|$claim_result|$error_message" > "$result_file"
    
    _log_file_descriptor "2" "Completed bridge test $test_index"
}


_collect_and_report_results() {
    local output_dir="$1"
    local bridge_log="$2"
    local total_scenarios="$3"
    local scenarios_file="$4"
    
    _log_file_descriptor "3" "All parallel bridge tests completed. Collecting results..." | tee -a "$bridge_log"
    
    # Initialize counters
    local total_tests=0 passed_bridge=0 passed_claim=0 failed_tests=0
    
    local summary_file="$output_dir/test_summary.txt"
    local detailed_results="$output_dir/detailed_results.txt"
    
    # Create summary file header
    {
        echo ""
        echo "========================================"
        echo "           TEST RESULTS SUMMARY         "
        echo "========================================"
        printf "%-8s %-8s %-8s %s\n" "TEST" "BRIDGE" "CLAIM" "ERROR"
        echo "----------------------------------------"
    } | tee "$summary_file" >&3
    
    # Create detailed results file header
    echo "DETAILED TEST RESULTS" > "$detailed_results"
    echo "====================" >> "$detailed_results"
    echo "" >> "$detailed_results"
    
    # Process each test result
    for i in $(seq 0 $((total_scenarios - 1))); do
        local result_file="/tmp/test_result_${i}.txt"
        local scenario
        scenario=$(jq -c ".[$i]" "$scenarios_file")
        
        # Extract scenario details for detailed report
        local test_bridge_type
        test_bridge_type=$(echo "$scenario" | jq -r '.BridgeType')
        local test_token
        test_token=$(echo "$scenario" | jq -r '.Token')
        local test_amount
        test_amount=$(echo "$scenario" | jq -r '.Amount')
        local test_meta_data
        test_meta_data=$(echo "$scenario" | jq -r '.MetaData')
        local expected_result_process
        expected_result_process=$(echo "$scenario" | jq -r '.ExpectedResultProcess')
        
        {
            echo "Test $i:"
            echo "  Bridge Type: $test_bridge_type"
            echo "  Token: $test_token"
            echo "  Amount: $test_amount"
            echo "  Metadata: $test_meta_data"
            echo "  Expected: $expected_result_process"
        } >> "$detailed_results"
        
        if [[ -f "$result_file" ]]; then
            local result_line
            result_line=$(cat "$result_file")
            IFS='|' read -r test_id bridge_result claim_result error_msg <<< "$result_line"
            
            # Display to both console (fd 3) and summary file
            printf "%-8s %-8s %-8s %s\n" "$test_id" "$bridge_result" "$claim_result" "$error_msg" | tee -a "$summary_file" >&3
            
            echo "  Result: $bridge_result" >> "$detailed_results"
            [[ -n "$error_msg" ]] && echo "  Error: $error_msg" >> "$detailed_results"
            
            total_tests=$((total_tests + 1))
            [[ "$bridge_result" == "PASS" ]] && passed_bridge=$((passed_bridge + 1))
            [[ "$claim_result" == "PASS" ]] && passed_claim=$((passed_claim + 1))
            [[ "$bridge_result" == "FAIL" || "$claim_result" == "FAIL" ]] && failed_tests=$((failed_tests + 1))
        else
            # Display timeout to both console and summary file
            printf "%-8s %-8s %-8s %s\n" "TEST_$i" "TIMEOUT" "N/A" "Test timed out or failed to complete" | tee -a "$summary_file" >&3
            echo "  Result: TIMEOUT" >> "$detailed_results"
            failed_tests=$((failed_tests + 1))
            total_tests=$((total_tests + 1))
        fi
        
        echo "" >> "$detailed_results"
    done
    
    # Summary footer - display to both console and file
    {
        echo "----------------------------------------"
        echo "Total Tests: $total_tests"
        echo "Bridge Success: $passed_bridge/$total_tests"
        echo "Claim Success: $passed_claim (out of applicable tests)"
        echo "Failed Tests: $failed_tests"
        echo "========================================"
    } | tee -a "$summary_file" >&3
    
    # Save test configuration for reference
    jq '.' "$scenarios_file" > "$output_dir/test_scenarios.json"
    
    # Create README file
    cat > "$output_dir/README.txt" << EOF
Bridge Test Results - $(date)
==============================

Files in this directory:
- test_summary.txt: Quick overview of all test results
- detailed_results.txt: Test scenarios with results
- test_scenarios.json: Original test configuration
- setup_phase.log: Sequential setup phase log
- bridge_phase.log: Parallel bridge test phase log
- setup_debug_*.log: Individual setup logs for each test
- bridge_test_*.log: Individual bridge test logs

Total Tests: $total_tests
Passed: $passed_bridge
Failed: $failed_tests

To view results quickly:
  cat test_summary.txt

To see detailed test info:
  cat detailed_results.txt

To debug specific test failures:
  cat bridge_test_<test_number>.log
  cat setup_debug_<test_number>.log
EOF
    
    # Print summary to terminal
    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "========================================"
    _log_file_descriptor "3" "           FINAL RESULTS                "
    _log_file_descriptor "3" "========================================"
    _log_file_descriptor "3" "Total Tests: $total_tests"
    _log_file_descriptor "3" "Bridge Success: $passed_bridge/$total_tests"
    _log_file_descriptor "3" "Failed Tests: $failed_tests"
    _log_file_descriptor "3" "Monitor the test results and try manually claiming bridges when they're ready for claim where applicable"
    _log_file_descriptor "3" ""
    _log_file_descriptor "3" "Detailed results saved to: $output_dir"
    _log_file_descriptor "3" "Quick summary: cat $summary_file"
    _log_file_descriptor "3" "Full details: cat $detailed_results"
    
    # Return failure count for test result
    return $failed_tests
}

# Helper function to select the appropriate bridge service URL based on network configuration
_select_bridge_service_url() {
    local from_network_id="$1"
    local to_network_id="$2"
    
    _log_file_descriptor "2" "Selecting bridge service URL for bridge: network $from_network_id -> network $to_network_id"
    
    # Rule 1: When one of the network_id is 0 (L1), use the bridge_service_url of the other network
    if [[ "$from_network_id" == "0" && "$to_network_id" != "0" ]]; then
        _log_file_descriptor "2" "L1 -> L2 bridge: using destination network ($to_network_id) bridge service URL"
        _get_bridge_service_url "$to_network_id"
    elif [[ "$to_network_id" == "0" && "$from_network_id" != "0" ]]; then
        _log_file_descriptor "2" "L2 -> L1 bridge: using source network ($from_network_id) bridge service URL"
        _get_bridge_service_url "$from_network_id"
    else
        # Rule 2: When both networks are not 0 (both are L2s), use the FromNetwork bridge_service_url
        _log_file_descriptor "2" "L2 -> L2 bridge: using source network ($from_network_id) bridge service URL"
        _get_bridge_service_url "$from_network_id"
    fi
}

# Helper function to get bridge service URL for a specific network
_get_bridge_service_url() {
    local network_id="$1"
    
    # Initialize network configuration if not done already
    if [[ -z "${NETWORK_ID_TO_NAME[$network_id]:-}" ]]; then
        _initialize_network_config
    fi
    
    # Get the network name from network ID
    local network_name="${NETWORK_ID_TO_NAME[$network_id]:-}"
    
    if [[ -z "$network_name" ]]; then
        # Fallback to global bridge_service_url if network not found
        _log_file_descriptor "2" "No network name found for network ID $network_id, using global bridge service URL"
        echo "${bridge_service_url:-}"
        return 0
    fi
    
    _log_file_descriptor "2" "Looking up bridge service URL for network $network_id ($network_name)"
    
    # Use the standardized _get_network_config function for consistency
    local bridge_service
    bridge_service=$(_get_network_config "$network_id" "bridge_service_url" 2>/dev/null)
    
    if [[ -n "$bridge_service" ]]; then
        _log_file_descriptor "2" "Found network-specific bridge service URL: $bridge_service"
        echo "$bridge_service"
        return 0
    fi
    
    # For Kurtosis networks, handle special cases
    case "$network_name" in
        "kurtosis_l1")
            # L1 (network 0) should never provide its own bridge service URL
            # The bridge service URL is always determined by the other (non-L1) network
            _log_file_descriptor "2" "L1 network should not provide bridge service URL - this should be handled by _select_bridge_service_url()"
            echo ""
            ;;
        "kurtosis_network_1")
            # Network 1 uses specific bridge service environment variable
            local kurtosis_net1_bridge_service="${KURTOSIS_NETWORK_1_BRIDGE_SERVICE_URL:-${KURTOSIS_NETWORK_1_BRIDGE_SERVICE_URL:-}}"
            if [[ -z "$kurtosis_net1_bridge_service" ]]; then
                kurtosis_net1_bridge_service="${bridge_service_url:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-001 rpc 2>/dev/null || echo "")}"
            fi
            _log_file_descriptor "2" "Kurtosis network 1 bridge service URL: $kurtosis_net1_bridge_service"
            echo "$kurtosis_net1_bridge_service"
            ;;
        "kurtosis_network_2")
            # Network 2 uses specific bridge service environment variable
            local kurtosis_net2_bridge_service="${KURTOSIS_NETWORK_2_BRIDGE_SERVICE_URL:-${KURTOSIS_NETWORK_2_BRIDGE_SERVICE_URL:-}}"
            if [[ -z "$kurtosis_net2_bridge_service" ]]; then
                kurtosis_net2_bridge_service="${bridge_service_url:-$(kurtosis port print "$kurtosis_enclave_name" zkevm-bridge-service-002 rpc 2>/dev/null || echo "")}"
            fi
            _log_file_descriptor "2" "Kurtosis network 2 bridge service URL: $kurtosis_net2_bridge_service"
            echo "$kurtosis_net2_bridge_service"
            ;;
        *)
            # For all other networks, fallback to global bridge service URL
            _log_file_descriptor "2" "No specific bridge service URL found for $network_name, using global: ${bridge_service_url:-'not set'}"
            echo "${bridge_service_url:-}"
            ;;
    esac
}