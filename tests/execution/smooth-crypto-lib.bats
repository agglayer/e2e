#!/usr/bin/env bats
# bats file_tags=standard

# This file tests the deployment of SmoothCrpytoLib - https://github.com/get-smooth/crypto-lib and interacting with it.

setup_file() {
    export kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l2_eth_address
    l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}
    export global_timeout="${GLOBAL_TIMEOUT:-1800s}"

    export exponential_growth_limit=12
    export TEMP_DIR
    TEMP_DIR=$(mktemp -d)
}

setup() {
    # source existing helper functions for ephemeral account setup
    # shellcheck disable=SC1091
    source "./tests/lxly/assets/bridge-tests-helper.bash"
}

# teardown_file() {
#     echo "Removing temp directory: $TEMP_DIR" >&3
#     rm -rf $TEMP_DIR
# }

@test "Setup SmoothCryptoLib" {
    echo "Temp working directory: $TEMP_DIR" >&3

    # Clone SmoothCryptoLib
    echo "Cloning SmoothCryptoLib repo..." >&3
    git clone https://github.com/get-smooth/crypto-lib.git "$TEMP_DIR/crypto-lib"
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Install and compile
    forge build --use 0.8.28 --force

    # shellcheck disable=SC2162
    find ./out -type f | grep SCL_ | grep -vi test | grep -vi deploy | grep .json | while read contract ; do
        bn="$(basename "$contract")"
        if [[ "$bn" = "SCL_EIP6565_UTILS.json" ]]; then
            # The SCL_EIP6565_UTILS.json file contains dirty bytecode objects which needs to be cleaned.
            jq '.bytecode.object |= (sub("[_$]"; ""; "g"))' ./out/libSCL_eddsaUtils.sol/SCL_EIP6565_UTILS.json > temp.json && mv temp.json ./out/libSCL_eddsaUtils.sol/SCL_EIP6565_UTILS.json
        fi
        echo "Deploying SCL: $bn" >&3
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json --create "$(jq -r '.bytecode.object' "$contract")" | tee -a smooth-crypto-lib.out > /"$TEMP_DIR"/crypto-lib/"$bn".deploy.json
    done
}

# HashLE method does not exist anymore.
# @test "Testing SHA512 - HashLE" {
#     echo "Starting SHA512 Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     echo "Command: cast send --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_sha512.json.deploy.json)\" \"HashLE(uint256)\" 0" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_sha512.json.deploy.json)" "HashLE(uint256)" 0
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_sha512.json.deploy.json)" "HashLE(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935

#     cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
#     for i in {1..256}; do
#         set -x
#         echo "Command: cast send --async --nonce $cur_nonce --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_sha512.json.deploy.json)\" \"HashLE(uint256)\" \"0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")\"" >&3
#         cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_sha512.json.deploy.json)" "HashLE(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
#         set +x
#         cur_nonce=$((cur_nonce + 1))
#     done
# }

@test "Testing EIP6565 - BasePointMultiply" {
    echo "Starting EIP6565 BasePointMultiply Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    # Use ephemeral accounts for parallel tests
    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "basepoint_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        # Fund ephemeral account
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        # Small delay to prevent overwhelming the network
        if (( i % 20 == 0 )); then
            wait # Wait for funding operations to complete
        fi
    done
    wait # Wait for all funding to complete
    
    # Execute tests with ephemeral accounts
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "basepoint_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "BasePointMultiply(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
        
        # Limit concurrent transactions
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

@test "Testing EIP6565 - BasePointMultiply_Edwards" {
    echo "Starting EIP6565 BasePointMultiply_Edwards Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    echo "Command: cast send --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)\" \"BasePointMultiply_Edwards(uint256)\" 0" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply_Edwards(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply_Edwards(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    # Use ephemeral accounts for parallel tests
    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "edwards_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)

        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "edwards_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "BasePointMultiply_Edwards(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
        
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

# # TODO: Fix ExpandSecret test
# # SCL_EIP6565_UTILS tests seem to work on Kurtosis L1, but fails on CDK-OP-Geth
# # error code -32000: invalid jump destination
# @test "Testing EIP6565 - ExpandSecret" {
#     echo "Starting EIP6565 ExpandSecret Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     sleep 5
#     # Test basic cases with main account
#     echo "Command: cast send --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)\" \"ExpandSecret(uint256)\" 0" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "ExpandSecret(uint256)" 0 >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "ExpandSecret(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

#     # Use ephemeral accounts for parallel tests
#     local contract_addr=$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "expand_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "expand_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "ExpandSecret(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
        
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
# }

# # TODO: Fix SetKey test
# # SCL_EIP6565_UTILS tests seem to work on Kurtosis L1, but fails on CDK-OP-Geth
# # error code -32000: invalid jump destination
# @test "Testing EIP6565 - SetKey" {
#     echo "Starting EIP6565 SetKey Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     # Test basic cases with main account
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "SetKey(uint256)" 0 >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "SetKey(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

#     # Use ephemeral accounts for parallel tests
#     local contract_addr=$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "setkey_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "setkey_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "SetKey(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
        
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
# }

@test "Testing EIP6565 - HashInternal" {
    echo "Starting EIP6565 HashInternal Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" 0 0 "" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 115792089237316195423570985008687907853269984665640564039457584007913129639935 "abcd1234" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" \
        115792089237316195423570985008687907853269984665640564039457584007913129639935 115792089237316195423570985008687907853269984665640564039457584007913129639935 \
        "00112233445566778899AABBCCDDEEFF" >&3

    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    
    # Exponential growth tests with main account (sequential for consistency)
    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in $(seq 1 "$exponential_growth_limit"); do
        cast send --gas-limit 3000000 --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "HashInternal(uint256,uint256,string)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "$hash_value" >&3
        hash_value="$hash_value$hash_value"
    done

    # Use ephemeral accounts for the 256 parallel tests
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "hashint_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "hashint_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "HashInternal(uint256,uint256,string)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" "abc123" >&3 &
            
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

# # TODO: Fix Sign test
# # SCL_EIP6565_UTILS tests seem to work on Kurtosis L1, but fails on CDK-OP-Geth
# # error code -32000: invalid jump destination
# @test "Testing EIP6565 - Sign" {
#     echo "Starting EIP6565 Sign Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     # Test basic cases with main account
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "Sign(uint256,uint256[2],string)" 0 "[0,0]" "abc123" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "Sign(uint256,uint256[2],string)" 1 "[0,0]" "abc123" >&3

#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "Sign(uint256,uint256[2],string)" \
#         115792089237316195423570985008687907853269984665640564039457584007913129639935 \
#         "[115792089237316195423570985008687907853269984665640564039457584007913129639935,115792089237316195423570985008687907853269984665640564039457584007913129639935]" \
#         "abc123" >&3

#     local contract_addr=$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)
    
#     # Exponential growth tests with main account
#     hash_value="00112233445566778899AABBCCDDEEFF"
#     for i in {1.."$exponential_growth_limit"}; do
#         cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Sign(uint256,uint256[2],string)" \
#             27066115479399555241574240779398896927011581316434074034167126962687364905698 \
#             "[42559113093733082793542566282911713742375005736614813947385187293220506342480,109370305882734025219925353605107763559738011796832715623096498452877702410736]" \
#             "$hash_value" >&3
#         hash_value="$hash_value$hash_value"
#     done

#     # Use ephemeral accounts for parallel tests
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "sign_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "sign_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Sign(uint256,uint256[2],string)" \
#             27066115479399555241574240779398896927011581316434074034167126962687364905698 \
#             "[42559113093733082793542566282911713742375005736614813947385187293220506342480,109370305882734025219925353605107763559738011796832715623096498452877702410736]" \
#             "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
            
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
# }

# # TODO: Fix SignSlow test
# # SCL_EIP6565_UTILS tests seem to work on Kurtosis L1, but fails on CDK-OP-Geth
# # error code -32000: invalid jump destination
# @test "Testing EIP6565 - SignSlow" {
#     echo "Starting EIP6565 SignSlow Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     # Test basic cases with main account
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "SignSlow(uint256,string)" 0 "abc123" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "SignSlow(uint256,string)" 1 "abc123" >&3

#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)" "SignSlow(uint256,string)" \
#         115792089237316195423570985008687907853269984665640564039457584007913129639935 \
#         "abc123" >&3

#     local contract_addr=$(jq -r '.contractAddress' SCL_EIP6565_UTILS.json.deploy.json)
    
#     # Exponential growth tests with main account
#     hash_value="00112233445566778899AABBCCDDEEFF"
#     for i in {1.."$exponential_growth_limit"}; do
#         cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "SignSlow(uint256,string)" \
#             27066115479399555241574240779398896927011581316434074034167126962687364905698 \
#             "$hash_value" >&3
#         hash_value="$hash_value$hash_value"
#     done

#     # Use ephemeral accounts for parallel tests
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "signslow_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "signslow_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "SignSlow(uint256,string)" \
#             27066115479399555241574240779398896927011581316434074034167126962687364905698 \
#             "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
            
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
# }

@test "Testing EIP6565 - Verify" {
    echo "Starting EIP6565 Verify Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" "abc123" 0 0 "[1,2,3,4,5]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" "abc123" 1 1 "[1,2,3,4,5]" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" \
        "john hilliard" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
        "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3

    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    
    # Exponential growth tests with main account
    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in $(seq 1 "$exponential_growth_limit"); do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Verify(string,uint256,uint256,uint256[5])" \
            "$hash_value" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
            hash_value="$hash_value$hash_value"
    done

    # Use ephemeral accounts for parallel tests
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "verify_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "verify_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Verify(string,uint256,uint256,uint256[5])" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3 &
            
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

@test "Testing EIP6565 - Verify_LE" {
    echo "Starting EIP6565 Verify_LE Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" "abc123" 0 0 "[1,2,3,4,5]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" "abc123" 1 1 "[1,2,3,4,5]" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" \
        "john hilliard" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
        "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3

    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    
    # Exponential growth tests with main account
    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in $(seq 1 "$exponential_growth_limit"); do
        cast send --gas-limit 3000000 --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Verify_LE(string,uint256,uint256,uint256[5])" \
            "$hash_value" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
            hash_value="$hash_value$hash_value"
    done

    # Use ephemeral accounts for parallel tests
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "verifyle_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "verifyle_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "Verify_LE(string,uint256,uint256,uint256[5])" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3 &
            
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

@test "Testing EIP6565 - ecPow128" {
    echo "Starting EIP6565 ecPow128 Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" 0 0 0 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" 1 1 1 1 >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
           >&3

    # Use ephemeral accounts for parallel tests (512 tests)
    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    for i in {1..512}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "ecpow_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 30 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..512}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "ecpow_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "ecPow128(uint256,uint256,uint256,uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
            
        if (( i % 70 == 0 )); then
            wait
        fi
    done
    wait
}

# # TODO: Fix edCompress test
# # SCL_EIP6565_UTILS tests seem to work on Kurtosis L1, but fails on CDK-OP-Geth
# # execution reverted: arithmetic underflow or overflow, data: "0x4e487b710000000000000000000000000000000000000000000000000000000000000011"
# @test "Testing EIP6565 - edCompress" {
#     echo "Starting EIP6565 edCompress Tests" >&3
#     cd "$TEMP_DIR/crypto-lib" || exit 1

#     # Test basic cases with main account
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" "[0,0]" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" "[1,1]" >&3

#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
#             "[115792089237316195423570985008687907853269984665640564039457584007913129639935,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
#             "[0,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3
#     cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
#             "[1,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3

#     # Use ephemeral accounts for the two sets of 256 parallel tests
#     local contract_addr=$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)
    
#     # First set with 0x00
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "edcomp1_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "edcomp1_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "edCompress(uint256[2])" \
#             "[0x00,0x$(head -c 31 /dev/urandom | xxd -p | tr -d "\n")]" >&3 &
            
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     # Second set with 0x01
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "edcomp2_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
#         local ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
#         _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
#         if (( i % 20 == 0 )); then
#             wait
#         fi
#     done
#     wait
    
#     for i in {1..256}; do
#         local ephemeral_data=$(_generate_ephemeral_account "edcomp2_$i")
#         local ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
#         cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" "edCompress(uint256[2])" \
#             "[0x01,0x$(head -c 31 /dev/urandom | xxd -p | tr -d "\n")]" >&3 &
            
#         if (( i % 50 == 0 )); then
#             wait
#         fi
#     done
#     wait
# }

@test "Testing RIP7212 - verify" {
    echo "Starting RIP7212 verify Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256,uint256)" 0x0000000000000000000000000000000000000000000000000000000000000000 0 0 0 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256,uint256)" 0x0000000000000000000000000000000000000000000000000000000000000001 1 1 1 1 >&3

    # Use ephemeral accounts for parallel tests
    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "rip7212_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "rip7212_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" \
            "verify(bytes32,uint256,uint256,uint256,uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
            
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}

@test "Testing ECDSAB4 - verify" {
    echo "Starting ECDSAB4 verify Tests" >&3
    cd "$TEMP_DIR/crypto-lib" || exit 1

    # Test basic cases with main account
    # shellcheck disable=SC2102
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256[10],uint256)" 0x0000000000000000000000000000000000000000000000000000000000000000 0 0 [0,0,0,0,0,0,0,0,0,0] 0 >&3
    # shellcheck disable=SC2102
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256[10],uint256)" 0x0000000000000000000000000000000000000000000000000000000000000001 1 1 [1,1,1,1,1,1,1,1,1,1] 1 >&3

    # Use ephemeral accounts for parallel tests
    local contract_addr
    contract_addr=$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        local ephemeral_address
        ephemeral_data=$(_generate_ephemeral_account "ecdsab4_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        ephemeral_address=$(echo "$ephemeral_data" | cut -d' ' -f2)
        
        _fund_ephemeral_account "$ephemeral_address" "$l2_rpc_url" "$l2_private_key" "1000000000000000000" &
        
        if (( i % 20 == 0 )); then
            wait
        fi
    done
    wait
    
    for i in {1..256}; do
        local ephemeral_data
        local ephemeral_private_key
        ephemeral_data=$(_generate_ephemeral_account "ecdsab4_$i")
        ephemeral_private_key=$(echo "$ephemeral_data" | cut -d' ' -f1)
        
        cast send --async --private-key "$ephemeral_private_key" --rpc-url "$l2_rpc_url" --json "$contract_addr" \
            "verify(bytes32,uint256,uint256,uint256[10],uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "[0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")]" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3 &
            
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    wait
}