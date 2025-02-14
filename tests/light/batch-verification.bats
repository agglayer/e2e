#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=light,batch-verification,el:cdk-erigon
@test "Verify batches" {
    # ✅ Validate required dependencies
    if ! command -v cast &> /dev/null; then
        echo "❌ ERROR: Foundry `cast` not installed. Install with: curl -L https://foundry.paradigm.xyz | bash"
        exit 1
    fi

    # ✅ Set test parameters
    verified_batches_target=0
    timeout=600  # 10 minutes
    start_time=$(date +%s)
    end_time=$((start_time + timeout))

    echo "📡 Using L2_RPC_URL: $l2_rpc_url"
    echo "🔑 Using Private Key: (hidden for security)"

    while true; do
        # ✅ Get the verified batch count
        verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$l2_rpc_url" zkevm_verifiedBatchNumber | sed 's/"//g')")"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

        # ✅ Trigger a transaction to push the network forward
        run cast send \
            --legacy \
            --rpc-url "$l2_rpc_url" \
            --private-key "$private_key" \
            --gas-limit 100_000 \
            --create 0x600160015B810190630000000456

        assert_success  # ✅ Ensure transaction was sent successfully

        # ✅ Check timeouts and batch verification progress
        current_time=$(date +%s)
        if ((current_time > end_time)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
            return 1  # ✅ Test fails on timeout
        fi

        if ((verified_batches > verified_batches_target)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... $verified_batches batches were verified!"
            return 0  # ✅ Test succeeds
        fi

        sleep 10
    done
}
