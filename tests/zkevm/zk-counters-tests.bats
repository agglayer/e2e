#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=heavy,zk-counters,el:cdk-erigon
@test "Test zkCounters" {
    echo "🚀 Running Go test for zkCounters..."

    # ✅ Run the Go test
    cd "$PROJECT_ROOT/core/golang"
    run go test -v -count=1 -race -p 1 ./tests/zk_counters_test.go -run TestZkCounters 
    assert_success
}
