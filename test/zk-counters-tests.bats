setup() {
    load 'helpers/common-setup'
    _common_setup
}

@test "Test zkCounters" {
    echo "Running go test to check zkCounters...."
    go test $TEST_DIR/zk_counters_test.go -run TestZkCounters -v
    assert_success
}
