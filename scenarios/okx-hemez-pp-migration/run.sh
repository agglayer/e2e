#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from .env if present
if [[ -f ".env" ]]; then
  echo "Loading environment from .env"
  # Export all variables defined in .env
  set -a
  source ".env"
  set +a
fi

# ====================== STEP 1 Create a temporary working directory =========
echo "Starting STEP 1 Create a temporary working directory "
# This directory will hold all test components
tdir=$(mktemp -d)
echo "Created temporary directory: $tdir"

# Create required subdirectories
for sub in anvil agglayer aggkit; do
  mkdir -p "$tdir/$sub"
done

# Set open permissions to allow all users full access
chmod -R 777 "$tdir"

echo "Working directory structure created under: $tdir"

echo "END STEP 1 Create a temporary working directory "
# ====================== END STEP 1 Create a temporary working directory =======

# ==================STEP 2: Build Special Aggkit Version========================
echo "Starting STEP 2: Build Special Aggkit Version"
# We need a specific branch with the certificate creation code for this upgrade
# Ensure $tdir is defined - already defined above
if [[ -z "${tdir:-}" ]]; then
  echo "Error: tdir is not set."
  exit 1
fi

echo "Building special aggkit version in $tdir"
pushd "$tdir" > /dev/null

# Clone or update the repository in aggkit-code
target="aggkit-code"
if [[ -d "$target" ]]; then
  echo "Directory $target exists; fetching updates"
  pushd "$target" > /dev/null
  git fetch --all
else
  echo "Cloning aggkit repository"
  git clone git@github.com:agglayer/aggkit.git "$target"
  pushd "$target" > /dev/null
fi

# Switch to the feature branch
echo "Checking out feat/hermez_to_pp_upgrade_patch"
git switch feat/hermez_to_pp_upgrade_patch

# Build Docker image
 echo "Building Docker image..."
make build-docker

# Return to original directory
popd > /dev/null
popd > /dev/null

echo "Special Aggkit version built successfully in $tdir/$target"
echo "END STEP 2: Build Special Aggkit Version"
# =======================END STEP 2 Build Special Aggkit Version ==============

# =======================STEP 3 Prepare Agglayer Contracts=====================
echo "Starting STEP 3 Prepare Agglayer Contracts"
# Clone the specific version of contracts needed for the rollup manager upgrade:
pushd "$tdir" > /dev/null             # cd into your target dir, hide output
git clone git@github.com:agglayer/agglayer-contracts.git
pushd agglayer-contracts > /dev/null  # cd into the repo, hide output
git checkout v11.0.0-rc.0             # switch to the exact tag
# Return to original directory
popd > /dev/null                      # back to $tdir
popd > /dev/null                      # back to where you started
echo "END STEP 3  Prepare Agglayer Contracts"
# ========================END STEP 3  Prepare Agglayer Contracts=================


# =======================STEP 4: L1 Environment Setup=============================
echo "Starting STEP 4  L1 Environment Setup"
#** Start Anvil Shadow Fork
# Anvil is an important component in the test process. We're going to
# use it to create a shadow fork of L1 mainnet.

# Directory for Anvil state
anvil_dir="$tdir/anvil"

# Verify Anvil state directory exists
if [[ ! -d "$anvil_dir" ]]; then
  echo "Error: Anvil directory $anvil_dir does not exist."
  exit 1
fi

# Ensure Docker network 'rpcs' exists
if ! docker network inspect rpcs >/dev/null 2>&1; then
  echo "Creating Docker network 'rpcs'"
  docker network create rpcs
fi

echo "Starting Anvil shadow fork using state directory: $anvil_dir"
echo "Using fork URL: $TENDERLY_FORK_URL"

echo "Starting Anvil shadow fork using state directory: $anvil_dir"

# Start Anvil with mainnet fork
# Block 22688021 is chosen as it's before the upgrade but recent enough

docker run -d -p 3000:8545 \
    --rm --name anvil \
    --network rpcs \
    --entrypoint "anvil" \
    ghcr.io/foundry-rs/foundry:latest \
    --block-time 12 \
    --host 0.0.0.0 \
    --fork-url "$TENDERLY_FORK_URL" \
    --state "$anvil_dir" \
    --fork-block-number 22688021

if [[ $? -eq 0 ]]; then
  echo "Anvil is running at http://localhost:3000"
else
  echo "Failed to start Anvil shadow fork" >&2
  exit 1
fi
echo "END STEP 4  L1 Environment Setup"
# =============================END STEP 4 ==============================================


# ============================= STEP 5 Configure Fork Environment ======================
echo "Starting STEP 5 Configure Fork Environment"
#There are two quick changes we'll make right away. First we'll use
#~evm_setNextBlockTimestamp~ to adjust the timestamp on the chain. If
#we skip this step various things can go wrong. Second we'll adjust the
#~_minDelay~ of the timelock contract. If we don't do this, we'll need
#to wait a few days in order to do this test. By running ~forge inspect
#PolygonZkEVMTimelock storage~ we got the storage layout ad we have a
#pretty good sense which storage slot needs to be modified to.
# Example
#╭-------------+---------------------------------------------------+------+--------+-------+---------------------------------------------------------╮
#| Name        | Type                                              | Slot | Offset | Bytes | Contract                                                |
#+===================================================================================================================================================+
#| _roles      | mapping(bytes32 => struct AccessControl.RoleData) | 0    | 0      | 32    | contracts/PolygonZkEVMTimelock.sol:PolygonZkEVMTimelock |
#|-------------+---------------------------------------------------+------+--------+-------+---------------------------------------------------------|
#| _timestamps | mapping(bytes32 => uint256)                       | 1    | 0      | 32    | contracts/PolygonZkEVMTimelock.sol:PolygonZkEVMTimelock |
#|-------------+---------------------------------------------------+------+--------+-------+---------------------------------------------------------|
#| _minDelay   | uint256                                           | 2    | 0      | 32    | contracts/PolygonZkEVMTimelock.sol:PolygonZkEVMTimelock |
#╰-------------+---------------------------------------------------+------+--------+-------+---------------------------------------------------------╯

# Ensure TIMLOCK_ADDRESS is provided via environment variable
if [[ -z "${TIMELOCK_ADDRESS:-}" ]]; then
  echo "Error: TIMELOCK_ADDRESS is not set. Please export your Timelock contract address as TIMELOCK_ADDRESS."
  exit 1
fi

# Wait at least 60 seconds
sleep 60

echo "Setting next block timestamp to current time"
echo "L1 RPC URL $L1_RPC_URL"
cast rpc --rpc-url http://127.0.0.1:3000 evm_setNextBlockTimestamp $(date +%s)


echo "Overriding _minDelay for Timelock"
cast rpc --rpc-url http://127.0.0.1:3000 anvil_setStorageAt "$TIMELOCK_ADDRESS" $(cast to-uint256 2) $(cast to-uint256 1)
echo "_minDelay override complete"

echo "END STEP 5 Configure Fork Environment"
# ============================= END STEP 5 Configure Fork Environment ===================================

# ============================= STEP 6 Create Test Keys ==============================================
echo "Starting STEP 6 Create Test Keys"
# We're runing a shadow fork of mainnet. This means we'll need new keys
# for the critical roles because we don't have access to the real OKX
# sequencer key or the real Agglayer key. We're going to create two new
# keys and store them in a configuration directory. Later on, we'll grant
# roles for these keys.

# Create the Agglayer test account
# cast wallet new
# Successfully created new keypair.
# Address:     0xaff8Ed903d079cD0E7fE29138b37B6AC8fFe4AdF
# Private key: "$AGGLAYER_TEST_ACCOUNT_PRIVATE_KEY"

echo "AggLayer Private Key: $AGGLAYER_TEST_ACCOUNT_PRIVATE_KEY"
echo "If prompted for password use: randompassword"
cast wallet import --private-key "$AGGLAYER_TEST_ACCOUNT_PRIVATE_KEY" --keystore-dir conf/ agglayer.keystore

# Create the Sequencer test account
# cast wallet new
# Successfully created new keypair.
# Address:     0x8Ad44b2b5368a3043901ee373dC6D400c6A2e83F
# Private key: "$SEQ_TEST_ACCOUNT_PRIVATE_KEY"

echo "Sequencer Private Key: $AGGLAYER_TEST_ACCOUNT_PRIVATE_KEY"
echo "If prompted for password use: randompassword"
cast wallet import --private-key "$SEQ_TEST_ACCOUNT_PRIVATE_KEY" --keystore-dir conf/ sequencer.keystore

echo "finished creating test accounts"
echo "To setup your own password, locate the password variable in: agglayer-config.toml & aggkit.toml files and update them with yours"

echo "END STEP 6 Create Test Keys"
# ============================= END STEP 6 Create Test Keys ======================

# =============================  STEP 7: Start Agglayer Components ===============
# At this point, we should be good to startup the Agglayer and Agglayer Prover.
# you will need an SP1 network key to run the agglayer-prover
echo "Starting STEP 7: Start Agglayer Components"

sp1_key="$SP1_KEY"

echo "The SP1 key: $SP1_KEY"
echo "Start the Agglayer Prover"
echo "The Network RPC URL: $NETWORK_RPC_URL"
docker run -d --rm \
    --name agglayer-prover \
    --network rpcs \
    -v "$PWD/conf:/etc/agglayer:ro" \
    -e "SP1_PRIVATE_KEY=$sp1_key" \
    -e "NETWORK_RPC_URL=$NETWORK_RPC_URL" \
    -e "RUST_BACKTRACE=1" \
    -e "NETWORK_PRIVATE_KEY=$sp1_key" \
    --entrypoint agglayer \
    ghcr.io/agglayer/agglayer:0.3.3 \
    prover --cfg /etc/agglayer/agglayer-prover-config.toml

 # Wait at least 60 seconds
sleep 60

echo "Starting the Agglayer Node"
docker run -d --rm \
    --name agglayer-node \
    --network rpcs \
    -v "$PWD/conf:/etc/agglayer:ro" \
    -v "$tdir/agglayer:/var/agglayer" \
    --entrypoint agglayer \
    ghcr.io/agglayer/agglayer:0.3.3 \
    run --cfg /etc/agglayer/agglayer-config.toml

 echo "AggLayer Prover & Node started succesfully"

 # Wait at least 60 seconds
sleep 60
echo "END STEP 7: Start Agglayer Components"
# =============================  END STEP 7: Start Agglayer Components ===============

# =============================  STEP 8: Permission Changes ==========================
# Grant Sequencer role
# Set up the new test account as trusted sequencer:
echo "Starting STEP 8: Permission Changes"
# Impersonate OKX admin account to grant permissions
echo "OKX Admin Account: $OKX_ADMIN_ACCOUNT"
cast rpc --rpc-url http://127.0.0.1:3000 anvil_impersonateAccount "$OKX_ADMIN_ACCOUNT"

# Set our test account as the trusted sequencer
cast send --unlocked --from "$OKX_ADMIN_ACCOUNT" --rpc-url http://127.0.0.1:3000 0x2B0ee28D4D51bC9aDde5E58E295873F61F4a0507 'setTrustedSequencer(address)' 0x8Ad44b2b5368a3043901ee373dC6D400c6A2e83F

# Stop impersonation
cast rpc --rpc-url http://127.0.0.1:3000 anvil_stopImpersonatingAccount "$OKX_ADMIN_ACCOUNT"
#+end_src


# Grant Aggregator Role
# We're going to make a similar call in order to grant the
# ~TRUSTED_AGGREGATOR_ROLE~ to our new Agglayer key.

#+begin_src bash
# Impersonate Polygon admin to grant aggregator role
echo "Polygon Admin Account: $POLYGON_ADMIN_ACCOUNT"
cast rpc --rpc-url http://127.0.0.1:3000 anvil_impersonateAccount "$POLYGON_ADMIN_ACCOUNT"

# Grant TRUSTED_AGGREGATOR_ROLE to our Agglayer account
cast send --unlocked --from "$POLYGON_ADMIN_ACCOUNT" --rpc-url http://127.0.0.1:3000 0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2 'grantRole(bytes32 role, address account)' $(cast keccak TRUSTED_AGGREGATOR_ROLE) 0xaff8Ed903d079cD0E7fE29138b37B6AC8fFe4AdF

# Stop impersonation
cast rpc --rpc-url http://127.0.0.1:3000 anvil_stopImpersonatingAccount "$POLYGON_ADMIN_ACCOUNT"

# Fund the Agglayer account for gas fees
cast rpc --rpc-url http://127.0.0.1:3000 anvil_setBalance 0xaff8Ed903d079cD0E7fE29138b37B6AC8fFe4AdF 1000000000000000000
#+end_src
echo "Finished Permission Changes"
echo "END STEP 8: Permission Changes"
# =============================  END STEP 8: Permission Changes ========================

# =============================  STEP 9: Contract Upgrade Process ======================
## Prepare Rollup Manager Upgrade
## Run upgrade scripts in the contracts repository:

echo "Starting STEP 9: Contract Upgrade Process"
# Start interactive container for running upgrade scripts
chmod +x upgrade-inside-container.sh

docker run --rm \
  --network rpcs \
  -v "$tdir/agglayer-contracts":/agglayer-contracts \
  -v "$PWD/conf":/etc/conf:ro \
  -v "$PWD/upgrade-inside-container.sh":/usr/local/bin/upgrade.sh:ro \
  node:22-bookworm \
  /usr/local/bin/upgrade.sh

echo "END STEP 9: Contract Upgrade Process"
# =============================  END STEP 9: Contract Upgrade Process ======================

# =============================  STEP 10: Execute Timelock Transactions ======================
# At this point, we've generated the timelock transactions that we need
# to execute. This will require impersonating the rollup manager admins
# account

echo "Starting STEP 10: Execute Timelock Transactions"
#+begin_src bash
# Impersonate rollup manager admin
cast rpc --rpc-url http://127.0.0.1:3000 anvil_impersonateAccount "$POLYGON_ADMIN_ACCOUNT"

# Schedule the new rollup type addition
cast send \
    --unlocked \
    --from "$POLYGON_ADMIN_ACCOUNT" \
    --rpc-url http://127.0.0.1:3000 \
    $(jq -r '.timelockContractAddress' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json) \
    $(jq -r '.scheduleData' $tdir/agglayer-contracts/tools/addRollupType/add_rollup_type_output.json)

# Wait at least 60 seconds
sleep 60

# Execute the rollup type addition
cast send \
    --unlocked \
    --from "$POLYGON_ADMIN_ACCOUNT" \
    --rpc-url http://127.0.0.1:3000 \
    $(jq -r '.timelockContractAddress' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json) \
    $(jq -r '.executeData' $tdir/agglayer-contracts/tools/addRollupType/add_rollup_type_output.json)

# Schedule the rollup manager upgrade
cast send \
    --unlocked \
    --from "$POLYGON_ADMIN_ACCOUNT" \
    --rpc-url http://127.0.0.1:3000 \
    $(jq -r '.timelockContractAddress' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json) \
    $(jq -r '.scheduleData' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json)

# Wait at least 60 seconds
sleep 60

# Execute the rollup manager upgrade
cast send \
    --unlocked \
    --from "$POLYGON_ADMIN_ACCOUNT" \
    --rpc-url http://127.0.0.1:3000 \
    $(jq -r '.timelockContractAddress' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json) \
    $(jq -r '.executeData' $tdir/agglayer-contracts/upgrade/upgrade-rollupManager-v0.3.1/upgrade_output.json)

# Stop impersonation
cast rpc --rpc-url http://127.0.0.1:3000 anvil_stopImpersonatingAccount "$POLYGON_ADMIN_ACCOUNT"
#+end_src
echo "END STEP 10: Execute Timelock Transactions"
# =============================  END STEP 10: Execute Timelock Transactions ======================


# =============================  STEP 11: Verify Upgrade ==========================================
# Now we can do a few sanity checks to make sure that everything worked
# as expected.
echo "Starting STEP 11: Verify Upgrade"

# Check rollup manager version (should be al-v0.3.1)
cast call --rpc-url http://127.0.0.1:3000 0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2 "ROLLUP_MANAGER_VERSION()(string)"

# Check rollup type count (should be 11)
cast call --rpc-url http://127.0.0.1:3000 0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2 "rollupTypeCount() external view returns (uint32)"

echo "END STEP 11: Verify Upgrade"
# =============================  END STEP 11: Verify Upgrade ==========================================


# =============================  STEP 12: Execute Migration ==========================================
# Assuming the rollup manager is upgraded and the rollup type count is
# 11 now, we should be good to proceed with the actual update.
echo "Starting STEP 12: Execute Migration"
# Impersonate admin for migration
cast rpc --rpc-url http://127.0.0.1:3000 anvil_impersonateAccount "$POLYGON_ADMIN_ACCOUNT"

# Initialize migration of rollup 3 (OKX) to type 11 (PP)
cast send \
    --unlocked \
    --from "$POLYGON_ADMIN_ACCOUNT" \
    --rpc-url http://127.0.0.1:3000 \
    0x5132A183E9F3CB7C848b0AAC5Ae0c4f0491B7aB2 "initMigrationToPP(uint32,uint32)" 3 11


# Stop impersonation
cast rpc --rpc-url http://127.0.0.1:3000 anvil_stopImpersonatingAccount "$POLYGON_ADMIN_ACCOUNT"

echo "END STEP 12: Execute Migration"
# =============================  END STEP 12: Execute Migration ==========================================


# =============================   STEP 13: Testing and Validation ==========================================
# Run Aggkit for Certificate Settlement
# At this point, the rollup should be upgraded to PP on L1. There are a
# lot of tests that need to be done. This is still a work in
# progress. As a starting point, we should run the aggkit and ensure a
# certificate can be settled:

# Run aggkit with specific components
echo "Run aggkit with specific components"
docker run \
    --rm \
    --name aggkit \
    --network rpcs \
    -v $tdir/aggkit:/tmp \
    -v $PWD/conf:/etc/aggkit \
    aggkit:local run --cfg=/etc/aggkit/aggkit.toml --components=aggsender,bridge

echo "If everything works, we should see this message at the end"
echo "================================================================================================================================================================================================================================================================"
#2025-06-13T14:09:23.304Z        INFO    aggsender/aggsender.go:174      Halting aggsender since certificate got sent successfully for end block %d17428134      {"pid": 1, "version": "v0.3.0-beta1-39-g0de426e", "module": "aggsender"}
#panic: AggSender halted after sending certificate until end block 17428134

#goroutine 157 [running]:
#github.com/agglayer/aggkit/aggsender.(*AggSender).upgradeUntilBlockAndHalt(0xc0003e8000, {0x1b4b238, 0x2717720}, 0x109eea6)
#        /app/aggsender/aggsender.go:176 +0x3e5
#github.com/agglayer/aggkit/aggsender.(*AggSender).Start(0xc0003e8000, {0x1b4b238, 0x2717720})
#        /app/aggsender/aggsender.go:152 +0x1fe
#created by main.start in goroutine 1
#        /app/cmd/run.go:119 +0xda5


echo "Starting Cleanup - FINAL STEP"
chmod +x cleanup.sh

. ./cleanup.sh full
