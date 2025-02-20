setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup

    # Load ENV variables
    export CDK_NETWORKCONFIG_L1_L1CHAINID
    CDK_NETWORKCONFIG_L1_L1CHAINID=$(cast chain-id --rpc-url "$(kurtosis port print cdk el-1-geth-lighthouse rpc)")

    export CDK_NETWORKCONFIG_L1_GLOBALEXITROOTMANAGERADDR
    CDK_NETWORKCONFIG_L1_GLOBALEXITROOTMANAGERADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | jq -r '.polygonZkEVMGlobalExitRootAddress')

    export CDK_NETWORKCONFIG_L1_ROLLUPMANAGERADDR
    CDK_NETWORKCONFIG_L1_ROLLUPMANAGERADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | jq -r '.polygonRollupManagerAddress')

    export CDK_NETWORKCONFIG_L1_POLADDR
    CDK_NETWORKCONFIG_L1_POLADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | jq -r '.polTokenAddress')

    export CDK_NETWORKCONFIG_L1_ZKEVMADDR
    CDK_NETWORKCONFIG_L1_ZKEVMADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm-contracts/sovereign-rollup-out.json' | jq -r '.sovereignRollupContract')

    export CDK_ETHERMAN_URL
    CDK_ETHERMAN_URL="http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"

    export CDK_ETHERMAN_ETHERMANCONFIG_URL="$CDK_ETHERMAN_URL"
    export CDK_ETHERMAN_ETHERMANCONFIG_L1CHAINID="$CDK_NETWORKCONFIG_L1_L1CHAINID"

    export CDK_COMMON_NETWORKID=2
    export CDK_COMMON_ISVALIDIUMMODE=false
    export CDK_COMMON_CONTRACTVERSIONS="banana"
    export CDK_LOG_LEVEL="debug"

    # Database paths
    export CDK_REORGDETECTORL1_DBPATH="./cdk-databases/reorgdetectorl1.sqlite"
    export CDK_REORGDETECTORL2_DBPATH="./cdk-databases/reorgdetectorl2.sqlite"
    export CDK_BRIDGEL2SYNC_DBPATH="./cdk-databases/bridgel2sync.sqlite"

    export CDK_BRIDGEL2SYNC_BRIDGEADDR
    CDK_BRIDGEL2SYNC_BRIDGEADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm-contracts/sovereign-rollup-out.json' | jq -r '.bridge_proxy_addr')

    export CDK_L1INFOTREESYNC_DBPATH="./cdk-databases/L1InfoTreeSync.sqlite"
    export CDK_L1INFOTREESYNC_GLOBALEXITROOTADDR="$CDK_NETWORKCONFIG_L1_GLOBALEXITROOTMANAGERADDR"
    export CDK_L1INFOTREESYNC_ROLLUPMANAGERADDR="$CDK_NETWORKCONFIG_L1_ROLLUPMANAGERADDR"
    export CDK_L1INFOTREESYNC_URLRPCL1="$CDK_ETHERMAN_URL"
    export CDK_L1INFOTREESYNC_INITIALBLOCK=0

    export CDK_AGGSENDER_STORAGEPATH="./cdk-databases/aggsender.sqlite"
    export CDK_AGGSENDER_AGGLAYERURL
    CDK_AGGSENDER_AGGLAYERURL=$(kurtosis port print cdk agglayer agglayer)

    export CDK_AGGSENDER_AGGSENDERPRIVATEKEY_PATH="./cdk-databases/sequencer.test.keystore"
    export CDK_AGGSENDER_AGGSENDERPRIVATEKEY_PASSWORD="testonly"

    export CDK_AGGSENDER_URLRPCL2
    CDK_AGGSENDER_URLRPCL2=$(kurtosis port print cdk op-el-1-op-geth-op-node-op-kurtosis rpc)

    export L1_Bridge_ADDR
    L1_Bridge_ADDR=$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | jq -r '.polygonZkEVMBridgeAddress')

    export SEQUENCER_PRIVATE_KEY="0x45f3ccdaff88ab1b3bb41472f09d5cde7cb20a6cbbc9197fddf64e2f3d67aaf2"

    echo "✅ ENV set successfully"
}

# bats test_tags=danger,agglayer-cert-test,cdk
@test "Agglayer valid cert test" {
    echo "🔧 Cleaning up previous databases..."
    rm -rf cdk-databases

    echo "📁 Creating necessary directories..."
    mkdir -p "cdk-databases"

    echo "🔑 Importing wallet..."
    cast wallet import --keystore-dir ./cdk-databases sequencer.test.keystore \
        --private-key "$SEQUENCER_PRIVATE_KEY" --unsafe-password "testonly"

    # Define amounts & private keys
    local amount_l1="1000000000000000000"
    local amount_l2="1"
    local l2_private_key="0xdfd01798f92667dbf91df722434e8fbe96af0211d4d1b82bbbbc8f1def7a814f"
    local l1_private_key="0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181"
    local dest_address="0xc949254d682d8c9ad5682521675b8f43b102aec4"
    local bridge_sig="bridgeAsset(uint32,address,uint256,address,bool,bytes)"

    echo "💰 Sending L1 Bridge transaction..."
    cast send --legacy --private-key "$l1_private_key" --value "$amount_l1" \
        --rpc-url "$CDK_ETHERMAN_URL" "$L1_Bridge_ADDR" \
        "$bridge_sig" "$CDK_COMMON_NETWORKID" "$dest_address" "$amount_l1" "$(cast az)" true "0x"

    echo "⏳ Waiting for L1 bridge to settle..."
    sleep 60

    echo "💰 Sending L2 Bridge transaction..."
    local l1_net_id=0
    cast send --legacy --private-key "$l2_private_key" --value "$amount_l2" \
        --rpc-url "$CDK_AGGSENDER_URLRPCL2" "$CDK_BRIDGEL2SYNC_BRIDGEADDR" \
        "$bridge_sig" "$l1_net_id" "$dest_address" "$amount_l2" "$(cast az)" true "0x"

    echo "✅ Running valid cert generator..."
    run validCert

    echo "🧹 Cleaning up test artifacts..."
    rm -rf cdk-databases

    assert_success
}

# bats test_tags=danger,agglayer-cert-fake-deposit-test,cdk
@test "Agglayer valid cert fake deposit test" {
    echo "🧹 Cleaning up previous databases..."
    rm -rf cdk-databases

    echo "📁 Creating necessary directories..."
    mkdir -p "cdk-databases"

    echo "🔑 Importing wallet..."
    cast wallet import --keystore-dir ./cdk-databases sequencer.test.keystore \
        --private-key "$SEQUENCER_PRIVATE_KEY" --unsafe-password "testonly"

    # Define amounts & private keys
    local amount_l1="1000000000000000000"
    local amount_l2="1"
    local l2_private_key="0xdfd01798f92667dbf91df722434e8fbe96af0211d4d1b82bbbbc8f1def7a814f"
    local l1_private_key="0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181"
    local dest_address="0xc949254d682d8c9ad5682521675b8f43b102aec4"
    local bridge_sig="bridgeAsset(uint32,address,uint256,address,bool,bytes)"

    echo "💰 Sending L1 Bridge transaction..."
    cast send --legacy --private-key "$l1_private_key" --value "$amount_l1" \
        --rpc-url "$CDK_ETHERMAN_URL" "$L1_Bridge_ADDR" \
        "$bridge_sig" "$CDK_COMMON_NETWORKID" "$dest_address" "$amount_l1" "$(cast az)" true "0x"

    echo "⏳ Waiting for L1 bridge to settle..."
    sleep 60

    echo "💰 Sending L2 Bridge transaction..."
    local l1_net_id=0
    cast send --legacy --private-key "$l2_private_key" --value "$amount_l2" \
        --rpc-url "$CDK_AGGSENDER_URLRPCL2" "$CDK_BRIDGEL2SYNC_BRIDGEADDR" \
        "$bridge_sig" "$l1_net_id" "$dest_address" "$amount_l2" "$(cast az)" true "0x"

    echo "✅ Running valid cert generator with fake bridge..."
    run validCert "--add-fake-bridge"
    
    assert_success

    echo "🧹 Cleaning up test artifacts..."
    rm -rf cdk-databases
}

# bats test_tags=danger,agglayer-random-cert-test,cdk
@test "Agglayer random cert test" {
    local network_id="2"
    local height="1004"
    local valid_private_key="0x45f3ccdaff88ab1b3bb41472f09d5cde7cb20a6cbbc9197fddf64e2f3d67aaf2"
    local invalid_private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

    echo "⚡ Sending Random Cert with invalid private key..."
    run sendRandomCert "$network_id" "$height" "$invalid_private_key"
    assert_failure
    assert_output --regexp "-10002 Rollup signature verification failed"

    echo "⚡ Sending Random Cert with valid private key but wrong global index..."
    run sendRandomCert "$network_id" "$height" "$valid_private_key" "--random-global-index"
    assert_failure
    assert_output --regexp "-10002 Rollup signature verification failed"

    echo "⚡ Sending Random Cert with valid private key but invalid height (should time out)..."
    run sendRandomCert "$network_id" "$height" "$valid_private_key"
    assert_failure
    assert_output --regexp "Error: Timed out waiting for certificate with hash 0x[a-fA-F0-9]{64}"

    echo "⚡ Sending Random Cert when a cert already exists at the same height (should be rejected)..."
    run sendRandomCert "$network_id" "$height" "$valid_private_key"
    assert_failure
    assert_output --regexp "-32602 Invalid argument: Unable to replace a pending certificate that is not in error"

    echo "⚡ Sending Random Cert to recover from previous situation (filling cert height gap)..."
    local new_height=$((height - 100))
    run sendRandomCert "$network_id" "$new_height" "$valid_private_key"
    assert_failure
    assert_output --regexp "-32603 Internal error: Invalid certificate candidate for network 2: [0-9]+ wasn't expected, current height [0-9]+"
}

function sendRandomCert() {
    local netID="$1"
    local height="$2"
    local private_key="$3"
    local extra_params="$4"

    echo "⚡ Sending Random Cert..."
    local spammer_output
    if ! spammer_output=$(agglayer-certificate-spammer random-certs \
        --url "$(kurtosis port print cdk agglayer agglayer)" \
        --private-key "$private_key" \
        --valid-signature \
        --network-id "$netID" \
        --height "$height" \
        "$extra_params" 2>&1); then
        echo "❌ Error: Failed to send Certificate. Output: $spammer_output"
        return 1
    fi

    echo "✅ Spammer Output: $spammer_output"
    local cert_hash
    cert_hash=$(extract_certificate_hash "$spammer_output")
    
    if [[ -z "$cert_hash" ]]; then
        echo "❌ Error: Failed to extract the certificate hash."
        return 1
    fi

    echo "🔄 Waiting for cert settlement: $cert_hash"
    local timeout=180
    local cert_output
    if ! cert_output=$(wait_for_cert "$cert_hash" "$timeout"); then
        echo "❌ Error: Cert settlement failed. Output: $cert_output"
        return 1
    fi

    echo "✅ Cert successfully settled"
    return 0
}



function extract_certificate_hash() {
    local spammer_output="$1"
    echo "$spammer_output" | grep 'Certificate sent with hash:' | awk '{print $8}' | tail -n 1
}

function wait_for_cert() {
    local cert_hash="$1"
    local timeout="$2"
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    while true; do
        if [[ $(date +%s) -gt $end_time ]]; then
            echo "❌ Error: Timed out waiting for certificate with hash $cert_hash"
            return 1
        fi

        local response
        response=$(curl --silent --location --request POST "$(kurtosis port print cdk agglayer agglayer)" \
            --header 'Content-Type: application/json' \
            --data-raw '{
                "jsonrpc": "2.0",
                "method": "interop_getCertificateHeader",
                "params": ["'"$cert_hash"'"],
                "id": 1
            }')

        local status
        status=$(echo "$response" | jq -r '.result.status')

        if [[ -n "$status" ]]; then
            case "$status" in
                "Pending")   echo "⏳ Certificate $cert_hash is pending..." ;;
                "Candidate") echo "🔄 Certificate $cert_hash is a candidate..." ;;
                "Settled")   
                    echo "✅ Certificate $cert_hash has been settled."
                    return 0
                    ;;
                *)
                    echo "❌ Error: Certificate $cert_hash is in an unknown state: $status"
                    return 1
                    ;;
            esac
        fi

        sleep 1
    done
}

function validCert() {
    local extra_param="$1"

    echo "⚡ Sending valid cert..."
    local spammer_output
    if ! spammer_output=$(agglayer-certificate-spammer valid-certs \
        --store-certificate \
        --single-cert \
        "$extra_param" 2>&1); then
        echo "❌ Error: Failed to send Certificate. Output: $spammer_output"
        return 1
    fi

    echo "✅ Spammer Output: $spammer_output"
    local cert_hash
    cert_hash=$(extract_certificate_hash "$spammer_output")

    if [[ -z "$cert_hash" ]]; then
        echo "❌ Error: Failed to extract the certificate hash."
        return 1
    fi

    echo "🔄 Waiting for cert settlement: $cert_hash"
    local timeout=180
    local cert_output
    if ! cert_output=$(wait_for_cert "$cert_hash" "$timeout"); then
        echo "❌ Error waiting for cert settlement. Output: $cert_output"
        return 1
    fi

    echo "✅ Cert successfully settled. Output: $cert_output"
    return 0
}

