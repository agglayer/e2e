#!/bin/env bash
#
# Attach New Committee Members Scenario Test
# =================================
#
# This script tests the process of attaching new AggOracle Committee members
# and AggSender Validators to an existing Kurtosis CDK network.
#
# Prerequisites:
# -------------
#
# 1. Set up environment variables in ../common/.env or export them:
#    - KURTOSIS_PACKAGE_HASH: Git hash of the kurtosis-cdk package to use
#    - ENCLAVE_NAME: Name for the Kurtosis enclave (e.g., "op")
#    - AGGSENDER_VALIDATOR_NUMBER: Total number of validators (e.g., 5)
#    - AGGSENDER_MULTISIG_THRESHOLD: Multisig threshold (e.g., 3)
#    - AGGORACLE_COMMITTEE_QUORUM: Committee quorum (e.g., 1)
#    - AGGORACLE_COMMITTEE_NUMBER: Total committee members (e.g., 4)
#    - KEYSTORE_PASSWORD: Password for keystore files
#    - ADMIN_PRIVATE_KEY: Private key with admin permissions
#
# 2. Prepare configuration directories with keystore files:
#    You can also use the existing configs. Add more if needed.
#    - ./configs-aggoracle-committee-002/
#    - ./configs-aggoracle-committee-003/
#    - ./configs-aggoracle-committee-004/
#    - ./configs-aggsender-validator-003/
#    - ./configs-aggsender-validator-004/
#    - ./configs-aggsender-validator-005/
#
# What this script does:
# ---------------------
# 1. Downloads and modifies Kurtosis CDK configuration
# 2. Spins up a CDK network with AggSender Validators and AggOracle Committee enabled
# 3. Extracts contract addresses and configures new committee members
# 4. Adds new AggOracle Committee members to the contract
# 5. Starts AggOracle Committee containers
# 6. Updates AggSender Validator signers and threshold
# 7. Starts AggSender Validator containers
#
# Usage:
# ------
# 1. Navigate to the script directory:
#    cd scenarios/attach-new-committee-members/
#
# 2. Make sure the script is executable if not already:
#    chmod +x run.sh
#
# 3. Source the env file
#    set -a
#    source env.example
#    set +a
#
# 4. Run the script:
#    ./run.sh
#
# Expected Output:
# ---------------
# The script will output progress logs showing each step.
# It will create a Kurtosis enclave, deploy contracts, and start Docker
# containers for the new committee members and validators.
#
set -e
# shellcheck source=scenarios/common/load-env.sh
source ../common/load-env.sh
load_env

# Sourced values from env file
kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
agg_sender_validator_total_number="$AGGSENDER_VALIDATOR_NUMBER"
agg_sender_multisig_threshold="$AGGSENDER_MULTISIG_THRESHOLD"
agg_oracle_committee_quorum="$AGGORACLE_COMMITTEE_QUORUM"
agg_oracle_committee_total_members="$AGGORACLE_COMMITTEE_NUMBER"

# curl aggchain-ecdsa-multisig.yml file
echo "📥 Downloading aggchain-ecdsa-multisig.yml file..."
curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/op-geth/aggchain-ecdsa-multisig.yml" > initial-aggchain-ecdsa-multisig.yml

# Modify configs to enable Aggsender Validator and AggOracle Committee
echo "🔧 Modifying YAML config to enable Aggsender Validator and AggOracle Committee..."
# shellcheck disable=SC2016
yq '.args.use_agg_sender_validator = true' initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

yq '.args.agg_sender_validator_total_number = '"$agg_sender_validator_total_number" initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

yq '.args.agg_sender_multisig_threshold = '"$agg_sender_multisig_threshold" initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

yq '.args.use_agg_oracle_committee = true' initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

yq '.args.agg_oracle_committee_quorum = '"$agg_oracle_committee_quorum" initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

yq '.args.agg_oracle_committee_total_members = '"$agg_oracle_committee_total_members" initial-aggchain-ecdsa-multisig.yml > temp.yml && mv temp.yml initial-aggchain-ecdsa-multisig.yml

# Spin up the network
echo "🚀 Starting Kurtosis network with enclave: $kurtosis_enclave_name"
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "initial-aggchain-ecdsa-multisig.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"

echo "🔗 Getting admin_private_key and keystore_password values..."
contracts_url="$(kurtosis port print $kurtosis_enclave_name contracts-001 http)"
admin_private_key="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_admin_private_key')"
keystore_password="$(curl -s "${contracts_url}/opt/input/input_args.json" | jq -r '.args.zkevm_l2_keystore_password')"

echo "🔗 Getting L1 and L2 RPC URLs..."
l1_rpc_url="http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)"
l2_rpc_url="$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)"

echo "L1 RPC URL: $l1_rpc_url"
echo "L2 RPC URL: $l2_rpc_url"

# Find the docker network running
echo "🔍 Finding Docker network for Kurtosis enclave..."
kurtosis_network=$(docker ps --filter "name=${kurtosis_enclave_name}" --format "table {{.Names}}\t{{.Networks}}" | grep -v NETWORKS | head -1 | awk '{print $2}')
echo "Kurtosis network: $kurtosis_network"

# Fetch aggoracleCommittee contract address and insert it into the configs
echo "📄 Fetching AggOracle Committee contract address..."
aggoracle_committee_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "jq -r .aggOracleCommitteeProxyAddress /opt/zkevm/combined.json")
echo "AggOracle Committee Address: $aggoracle_committee_address"

echo "⚙️ Updating config files with AggOracle Committee address..."
sed -i "s/AggOracleCommitteeAddr = .*/AggOracleCommitteeAddr = \"$aggoracle_committee_address\"/" ./configs-aggoracle-committee-002/config.toml
sed -i "s/AggOracleCommitteeAddr = .*/AggOracleCommitteeAddr = \"$aggoracle_committee_address\"/" ./configs-aggoracle-committee-003/config.toml
sed -i "s/AggOracleCommitteeAddr = .*/AggOracleCommitteeAddr = \"$aggoracle_committee_address\"/" ./configs-aggoracle-committee-004/config.toml

# Get the address from the keystore
echo "🔑 Extracting addresses from aggoracle committee keystores..."
aggoracle_committee_002_address=$(cast wallet address --keystore "./configs-aggoracle-committee-002/aggoracle-2.keystore" --password "$keystore_password")
aggoracle_committee_003_address=$(cast wallet address --keystore "./configs-aggoracle-committee-003/aggoracle-3.keystore" --password "$keystore_password")
aggoracle_committee_004_address=$(cast wallet address --keystore "./configs-aggoracle-committee-004/aggoracle-4.keystore" --password "$keystore_password")

echo "AggOracle Committee 002 Address: $aggoracle_committee_002_address"
echo "AggOracle Committee 003 Address: $aggoracle_committee_003_address"  
echo "AggOracle Committee 004 Address: $aggoracle_committee_004_address"

# Add new aggoracle-committee member
echo "📝 Adding new AggOracle Committee members to contract..."
cast send "$aggoracle_committee_address" "addOracleMember(address)" "$aggoracle_committee_002_address" --rpc-url $l2_rpc_url --private-key $admin_private_key
cast send "$aggoracle_committee_address" "addOracleMember(address)" "$aggoracle_committee_003_address" --rpc-url $l2_rpc_url --private-key $admin_private_key
cast send "$aggoracle_committee_address" "addOracleMember(address)" "$aggoracle_committee_004_address" --rpc-url $l2_rpc_url --private-key $admin_private_key

# Check new aggoracle-committee members are added by calling the contract
echo "✅ Verifying AggOracle Committee members were added..."
cast call "$aggoracle_committee_address" "getAllAggOracleMembers()(address[])" --rpc-url $l2_rpc_url

# Spin up new aggoracle-committee container and attach to existing docker network
echo "🐳 Starting AggOracle Committee container..."
docker run -d --name aggkit-001-aggoracle-committee-002 \
  --network "$kurtosis_network" \
  -v ./configs-aggoracle-committee-002:/etc/aggkit \
  -p 5576 \
  -p 6060 \
  ghcr.io/agglayer/aggkit:0.7.0-beta8 \
  run --cfg=/etc/aggkit/config.toml --components=aggoracle

# Depending on the desired number of aggoracle-committee members, we can spin up more
# docker run -d --name aggkit-001-aggoracle-committee-003 \
#   --network "$kurtosis_network" \
#   -v ./configs-aggoracle-committee-003:/etc/aggkit \
#   -p 5576 \
#   -p 6060 \
#   ghcr.io/agglayer/aggkit:0.7.0-beta8 \
#   run --cfg=/etc/aggkit/config.toml --components=aggoracle

# docker run -d --name aggkit-001-aggoracle-committee-004 \
#   --network "$kurtosis_network" \
#   -v ./configs-aggoracle-committee-004:/etc/aggkit \
#   -p 5576 \
#   -p 6060 \
#   ghcr.io/agglayer/aggkit:0.7.0-beta8 \
#   run --cfg=/etc/aggkit/config.toml --components=aggoracle

# Fetch rollup contract address and insert it into the configs
echo "📄 Fetching AggLayer Gateway contract address..."
agglayer_gateway_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "jq -r .aggLayerGatewayAddress /opt/zkevm/combined.json")
echo "AggLayer Gateway Address: $agglayer_gateway_address"

# Get the address from the keystore
echo "🔑 Extracting addresses from aggsender validator keystores..."
aggsender_validator_003_address=$(cast wallet address --keystore "./configs-aggsender-validator-003/aggsendervalidator-3.keystore" --password "$keystore_password")
aggsender_validator_004_address=$(cast wallet address --keystore "./configs-aggsender-validator-004/aggsendervalidator-4.keystore" --password "$keystore_password")
aggsender_validator_005_address=$(cast wallet address --keystore "./configs-aggsender-validator-005/aggsendervalidator-5.keystore" --password "$keystore_password")

echo "AggSender Validator 003 Address: $aggsender_validator_003_address"
echo "AggSender Validator 004 Address: $aggsender_validator_004_address"
echo "AggSender Validator 005 Address: $aggsender_validator_005_address"

# Add existing and new aggsender-validators
echo "📄 Getting existing AggSender Validator addresses from rollup parameters..."
aggsender_validator_001_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "jq -r '.aggchainParams.signers[0][0]' /opt/zkevm/create_rollup_parameters.json")
aggsender_validator_002_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 "jq -r '.aggchainParams.signers[1][0]' /opt/zkevm/create_rollup_parameters.json")

echo "Existing AggSender Validator 001 Address: $aggsender_validator_001_address"
echo "Existing AggSender Validator 002 Address: $aggsender_validator_002_address"

echo "📝 Updating signers and threshold on AggLayer Gateway..."
cast send "$agglayer_gateway_address" \
  "updateSignersAndThreshold((address,uint256)[],(address,string)[],uint256)" \
  "[]" \
  "[($aggsender_validator_001_address,\" \"),($aggsender_validator_002_address,\"http://aggkit-001-aggsender-validator-002:5578\"),($aggsender_validator_003_address,\"http://aggkit-001-aggsender-validator-003:5578\"),($aggsender_validator_004_address,\"http://aggkit-001-aggsender-validator-004:5578\"),($aggsender_validator_005_address,\"http://aggkit-001-aggsender-validator-005:5578\")]" \
  "$agg_sender_multisig_threshold" \
  --rpc-url $l1_rpc_url \
  --private-key $admin_private_key

# Check the signers are added
echo "✅ Verifying signers were updated..."
cast call "$agglayer_gateway_address" "getAggchainSignerInfos()((address,string)[])" --rpc-url "$l1_rpc_url"

# Spin up new aggkit-001-aggsender-validator container and attach to existing docker network
echo "🐳 Starting AggSender Validator container..."
docker run -d --name aggkit-001-aggsender-validator-003 \
  --network "$kurtosis_network" \
  -v ./configs-aggsender-validator-003:/etc/aggkit \
  -p 5576 \
  -p 5578 \
  -p 6060 \
  ghcr.io/agglayer/aggkit:0.7.0-beta8 \
  run --cfg=/etc/aggkit/config.toml --components=aggsender-validator

# Depending on the desired number of aggsender-validators, we can spin up more
# docker run -d --name aggkit-001-aggsender-validator-004 \
#   --network "$kurtosis_network" \
#   -v ./configs-aggsender-validator-004:/etc/aggkit \
#   -p 5576 \
#   -p 5578 \
#   -p 6060 \
#   ghcr.io/agglayer/aggkit:0.7.0-beta8 \
#   run --cfg=/etc/aggkit/config.toml --components=aggsender-validator

# docker run -d --name aggkit-001-aggsender-validator-005 \
#   --network "$kurtosis_network" \
#   -v ./configs-aggsender-validator-005:/etc/aggkit \
#   -p 5576 \
#   -p 5578 \
#   -p 6060 \
#   ghcr.io/agglayer/aggkit:0.7.0-beta8 \
#   run --cfg=/etc/aggkit/config.toml --components=aggsender-validator

echo "✅ Script completed successfully!"
exit