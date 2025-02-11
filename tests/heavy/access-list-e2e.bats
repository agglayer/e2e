#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/common.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    # ✅ Kurtosis service variables
    export erigon_sequencer_node=${KURTOSIS_ERIGON_SEQUENCER:-cdk-erigon-sequencer-001}
    export kurtosis_sequencer_wrapper=${KURTOSIS_SEQUENCER_WRAPPER:-"kurtosis service exec $enclave $erigon_sequencer_node"}
    export data_dir=${ACL_DATA_DIR:-"/home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls"}
    export receiver=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
}

teardown() {
    run set_acl_mode "disabled"
}

# ✅ Helper function: Add address to ACL dynamically
add_to_access_list() {
    local acl_type="$1"
    local policy="$2"
    local sender=$(cast wallet address "$private_key")

    run $kurtosis_sequencer_wrapper "acl add --datadir $data_dir --address $sender --type $acl_type --policy $policy"
}

# ✅ Helper function: Set ACL mode dynamically
set_acl_mode() {
    local mode="$1"
    run $kurtosis_sequencer_wrapper "acl mode --datadir $data_dir --mode $mode"
}

# bats test_tags=light,access-list
@test "Test Block List - Sending regular transaction when address not in block list" {
    local value="10ether"
    run set_acl_mode "blocklist"
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$value"

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

# bats test_tags=light,access-list
@test "Test Block List - Sending contract deploy transaction when address not in block list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"
    run set_acl_mode "blocklist"
    run deploy_contract "$l2_rpc_url" "$private_key" "$contract_artifact"

    assert_success
    contract_addr=$(echo "$output" | tail -n 1)
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}

# bats test_tags=light,access-list
@test "Test Block List - Sending regular transaction when address is in block list" {
    local value="10ether"

    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "sendTx"
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$value"

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

# bats test_tags=light,access-list
@test "Test Block List - Sending contract deploy transaction when address is in block list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "deploy"
    run deploy_contract "$l2_rpc_url" "$private_key" "$contract_artifact"

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

# bats test_tags=light,access-list
@test "Test Allow List - Sending regular transaction when address not in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$value"

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

# bats test_tags=light,access-list
@test "Test Allow List - Sending contract deploy transaction when address not in allow list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "allowlist"
    run deploy_contract "$l2_rpc_url" "$private_key" "$contract_artifact"

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

# bats test_tags=light,access-list
@test "Test Allow List - Sending regular transaction when address is in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "sendTx"
    run send_tx "$l2_rpc_url" "$private_key" "$receiver" "$value"

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

# bats test_tags=light,access-list
@test "Test Allow List - Sending contract deploy transaction when address is in allow list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "deploy"
    run deploy_contract "$l2_rpc_url" "$private_key" "$contract_artifact"

    assert_success
    contract_addr=$(echo "$output" | tail -n 1)
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}
