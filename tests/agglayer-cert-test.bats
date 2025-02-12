setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats test_tags=agglayer-cert-test
@test "Agglayer random cert test" {
    [ "${KURTOSIS_ENCLAVE}" == "cdk" ]
    local network_id="2"
    local height="1000"
    run sendRandomCert $network_id $height
    # echo "Captured Exit Code: $status"
    # echo "Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "Error: Timed out waiting for certificate with hash 0x[a-fA-F0-9]{64}"

    run sendRandomCert $network_id $height
    # echo "2 Captured Exit Code: $status"
    # echo "2 Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "-32602 Invalid argument: Unable to replace a pending certificate that is not in error"

    new_height=$((height - 100))
    run sendRandomCert $network_id $new_height
    # echo "3 Captured Exit Code: $status"
    # echo "3 Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "-32603 Internal error: Invalid certificate candidate for network 2: [0-9]+ wasn't expected, current height [0-9]+"
}

function sendRandomCert() {
    local netID="$1"
    local height="$2"
    spammer_output=$(agglayer-certificate-spammer random-certs --url $(kurtosis port print cdk agglayer agglayer) --private-key 0x45f3ccdaff88ab1b3bb41472f09d5cde7cb20a6cbbc9197fddf64e2f3d67aaf2 --valid-signature --network-id $netID --height "$height"  2>&1)
    if [[ $status -ne 0 ]]; then
        echo "Error: Failed to send Certificate. Output: $spammer_output"
        return 1
    fi
    cert_hash=$(extract_certificate_hash "$spammer_output")
    if [[ -z "$cert_hash" ]] ; then
       echo "Error: Failed to extract the certificate hash."
       return 1
    fi
    echo $cert_hash
    local timeout=5
    run wait_for_cert $cert_hash $timeout
    # Check the exit status
    if [[ $status == 0 ]]; then
        echo "Cert successfully settled"
        return 0
    else
        echo "error waiting for cert to be settled"
        return 1
    fi
}

function extract_certificate_hash() {
    local spammer_output="$1"
    echo "$spammer_output" | grep 'Certificate sent with hash:' | awk '{print $8}' | tail -n 1
}

function wait_for_cert() {
    local cert_hash="$1"
    local timeout="$2"
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    while true; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "Error: Timed out waiting for certificate with hash $cert_hash"
            return 1
        fi
        status=$(curl --silent --location --request POST $(kurtosis port print cdk agglayer agglayer) \
            --header 'Content-Type: application/json' \
            --data-raw '{
                "jsonrpc": "2.0",
                "method": "interop_getCertificateHeader",
                "params": ["'$cert_hash'"],
                "id": 1
            }' | jq | grep 'status' | awk -F'"' '{print $4}')
        if [[ -n "$status" ]]; then
            if [[ $status == "Pending" ]]; then
                echo "Certificate with hash $cert_hash is pending"
            elif [[ $status == "Settled" ]]; then
                echo "Certificate with hash $cert_hash is settled"
                return 0
            else
                echo "Error: Certificate with hash $cert_hash is in an unknown state: $status"
                return 1
            fi
        fi
        sleep 1
    done
}