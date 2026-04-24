#!/usr/bin/env bats
# bats file_tags=pos

# pos-portal (PoS) bridge tests — see ./README.md for how Plasma relates to pos-portal.

setup() {
  load "../../../core/helpers/pos-setup.bash"
  load "../../../core/helpers/scripts/eventually.bash"
  load "../../../core/helpers/scripts/pos-bridge.bash"
  pos_setup

  bridge_amount=$(cast to-unit 1ether wei)
  timeout_seconds=${TIMEOUT_SECONDS:-"180"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
}

# Mint `amount` DummyERC20 to the deployer on L1. DummyERC20 exposes a public mint.
_mint_dummy_erc20() {
  local amount="$1"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC20}" "mint(uint256)" "${amount}"
}

##############################################################################
# ETH (Native L1) / MaticWETH
##############################################################################

# bats test_tags=bridge,transaction-eth
@test "bridge ETH from L1 to L2 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  initial_l1_eth=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_l2_weth=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_MATIC_WETH}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  echo "Initial L1 ETH: ${initial_l1_eth}"
  echo "Initial L2 MaticWETH: ${initial_l2_weth}"

  heimdall_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_count=$(eval "${bor_state_sync_count_cmd}")

  echo "Calling RootChainManager.depositEtherFor..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value "${bridge_amount}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositEtherFor(address)" "${address}"

  wait_for_state_sync_after_deposit "${heimdall_count}" "${bor_count}"

  echo "Monitoring L2 MaticWETH balance..."
  assert_token_balance_eventually_greater_or_equal "${L2_MATIC_WETH}" "${address}" "$(echo "${initial_l2_weth} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-eth
@test "withdraw ETH from L2 to L1 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Seed L2 MaticWETH if empty (bridge 1 ETH in first).
  l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_MATIC_WETH}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  if [[ "${l2_balance}" == "0" ]]; then
    hm=$(eval "${heimdall_state_sync_count_cmd}")
    bc_=$(eval "${bor_state_sync_count_cmd}")
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --value "${bridge_amount}" \
      "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositEtherFor(address)" "${address}"
    wait_for_state_sync_after_deposit "${hm}" "${bc_}"
  fi

  initial_l1_eth=$(cast balance --rpc-url "${L1_RPC_URL}" "${address}")
  initial_checkpoint=$(latest_checkpoint_id)

  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} MaticWETH on L2..."
  burn=$(cast send --rpc-url "${L2_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei --priority-gas-price 30gwei --gas-limit 200000 --json \
    "${L2_MATIC_WETH}" "withdraw(uint256)" "${withdraw_amount}")
  burn_tx=$(echo "${burn}" | jq --raw-output ".transactionHash")

  echo "Waiting for a new checkpoint on L1..."
  wait_for_new_checkpoint "${initial_checkpoint}"

  echo "Generating exit payload..."
  payload=$(generate_pos_exit_payload "${burn_tx}" 0 $((2 * timeout_seconds)))

  echo "Submitting exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "exit(bytes)" "${payload}"

  # EtherPredicate releases real ETH to the exitor on L1. Account for gas consumed by the exit tx.
  # Allow up to 0.01 ETH of gas overhead (matches plasma MaticWeth test tolerance).
  echo "Verifying L1 ETH balance increased by roughly withdraw_amount..."
  expected_min=$(echo "${initial_l1_eth} + ${withdraw_amount} - 10000000000000000" | bc)
  assert_ether_balance_eventually_greater_or_equal "${address}" "${expected_min}" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC20
##############################################################################

# bats test_tags=bridge,transaction-erc20
@test "bridge ERC20 from L1 to L2 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Ensure the deployer holds enough DummyERC20 to cover the deposit.
  _mint_dummy_erc20 "${bridge_amount}"

  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_DUMMY_ERC20}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_DUMMY_ERC20}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  echo "Initial L1 DummyERC20: ${initial_l1_balance}"
  echo "Initial L2 ChildERC20: ${initial_l2_balance}"

  heimdall_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_count=$(eval "${bor_state_sync_count_cmd}")

  echo "Approving ERC20Predicate to spend DummyERC20..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC20}" "approve(address,uint)" "${L1_ERC20_PORTAL_PREDICATE_PROXY}" "${bridge_amount}"

  echo "Calling RootChainManager.depositFor..."
  # depositData for ERC20 is abi.encode(amount) — a single uint256 word.
  deposit_data=$(cast abi-encode "f(uint256)" "${bridge_amount}")
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
    "${address}" "${L1_DUMMY_ERC20}" "${deposit_data}"

  wait_for_state_sync_after_deposit "${heimdall_count}" "${bor_count}"

  echo "Monitoring L1 DummyERC20 balance..."
  assert_token_balance_eventually_lower_or_equal "${L1_DUMMY_ERC20}" "${address}" "$(echo "${initial_l1_balance} - ${bridge_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"

  echo "Monitoring L2 ChildERC20 balance..."
  assert_token_balance_eventually_greater_or_equal "${L2_DUMMY_ERC20}" "${address}" "$(echo "${initial_l2_balance} + ${bridge_amount}" | bc)" "${L2_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-erc20
@test "withdraw ERC20 from L2 to L1 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")

  # Seed L2 balance if needed by running a deposit first. To keep this test self-contained
  # we assume a prior bridge test landed funds; fall back to a deposit if the L2 balance is 0.
  l2_balance=$(cast call --rpc-url "${L2_RPC_URL}" --json "${L2_DUMMY_ERC20}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  if [[ "${l2_balance}" == "0" ]]; then
    echo "L2 balance is 0, bridging in first..."
    _mint_dummy_erc20 "${bridge_amount}"
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
      "${L1_DUMMY_ERC20}" "approve(address,uint)" "${L1_ERC20_PORTAL_PREDICATE_PROXY}" "${bridge_amount}"
    hm=$(eval "${heimdall_state_sync_count_cmd}")
    bc_=$(eval "${bor_state_sync_count_cmd}")
    deposit_data=$(cast abi-encode "f(uint256)" "${bridge_amount}")
    cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
      "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
      "${address}" "${L1_DUMMY_ERC20}" "${deposit_data}"
    wait_for_state_sync_after_deposit "${hm}" "${bc_}"
  fi

  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_DUMMY_ERC20}" "balanceOf(address)(uint)" "${address}" | jq --raw-output '.[0]')
  initial_checkpoint=$(latest_checkpoint_id)

  withdraw_amount=$(cast to-unit 1ether wei)
  echo "Burning ${withdraw_amount} ChildERC20 on L2..."
  withdraw_receipt=$(cast send --rpc-url "${L2_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei --priority-gas-price 30gwei --gas-limit 200000 --json \
    "${L2_DUMMY_ERC20}" "withdraw(uint256)" "${withdraw_amount}")
  withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq --raw-output ".transactionHash")
  echo "Burn tx: ${withdraw_tx_hash}"

  echo "Waiting for a new checkpoint on L1..."
  wait_for_new_checkpoint "${initial_checkpoint}"

  echo "Generating exit payload..."
  # ChildERC20.withdraw emits only a Transfer event (to zero address) at log index 0.
  payload=$(generate_pos_exit_payload "${withdraw_tx_hash}" 0 $((2 * timeout_seconds)))

  echo "Submitting exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "exit(bytes)" "${payload}"

  echo "Verifying L1 DummyERC20 balance increased..."
  assert_token_balance_eventually_greater_or_equal "${L1_DUMMY_ERC20}" "${address}" \
    "$(echo "${initial_l1_balance} + ${withdraw_amount}" | bc)" "${L1_RPC_URL}" "${timeout_seconds}" "${interval_seconds}"
}

##############################################################################
# ERC721
##############################################################################

# bats test_tags=bridge,transaction-erc721
@test "bridge ERC721 from L1 to L2 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")
  # Use timestamp as tokenId to avoid collisions across reruns.
  token_id=$(( $(date +%s%N) ))

  echo "Minting DummyERC721 tokenId=${token_id}..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC721}" "mint(uint256)" "${token_id}"

  heimdall_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_count=$(eval "${bor_state_sync_count_cmd}")

  echo "Approving ERC721Predicate..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC721}" "approve(address,uint)" "${L1_ERC721_PORTAL_PREDICATE_PROXY}" "${token_id}"

  echo "Calling RootChainManager.depositFor for ERC721..."
  deposit_data=$(cast abi-encode "f(uint256)" "${token_id}")
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
    "${address}" "${L1_DUMMY_ERC721}" "${deposit_data}"

  wait_for_state_sync_after_deposit "${heimdall_count}" "${bor_count}"

  echo "Verifying tokenId on L2 ChildERC721..."
  want=$(echo "${address}" | tr "[:upper:]" "[:lower:]")
  got=$(cast call --rpc-url "${L2_RPC_URL}" "${L2_DUMMY_ERC721}" "ownerOf(uint256)(address)" "${token_id}" | tr "[:upper:]" "[:lower:]")
  [[ "${got}" == "${want}" ]] || { echo "Owner mismatch: got=${got} want=${want}"; exit 1; }
}

# bats test_tags=withdraw,transaction-erc721
@test "withdraw ERC721 from L2 to L1 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")
  token_id=$(( $(date +%s%N) ))

  echo "Seeding L2 with tokenId=${token_id}: mint on L1, bridge, then withdraw..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC721}" "mint(uint256)" "${token_id}"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC721}" "approve(address,uint)" "${L1_ERC721_PORTAL_PREDICATE_PROXY}" "${token_id}"
  hm=$(eval "${heimdall_state_sync_count_cmd}")
  bc_=$(eval "${bor_state_sync_count_cmd}")
  deposit_data=$(cast abi-encode "f(uint256)" "${token_id}")
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
    "${address}" "${L1_DUMMY_ERC721}" "${deposit_data}"
  wait_for_state_sync_after_deposit "${hm}" "${bc_}"

  initial_checkpoint=$(latest_checkpoint_id)

  echo "Burning ChildERC721 tokenId=${token_id} on L2..."
  burn=$(cast send --rpc-url "${L2_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei --priority-gas-price 30gwei --gas-limit 200000 --json \
    "${L2_DUMMY_ERC721}" "withdraw(uint256)" "${token_id}")
  burn_tx=$(echo "${burn}" | jq --raw-output ".transactionHash")

  echo "Waiting for a new checkpoint on L1..."
  wait_for_new_checkpoint "${initial_checkpoint}"

  echo "Generating exit payload..."
  # ChildERC721._burn emits Approval then Transfer, so the Transfer we exit on is log index 1.
  payload=$(generate_pos_exit_payload "${burn_tx}" 1 $((2 * timeout_seconds)))

  echo "Submitting exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "exit(bytes)" "${payload}"

  echo "Verifying L1 DummyERC721 ownership restored..."
  want=$(echo "${address}" | tr "[:upper:]" "[:lower:]")
  got=$(cast call --rpc-url "${L1_RPC_URL}" "${L1_DUMMY_ERC721}" "ownerOf(uint256)(address)" "${token_id}" | tr "[:upper:]" "[:lower:]")
  [[ "${got}" == "${want}" ]] || { echo "Owner mismatch: got=${got} want=${want}"; exit 1; }
}

##############################################################################
# ERC1155
##############################################################################

# bats test_tags=bridge,transaction-erc1155
@test "bridge ERC1155 from L1 to L2 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")
  # Fresh id per run so balances don't leak between runs.
  id=$(( $(date +%s%N) ))
  amount=100

  echo "Minting DummyERC1155 id=${id} amount=${amount}..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC1155}" "mint(address,uint256,uint256)" "${address}" "${id}" "${amount}"

  heimdall_count=$(eval "${heimdall_state_sync_count_cmd}")
  bor_count=$(eval "${bor_state_sync_count_cmd}")

  echo "setApprovalForAll on ERC1155Predicate..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC1155}" "setApprovalForAll(address,bool)" "${L1_ERC1155_PORTAL_PREDICATE_PROXY}" true

  echo "Calling RootChainManager.depositFor for ERC1155..."
  # depositData = abi.encode(uint256[] ids, uint256[] amounts, bytes data).
  deposit_data=$(cast abi-encode "f(uint256[],uint256[],bytes)" "[${id}]" "[${amount}]" "0x")
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
    "${address}" "${L1_DUMMY_ERC1155}" "${deposit_data}"

  wait_for_state_sync_after_deposit "${heimdall_count}" "${bor_count}"

  echo "Verifying L2 ChildERC1155 balance..."
  l2_balance_cmd='cast call --rpc-url "${L2_RPC_URL}" --json "${L2_DUMMY_ERC1155}" "balanceOf(address,uint256)(uint)" "'"${address}"'" "'"${id}"'" | jq -r ".[0]"'
  assert_command_eventually_greater_or_equal "${l2_balance_cmd}" "${amount}" "${timeout_seconds}" "${interval_seconds}"
}

# bats test_tags=withdraw,transaction-erc1155
@test "withdraw ERC1155 from L2 to L1 via pos bridge" {
  address=$(cast wallet address --private-key "${PRIVATE_KEY}")
  id=$(( $(date +%s%N) ))
  amount=100

  echo "Seeding L2 ERC1155 (id=${id}, amount=${amount}): mint, approve, bridge..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC1155}" "mint(address,uint256,uint256)" "${address}" "${id}" "${amount}"
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_DUMMY_ERC1155}" "setApprovalForAll(address,bool)" "${L1_ERC1155_PORTAL_PREDICATE_PROXY}" true
  hm=$(eval "${heimdall_state_sync_count_cmd}")
  bc_=$(eval "${bor_state_sync_count_cmd}")
  deposit_data=$(cast abi-encode "f(uint256[],uint256[],bytes)" "[${id}]" "[${amount}]" "0x")
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "depositFor(address,address,bytes)" \
    "${address}" "${L1_DUMMY_ERC1155}" "${deposit_data}"
  wait_for_state_sync_after_deposit "${hm}" "${bc_}"

  initial_l1_balance=$(cast call --rpc-url "${L1_RPC_URL}" --json "${L1_DUMMY_ERC1155}" "balanceOf(address,uint256)(uint)" "${address}" "${id}" | jq --raw-output '.[0]')
  initial_checkpoint=$(latest_checkpoint_id)

  echo "Burning ChildERC1155 on L2 via withdrawSingle..."
  burn=$(cast send --rpc-url "${L2_RPC_URL}" --private-key "${PRIVATE_KEY}" \
    --gas-price 30gwei --priority-gas-price 30gwei --gas-limit 200000 --json \
    "${L2_DUMMY_ERC1155}" "withdrawSingle(uint256,uint256)" "${id}" "${amount}")
  burn_tx=$(echo "${burn}" | jq --raw-output ".transactionHash")

  echo "Waiting for a new checkpoint on L1..."
  wait_for_new_checkpoint "${initial_checkpoint}"

  echo "Generating exit payload..."
  payload=$(generate_pos_exit_payload "${burn_tx}" 0 $((2 * timeout_seconds)))

  echo "Submitting exit on L1..."
  cast send --rpc-url "${L1_RPC_URL}" --private-key "${PRIVATE_KEY}" --gas-limit 500000 \
    "${L1_ROOT_CHAIN_MANAGER_PROXY}" "exit(bytes)" "${payload}"

  echo "Verifying L1 DummyERC1155 balance increased..."
  l1_balance_cmd='cast call --rpc-url "${L1_RPC_URL}" --json "${L1_DUMMY_ERC1155}" "balanceOf(address,uint256)(uint)" "'"${address}"'" "'"${id}"'" | jq -r ".[0]"'
  assert_command_eventually_greater_or_equal "${l1_balance_cmd}" "$(echo "${initial_l1_balance} + ${amount}" | bc)" "${timeout_seconds}" "${interval_seconds}"
}
