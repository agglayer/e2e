#!/usr/bin/env bats
# bats file_tags=standard-kurtosis,execution

# This file tests the deployment of Railgun - https://docs.railgun.org/developer-guide/wallet/getting-started and interacting with its contracts.

setup() {
    kurtosis_enclave_name="${ENCLAVE_NAME:-op}"

    l2_private_key=${L2_PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    l2_rpc_url=${L2_RPC_URL:-"$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"}

    export TEMP_DIR
    TEMP_DIR=$(mktemp -d)
}

teardown_file() {
    rm -rf "$TEMP_DIR"
}

# bats test_tags=railgun
@test "Setup Railgun" {
    echo "Temp working directory: $TEMP_DIR" >&3

    # Clone Railgun contracts
    echo "Cloning Railgun repo..." >&3
    git clone https://github.com/Railgun-Privacy/contract "$TEMP_DIR/railgun"
    cd "$TEMP_DIR/railgun" || exit 1

    # Install and compile
    echo "Installing Railgun contracts and dependencies..." >&3
    npm install
    npx hardhat compile

    sed -i '/defaultNetwork:/a\
    networks: {\
        executiontests: {\
        url: "'"$l2_rpc_url"'",\
        accounts: ["'"$l2_private_key"'"],\
        },\
    },' "$TEMP_DIR/railgun/hardhat.config.ts"

    echo "Railgun repo setup completed successfully"

    echo "Running Railgun hardhat tests" >&3
    npx hardhat deploy:test --network executiontests >&3
}
