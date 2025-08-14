#!/usr/bin/env bats
# bats file_tags=cdk

setup() {
    load '../../core/helpers/agglayer-cdk-common-setup'
    _agglayer_cdk_common_setup
}

@test "Verify batches" {
    echo "Waiting 10 minutes to get some verified batch...."
    run $PROJECT_ROOT/core/helpers/scripts/batch_verification_monitor.sh 0 600
    assert_success
}
