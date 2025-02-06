setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats file_tags=tagged

# bats test_tags=light
@test "Test light" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi

    echo "Running go test accordingly to tags..."
    cd $PROJECT_ROOT/core/golang
    run go test ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}

# bats test_tags=heavy
@test "Test heavy" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi

    echo "Running go test accordingly to tags..."
    cd $PROJECT_ROOT/core/golang
    run go test ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}

# bats test_tags=danger
@test "Test danger" {
    # Ensure PROJECT_ROOT is correct
    if [[ "$PROJECT_ROOT" == *"/tests"* ]]; then
        echo "🚨 ERROR: PROJECT_ROOT is incorrect ($PROJECT_ROOT) – Auto-fixing..."
        PROJECT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
        export PROJECT_ROOT
        echo "✅ Fixed PROJECT_ROOT: $PROJECT_ROOT"
    fi

    echo "Running go test accordingly to tags..."
    cd $PROJECT_ROOT/core/golang
    run go test ./tests/tagged_test.go -run "(TestSuccess)" -v
    assert_success
}