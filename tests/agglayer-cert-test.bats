setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats test_tags=agglayer-cert-test
@test "Agglayer random cert test" {
    [ "${KURTOSIS_ENCLAVE}" == "cdk" ]
    local network_id="2"
    local height="1000"
    local valid_private_key="0x45f3ccdaff88ab1b3bb41472f09d5cde7cb20a6cbbc9197fddf64e2f3d67aaf2"
    local invalid_private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

    # Random Cert using invalid private key
    run sendRandomCert $network_id $height $invalid_private_key
    assert_failure
    assert_output --regexp "-10002 Rollup signature verification failed"

    status=0
    output=""
    # Random Cert using valid private key but wrong global index
    run sendRandomCert $network_id $height $valid_private_key "--random-global-index"
    assert_failure
    assert_output --regexp "-10002 Rollup signature verification failed" # TODO: This should return "invalid global index" or something like that. Not implemented yet in AggLayer

    status=0
    output=""
    # Random Cert using valid private key but invalid height. Cert should never be settled
    run sendRandomCert $network_id $height $valid_private_key
    # echo "Captured Exit Code: $status"
    # echo "Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "Error: Timed out waiting for certificate with hash 0x[a-fA-F0-9]{64}"

    status=0
    output=""
    # Random Cert using valid private key but there is already a cert with the same height.
    # Cert should be rejected.
    run sendRandomCert $network_id $height $valid_private_key
    # echo "2 Captured Exit Code: $status"
    # echo "2 Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "-32602 Invalid argument: Unable to replace a pending certificate that is not in error"

    status=0
    output=""
    # Random Cert using valid private key that tries to fill the gap in cert height.
    # This should be possible to recover from previous situation
    new_height=$((height - 100))
    run sendRandomCert $network_id $new_height $valid_private_key
    # echo "3 Captured Exit Code: $status"
    # echo "3 Captured Exit Message: $output"
    assert_failure
    assert_output --regexp "-32603 Internal error: Invalid certificate candidate for network 2: [0-9]+ wasn't expected, current height [0-9]+"
}

function sendRandomCert() {
    local netID="$1"
    local height="$2"
    local private_key="$3"
    local extra_params=$4
    spammer_output=$(agglayer-certificate-spammer random-certs --url $(kurtosis port print cdk agglayer agglayer) --private-key $private_key --valid-signature --network-id $netID --height "$height" $extra_params 2>&1)
    if [[ $status -ne 0 ]]; then
        echo "Error: Failed to send Certificate. Output: $spammer_output"
        return 1
    fi
    echo "Spammer Output: $spammer_output"
    cert_hash=$(extract_certificate_hash "$spammer_output")
    if [[ -z "$cert_hash" ]] ; then
       echo "Error: Failed to extract the certificate hash."
       return 1
    fi
    echo $cert_hash
    local timeout=180
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
            elif [[ $status == "Candidate" ]]; then
                echo "Certificate with hash $cert_hash is candidate"
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

# bats test_tags=agglayer-cert-test
@test "Agglayer valid cert test" {
    # Create db folder and set ENV
    mkdir -p "cdk-databases"
    source ./scripts/set-valid-cert-spammer-env.sh

    ## Send L1 Bridge
    local amount_l1="1000000000000000000"
    local amount_l2="1"
    local l2_private_key="0xdfd01798f92667dbf91df722434e8fbe96af0211d4d1b82bbbbc8f1def7a814f"
    local l1_private_key="0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181"
    local dest_address="0xc949254d682d8c9ad5682521675b8f43b102aec4"
    readonly bridge_sig='bridgeAsset(uint32,address,uint256,address,bool,bytes)'
    cast send --legacy --private-key $l1_private_key --value $amount_l1 --rpc-url $CDK_ETHERMAN_URL $L1_Bridge_ADDR $bridge_sig $CDK_COMMON_NETWORKID $dest_address $amount_l1 $(cast az) true "0x"
    
    ## Wait for the bridge to be claimed by the bridge service
    sleep 60

    ## Send L2 Bridge
    local l1_net_id=0
    cast send --legacy --private-key $l2_private_key --value $amount_l2 --rpc-url $CDK_AGGSENDER_URLRPCL2 $CDK_BRIDGEL2SYNC_BRIDGEADDR $bridge_sig $l1_net_id $dest_address $amount_l2 $(cast az) true "0x"

    ## Run valid cert generator
    run validCert
    # echo "Captured Exit Code: $status"
    # echo "Captured Exit Message: $output"
    assert_failure
    rm -r cdk-databases
}

function validCert() {
    spammer_output=$(agglayer-certificate-spammer valid-certs --add-fake-bridge --store-certificate --single-cert 2>&1)
    if [[ $status -ne 0 ]]; then
        echo "Error: Failed to send Certificate. Output: $spammer_output"
        return 1
    fi
    cert_hash=$(extract_certificate_hash "$spammer_output")
    if [[ -z "$cert_hash" ]] ; then
       echo "Error: Failed to extract the certificate hash."
       return 1
    fi
    local timeout=180
    run wait_for_cert $cert_hash $timeout
    if [[ $status == 0 ]]; then
        echo "Cert successfully settled: \n$output"
        return 0
    else
        echo "error waiting for cert to be settled: \n $output"
        return 1
    fi
}
