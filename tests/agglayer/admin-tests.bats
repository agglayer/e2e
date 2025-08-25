#!/usr/bin/env bats
# bats file_tags=agglayer

setup() {
    true
}

setup_file() {
    kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"cdk"}

    agglayer_admin_url=${AGGLAYER_ADMIN_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-admin)"}
    agglayer_rpc_url=${AGGLAYER_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" agglayer aglr-readrpc)"}
    export agglayer_admin_url agglayer_rpc_url

    l1_rpc_url=${L1_RPC_URL:-"http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)"}
    contracts_rpc=$(kurtosis port print $kurtosis_enclave_name contracts-001 http)
    chain_id=$(curl -s "${contracts_rpc}/opt/zkevm/combined.json" | jq -r .rollupChainID)
    rollup_mgr=$(curl -s "${contracts_rpc}/opt/zkevm/combined.json" | jq -r .polygonRollupManagerAddress)

    rollup_id=$(cast call $rollup_mgr 'chainIDToRollupID(uint64)' $chain_id --rpc-url $l1_rpc_url | cast to-dec)
    export rollup_id
}

function interop_getLatestKnownCertificateHeader() {
    # Iterate until there is one certificate (no null answer)
    while true; do
        run cast rpc --rpc-url "$agglayer_rpc_url" interop_getLatestKnownCertificateHeader "$rollup_id"
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to get latest known certificate header using interop_getLatestKnownCertificateHeader: $output"
            exit 1
        else
            certificate_id=$(echo "$output" | jq -r '.certificate_id')
            if [ -n "$certificate_id" ]; then
                break
            fi
            sleep 3
        fi
    done
    echo $certificate_id
}

# bats test_tags=admin-api,certificate-management
@test "admin_getCertificate returns certificate data for valid certificate ID" {
    # First get a known certificate ID from regular API
    certificate_id=$(interop_getLatestKnownCertificateHeader)
    echo "✅ Successfully retrieved latest known certificate header for $certificate_id"
  
    # Test admin_getCertificate
    run cast rpc --rpc-url "$agglayer_admin_url" admin_getCertificate "$certificate_id"
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Failed to get certificate data with admin_getCertificate: $output"
        exit 1
    else
        # Verify response structure - should return [Certificate, Option<CertificateHeader>]
        if ! echo "$output" | jq -e 'length == 2'; then
            echo "❌ admin_getCertificate should return an array with 2 elements [Certificate, CertificateHeader]: $output"
            exit 1
        fi
        cer_network_id=$(echo "$output" | jq -r '.[0].network_id')
        chd_network_id=$(echo "$output" | jq -r '.[1].network_id')
        cer_height=$(echo "$output" | jq -r '.[0].height')
        chd_height=$(echo "$output" | jq -r '.[1].height')
        cer_prev_ler=$(echo "$output" | jq -r '.[0].prev_local_exit_root')
        chd_prev_ler=$(echo "$output" | jq -r '.[1].prev_local_exit_root')
        cer_new_ler=$(echo "$output" | jq -r '.[0].new_local_exit_root')
        chd_new_ler=$(echo "$output" | jq -r '.[1].new_local_exit_root')
        cer_metadata=$(echo "$output" | jq -r '.[0].metadata')
        chd_metadata=$(echo "$output" | jq -r '.[1].metadata')
        certificate_status=$(echo "$output" | jq -r '.[1].status')
        # Check everything has a value:
        if [[ -z "$cer_network_id" || -z "$chd_network_id" || -z "$cer_height" || -z "$chd_height" || -z "$cer_prev_ler" || -z "$chd_prev_ler" || -z "$cer_new_ler" || -z "$chd_new_ler" || -z "$cer_metadata" || -z "$chd_metadata" || -z "$certificate_status" ]]; then
            echo "❌ One or more variables are null"
            exit 1
        fi
        # Check everything matches certificate vs header
        if [[ "$cer_network_id" != "$chd_network_id" ]]; then
            echo "❌ Network IDs do not match: $cer_network_id vs $chd_network_id"
            exit 1
        fi
        if [[ "$cer_height" != "$chd_height" ]]; then
            echo "❌ Heights do not match: $cer_height vs $chd_height"
            exit 1
        fi
        if [[ "$cer_prev_ler" != "$chd_prev_ler" ]]; then
            echo "❌ Previous local exit roots do not match: $cer_prev_ler vs $chd_prev_ler"
            exit 1
        fi
        if [[ "$cer_new_ler" != "$chd_new_ler" ]]; then
            echo "❌ New local exit roots do not match: $cer_new_ler vs $chd_new_ler"
            exit 1
        fi
        if [[ "$cer_metadata" != "$chd_metadata" ]]; then
            echo "❌ Metadata do not match: $cer_metadata vs $chd_metadata"
            exit 1
        fi
    fi
    echo "✅ Successfully retrieved certificate data for $certificate_id with status $certificate_status"
}

# bats test_tags=admin-api,certificate-management
@test "admin_getCertificate returns error for invalid certificate ID" {
    invalid_cert_id="0x0000000000000000000000000000000000000000000000000000000000000000"
    
    run cast rpc --rpc-url "$agglayer_admin_url" admin_getCertificate "$invalid_cert_id"
    if [[ "$status" -eq 0 ]]; then
        echo "❌ Expected error for invalid certificate id with admin_getCertificate, but got success: "
        exit 1
    else
        echo "✅ Successfully handled invalid certificate id with admin_getCertificate"
    fi
}

# bats test_tags=admin-api,state-management
@test "admin_setLatestPendingCertificate with valid certificate ID" {
    # Get a valid certificate first
    certificate_id=$(interop_getLatestKnownCertificateHeader)
    echo "✅ Successfully retrieved latest known certificate header for $certificate_id, waiting for a new one..."

    new_certificate_id=$(interop_getLatestKnownCertificateHeader)
    while [[ "$new_certificate_id" == "$certificate_id" ]]; do
        echo "⏳ Waiting for new certificate to be created..."
        sleep 10
        new_certificate_id=$(interop_getLatestKnownCertificateHeader)
    done
    echo "✅ Successfully retrieved a new latest known certificate header for $new_certificate_id"

    # Test admin_setLatestPendingCertificate
    run cast rpc --rpc-url "$agglayer_admin_url" admin_setLatestPendingCertificate "$certificate_id"
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to set last pending certificate using admin_setLatestPendingCertificate: $output"
        exit 1
    else
        echo "✅ Successfully called admin_setLatestPendingCertificate with certificate $certificate_id, let's verify..."
    fi

    updated_certificate_id=$(interop_getLatestKnownCertificateHeader)
    if [[ "$updated_certificate_id" == "$new_certificate_id" ]]; then
        echo "❌ Failed to update latest known certificate, after calling admin_setLatestPendingCertificate it's still $updated_certificate_id"
        exit 1
    else
        echo "✅ Successfully updated latest known certificate header to $updated_certificate_id"
    fi
}
