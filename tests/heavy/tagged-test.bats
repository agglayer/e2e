setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats test_tags=heavy,tagged-test
@test "Test TAGS" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    
    echo "Running go test accordingly to tags..."
    cd $PROJECT_ROOT/core/go
    run go test ./tests/tagged_test.go -run "(TestFail|TestUnchecked|TestUntagged)" -v
    assert_success
}
