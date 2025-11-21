#!/usr/bin/env bats
# bats file_tags=foo

setup_file() {
    # shellcheck source=core/helpers/common.bash
    source "$BATS_TEST_DIRNAME/../core/helpers/common.bash"
    _setup_vars
}

@test "foo" {
    echo "foo"
}