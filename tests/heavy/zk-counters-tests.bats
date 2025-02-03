setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

@test "Test zkCounters" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    
    echo "Running go test to check zkCounters...."
    cd $PROJECT_ROOT/core/go
    run go test ./tests/zk_counters_test.go -run TestZkCounters -v
    assert_success
}
