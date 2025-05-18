setup() {
    load '../../core/helpers/common-setup'
    _common_setup

    readonly erigon_sequencer_node=${KURTOSIS_ERIGON_SEQUENCER:-cdk-erigon-sequencer-001}
    readonly kurtosis_sequencer_wrapper=${KURTOSIS_SEQUENCER_WRAPPER:-"kurtosis service exec $ENCLAVE $erigon_sequencer_node"}
    readonly data_dir=${ACL_DATA_DIR:-"/home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls"}
}

teardown() {
    run set_acl_mode "disabled"
}

# Helper function to add address to acl dynamically
add_to_access_list() {
    local acl_type="$1"
    local policy="$2"
    local sender=$(cast wallet address "$sender_private_key")

    run $kurtosis_sequencer_wrapper "acl add --datadir $data_dir --address $sender --type $acl_type --policy $policy"
}

# Helper function to set the acl mode command dynamically
set_acl_mode() {
    local mode="$1"

    run $kurtosis_sequencer_wrapper "acl mode --datadir $data_dir --mode $mode"
}

@test "Test Block List - Sending regular transaction when address not in block list" {
    local value="10ether"
    run set_acl_mode "blocklist"
    run send_tx $L2_RPC_URL $sender_private_key $receiver $value

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

@test "Test Block List - Sending contracts deploy transaction when address not in block list" {
    run set_acl_mode "blocklist"
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path

    assert_success

    contract_addr=$(echo "$output" | tail -n 1)
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}

@test "Test Block List - Sending regular transaction when address is in block list" {
    local value="10ether"

    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "sendTx"

    run send_tx $L2_RPC_URL $sender_private_key $receiver $value

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

@test "Test Block List - Sending contracts deploy transaction when address is in block list" {
    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "deploy"
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

@test "Test Allow List - Sending regular transaction when address not in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run send_tx $L2_RPC_URL $sender_private_key $receiver $value

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

@test "Test Allow List - Sending contracts deploy transaction when address not in allow list" {
    run set_acl_mode "allowlist"
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

@test "Test Allow List - Sending regular transaction when address is in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "sendTx"
    run send_tx $L2_RPC_URL $sender_private_key $receiver $value

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

@test "Test Allow List - Sending contracts deploy transaction when address is in allow list" {
    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "deploy"
    run deploy_contract $L2_RPC_URL $sender_private_key $erc20_artifact_path

    assert_success

    contract_addr=$(echo "$output" | tail -n 1)
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}
