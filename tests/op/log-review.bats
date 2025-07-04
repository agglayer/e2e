#!/usr/bin/env bats

# This test uses polycli dockerlogger to collect all logs of specified levels of specified services within a docker network.
# The collected logs are then matched against a pre-defined keyword filter to check for critical/known issues.
setup() {
    kurtosis_enclave_name=${ENCLAVE_NAME:-"op"}
    log_keyword_filter=${LOG_KEYWORD_FILTER:-"ERR|EROR|ERROR|FATAL|CRIT"}
    services_filter=${SERVICES_FILTER:-"agglayer,aggkit,op-proposer,succinct,prover"}
}

@test "Check for critical error logs" {
    # Run the command and capture output and status
    # Removing null bytes from the polycli dockerlogger output is essential for this test
    # timeout is essential because polycli dockerlogger is an ongoing process
    logs=$(timeout 1s polycli dockerlogger --network "kt-$kurtosis_enclave_name" --levels "error,fatal,crit" --service "$services_filter" | tr -d '\0')

    # Filter out non-text characters and check for error-related keywords
    if echo "$logs" | grep -E "$log_keyword_filter"; then
        echo "Expected no errors, but got: $logs" >&3
        exit 1
    else
        echo "No error keywords '$log_keyword_filter' were found in kt-$kurtosis_enclave_name network" >&3
    fi
}