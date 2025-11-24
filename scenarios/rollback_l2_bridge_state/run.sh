#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"
sp1_key="$SP1_NETWORK_KEY"
range_proof_interval="$RANGE_PROOF_INTERVAL_OVERRIDE"

rm -rf pp.yml
kurtosis clean --all

# Start a PP chain up
if [[ $MOCK_MODE == true ]]; then
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/op-succinct/mock-prover.yml" > pp.yml
else
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/op-succinct/real-prover.yml" > pp.yml
fi

# Create a yaml file that has the pp consense configured but ideally a real prover
# yq '
#   .args.sp1_prover_key = strenv(sp1_key) |
#   .args.consensus_contract_type = "pessimistic" |
#   .deployment_stages.deploy_op_succinct = false
# ' tmp-pp.yml > initial-pp.yml

# # TEMPORARY TO SPEED UP TESTING
# yq '
#   .optimism_package.chains[0].batcher_params.max_channel_duration = 2 |
#   .args.op_succinct_range_proof_interval = strenv(range_proof_interval) |
#   .args.l1_seconds_per_slot = 1
# ' initial-pp.yml > _t && mv _t initial-pp.yml

# Spin up the network
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file "pp.yml" \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"

# Do some bridges and let everything settle
bridge_service_url="$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)"
bridge_spammer_wallet_private_key="$(kurtosis service exec $kurtosis_enclave_name bridge-spammer-001 'echo "$PRIVATE_KEY"')"
bridge_spammer_wallet_address=$(cast wallet address --private-key $bridge_spammer_wallet_private_key)
echo "Bridge spammer wallet address: $bridge_spammer_wallet_address"
sleep 180 # Wait for the bridge spammer to generate some traffic
kurtosis service stop $kurtosis_enclave_name bridge-spammer-001

while true; do
  if curl -s "$bridge_service_url/bridges/$bridge_spammer_wallet_address?net_id=1&dest_net=0" \
    | jq -e '
        .deposits
        | all(.[]; .ready_for_claim == true)
      ' > /dev/null; then

    echo "✅ All deposits are ready_for_claim = true"
    break
  else
    echo "⏳ Still some deposit is ready_for_claim = false, waiting..."
    sleep 5
  fi
done

# Stop the batcher
# kurtosis service stop $kurtosis_enclave_name op-batcher-001

# Do some bridges
l2_rpc_url="$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)"
l2_bridge_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 'cat /opt/zkevm/combined.json' | jq | grep "polygonZkEVML2BridgeAddress" | awk -F'"' '{print $4}')
for i in {1..10}; do
  polycli ulxly bridge asset \
    --value 1 \
    --gas-limit 1250000 \
    --bridge-address "$l2_bridge_address" \
    --destination-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --destination-network 0 \
    --rpc-url "$l2_rpc_url" \
    --private-key "$bridge_spammer_wallet_private_key"
done

# UnsetClaims on L2
private_key=$(curl -fsSL https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/input_parser.star | sed -nE 's/.*"l2_sovereignadmin_private_key"[[:space:]]*:[[:space:]]*"(0x[0-9a-fA-F]{64})".*/\1/p')
indexes=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/claims/$bridge_spammer_wallet_address" | jq -r '.claims | sort_by(.index) | reverse | .[0:2] | .[].index')
global_indexes=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/claims/$bridge_spammer_wallet_address" | jq -r '.claims | sort_by(.index) | reverse | .[0:2] | map(.global_index) | join(",")')
echo "l2_rpc_url: $l2_rpc_url"
echo "l2_bridge_address: $l2_bridge_address"
echo "private_key: $private_key"
echo "global_Indexes: $global_indexes"
cast send $l2_bridge_address "unsetMultipleClaims(uint256[])" "[$global_indexes]" --private-key $private_key --rpc-url $l2_rpc_url
#echo "cast call $l2_bridge_address \"unsetMultipleClaims(uint256[])\" \"[$global_indexes]\" --private-key $private_key --rpc-url $l2_rpc_url"
sleep 10 # Wait for the tx to be synced

# Check if unsetClaims worked
new_all_indexes=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/claims/$bridge_spammer_wallet_address" | jq -r '.claims | sort_by(.index) | reverse | .[].index')
any_left=false
for idx in $indexes; do
  if printf '%s\n' "$new_all_indexes" | grep -Fxq "$idx"; then
    any_left=true
    break
  fi
done

if [[ "$any_left" == true ]]; then
  echo "❌ Error: Some claims were not properly unset"
  exit 1
else
  echo "✅ All specified claims were successfully unset"
fi

# SetClaims on L2
cast send $l2_bridge_address "setMultipleClaims(uint256[])" "[$global_indexes]" --private-key $private_key --rpc-url $l2_rpc_url
sleep 10 # Wait for the tx to be synced

# Check if setClaims worked
new_all_indexes=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/claims/$bridge_spammer_wallet_address" | jq -r '.claims | sort_by(.index) | reverse | .[].index')
missing=false
for idx in $indexes; do
  if ! printf '%s\n' "$new_all_indexes" | grep -Fxq "$idx"; then
    echo "❌ Claim with index $idx was not restored"
    missing=true
    break
  fi
done

if [[ "$missing" == true ]]; then
  echo "❌ Error: Some claims were not properly restored"
  #exit 1
else
  echo "✅ All specified claims were successfully restored"
fi

# BackwardLET
index_to_remove=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/bridges/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | jq '[.deposits[] | select(.ready_for_claim == false)] | .[2].deposit_cnt')
RESP=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/backward-let?net_id=1&deposit_cnt=$index_to_remove")

root=$(jq -r '.root' <<< "$RESP")
leaf_hash=$(jq -r '.leaf_hash' <<< "$RESP")
# mapfile -t FRONTIER < <(jq -r '.frontier[]' <<< "$RESP")
# mapfile -t ROLLUP_MERKLE_PROOF < <(jq -r '.rollup_merkle_proof[]' <<< "$RESP")
frontier=$(jq -r '.frontier | "[" + (join(",")) + "]"' <<< "$RESP")
rollup_merkle_proof=$(jq -r '.rollup_merkle_proof | "[" + (join(",")) + "]"' <<< "$RESP")

cast send $l2_bridge_address "activateEmergencyState()" --private-key $private_key --rpc-url $l2_rpc_url
# echo "cast send $l2_bridge_address \"backwardLET(uint256,bytes32[32],bytes32,bytes32[32])\" \"$index_to_remove\" \"$frontier\" \"$leaf_hash\" \"$rollup_merkle_proof\" --private-key $private_key --rpc-url $l2_rpc_url"
cast send $l2_bridge_address "backwardLET(uint256,bytes32[32],bytes32,bytes32[32])" "$index_to_remove" "$frontier" "$leaf_hash" "$rollup_merkle_proof" --private-key $private_key --rpc-url $l2_rpc_url
cast send $l2_bridge_address "deactivateEmergencyState()" --private-key $private_key --rpc-url $l2_rpc_url
sleep 10 # Wait for the tx to be synced
last_index=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/bridges/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | jq '[.deposits[] | select(.ready_for_claim == false)] | .[0].deposit_cnt')
if [[ "$last_index" -eq $(( index_to_remove - 1 )) ]]; then
  echo "✅ BackwardLET worked successfully"
else
  echo "❌ BackwardLET failed"
  exit 1
fi

echo "polycli ulxly bridge asset --value 1 --gas-limit 1250000 --bridge-address \"$l2_bridge_address\" --destination-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --destination-network 0 --rpc-url \"$l2_rpc_url\" --private-key \"$bridge_spammer_wallet_private_key\""

# ideally the aggkit will still generate a certificate for this test case... but in real life we don't want certificates to be created in this scenaro
# The aggsender shoud settle

# Wait for all deposits to be ready_for_claim again
# while true; do
#   if curl -s "$bridge_service_url/bridges/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266?net_id=1&dest_net=0" \
#     | jq -e '
#         .deposits
#         | all(.[]; .ready_for_claim == true)
#       ' > /dev/null; then

#     echo "✅ All deposits are ready_for_claim = true"
#     break
#   else
#     echo "⏳ Still some deposit is ready_for_claim = false, waiting..."
#     sleep 5
#   fi
# done

# kurtosis service start $kurtosis_enclave_name op-batcher-001

# Stop the op-node / op-geth - delete the l2 state entirely
# kurtosis service stop "$kurtosis_enclave_name" op-batcher-001

# kurtosis service exec rollback-l2-bridge-state-test op-el-1-op-geth-op-node-001 '
#   set -e
#   echo "Contents of /data before wipe:"
#   ls -R /data || true
#   rm -rf /data/geth/execution-data/geth/chaindata/*
#   rm -rf /data/geth/execution-data/geth/nodes/*
#   echo "✅ Wiped /data/geth"
# '
# kurtosis service restart "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001
# l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" op-el-1-op-geth-op-node-001 rpc)"
# echo "⏳ Waiting op-geth/op-node to be available..."
# until cast block-number --rpc-url "$l2_rpc_url" > /dev/null 2>&1; do
#   sleep 5
# done
# echo "✅ L2 RPC active again"
# kurtosis service start "$kurtosis_enclave_name" op-batcher-001

# Resync the op-node / op-geth from L1
# start the batcher back up
# Send a bridge transaction
# Wait for some exposion