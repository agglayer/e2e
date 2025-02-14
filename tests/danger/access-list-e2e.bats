#!/usr/bin/env bats

setup() {
    load "$PROJECT_ROOT/core/helpers/common-setup.bash"
    load "$PROJECT_ROOT/core/helpers/common.bash"
    _common_setup  # ✅ Standardized setup (wallet, funding, RPC, etc.)

    # ✅ Standardized Kurtosis service variables
    export ERIGON_SEQUENCER_NODE=${KURTOSIS_ERIGON_SEQUENCER:-cdk-erigon-sequencer-001}
    export KURTOSIS_SEQUENCER_WRAPPER=${KURTOSIS_SEQUENCER_WRAPPER:-"kurtosis service exec $ENCLAVE $ERIGON_SEQUENCER_NODE"}
    export DATA_DIR=${ACL_DATA_DIR:-"/home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls"}
    export RECEIVER=${RECEIVER:-"0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6"}
}

teardown() {
    run set_acl_mode "disabled"
}

# ✅ Helper function: Add address to ACL dynamically
add_to_access_list() {
    local acl_type="$1"
    local policy="$2"
    local sender
    sender=$(cast wallet address "$PRIVATE_KEY")

    echo "🔒 Adding $sender to ACL ($acl_type, $policy)"
    run $KURTOSIS_SEQUENCER_WRAPPER "acl add --datadir $DATA_DIR --address $sender --type $acl_type --policy $policy"
}

# ✅ Helper function: Set ACL mode dynamically
set_acl_mode() {
    local mode="$1"
    echo "🔄 Setting ACL mode: $mode"
    run $KURTOSIS_SEQUENCER_WRAPPER "acl mode --datadir $DATA_DIR --mode $mode"
}

# bats test_tags=danger,access-list
@test "Test Block List - Sending regular transaction when address not in block list" {
    local value="10ether"
    
    run set_acl_mode "blocklist"
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$value"

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

# bats test_tags=danger,access-list
@test "Test Block List - Sending contract deploy transaction when address not in block list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "blocklist"
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"

    assert_success
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}

# bats test_tags=danger,access-list
@test "Test Block List - Sending regular transaction when address is in block list" {
    local value="10ether"

    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "sendTx"
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$value"

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

# bats test_tags=danger,access-list
@test "Test Block List - Sending contract deploy transaction when address is in block list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "blocklist"
    run add_to_access_list "blocklist" "deploy"
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

# bats test_tags=danger,access-list
@test "Test Allow List - Sending regular transaction when address not in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$value"

    assert_failure
    assert_output --partial "sender disallowed to send tx by ACL policy"
}

# bats test_tags=danger,access-list
@test "Test Allow List - Sending contract deploy transaction when address not in allow list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "allowlist"
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"

    assert_failure
    assert_output --partial "sender disallowed to deploy contract by ACL policy"
}

# bats test_tags=danger,access-list
@test "Test Allow List - Sending regular transaction when address is in allow list" {
    local value="10ether"

    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "sendTx"
    run send_tx "$L2_RPC_URL" "$PRIVATE_KEY" "$RECEIVER" "$value"

    assert_success
    assert_output --regexp "Transaction successful \(transaction hash: 0x[a-fA-F0-9]{64}\)"
}

# bats test_tags=danger,access-list
@test "Test Allow List - Sending contract deploy transaction when address is in allow list" {
    local contract_artifact="./core/contracts/erc20mock/ERC20Mock.json"

    run set_acl_mode "allowlist"
    run add_to_access_list "allowlist" "deploy"
    run deploy_contract "$L2_RPC_URL" "$PRIVATE_KEY" "$contract_artifact"

    assert_success
    assert_output --regexp "0x[a-fA-F0-9]{40}"
}
