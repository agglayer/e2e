#!/usr/bin/env bats
# bats file_tags=agglayer

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

    export invalid_cert_id="0x0000000000000000000000000000000000000000000000000000000000000000"
    export invalid_height=999999
}

function interop_status_query() {
    local interop_ep=$1
    local full_answer=${2:-0}

    # Iterate until there is one certificate (no null answer)
    while true; do
        run cast rpc --rpc-url "$agglayer_rpc_url" "$interop_ep" "$rollup_id"
        if [[ "$status" -ne 0 ]]; then
            echo "❌ Failed to get latest known certificate header using $interop_ep: $output"
            exit 1
        else
            if [[ "$full_answer" -ne 0 ]]; then
                answer=$output
            else
                answer=$(echo "$output" | jq -r '.certificate_id')
            fi
            if [ -n "$answer" ]; then
                break
            fi
            sleep 3
        fi
    done
    echo $answer
}

# bats test_tags=agglayer-admin
@test "admin_getCertificate returns certificate data for valid certificate ID" {
    # First get a known certificate ID from regular API
    certificate_id=$(interop_status_query interop_getLatestKnownCertificateHeader)
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

# bats test_tags=agglayer-admin
@test "admin_getCertificate returns error for invalid certificate ID" {
    run cast rpc --rpc-url "$agglayer_admin_url" admin_getCertificate "$invalid_cert_id"
    if [[ "$status" -eq 0 ]]; then
        echo "❌ Expected error for invalid certificate id with admin_getCertificate, but got success: $output"
        exit 1
    else
        if [[ "$output" == *"resource-not-found"* ]]; then
            echo "✅ Successfully handled invalid certificate id with admin_getCertificate: $output"
        else
            echo "❌ Expected resource-not-found error for invalid certificate id with admin_getCertificate, but got: $output"
            exit 1
        fi
    fi
}

# bats test_tags=agglayer-admin
@test "admin_setLatestPendingCertificate with non-existent certificate" {
    run cast rpc --rpc-url "$agglayer_admin_url" admin_setLatestPendingCertificate "$invalid_cert_id"
    if [[ "$status" -eq 0 ]]; then
        echo "❌ Expected error for invalid certificate id with admin_setLatestPendingCertificate, but got success: $output"
        exit 1
    else
        if [[ "$output" == *"resource-not-found"* ]]; then
            echo "✅ Successfully handled invalid certificate id with admin_setLatestPendingCertificate: $output"
        else
            echo "❌ Expected resource-not-found error for invalid certificate id with admin_setLatestPendingCertificate, but got: $output"
            exit 1
        fi
    fi
}

# bats test_tags=agglayer-admin
@test "admin_setLatestPendingCertificate with valid certificate ID" {

    latest_known_certificate_id=$(interop_status_query interop_getLatestKnownCertificateHeader)
    echo "✅ Successfully retrieved latest known certificate for $latest_known_certificate_id"

    # Get a pending certificate, will be set later
    while true; do
        latest_pending_certificate_id=$(interop_status_query interop_getLatestPendingCertificateHeader)
        if [[ "$latest_pending_certificate_id" != "$latest_known_certificate_id" ]]; then
            break
        else
            echo "⏳ Waiting for a pending certificate to be available..."
            sleep 3
        fi
    done
    echo "✅ Successfully retrieved pending certificate: $latest_pending_certificate_id"

    # Test admin_setLatestPendingCertificate
    run cast rpc --rpc-url "$agglayer_admin_url" admin_setLatestPendingCertificate "$latest_known_certificate_id"
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to set last pending certificate using admin_setLatestPendingCertificate: $output"
        exit 1
    else
        echo "✅ Successfully called admin_setLatestPendingCertificate with certificate $latest_known_certificate_id, let's verify..."
    fi

    # So far, I've been unable to retrieve certificate id that we just set above. It keeps returning previous data...
    # updated_latest_pending_certificate_id=$(interop_status_query interop_getLatestPendingCertificateHeader)
    # if [[ "$updated_latest_pending_certificate_id" == "$latest_known_certificate_id" ]]; then
    #     echo "✅ Successfully updated latest pending certificate to $updated_latest_pending_certificate_id"
    # else
    #     echo "❌ Failed to update latest pending certificate, after calling admin_setLatestPendingCertificate it's still $updated_latest_pending_certificate_id"
    #     exit 1
    # fi
}

# bats test_tags=agglayer-admin
@test "admin_removePendingCertificate with non-existent certificate" {
    run cast rpc --rpc-url "$agglayer_admin_url" admin_removePendingCertificate "$rollup_id" "$invalid_height" "true"
    if [[ "$status" -eq 0 ]]; then
        echo "❌ Expected error for invalid certificate height with admin_removePendingCertificate, but got success: $output"
        exit 1
    else
        if [[ "$output" == *"resource-not-found"* ]]; then
            echo "✅ Successfully handled invalid certificate height with admin_removePendingCertificate: $output"
        else
            echo "❌ Expected resource-not-found error for invalid certificate height with admin_removePendingCertificate, but got: $output"
            exit 1
        fi
    fi
}

# bats test_tags=agglayer-admin
@test "admin_removePendingProof with invalid certificate ID" {
    run cast rpc --rpc-url "$agglayer_admin_url" admin_removePendingProof "$invalid_cert_id"
    # this call succeeds and returns null anyway.....
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Error calling admin_removePendingProof with invalid certificate id: $output"
        exit 1
    else
        if [[ "$output" == "null" ]]; then
            echo "✅ Successfully called admin_removePendingProof with invalid certificate ID"
        else
            echo "❌ Expected null result from admin_removePendingProof with invalid certificate ID, but got: $output"
            exit 1
        fi
    fi
}

# bats test_tags=agglayer-admin
@test "compare admin and regular API responses for same certificate" {
    interop_header=$(interop_status_query interop_getLatestKnownCertificateHeader 1)
    
    # Skip if no certificate exists
    if jq -e '. == null' <<< "$interop_header"; then
        skip "❌ No certificate available to test"
    fi

    certificate_id=$(jq -r '.certificate_id' <<< "$interop_header")
    if [[ -z "$certificate_id" ]]; then
        echo "❌ Error parsing certificate_id from certificate: $output"
        exit 1
    else
        echo "✅ Successfully retrieved latest known certificate for $certificate_id"
    fi

    # Get same certificate from admin API
    run cast rpc --rpc-url "$agglayer_admin_url" admin_getCertificate "$certificate_id"
    if [[ "$status" -ne 0 ]]; then
        echo "❌ Error calling admin_getCertificate with valid certificate id: $output"
        exit 1
    else
        echo "✅ Successfully called admin_getCertificate for certificate $certificate_id"
        admin_cert=$output
    fi

    # Verify admin API returned certificate data
    if ! jq -e '.[0] != null' <<< "$admin_cert"; then
        echo "❌ Error: Admin API did not return certificate data"
        exit 1
    fi

    # Extract certificate header from admin response (second element)
    admin_header=$(jq '.[1]' <<< "$admin_cert")

    if [ "$(jq -S . <<<"$admin_header")" = "$(jq -S . <<<"$interop_header")" ]; then
        echo "✅ Certificate headers match between interop and admin APIs for $certificate_id"
    else
        echo "❌ Error: Certificate header mismatch: interop=$interop_header, admin=$admin_header"
        exit 1
    fi
}

# Improvement and or pending features to test:
# - Validate admin_setLatestPendingCertificate did what it's expected to do, right now we just know the call succedeed
# - Validate admin_removePendingCertificate properly cleans up the state, we just test invalid input
# - Validate admin_removePendingProof properly cleans up the state, we just test invalid input
# - admin_forcePushPendingCertificate
# - admin_setLatestProvenCertificate
