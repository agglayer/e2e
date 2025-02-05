setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

@test "Test env var" {
    [ "${KURTOSIS_ENCLAVE}" == "cdk" ]
}