setup() {
    load 'helpers/common-setup'
    _common_setup
}

@test "Verify batches" {
    echo "Starting batch verification monitoring for 10 minutes..."

    # Run the batch verification monitor script directly to stream logs
    $PROJECT_ROOT/bats-scripts/batch_verification_monitor.sh 0 600 2>&1

    # Assert the script completed successfully (this will only run if the script exits 0)
    [[ $? -eq 0 ]] || fail "Batch verification did not complete successfully"
}
