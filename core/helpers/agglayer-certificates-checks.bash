# This function contains helper functions to interact with the agglayer node to get information of pending or latest certificates.
agglayer_certificates_checks_setup() {
    check_non_null() [[ -n "$1" && "$1" != "null" ]]
    check_null() [[ "$1" == "null" ]]

    function wait_for_non_null_cert() {
        echo "Checking non-null certificate..."
        start=$((SECONDS))
        while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_non_null "$output"; do
            [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for non-null certificate"; exit 1; }
            echo "Retrying..."
            sleep $retry_interval
        done
        echo "Non-null latest pending certificate: $output"
    }

    function wait_for_null_cert() {
        echo "Checking null last pending certificate..."
        start=$((SECONDS))
        while ! output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null) || ! check_null "$output"; do
            [[ $((SECONDS - start)) -ge $timeout ]] && { echo "Error: Timeout ($timeout s) for null certificate"; exit 1; }
            echo "Retrying: $output"
            sleep $retry_interval
        done
        echo "Null latest pending certificate confirmed"
    }

    function check_for_null_cert() {
        echo "Checking null last pending certificate..."
        output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestPendingCertificateHeader 1 | jq '.' 2>/dev/null)
        if check_null "$output"; then
            echo "Null latest pending certificate confirmed"
            return 0
        else
            echo "Certificate is not null: $output"
            return 1
        fi
    }

    function check_for_latest_settled_cert() {
        echo "Checking latest settled certificate..."
        output=$(cast rpc --rpc-url $(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc) interop_getLatestSettledCertificateHeader 1 | jq '.' 2>/dev/null)
        if check_non_null "$output"; then
            echo "Non-null latest settled certificate: $output"
            return 0
        else
            echo "Certificate is null: $output"
            return 1
        fi
    }

    function check_block_increase() {
        echo "Checking last settled certificate" >&3
        local first_block=$(cast rpc --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata' | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
        echo "Initial block: $first_block" >&3
        
        sleep $retry_interval
        
        local second_block=$(cast rpc --rpc-url "$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)" interop_getLatestSettledCertificateHeader 1 | jq -r '.metadata' | perl -e '$_=<>; s/^\s+|\s+$//g; s/^0x//; $_=pack("H*",$_); my ($v,$f,$o,$c)=unpack("C Q> L> L>",$_); printf "{\"v\":%d,\"f\":%d,\"o\":%d,\"c\":%d}\n", $v, $f, $o, $c' | jq '.f + .o')
        echo "Latest block: $second_block" >&3
        
        if [[ $second_block -gt $first_block ]]; then
            echo "Block number has increased from $first_block to $second_block" >&3
            return 0
        else
            echo "Error: Block number has not increased ($first_block -> $second_block)" >&3
            return 1
        fi
    }

    function print_settlement_info() {
        # We should loop until this number is greater than 1... This indicated a finalized L1 settlement
        printf "The latest block number recorded on L1: "
        cast call --rpc-url "$l1_rpc_url" "$rollup_address" 'latestBlockNumber() external view returns (uint256)'

        # We can make sure there is an event as well
        echo "VerifyPessimisticStateTransition(uint32,bytes32,bytes32,bytes32,bytes32,bytes32,address) events recorded: "
        cast logs --json  --rpc-url "$l1_rpc_url" --address "$rollup_manager_address" 0xdf47e7dbf79874ec576f516c40bc1483f7c8ddf4b45bfd4baff4650f1229a711 | jq '.'

        # We can check for an 'OutputProposed(bytes32,uint256,uint256,uint256)' event to make sure the block number has advanced
        echo "OutputProposed(bytes32,uint256,uint256,uint256) events recorded: "
        cast logs --json  --rpc-url "$l1_rpc_url" --address "$rollup_address" 0xa7aaf2512769da4e444e3de247be2564225c2e7a8f74cfe528e46e17d24868e2| jq '.'
    }
}