setup() {
    load 'helpers/common-setup'
    _common_setup
}

@test "Test TAGS" {
    echo "Running go test accordingly to tags..."
    run go test $PROJECT_ROOT/test/tagged_test.go -v
    assert_success
}
