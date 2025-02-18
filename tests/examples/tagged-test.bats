#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    # ✅ Ensure RPC URL is available
    export L2_RPC_URL="${L2_RPC_URL:-http://127.0.0.1:53998}"

    # ✅ Set Go test file dynamically (allows overriding)
    export GO_TEST_FILE="${GO_TEST_FILE:-./tests/tagged_test.go}"
}

# bats test_tags=light,examples
@test "Test light" {
    echo "🚀 Running Go test (Light)..."
    pushd "$PROJECT_ROOT/core/golang" > /dev/null
    run go test -v -count=1 -race -p 1 "$GO_TEST_FILE" -run "(TestSuccess)" -v
    popd > /dev/null
    assert_success
}

# bats test_tags=heavy,examples
@test "Test heavy" {
    echo "🚀 Running Go test (Heavy)..."
    pushd "$PROJECT_ROOT/core/golang" > /dev/null
    run go test -v -count=1 -race -p 1 "$GO_TEST_FILE" -run "(TestSuccess)" -v
    popd > /dev/null
    assert_success
}

# bats test_tags=danger,examples
@test "Test danger" {
    echo "🚀 Running Go test (Danger)..."
    pushd "$PROJECT_ROOT/core/golang" > /dev/null
    run go test -v -count=1 -race -p 1 "$GO_TEST_FILE" -run "(TestSuccess)" -v
    popd > /dev/null
    assert_success
}
