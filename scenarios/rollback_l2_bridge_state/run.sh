#!/bin/env bash
set -e
source ../common/load-env.sh
load_env

kurtosis_hash="$KURTOSIS_PACKAGE_HASH"
kurtosis_enclave_name="$ENCLAVE_NAME"

rm -rf pp.yml
kurtosis clean --all

# Start a PP chain up
if [[ $MOCK_MODE == true ]]; then
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/op-succinct/mock-prover.yml" > pp.yml
else
  curl -s "https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/$kurtosis_hash/.github/tests/op-succinct/real-prover.yml" > pp.yml
fi

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
kurtosis service stop $kurtosis_enclave_name op-batcher-001
initial_block_dec=$(cast block-number --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)")

# Do some bridges
l2_rpc_url="$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)"
l2_bridge_address=$(kurtosis service exec $kurtosis_enclave_name contracts-001 'cat /opt/zkevm/combined.json' | jq | grep "polygonZkEVML2BridgeAddress" | awk -F'"' '{print $4}')
for _ in {1..10}; do
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

# Read information before unsetting the claims
first_idx=$(echo "$indexes" | head -n1)
second_idx=$(echo "$indexes" | head -n2 | tail -n1)

resp=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/merkle-proof?net_id=0&deposit_cnt=$first_idx")
local_proof=$(echo "$resp" | jq -r '.proof.merkle_proof | join(",")')
rollup_proof=$(echo "$resp" | jq -r '.proof.rollup_merkle_proof | join(",")')
main_exit_root=$(echo "$resp"   | jq -r '.proof.main_exit_root')
rollup_exit_root=$(echo "$resp" | jq -r '.proof.rollup_exit_root')

resp_2=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/merkle-proof?net_id=0&deposit_cnt=$second_idx")
local_proof_2=$(echo "$resp_2" | jq -r '.proof.merkle_proof | join(",")')
rollup_proof_2=$(echo "$resp_2" | jq -r '.proof.rollup_merkle_proof | join(",")')
main_exit_root_2=$(echo "$resp_2"   | jq -r '.proof.main_exit_root')
rollup_exit_root_2=$(echo "$resp_2" | jq -r '.proof.rollup_exit_root')

cast send $l2_bridge_address "unsetMultipleClaims(uint256[])" "[$global_indexes]" --private-key $private_key --rpc-url $l2_rpc_url
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
  exit 1
else
  echo "✅ All specified claims were successfully restored"
fi

# forceEmitDetailedClaimEvent for the aggkit
IFS=',' read -r first_global_index second_global_index <<< "$global_indexes"
cast send $l2_bridge_address \
  "forceEmitDetailedClaimEvent((bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint8,uint32,address,uint32,address,uint256,bytes)[])" \
  "[([$local_proof],[$rollup_proof],$first_global_index,$main_exit_root,$rollup_exit_root,0,0,0x0000000000000000000000000000000000000000,0,0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,1,0x),([$local_proof_2],[$rollup_proof_2],$second_global_index,$main_exit_root_2,$rollup_exit_root_2,0,0,0x0000000000000000000000000000000000000000,0,0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,1,0x)]" \
  --rpc-url $l2_rpc_url --private-key $private_key

# BackwardLET
index_to_remove=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/bridges/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | jq '[.deposits[] | select(.ready_for_claim == false)] | .[2].deposit_cnt')
RESP=$(curl -s "$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/backward-let?net_id=1&deposit_cnt=$index_to_remove")

leaf_hash=$(jq -r '.leaf_hash' <<< "$RESP")
frontier=$(jq -r '.frontier | "[" + (join(",")) + "]"' <<< "$RESP")
rollup_merkle_proof=$(jq -r '.rollup_merkle_proof | "[" + (join(",")) + "]"' <<< "$RESP")

cast send $l2_bridge_address "activateEmergencyState()" --private-key $private_key --rpc-url $l2_rpc_url
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

# L2 reorg
echo "Last L2 Block before deleting the state: $(cast block-number --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)")"
echo "blockhash($((initial_block_dec +1))) $(cast block $((initial_block_dec +1)) --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)" --json | jq -r '.hash')"
echo "blockhash($((initial_block_dec +2))) $(cast block $((initial_block_dec +2)) --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)" --json | jq -r '.hash')"
echo "blockhash($((initial_block_dec +3))) $(cast block $((initial_block_dec +3)) --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)" --json | jq -r '.hash')"
final_block_dec=$(cast block-number --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)")
echo "blockhash($final_block_dec) $(cast block $final_block_dec --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)" --json | jq -r '.hash')"
reorg_depth=$(( final_block_dec - initial_block_dec ))
echo "Reorg depth will be: $reorg_depth blocks"
target_hex=$(printf "0x%x" "$initial_block_dec")

kurtosis service stop $kurtosis_enclave_name op-cl-1-op-node-op-geth-001
cast rpc debug_setHead "$target_hex" --rpc-url "$(kurtosis port print $kurtosis_enclave_name op-el-1-op-geth-op-node-001 rpc)"

echo "Last L2 Block after deleting the state: $(cast block-number --rpc-url $l2_rpc_url)"

kurtosis service start $kurtosis_enclave_name op-cl-1-op-node-op-geth-001
kurtosis service start $kurtosis_enclave_name op-batcher-001

polycli ulxly bridge asset \
    --value 1 \
    --gas-limit 1250000 \
    --bridge-address "$l2_bridge_address" \
    --destination-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --destination-network 0 \
    --rpc-url "$l2_rpc_url" \
    --private-key "$bridge_spammer_wallet_private_key"

sleep 10 # Wait for the tx to be synced
timeout=300
start=$SECONDS
while true; do
  if curl -s "$bridge_service_url/bridges/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266?net_id=1&dest_net=0" \
    | jq -e '
        .deposits
        | all(.[]; .ready_for_claim == true)
      ' > /dev/null; then

    echo "✅ All deposits are ready_for_claim = true"
    break
  else
    echo "⏳ Still some deposit is ready_for_claim = false, waiting..."
  fi

  # Timeout 5 min
  if (( SECONDS - start >= timeout )); then
    echo "❌ Timeout: deposits are not all ready_for_claim after 5 minutes"
    exit 1
  fi

  sleep 5
done