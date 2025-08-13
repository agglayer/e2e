#!/usr/bin/env bats

#
# This file implements tests for EIP-7702: Set Code for EOAs
# https://eips.ethereum.org/EIPS/eip-7702
#

setup() {
    true
}


setup_file() {
    export kurtosis_enclave_name=${KURTOSIS_ENCLAVE_NAME:-"pectra"}

    if [[ -n "$L2_RPC_URL" ]]; then
        export l2_rpc_url="$L2_RPC_URL"
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc 2>/dev/null); then
        export l2_rpc_url
    elif l2_rpc_url=$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc 2>/dev/null); then
        export l2_rpc_url
    else
        echo "❌ Failed to determine L2 RPC URL. Please set L2_RPC_URL" >&2
        exit 1
    fi

    export l2_chain_id=${L2_CHAIN_ID:-"$(cast chain-id --rpc-url $l2_rpc_url)"}
    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_address=$(cast wallet address --private-key $l2_private_key)
    export l2_address

    delegated_bytecode=$(cat contracts/Delegated.json | jq -r .bytecode.object)
    export delegated_bytecode

    # Random wallet
    alice_wallet=$(cast wallet new --json)
    alice_address=$(echo "$alice_wallet" | jq -r '.[0].address')
    alice_private_key=$(echo "$alice_wallet" | jq -r '.[0].private_key')

    # fund alice
    fund_value_ether=0.1

    fund_value_wei=$(echo $fund_value_ether | cast to-wei)
    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --value $fund_value_wei $alice_address
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to fund Alice's wallet: $output"
        exit 1
    else
        echo "✅ Successfully funded Alice's wallet"
    fi

    # assert alice got funded
    alice_balance=$(cast balance --rpc-url $l2_rpc_url $alice_address)
    if [ $alice_balance -lt $fund_value_wei ]; then
        echo "❌ Failed to fund Alice's wallet, current balance: $alice_balance"
        exit 1
    fi

    export alice_address
    export alice_private_key
}

function deploy_contract() {
    # Deploy the contract
    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --create $delegated_bytecode --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to deploy contract: $output"
        exit 1
    fi

    contract_address=$(echo "$output" | jq -r '.contractAddress')
    if [ -z "$contract_address" ]; then
        echo "❌ Contract address not found in output"
        exit 1
    fi

    echo $contract_address
}

function create_authorization_element() {
    local chain_id=$1
    local address=$2
    local nonce=$3
    local signing_key=$4

    json_input="$(jq -cn \
        --argjson chain_id $chain_id \
        --arg to "$address" \
        --argjson nonce $nonce \
        '[
            $chain_id,
            $to,
            $nonce
        ]')"

    rlp_payload=$(cast to-rlp "$json_input")

    rlp_signing_data=$(cast keccak "0x05${rlp_payload:2}")

    # Sign the authorization data
    signature=$(cast wallet sign --no-hash --private-key "$signing_key" "$rlp_signing_data")
    signature=${signature#0x}
    signature_r="0x${signature:0:64}"
    signature_s="0x${signature:64:64}"
    raw_v=$((16#${signature:128:2}))
    y_parity=$((raw_v - 27))

    authorization_element=$(jq -cn \
        --argjson chain_id $chain_id \
        --arg to "$address" \
        --argjson nonce $nonce \
        --argjson y_parity $y_parity \
        --arg r "$signature_r" \
        --arg s "$signature_s" \
        '[
            $chain_id,
            $to,
            $nonce,
            $y_parity,
            $r,
            $s
        ]'
    )
    echo $authorization_element
}

@test "EIP-7702 Delegated contract with log event" {
    tx_type="0x04"  # EIP-7702 transaction type

    contract_address=$(deploy_contract)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract"
        exit 1
    fi
    echo "Delegated contract deployed at: $contract_address"

    nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$alice_address")
    if [ -z "$nonce" ]; then
        echo "❌ Failed to get nonce for address $alice_address"
        exit 1
    else
        next_nonce=$((nonce + 1))
        echo "Nonce for EOA address $alice_address: $nonce, next_nonce: $next_nonce"
    fi

    authorization_element=$(create_authorization_element "$l2_chain_id" "$contract_address" "$next_nonce" "$alice_private_key")
    if [ -z "$authorization_element" ]; then
        echo "❌ Failed to create authorization element"
        exit 1
    fi
    echo "Got authorization element for EIP-7702 tx"

    gas_limit=2000000
    gas_price=1000000000  # 1 gwei
    tx_data="0x"

    json_input=$(jq -cn \
        --argjson chain_id $l2_chain_id \
        --argjson nonce $nonce \
        --argjson max_fee $gas_price \
        --argjson max_priority $gas_price \
        --argjson gas $gas_limit \
        --arg to "$alice_address" \
        --argjson value 0 \
        --arg data "$tx_data" \
        --argjson authorization_element "$authorization_element" \
        '[
            $chain_id,
            $nonce,
            $max_priority,
            $max_fee,
            $gas,
            $to,
            $value,
            $data,
            [],
            [$authorization_element]
        ]'
    )

    # RLP encode the transaction
    rlp_payload=$(cast to-rlp "$json_input")
    signing_data=$(cast keccak "${tx_type}${rlp_payload:2}")

    # Sign it
    signature=$(cast wallet sign --no-hash --private-key "$alice_private_key" "$signing_data")
    signature=${signature#0x}
    signature_r="0x${signature:0:64}"
    signature_s="0x${signature:64:64}"
    raw_v=$((16#${signature:128:2}))
    y_parity=$((raw_v - 27))

    # Final transaction fields with signature
    final_tx=$(jq -cn \
        --argjson chain_id $l2_chain_id \
        --argjson nonce $nonce \
        --argjson max_fee $gas_price \
        --argjson max_priority $gas_price \
        --argjson gas $gas_limit \
        --arg to "$alice_address" \
        --argjson value 0 \
        --argjson authorization_element "$authorization_element" \
        --arg data "$tx_data" \
        --argjson y_parity $y_parity \
        --arg r "$signature_r" \
        --arg s "$signature_s" \
        '[
            $chain_id,
            $nonce,
            $max_priority,
            $max_fee,
            $gas,
            $to,
            $value,
            $data,
            [],
            [$authorization_element],
            $y_parity,
            $r,
            $s
        ]'
    )

    # RLP encode signed transaction
    signed_rlp=$(cast to-rlp "$final_tx")

    # Prepend tx type byte
    full_tx="${tx_type}${signed_rlp:2}"

    echo "Publishing Signed EIP-7702 tx"

    # Submit transaction
    run cast publish "$full_tx" --rpc-url "$l2_rpc_url" --json
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to send transaction: $output"
        echo "Raw full transaction: $full_tx"
        exit 1
    else
        tx_hash=$(echo "$output" | jq -r '.transactionHash')
        tx_type=$(echo "$output" | jq -r '.type')
        echo "Transaction sent successfully, tx_hash: $tx_hash, tx type: $tx_type"
    fi

    run cast send --json --rpc-url $l2_rpc_url --private-key $alice_private_key $alice_address "delegatedTest()"
    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to send delegated transaction: $output"
        exit 1
    else
        tx_hash=$(echo "$output" | jq -r '.transactionHash')
        logs=$(echo "$output" | jq -r '.logs')
        # Assert logs are not empty array []:
        if [ "$logs" == "[]" ]; then
            echo "❌ No logs found in delegated transaction: $tx_hash"
            exit 1
        fi
    fi
    echo "Delegated transaction executed successfully with hash: $tx_hash, logs: $logs"
}
