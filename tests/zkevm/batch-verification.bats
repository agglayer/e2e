#!/usr/bin/env bats
# bats file_tags=zkevm

setup() {
    load "$PROJECT_ROOT/core/helpers/agglayer-cdk-common-setup.bash"
    _agglayer_cdk_common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)
}

# bats file_tags=light,batch-verification,el:cdk-erigon
@test "Verify batches" {
    # ✅ Ensure Foundry's `cast` is available
    if ! command -v cast &> /dev/null; then
        echo "❌ ERROR: Foundry $(cast) not installed. Install with: curl -L https://foundry.paradigm.xyz | bash"
        exit 1
    fi

    # ✅ Test Parameters
    local VERIFIED_BATCHES_TARGET=0
    local TIMEOUT=600  # 10 minutes
    local START_TIME
    local END_TIME
    local CURRENT_TIME

    START_TIME=$(date +%s)
    END_TIME=$((START_TIME + TIMEOUT))

    echo "📡 Using L2_RPC_URL: $L2_RPC_URL"
    echo "🔑 Using Private Key: (hidden for security)"

    while true; do
        # ✅ Get the verified batch count
        local VERIFIED_BATCHES
        VERIFIED_BATCHES=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_verifiedBatchNumber | tr -d '"')

        # ✅ Check for errors
        if [[ -z "$VERIFIED_BATCHES" || "$VERIFIED_BATCHES" == "null" ]]; then
            echo "❌ ERROR: Failed to fetch batch number from RPC."
            return 1
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔢 Verified Batches: $VERIFIED_BATCHES"

        # ✅ Send a dummy transaction to advance the network
        echo "🚀 Sending dummy transaction to push batch verification forward..."
        run cast send \
            --legacy \
            --rpc-url "$L2_RPC_URL" \
            --private-key "$PRIVATE_KEY" \
            --gas-limit 100000 \
            --create 0x600160015B810190630000000456

        assert_success  # ✅ Ensure transaction was sent successfully

        # ✅ Timeout & Progress Check
        CURRENT_TIME=$(date +%s)
        if ((CURRENT_TIME > END_TIME)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⏳ ❌ Timeout reached! Exiting..."
            return 1  # ✅ Fail test if timeout occurs
        fi

        if ((VERIFIED_BATCHES > VERIFIED_BATCHES_TARGET)); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Success! $VERIFIED_BATCHES batches verified."
            return 0  # ✅ Test succeeds
        fi

        sleep 10  # 🕒 Wait before retrying
    done
}
