# This function sets up environment variables for `pos` tests using a Kurtosis Polygon PoS
# environment if they are not already provided.
pos_setup() {
  # Private key used to send transactions.
  export PRIVATE_KEY=${PRIVATE_KEY:-"0xd40311b5a5ca5eaeb48dfba5403bde4993ece8eccf4190e98e19fcd4754260ea"}
  echo "PRIVATE_KEY=${PRIVATE_KEY}"

  # The name of the Kurtosis enclave (used for default values).
  export ENCLAVE_NAME=${ENCLAVE_NAME:-"pos"}
  echo "ENCLAVE_NAME=${ENCLAVE_NAME}"

  # L1 and L2 RPC and API URLs.
  if [[ -z "${L1_RPC_URL:-}" ]]; then
    if l1_rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" el-1-geth-lighthouse rpc 2>/dev/null); then
      export L1_RPC_URL="http://${l1_rpc_port}"
    elif l1_rpc_port=$(kurtosis port print "${ENCLAVE_NAME}" el-1-reth-lighthouse rpc 2>/dev/null); then
      export L1_RPC_URL="http://${l1_rpc_port}"
    else
      echo "❌ Failed to resolve L1 RPC URL from Kurtosis (tried el-1-geth-lighthouse and el-1-reth-lighthouse)"
      exit 1
    fi
  fi
  echo "L1_RPC_URL=${L1_RPC_URL}"

  export L2_RPC_URL=${L2_RPC_URL:-$(kurtosis port print "${ENCLAVE_NAME}" "l2-el-1-bor-heimdall-v2-validator" rpc)}
  export L2_CL_API_URL=${L2_CL_API_URL:-$(kurtosis port print "${ENCLAVE_NAME}" "l2-cl-1-heimdall-v2-bor-validator" http)}

  echo "L2_RPC_URL=${L2_RPC_URL}"
  echo "L2_CL_API_URL=${L2_CL_API_URL}"

  if [[ -z "${L1_GOVERNANCE_PROXY_ADDRESS:-}" ]] ||
    [[ -z "${L1_ROOT_CHAIN_PROXY_ADDRESS:-}" ]] ||
    [[ -z "${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-}" ]] ||
    [[ -z "${L1_WITHDRAW_MANAGER_PROXY_ADDRESS:-}" ]] ||
    [[ -z "${L1_ERC20_PREDICATE_ADDRESS:-}" ]] ||
    [[ -z "${L1_ERC721_PREDICATE_ADDRESS:-}" ]] ||
    [[ -z "${L1_STAKE_MANAGER_PROXY_ADDRESS:-}" ]] ||
    [[ -z "${L1_STAKING_INFO_ADDRESS:-}" ]] ||
    [[ -z "${L1_MATIC_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L1_POL_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L1_WETH_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L1_ERC20_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L1_ERC721_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L2_STATE_RECEIVER_ADDRESS:-}" ]] ||
    [[ -z "${L2_WETH_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L2_ERC20_TOKEN_ADDRESS:-}" ]] ||
    [[ -z "${L2_ERC721_TOKEN_ADDRESS:-}" ]]; then
    plasma_bridge_addresses=$(kurtosis files inspect "${ENCLAVE_NAME}" plasma-bridge-addresses contractAddresses.json | jq)

    # L1 contract addresses.
    export L1_GOVERNANCE_PROXY_ADDRESS=${L1_GOVERNANCE_PROXY_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.GovernanceProxy')}
    echo "L1_GOVERNANCE_PROXY_ADDRESS=${L1_GOVERNANCE_PROXY_ADDRESS}"

    export L1_ROOT_CHAIN_PROXY_ADDRESS=${L1_ROOT_CHAIN_PROXY_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.RootChainProxy')}
    echo "L1_ROOT_CHAIN_PROXY_ADDRESS=${L1_ROOT_CHAIN_PROXY_ADDRESS}"

    export L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.DepositManagerProxy')}
    echo "L1_DEPOSIT_MANAGER_PROXY_ADDRESS=${L1_DEPOSIT_MANAGER_PROXY_ADDRESS}"

    export L1_WITHDRAW_MANAGER_PROXY_ADDRESS=${L1_WITHDRAW_MANAGER_PROXY_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.WithdrawManagerProxy')}
    echo "L1_WITHDRAW_MANAGER_PROXY_ADDRESS=${L1_WITHDRAW_MANAGER_PROXY_ADDRESS}"

    export L1_ERC20_PREDICATE_ADDRESS=${L1_ERC20_PREDICATE_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.predicates.ERC20Predicate')}
    echo "L1_ERC20_PREDICATE_ADDRESS=${L1_ERC20_PREDICATE_ADDRESS}"

    export L1_ERC721_PREDICATE_ADDRESS=${L1_ERC721_PREDICATE_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.predicates.ERC721Predicate')}
    echo "L1_ERC721_PREDICATE_ADDRESS=${L1_ERC721_PREDICATE_ADDRESS}"

    export L1_STAKE_MANAGER_PROXY_ADDRESS=${L1_STAKE_MANAGER_PROXY_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.StakeManagerProxy')}
    echo "L1_STAKE_MANAGER_PROXY_ADDRESS=${L1_STAKE_MANAGER_PROXY_ADDRESS}"

    export L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.StakingInfo')}
    echo "L1_STAKING_INFO_ADDRESS=${L1_STAKING_INFO_ADDRESS}"

    export L1_MATIC_TOKEN_ADDRESS=${L1_MATIC_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.tokens.MaticToken')}
    echo "L1_MATIC_TOKEN_ADDRESS=${L1_MATIC_TOKEN_ADDRESS}"

    export L1_POL_TOKEN_ADDRESS=${L1_POL_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.tokens.PolToken')}
    echo "L1_POL_TOKEN_ADDRESS=${L1_POL_TOKEN_ADDRESS}"

    export L1_ERC20_TOKEN_ADDRESS=${L1_ERC20_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.tokens.TestToken')}
    echo "L1_ERC20_TOKEN_ADDRESS=${L1_ERC20_TOKEN_ADDRESS}"

    export L1_ERC721_TOKEN_ADDRESS=${L1_ERC721_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.tokens.RootERC721')}
    echo "L1_ERC721_TOKEN_ADDRESS=${L1_ERC721_TOKEN_ADDRESS}"

    # L2 contract addresses.
    export L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS:-$(kurtosis files inspect "${ENCLAVE_NAME}" l2-el-genesis genesis.json | jq --raw-output '.config.bor.stateReceiverContract')}
    echo "L2_STATE_RECEIVER_ADDRESS=${L2_STATE_RECEIVER_ADDRESS}"

    export L2_ERC20_TOKEN_ADDRESS=${L2_ERC20_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.child.tokens.TestToken')}
    echo "L2_ERC20_TOKEN_ADDRESS=${L2_ERC20_TOKEN_ADDRESS}"

    export L2_ERC721_TOKEN_ADDRESS=${L2_ERC721_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.child.tokens.RootERC721')}
    echo "L2_ERC721_TOKEN_ADDRESS=${L2_ERC721_TOKEN_ADDRESS}"

    export L1_WETH_TOKEN_ADDRESS=${L1_WETH_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.root.tokens.MaticWeth')}
    echo "L1_WETH_TOKEN_ADDRESS=${L1_WETH_TOKEN_ADDRESS}"

    export L2_WETH_TOKEN_ADDRESS=${L2_WETH_TOKEN_ADDRESS:-$(echo "${plasma_bridge_addresses}" | jq --raw-output '.child.tokens.MaticWeth')}
    echo "L2_WETH_TOKEN_ADDRESS=${L2_WETH_TOKEN_ADDRESS}"
  fi

  # pos-bridge addresses (pos-portal)
  if [[ -z "${L1_ROOT_CHAIN_MANAGER_PROXY:-}" ]] ||
    [[ -z "${L1_ERC20_PORTAL_PREDICATE_PROXY:-}" ]] ||
    [[ -z "${L1_DUMMY_ERC20:-}" ]] ||
    [[ -z "${L2_DUMMY_ERC1155:-}" ]]; then
    pos_portal_addresses=$(kurtosis files inspect "${ENCLAVE_NAME}" pos-portal-addresses contractAddresses.json | jq)
    export L1_ROOT_CHAIN_MANAGER_PROXY=${L1_ROOT_CHAIN_MANAGER_PROXY:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.RootChainManagerProxy')}
    export L1_ERC20_PORTAL_PREDICATE_PROXY=${L1_ERC20_PORTAL_PREDICATE_PROXY:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.ERC20PredicateProxy')}
    export L1_ERC721_PORTAL_PREDICATE_PROXY=${L1_ERC721_PORTAL_PREDICATE_PROXY:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.ERC721PredicateProxy')}
    export L1_ERC1155_PORTAL_PREDICATE_PROXY=${L1_ERC1155_PORTAL_PREDICATE_PROXY:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.ERC1155PredicateProxy')}
    export L1_ETHER_PORTAL_PREDICATE_PROXY=${L1_ETHER_PORTAL_PREDICATE_PROXY:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.EtherPredicateProxy')}
    export L1_DUMMY_ERC20=${L1_DUMMY_ERC20:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.DummyERC20')}
    export L2_DUMMY_ERC20=${L2_DUMMY_ERC20:-$(echo "${pos_portal_addresses}" | jq --raw-output '.child.posPortal.DummyERC20')}
    export L1_DUMMY_ERC721=${L1_DUMMY_ERC721:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.DummyERC721')}
    export L2_DUMMY_ERC721=${L2_DUMMY_ERC721:-$(echo "${pos_portal_addresses}" | jq --raw-output '.child.posPortal.DummyERC721')}
    export L1_DUMMY_ERC1155=${L1_DUMMY_ERC1155:-$(echo "${pos_portal_addresses}" | jq --raw-output '.root.posPortal.DummyERC1155')}
    export L2_DUMMY_ERC1155=${L2_DUMMY_ERC1155:-$(echo "${pos_portal_addresses}" | jq --raw-output '.child.posPortal.DummyERC1155')}
    export L2_MATIC_WETH=${L2_MATIC_WETH:-$(echo "${pos_portal_addresses}" | jq --raw-output '.child.posPortal.MaticWETH')}
    echo "L1_ROOT_CHAIN_MANAGER_PROXY=${L1_ROOT_CHAIN_MANAGER_PROXY}"
    echo "L2_MATIC_WETH=${L2_MATIC_WETH}"
  fi
}

# Create and fund an ephemeral wallet. Sets ephemeral_private_key and
# ephemeral_address. Calls `skip` if the chain is not processing transactions
# (e.g. stalled in mixed-version networks).
#
# Usage: _fund_ephemeral [amount]   (default: 1ether)
_fund_ephemeral() {
    local amount="${1:-1ether}"
    local wallet_json
    wallet_json=$(cast wallet new --json | jq '.[0]')
    # shellcheck disable=SC2034  # intentional global: used by calling test scripts
    ephemeral_private_key=$(echo "$wallet_json" | jq -r '.private_key')
    ephemeral_address=$(echo "$wallet_json" | jq -r '.address')
    echo "ephemeral_address: $ephemeral_address" >&3

    local _err
    if ! _err=$(cast send --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" \
            --legacy --gas-limit 21000 --value "$amount" "$ephemeral_address" 2>&1 >/dev/null); then
        case "$_err" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                skip "Chain stalled — cannot fund ephemeral wallet"
                ;;
            *)
                echo "Fund ephemeral failed: $_err" >&2
                return 1
                ;;
        esac
    fi
}

# Wrapper around `cast send` that skips the test on chain-stall errors.
# Use inside @test functions where a `cast send` is needed.
#
# Usage: _send_or_skip [cast send args...]
_send_or_skip() {
    local _err
    if ! _err=$(cast send "$@" 2>&1); then
        case "$_err" in
            *"replacement transaction underpriced"*|*"not confirmed within"*|*"nonce too low"*)
                skip "Chain stalled — transaction cannot be submitted"
                ;;
            *)
                echo "$_err" >&2
                return 1
                ;;
        esac
    fi
    echo "$_err"
}
