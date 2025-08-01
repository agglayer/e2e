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
    export l2_address=$(cast wallet address --private-key $l2_private_key)

    # This is the bytecode for the SimpleAccount contract below
    export SCA_BYTECODE="0x6080604052348015600e575f5ffd5b506102b68061001c5f395ff3fe608060405234801561000f575f5ffd5b5060043610610029575f3560e01c8063b61d27f61461002d575b5f5ffd5b610047600480360381019061004291906101bb565b610049565b005b5f8473ffffffffffffffffffffffffffffffffffffffff16848484604051610072929190610268565b5f6040518083038185875af1925050503d805f81146100ac576040519150601f19603f3d011682016040523d82523d5f602084013e6100b1565b606091505b50509050806100be575f5ffd5b5050505050565b5f5ffd5b5f5ffd5b5f73ffffffffffffffffffffffffffffffffffffffff82169050919050565b5f6100f6826100cd565b9050919050565b610106816100ec565b8114610110575f5ffd5b50565b5f81359050610121816100fd565b92915050565b5f819050919050565b61013981610127565b8114610143575f5ffd5b50565b5f8135905061015481610130565b92915050565b5f5ffd5b5f5ffd5b5f5ffd5b5f5f83601f84011261017b5761017a61015a565b5b8235905067ffffffffffffffff8111156101985761019761015e565b5b6020830191508360018202830111156101b4576101b3610162565b5b9250929050565b5f5f5f5f606085870312156101d3576101d26100c5565b5b5f6101e087828801610113565b94505060206101f187828801610146565b935050604085013567ffffffffffffffff811115610212576102116100c9565b5b61021e87828801610166565b925092505092959194509250565b5f81905092915050565b828183375f83830152505050565b5f61024f838561022c565b935061025c838584610236565b82840190509392505050565b5f610274828486610244565b9150819050939250505056fea2646970667358221220927ff79d6008243442f81f3ffa1afbc241fa1c3f497e5ddd9c25efdbbfeb604b64736f6c634300081e0033"
    # // Example SCA (SimpleAccount.sol)
    # contract SimpleAccount {
    #     function execute(address to, uint256 value, bytes calldata data) external {
    #         (bool success, ) = to.call{value: value}(data);
    #         require(success);
    #     }
    # }

    # Random wallet
    random_wallet=$(cast wallet new --json)
    random_address=$(echo "$random_wallet" | jq -r '.[0].address')
    # random_private_key=$(echo "$random_wallet" | jq -r '.[0].privateKey')

    export random_address
}

function deploy_contract() {
    # Deploy the contract
    run cast send --rpc-url $l2_rpc_url --private-key $l2_private_key --create $SCA_BYTECODE --json
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

    json_input="$(jq -cn \
        --arg chain_id "$(printf "0x%x" "$chain_id")" \
        --arg to "$address" \
        --arg nonce "$(printf "0x%x" "$nonce")" \
        '[
            $chain_id,
            $to,
            $nonce
        ]')"

    rlp_payload=$(cast to-rlp "$json_input")

    rlp_signing_data=$(cast keccak "0x05${rlp_payload:2}")

    # Sign the authorization data
    signature=$(cast wallet sign --no-hash --private-key "$l2_private_key" "$rlp_signing_data")
    signature=${signature#0x}
    signature_r="0x${signature:0:64}"
    signature_s="0x${signature:64:64}"
    signature_v="0x${signature:128:2}"

    authorization_element=$(jq -cn \
        --arg chain_id "$(printf "0x%x" "$chain_id")" \
        --arg to "$address" \
        --arg nonce "$(printf "0x%x" "$nonce")" \
        --arg v "$signature_v" \
        --arg r "$signature_r" \
        --arg s "$signature_s" \
        '[
            $chain_id,
            $to,
            $nonce,
            $v,
            $r,
            $s
        ]'
    )

    echo $authorization_element
}



@test "EIP-7702 Temporary Smart Contract Account" {
    tx_type="0x04"  # EIP-7702 transaction type

    contract_address=$(deploy_contract)
    if [ -z "$contract_address" ]; then
        echo "❌ Failed to deploy contract"
        exit 1
    fi
    echo "Contract deployed at: $contract_address"

    nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_address")
    if [ -z "$nonce" ]; then
        echo "❌ Failed to get nonce for address $l2_address"
        exit 1
    fi
    echo "Nonce for address $l2_address: $nonce"

    authorization_element=$(create_authorization_element "$l2_chain_id" "$contract_address" "$nonce")
    #authorization_element="[]"
    if [ -z "$authorization_element" ]; then
        echo "❌ Failed to create authorization element"
        exit 1
    fi
    echo "Authorization Element: $authorization_element"


    gas_limit=2000000
    gas_price=1000000000  # 1 gwei

    # SCA payload - just sends 1 wei to a random address
    encoded_data=$(cast abi-encode "execute(address,uint256,bytes)" "$random_address" 1 "0x")
    # encoded_data="0x"

    # Convert values to hex
    hex_chain_id=$(printf "0x%x" "$l2_chain_id")
    hex_nonce=$(printf "0x%x" "$nonce")
    hex_gas_limit=$(printf "0x%x" "$gas_limit")
    hex_gas_price=$(printf "0x%x" "$gas_price")


    json_input="$(jq -cn \
        --arg chain_id "$hex_chain_id" \
        --arg nonce "$hex_nonce" \
        --arg max_fee "$hex_gas_price" \
        --arg max_priority "$hex_gas_price" \
        --arg gas "$hex_gas_limit" \
        --arg to "$contract_address" \
        --arg value "0x01" \
        --arg data "$encoded_data" \
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
        ]')"

    echo "JSON Input: $json_input"

    # RLP encode the transaction
    rlp_payload=$(cast to-rlp "$json_input")
    signing_data=$(cast keccak "${tx_type}${rlp_payload:2}")

    echo "Signing Data: $signing_data"

    # Sign it
    signature=$(cast wallet sign --no-hash --private-key "$l2_private_key" "$signing_data")
    signature=${signature#0x}
    signature_r="0x${signature:0:64}"
    signature_s="0x${signature:64:64}"
    signature_v="0x${signature:128:2}"
    if [ "$signature_vw" = "0x00" ]; then
        signature_v="0x"
    fi

    v_dec=$((signature_v))
    # Subtract 0x1b (27 decimal)
    result_dec=$((v_dec - 0x1b))
    # For EIP-7702, when V is 0, use empty value instead of 0x00
    if [ $result_dec -eq 0 ]; then
        signature_v="0x"
    else
        signature_v=$(printf "0x%02x" $result_dec)
    fi

    # Final transaction fields with signature
    final_tx=$(jq -cn \
    --arg chain_id "$hex_chain_id" \
    --arg nonce "$hex_nonce" \
    --arg max_fee "$hex_gas_price" \
    --arg max_priority "$hex_gas_price" \
    --arg gas "$hex_gas_limit" \
    --arg to "$contract_address" \
    --arg value "0x01" \
    --argjson authorization_element "$authorization_element" \
    --arg data "$encoded_data" \
    --arg v "$signature_v" \
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
        $v,
        $r,
        $s
    ]'
    )

    echo "Final Transaction: $final_tx"

    # RLP encode signed transaction
    signed_rlp=$(cast to-rlp "$final_tx")

    # Prepend tx type byte
    full_tx="${tx_type}${signed_rlp:2}"

    echo "Signatures: signature=$signature v=$signature_v, r=$signature_r, s=$signature_s"

    # Submit transaction
    run cast publish "$full_tx" --rpc-url "$l2_rpc_url" --json

    if [ "$status" -ne 0 ]; then
        echo "❌ Failed to send transaction: $output"
        echo "Raw full transaction: $full_tx"
        exit 1
    fi

    echo "Transaction sent successfully: $output"
    echo "Raw full transaction: $full_tx"
}
