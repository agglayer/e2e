setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup"
    _common_setup
}

# bats test_tags=light,batch-verification
@test "Verify batches" {
    # ✅ Validate required ENV vars
    if [[ -z "${L2_RPC_URL:-}" || -z "${L2_SENDER_PRIVATE_KEY:-}" ]]; then
        echo "❌ ERROR: Required ENV vars missing! Ensure L2_RPC_URL and L2_SENDER_PRIVATE_KEY are set."
        exit 1
    fi

    # ✅ Ensure `cast` is installed
    if ! command -v cast &> /dev/null; then
        echo "❌ ERROR: Foundry `cast` not installed. Install with: curl -L https://foundry.paradigm.xyz | bash"
        exit 1
    fi

    # Set test parameters
    verified_batches_target=0
    timeout=600  # 10 minutes

    start_time=$(date +%s)
    end_time=$((start_time + timeout))

    echo "📡 Using L2_RPC_URL: $L2_RPC_URL"
    echo "🔑 Using L2_SENDER_PRIVATE_KEY: (hidden for security)"

    while true; do
        # ✅ Get the verified batch count
        verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_verifiedBatchNumber | sed 's/"//g')")"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

        # ✅ Trigger a transaction to push the network forward
        run cast send \
            --legacy \
            --rpc-url "$L2_RPC_URL" \
            --private-key "$L2_SENDER_PRIVATE_KEY" \
            --gas-limit 100_000 \
            --create 0x600160015B810190630000000456

        assert_success  # ✅ Ensure transaction was sent successfully

        current_time=$(date +%s)
        if ((current_time > end_time)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
            return 1  # ✅ Use `return 1` for failure
        fi

        if ((verified_batches > verified_batches_target)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... $verified_batches batches were verified!"
            return 0  # ✅ Mark test as successful
        fi

        sleep 10
    done
}
