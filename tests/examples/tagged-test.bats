#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=tagged

# bats test_tags=light,examples
@test "Test light" {
    echo "🚀 Running Go test (Light)..."
    cd "$PROJECT_ROOT/core/golang"
    run go test -v -count=1 -race -p 1 ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}

# bats test_tags=heavy,examples
@test "Test heavy" {
    echo "🚀 Running Go test (Heavy)..."
    cd "$PROJECT_ROOT/core/golang"
    run go test -v -count=1 -race -p 1 ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}

# bats test_tags=danger,examples
@test "Test danger" {
    echo "🚀 Running Go test (Danger)..."
    cd "$PROJECT_ROOT/core/golang"
    run go test -v -count=1 -race -p 1 ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}
