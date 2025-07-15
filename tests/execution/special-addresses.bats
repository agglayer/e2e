#!/usr/bin/env bats

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    # source existing helper functions for ephemeral account setup
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}


@test "Call special addresses" {
    local ephemeral_data=$(_generate_ephemeral_account "1")
    local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
    local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
    
    echo "ephemeral_address: $ephemeral_address" >&3
    # Fund the ephemeral account using imported function
    _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000"
    
    nonce=$(cast nonce --rpc-url "$l2_rpc_url" $ephemeral_address)
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000000" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000001" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000002" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000003" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000004" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000005" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000006" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000007" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000008" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x0000000000000000000000000000000000000009" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x000000000000000000000000000000000000000A" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x4D1A2e2bB4F88F0250f26Ffff098B0b30B26BF38" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0xdeadbeef00000000000000000000000000000000" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0xB928f69Bb1D91Cd65274e3c79d8986362984fDA3" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0xD04116cDd17beBE565EB2422F2497E06cC1C9833" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x70f2b2914A2a4b783FaEFb75f459A580616Fcb5e" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x60f3f640a8508fC6a86d45DF051962668E1e8AC7" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x1d8bfDC5D46DC4f61D6b6115972536eBE6A8854C" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0xE33C0C7F7df4809055C3ebA6c09CFe4BaF1BD9e0" >> well-known-addresses.out
    nonce=$((nonce + 1))
    cast send --async --nonce $nonce --legacy --from "$ephemeral_address" --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --gas-limit 100000 --value 2 --json "0x000000000000000000000000000000005ca1ab1e" >> well-known-addresses.out
}
