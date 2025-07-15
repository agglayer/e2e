#!/usr/bin/env bats

# This file tests the deployment of SmoothCrpytoLib - https://github.com/get-smooth/crypto-lib and interacting with it.

setup_file() {
    export kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    export l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    export l2_eth_address=$(cast wallet address --private-key "$l2_private_key")
    export l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    export TEMP_DIR=$(mktemp -d)
    export exponential_growth_limit=12
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
    forge build

    find . -type f | grep SCL_ | grep -vi test | grep -vi deploy | grep .json | while read contract ; do
        bn="$(basename $contract)"
        echo "Deploying SCL: $bn" >&3
        # echo "Command: cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json --create $(jq -r '.bytecode.object' $contract)" >&3
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json --create $(jq -r '.bytecode.object' $contract) | tee -a smooth-crypto-lib.out > /"$TEMP_DIR"/crypto-lib/$bn.deploy.json
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

    # echo "Command: cast send --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)\" \"BasePointMultiply(uint256)\"" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - BasePointMultiply_Edwards" {
    echo "Starting EIP6565 BasePointMultiply_Edwards Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    echo "Command: cast send --private-key \"$l2_private_key\" --rpc-url \"$l2_rpc_url\" --json \"$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)\" \"BasePointMultiply_Edwards(uint256)\" 0" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply_Edwards(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply_Edwards(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "BasePointMultiply_Edwards(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - ExpandSecret" {
    echo "Starting EIP6565 ExpandSecret Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ExpandSecret(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ExpandSecret(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ExpandSecret(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - SetKey" {
    echo "Starting EIP6565 SetKey Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SetKey(uint256)" 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SetKey(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SetKey(uint256)" "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - HashInternal" {
    echo "Starting EIP6565 HashInternal Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" 0 0 "" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 115792089237316195423570985008687907853269984665640564039457584007913129639935 "abcd1234" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" \
        115792089237316195423570985008687907853269984665640564039457584007913129639935 115792089237316195423570985008687907853269984665640564039457584007913129639935 \
        "00112233445566778899AABBCCDDEEFF" >&3

    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in {1.."$exponential_growth_limit"}; do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "$hash_value" >&3
        hash_value="$hash_value$hash_value"
    done

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "HashInternal(uint256,uint256,string)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" "abc123" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

# Get a public key
# cast call --rpc-url http://127.0.0.1:32873 0x0a1a630f85f9e58b345f6cb9197c51fa1db01639 'SetKey(uint256)(uint256[5],uint256[2])' "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")"
@test "Testing EIP6565 - Sign" {
    echo "Starting EIP6565 Sign Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Sign(uint256,uint256[2],string)" 0 "[0,0]" "abc123" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Sign(uint256,uint256[2],string)" 1 "[0,0]" "abc123" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Sign(uint256,uint256[2],string)" \
        115792089237316195423570985008687907853269984665640564039457584007913129639935 \
        "[115792089237316195423570985008687907853269984665640564039457584007913129639935,115792089237316195423570985008687907853269984665640564039457584007913129639935]" \
        "abc123" >&3

    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in {1.."$exponential_growth_limit"}; do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Sign(uint256,uint256[2],string)" \
            27066115479399555241574240779398896927011581316434074034167126962687364905698 \
            "[42559113093733082793542566282911713742375005736614813947385187293220506342480,109370305882734025219925353605107763559738011796832715623096498452877702410736]" \
            "$hash_value" >&3
        hash_value="$hash_value$hash_value"
    done

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Sign(uint256,uint256[2],string)" \
            27066115479399555241574240779398896927011581316434074034167126962687364905698 \
            "[42559113093733082793542566282911713742375005736614813947385187293220506342480,109370305882734025219925353605107763559738011796832715623096498452877702410736]" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - SignSlow" {
    echo "Starting EIP6565 SignSlow Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SignSlow(uint256,string)" 0 "abc123" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SignSlow(uint256,string)" 1 "abc123" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SignSlow(uint256,string)" \
        115792089237316195423570985008687907853269984665640564039457584007913129639935 \
        "abc123" >&3

    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in {1.."$exponential_growth_limit"}; do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SignSlow(uint256,string)" \
            27066115479399555241574240779398896927011581316434074034167126962687364905698 \
            "$hash_value" >&3
        hash_value="$hash_value$hash_value"
    done

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "SignSlow(uint256,string)" \
            27066115479399555241574240779398896927011581316434074034167126962687364905698 \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

# Get a public key
# cast call --rpc-url http://127.0.0.1:32873 0x0a1a630f85f9e58b345f6cb9197c51fa1db01639 'SetKey(uint256)(uint256[5],uint256[2])' "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")"
# [53319167224459106466702007959349135256467467536905411832330885206999252279614, 2284080886966133992729186839123998120798894513958078808115507875162306287204, 3246207250587195530816989123778609896848374867114298476970577533647877040319, 5104207593475419821130674724844498252015686184978827304375352455858058969127, 58862539542128022353275577081232159455015340604490348195085361478951058225917]
# [35849341243594196611585402578871739724534359549608202268592130981855193350768, 109934417611414458827248970371904155695069847997685404682729446397321486897950]
# cast call --rpc-url http://127.0.0.1:32873 0x0a1a630f85f9e58b345f6cb9197c51fa1db01639 "Sign(uint256,uint256[2],string)" 58862539542128022353275577081232159455015340604490348195085361478951058225917 "[35849341243594196611585402578871739724534359549608202268592130981855193350768,109934417611414458827248970371904155695069847997685404682729446397321486897950]" "john hilliard"
# 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad6956e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08
# None of these seem to veriy so something is wrong... But it still takes up space
@test "Testing EIP6565 - Verify" {
    echo "Starting EIP6565 Verify Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" "abc123" 0 0 "[1,2,3,4,5]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" "abc123" 1 1 "[1,2,3,4,5]" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" \
        "john hilliard" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
        "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3

    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in {1.."$exponential_growth_limit"}; do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" \
            "$hash_value" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
            hash_value="$hash_value$hash_value"
    done

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify(string,uint256,uint256,uint256[5])" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - Verify_LE" {
    echo "Starting EIP6565 Verify_LE Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" "abc123" 0 0 "[1,2,3,4,5]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" "abc123" 1 1 "[1,2,3,4,5]" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" \
        "john hilliard" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
        "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3

    hash_value="00112233445566778899AABBCCDDEEFF"
    for i in {1.."$exponential_growth_limit"}; do
        cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" \
            "$hash_value" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
            hash_value="$hash_value$hash_value"
    done

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "Verify_LE(string,uint256,uint256,uint256[5])" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" 0x392ffe32f4b301dd3f77870c863847a53d394ab17d972e0b01fadc45402ad695 0x6e0dfbdf624e7184286c487907f7a389543d0c43ad9e5f27a5c749d4e5e72f08 \
            "[53319167224459106466702007959349135256467467536905411832330885206999252279614,2284080886966133992729186839123998120798894513958078808115507875162306287204,3246207250587195530816989123778609896848374867114298476970577533647877040319,5104207593475419821130674724844498252015686184978827304375352455858058969127,58862539542128022353275577081232159455015340604490348195085361478951058225917]" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - ecPow128" {
    echo "Starting EIP6565 ecPow128 Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" 0 0 0 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" 1 1 1 1 >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
            115792089237316195423570985008687907853269984665640564039457584007913129639935 \
           >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..512}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "ecPow128(uint256,uint256,uint256,uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing EIP6565 - edCompress" {
    echo "Starting EIP6565 edCompress Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" "[0,0]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" "[1,1]" >&3

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
            "[115792089237316195423570985008687907853269984665640564039457584007913129639935,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
            "[0,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
            "[1,115792089237316195423570985008687907853269984665640564039457584007913129639935]" >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
            "[0x00,0x$(head -c 31 /dev/urandom | xxd -p | tr -d "\n")]" >&3
        cur_nonce=$((cur_nonce + 1))
    done
    for i in {1..256}; do
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_EIP6565.json.deploy.json)" "edCompress(uint256[2])" \
            "[0x01,0x$(head -c 31 /dev/urandom | xxd -p | tr -d "\n")]" >&3
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing RIP7212 - verify" {
    echo "Starting RIP7212 verify Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256,uint256)" 0x0000000000000000000000000000000000000000000000000000000000000000 0 0 0 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256,uint256)" 0x0000000000000000000000000000000000000000000000000000000000000001 1 1 1 1 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_RIP7212.json.deploy.json)" \
            "verify(bytes32,uint256,uint256,uint256,uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}

@test "Testing ECDSAB4 - verify" {
    echo "Starting ECDSAB4 verify Tests" >&3

    cd "$TEMP_DIR/crypto-lib" || exit 1

    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256[10],uint256)" 0x0000000000000000000000000000000000000000000000000000000000000000 0 0 [0,0,0,0,0,0,0,0,0,0] 0 >&3
    cast send --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)" "verify(bytes32,uint256,uint256,uint256[10],uint256)" 0x0000000000000000000000000000000000000000000000000000000000000001 1 1 [1,1,1,1,1,1,1,1,1,1] 1 >&3

    cur_nonce=$(cast nonce --rpc-url "$l2_rpc_url" "$l2_eth_address")
    for i in {1..256}; do
        set -x
        cast send --async --nonce $cur_nonce --private-key "$l2_private_key" --rpc-url "$l2_rpc_url" --json "$(jq -r '.contractAddress' SCL_ECDSAB4.json.deploy.json)" \
            "verify(bytes32,uint256,uint256,uint256[10],uint256)" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" \
            "[0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n"),0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")]" \
            "0x$(head -c 32 /dev/urandom | xxd -p | tr -d "\n")" >&3
        set +x
        cur_nonce=$((cur_nonce + 1))
    done
}