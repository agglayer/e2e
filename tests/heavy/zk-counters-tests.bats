#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=heavy,zk-counters
@test "Test zkCounters" {
    echo "🚀 Running Go test for zkCounters..."

    # ✅ Run the Go test
    cd "$PROJECT_ROOT/core/go"
    run go test ./tests/zk_counters_test.go -run TestZkCounters -v
    assert_success
}
