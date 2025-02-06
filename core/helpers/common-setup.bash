_common_setup() {
    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'

    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    PATH="$PROJECT_ROOT/src:$PATH"
    
    GAS_TOKEN_ADDR="${GAS_TOKEN_ADDR:-0x72ae2643518179cF01bcA3278a37ceAD408DE8b2}"

    # ERC20 contracts function signatures
    readonly mint_fn_sig="function mint(address,uint256)"
    readonly balance_of_fn_sig="function balanceOf(address) (uint256)"
    readonly approve_fn_sig="function approve(address,uint256)"

    # Kurtosis enclave and service identifiers
    readonly enclave=${KURTOSIS_ENCLAVE:-cdk}
    readonly contracts_container=${KURTOSIS_CONTRACTS:-contracts-001}
    readonly contracts_service_wrapper=${KURTOSIS_CONTRACTS_WRAPPER:-"kurtosis service exec $enclave $contracts_container"}
    readonly erigon_rpc_node=${KURTOSIS_ERIGON_RPC:-cdk-erigon-rpc-001}

    # ✅ Standardized L2 RPC URL Handling
    if [[ -n "${L2_RPC_URL:-}" ]]; then
        readonly l2_rpc_url="$L2_RPC_URL"
    elif [[ -n "${KURTOSIS_ENCLAVE:-}" ]]; then
        readonly l2_rpc_url="$(kurtosis port print "$enclave" "$erigon_rpc_node" rpc)"
    else
        echo "❌ ERROR: No valid RPC URL found! Set L2_RPC_URL, or, ensure Kurtosis is running and specify KURTOSIS_ENCLAVE name as env var." >&2
        exit 1
    fi

    echo "🔧 Using L2 RPC URL: $l2_rpc_url"

    # ✅ Standardized Private Key Handling
    private_key="${L2_SENDER_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}"
}
