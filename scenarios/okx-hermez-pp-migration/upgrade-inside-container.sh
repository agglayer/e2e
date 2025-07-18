#!/usr/bin/env bash
set -euxo pipefail

# The rest of these commands would run within the docker shell
apt-get update
apt-get -y install jq zile

TARGET="/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1"

# change into it
cd "$TARGET"

# Configure upgrade parameters
jq '.tagSCPreviousVersion = "FEP-v10.0.0-rc.0"' upgrade_parameters.json.example > _t; mv _t upgrade_parameters.json
jq '.rollupManagerAddress = "0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2"' upgrade_parameters.json > _t; mv _t upgrade_parameters.json
# We're setting a very short timelockDelay here in order to speed things up
jq '.timelockDelay = "60"' upgrade_parameters.json > _t; mv _t upgrade_parameters.json
jq '.timelockSalt = "0x0000000000000000000000000000000000000000000000000000000000000000"' upgrade_parameters.json > _t; mv _t upgrade_parameters.json
jq '.test = true' upgrade_parameters.json > _t; mv _t upgrade_parameters.json


# Prepare environment
cd /agglayer-contracts
mkdir /agglayer-contracts/.openzeppelin
cp upgrade/upgradePessimistic/mainnet-info/mainnet.json .openzeppelin/mainnet.json
git config --global --add safe.directory /agglayer-contracts
npm i

export MAINNET_PROVIDER=http://anvil:8545
npx hardhat run ./upgrade/upgrade-rollupManager-v0.3.1/upgrade-rollupManager-v0.3.1.ts --network mainnet


# Prepare new rollup type configuration
cat << EOF > tools/addRollupType/add_rollup_type.json
{
    "type": "Timelock",
    "consensusContract": "PolygonPessimisticConsensus",
    "consensusContractAddress": "0x18C45DD422f6587357a6d3b23307E75D42b2bc5B",
    "polygonRollupManagerAddress": "0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2",
    "verifierAddress": "0x0459d576A6223fEeA177Fb3DF53C9c77BF84C459",
    "description": "Type: Pessimistic, Version: v0.3.3, genesis: /ipfs/QmUXnRoPbUmZuEZCGyiHjEsoNcFVu3hLtSvhpnfBS2mAYU",
    "forkID": 12,
    "timelockDelay": 60,
    "programVKey": "0x00eff0b6998df46ec388bb305618089ae3dc74e513e7676b2e1909694f49cc30",
    "outputPath": "add_rollup_type_output.json"
}
EOF


# Add the new rollup type
npx hardhat run ./tools/addRollupType/addRollupType.ts --network mainnet

# we can exit the shell show
exit