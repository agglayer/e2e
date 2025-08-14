#!/usr/bin/env bats
# bats file_tags=op

setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}
    chain_id=${CHAIN_ID:-"2151908"}
    working_directory="/tmp"

    # List from https://ethereum.org/en/history/ and https://docs.optimism.io/operators/node-operators/network-upgrades
    required_forks=(
        "homesteadBlock"
        "byzantiumBlock"
        "constantinopleBlock"
        "petersburgBlock"
        "istanbulBlock"
        "muirGlacierBlock"
        "berlinBlock"
        "arrowGlacierBlock"
        "grayGlacierBlock"
        "shanghaiTime"
        "cancunTime"
        "pragueTime"
        "bedrockBlock"
        "regolithTime"
        "canyonTime"
        "ecotoneTime"
        "fjordTime"
        "graniteTime"
        "holoceneTime"
        "isthmusTime"
    )
}


@test "Check L2 supported forks" {
    op_el_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep op-el-1-op-geth-op-node-001 | awk '{print $1}')
    op_el_container_name=op-el-1-op-geth-op-node-001--$op_el_uuid

    docker cp $op_el_container_name:/network-configs/genesis-$chain_id.json $working_directory/genesis-$chain_id.json
    jq -r ".config" $working_directory/genesis-$chain_id.json > $working_directory/supported-forks-$chain_id.json

    echo "=== Genesis configuration ===" >&3
    cat $working_directory/supported-forks-$chain_id.json >&3
    echo "" >&3
    
    # Check if all required forks are present
    echo "=== Checking required hardforks ===" >&3
    missing_forks=()
    
    for fork in "${required_forks[@]}"; do
        if jq -e "has(\"$fork\")" $working_directory/supported-forks-$chain_id.json > /dev/null; then
            echo "✅ $fork: ACTIVATED" >&3
        else
            echo "❌ $fork: MISSING" >&3
            missing_forks+=("$fork")
        fi
    done
    
    # Fail the test if any required forks are missing
    if [[ ${#missing_forks[@]} -gt 0 ]]; then
        echo "" >&3
        echo "ERROR: Missing required hardforks: ${missing_forks[*]}" >&3
        exit 1
    fi
    
    echo "" >&3
    echo "✅ All required hardforks are present" >&3
}