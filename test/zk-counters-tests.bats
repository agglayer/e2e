setup() {
    load 'helpers/common-setup'
    _common_setup
}

@test "Test zkCounters" {
    echo "Running go test to check zkCounters...."
    run go test $PROJECT_ROOT/test/zk_counters_test.go -run TestZkCounters -v
    assert_success
}
