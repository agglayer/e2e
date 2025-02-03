setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

@test "Test TAGS" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    
    echo "Running go test accordingly to tags..."
    run go test $PROJECT_ROOT/core/GO/tagged_test.go -v
    assert_success
}
