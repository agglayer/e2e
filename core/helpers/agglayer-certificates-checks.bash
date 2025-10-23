# This script contains a helper function to interact with the agglayer node for certificate and block checks.

# Helper functions to check output conditions
# shellcheck disable=SC1009,SC1073,SC1064,SC1072
check_non_null() {
    [[ -n "$1" && "$1" != "null" ]]
}
check_null() {
    [[ -z "$1" || "$1" == "null" ]]
}

# Generic function to wait for a condition with retry and timeout
wait_for_condition() {
    local check_type="$1"  # e.g., null_cert, non_null_cert, block_increase, settled_cert
        local timeout="$2"     # Timeout in seconds
        local retry_interval="$3"  # Retry interval in seconds
        local success_msg="$4"    # Success message
        local error_msg="$5"      # Error message
        local output_file="${6:-3}"  # File descriptor for output (default to 3)

    echo "Starting check for $check_type..." >&"$output_file"
    local start=$SECONDS

    # persistent vars across loop iterations
    local first_block=""
    local first_height=""

    while true; do
        case "$check_type" in
            "null_cert"|"non_null_cert"|"settled_cert")
                local output
                if [[ "$check_type" == "settled_cert" ]]; then
                    output=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq '.' 2>/dev/null)
                else
                    output=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null)
                fi

                case "$check_type" in
                    "null_cert")
                        if check_null "$output"; then
                            echo "$success_msg" >&"$output_file"
                            return 0
                        fi
                        ;;
                    "non_null_cert"|"settled_cert")
                        if check_non_null "$output"; then
                            echo "$success_msg: $output" >&"$output_file"
                            return 0
                        fi
                        ;;
                esac
                echo "Current output: $output" >&"$output_file"
                ;;

            "block_increase")
                # Only set first_block once, outside the retry loop
                if [[ -z "$first_block" ]]; then
                    first_block=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata' | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
                    echo "Initial block: $first_block" >&"$output_file"
                fi

                sleep "$retry_interval"

                local second_block
                second_block=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata' | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
                echo "Latest block: $second_block" >&"$output_file"

                if [[ "$second_block" -gt "$first_block" ]]; then
                    echo "$success_msg: $first_block to $second_block" >&"$output_file"
                    return 0
                fi
                echo "Retrying block increase check..." >&"$output_file"
                ;;

            "height_increase")
                # Only set first_height once, outside the retry loop
                if [[ -z "$first_height" ]]; then
                    first_height=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.height')
                    echo "Initial height: $first_height" >&"$output_file"
                fi

                sleep "$retry_interval"

                local second_height
                second_height=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.height')
                echo "Latest height: $second_height" >&"$output_file"

                if [[ "$second_height" -gt "$first_height" ]]; then
                    echo "$success_msg: $first_height to $second_height" >&"$output_file"
                    return 0
                fi
                echo "Retrying height increase check..." >&"$output_file"
                ;;

            *)
                echo "Error: Unknown check type: $check_type" >&"$output_file"
                return 1
                ;;
        esac

        if [[ $((SECONDS - start)) -ge $timeout ]]; then
            echo "$error_msg" >&"$output_file"
            return 1
        fi

        echo "Retrying..." >&"$output_file"
        sleep "$retry_interval"
    done
}

# Function to check settlement information with error handling
print_settlement_info() {
    # Validate environment variables
    if [[ -z "$l1_rpc_url" || -z "$rollup_address" || -z "$rollup_manager_address" ]]; then
        echo "Error: Missing required environment variables (l1_rpc_url, rollup_address, or rollup_manager_address)" >&3
        return 1
    fi

    # Check if L1 RPC is reachable
    if ! curl -s --fail "$l1_rpc_url" >/dev/null; then
        echo "Error: L1 RPC URL ($l1_rpc_url) is not reachable" >&3
        return 1
    fi

    echo "Fetching L1 settlement information..." >&3
    echo "L1 RPC URL: $l1_rpc_url" >&3
    echo "Rollup Address: $rollup_address" >&3
    echo "Rollup Manager Address: $rollup_manager_address" >&3

    # Fetch latest block number
    echo "The latest block number recorded on L1: " >&3
    if ! output=$(cast call --rpc-url "$l1_rpc_url" "$rollup_address" 'latestBlockNumber() external view returns (uint256)' 2>&1 >&3); then
        echo "Error: Failed to fetch latest block number: $output" >&3
    else
        echo "$output" >&3
    fi

    # Fetch VerifyPessimisticStateTransition events
    echo "VerifyPessimisticStateTransition(uint32,bytes32,bytes32,bytes32,bytes32,bytes32,address) events recorded: " >&3
    if ! events=$(cast logs --json --rpc-url "$l1_rpc_url" --address "$rollup_manager_address" 0xdf47e7dbf79874ec576f516c40bc1483f7c8ddf4b45bfd4baff4650f1229a711 2>&1 | jq '.' >&3); then
        echo "Error: Failed to fetch VerifyPessimisticStateTransition events: $events" >&3
    fi

    # Fetch OutputProposed events
    echo "OutputProposed(bytes32,uint256,uint256,uint256) events recorded: " >&3
    if ! events=$(cast logs --json --rpc-url "$l1_rpc_url" --address "$rollup_address" 0xa7aaf2512769da4e444e3de247be2564225c2e7a8f74cfe528e46e17d24868e2 2>&1 | jq '.' >&3); then
        echo "Error: Failed to fetch OutputProposed events: $events" >&3
    fi
}

# Wrapper functions for specific checks
wait_for_non_null_cert() {
    wait_for_condition "non_null_cert" "$timeout" "$retry_interval" "Non-null latest pending certificate" "Error: Timeout ($timeout s) for non-null certificate"
}

wait_for_null_cert() {
    wait_for_condition "null_cert" "$timeout" "$retry_interval" "Null latest pending certificate confirmed" "Error: Timeout ($timeout s) for null certificate"
}

check_for_null_cert() {
    local output
    output=$(cast rpc --rpc-url "$(kurtosis port print "${kurtosis_enclave_name-""}" agglayer aglr-readrpc)" interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null)
    if check_null "$output"; then
        echo "Null latest pending certificate confirmed" >&3
        return 0
    else
        echo "Certificate is not null: $output" >&3
        return 1
    fi
}

check_for_latest_settled_cert() {
    wait_for_condition "settled_cert" "$timeout" "$retry_interval" "Non-null latest settled certificate" "Error: Timeout ($timeout s) for settled certificate"
}


check_height_increase() {
    wait_for_condition "height_increase" "$timeout" "$retry_interval" "Height number has increased" "Error: Timeout ($timeout s) waiting for height increase"
}

ensure_non_null_cert() {
    if check_for_null_cert; then
        if ! check_for_latest_settled_cert; then
            wait_for_non_null_cert
        fi
    else
        wait_for_non_null_cert
    fi
}