setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats test_tags=heavy,zk-counters
@test "Test zkCounters" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi
    
    echo "Running go test to check zkCounters...."
    cd $PROJECT_ROOT/core/golang
    run go test -v -count=1 -race -p 1 ./tests/zk_counters_test.go -run TestZkCounters 
    assert_success
}
