# pos-veblop

## Scenarios

<https://docs.google.com/spreadsheets/d/1XiEXlTpx24qiBgDbq9iijYts-04j-kutIF1cMdRaO0s/edit?gid=365332587#gid=365332587>

- [ ] 1. Single producer per span (TODO)
- [x] 2. No reorgs during rotation
- [x] 3. Candidate limit <= 3
- [x] 4. Equal slot distribution
- [ ] 5. 2/3 threshold - active producer

## Testing

### Scenarios: 2 and 3

The script launches a Polygon PoS devnet with 5 validators and 4 rpc nodes. It waits until block 256 to ensure VEBloP is active, then simulates a failure by isolating the current block producer’s EL node from the rest of the EL nodes for 15 seconds. The remaining validators detect the producer’s inactivity and trigger a rotation, ending the current span and immediately starting the next one. The chain progresses smoothly without halting or reorgs.

Invariants checked:

- Each span has a minimum of one selected producer and a maximum of three selected producers.

```bash
export ENCLAVE_NAME="pos-veblop"
./run.sh --env .env.default
bats --filter-tags veblop tests/pos/veblop.bats
```

Result:

```bash
veblop.bats
 ✓ isolate the current block producer mid-span to trigger a producer rotation
 ✓ enforce minimum one and maximum three selected producers per span

2 tests, 0 failures


real 1m4.685s
user 0m5.361s
sys 0m1.434s
```

### Scenario 4

The script starts a Polygon PoS devnet with 5 validators and 4 RPC nodes. It waits until block 1000 to ensure VEBloP is active and that multiple spans with producer rotations have occurred. It then verifies whether block producer slots are evenly distributed over the last 1000 blocks, allowing a tolerance of ±1 span (128 blocks).

Note: Waiting for more blocks, e.g., 10,000, would provide greater confidence in validating this invariant.

```bash
export ENCLAVE_NAME="pos-veblop-4"
./run.sh --env .env.default

echo "Waiting for block 1000..."
while true; do
  l2_rpc_url=$(kurtosis port print "pos-veblop" "l2-el-1-bor-heimdall-v2-validator" rpc)
  block_number=$(cast bn --rpc-url "$l2_rpc_url")
  echo "Block number: $block_number"

  if (( block_number > 1000 )); then
    echo "✅ Block number exceeded 1000"
    break
  fi
  sleep 20
done

export ENCLAVE_NAME="pos-veblop"
bats --filter-tags equal-slot-distribution tests/pos/veblop.bats
```

Result:

```bash
veblop.bats
 ✓ enforce equal slot distribution between block producers
 ✓ enforce equal block distribution between block producers

2 tests, 0 failures


real 0m36.413s
user 0m16.265s
sys 0m21.489s
```

### Scenario 5

All the validators have the same stake (10 000 ether) and thus the same voting power (`10000`) by default.

```bash
kurtosis files inspect pos-veblop l2-cl-genesis genesis.json | jq '.app_state.bor.spans[0].validator_set.validators'
```

```json
[
  {
    "end_epoch": "0",
    "jailed": false,
    "last_updated": "",
    "nonce": "1",
    "proposer_priority": "0",
    "pub_key": "BJPocX9GsUbr+5kVnrE6XQRMGRmYZWyLeQB7FgUbsf92LQmITkN4PYmN1H9iIK8EAgbKu9Rcmia7J4pSLD1Tih8=",
    "signer": "0x97538585a02A3f1B1297EB9979cE1b34ff953f1E",
    "start_epoch": "0",
    "val_id": "1",
    "voting_power": "10000"
  },
  {
    "end_epoch": "0",
    "jailed": false,
    "last_updated": "",
    "nonce": "1",
    "proposer_priority": "0",
    "pub_key": "BA9VTa8ALDWSganFw8tmOcqxIln1cNbRDLFeP4KnnnWqSSTwH1MAaLSgET935pulQ0ygEQChgvvKJgninEqd6R8=",
    "signer": "0xeeE6f79486542f85290920073947bc9672C6ACE5",
    "start_epoch": "0",
    "val_id": "2",
    "voting_power": "10000"
  },
  {
    "end_epoch": "0",
    "jailed": false,
    "last_updated": "",
    "nonce": "1",
    "proposer_priority": "0",
    "pub_key": "BMwO60q+UgmZ7jEKoKmkhVJ+3VhMH9npmBFE/yxXTlv4e1VJkCr9BasrXFC9ix8sb2SNpxcj/fVyGv45xv5JGkU=",
    "signer": "0xA831F4E702F374aBf14d8005e21DC6d17d84DfCc",
    "start_epoch": "0",
    "val_id": "3",
    "voting_power": "10000"
  }
]
```

We tweaked the package a little bit so that the first validator stakes 10 times more than the other.

```bash
git diff stateless
```

```diff
diff --git a/static_files/contracts/deploy-l1-contracts.sh b/static_files/contracts/deploy-l1-contracts.sh
index ab15dc7..22456d8 100644
--- a/static_files/contracts/deploy-l1-contracts.sh
+++ b/static_files/contracts/deploy-l1-contracts.sh
@@ -110,19 +110,32 @@ jq -n '[]' > "${VALIDATORS_CONFIG_FILE}"

 echo "Staking for each validator node..."
 IFS=';' read -ra validator_accounts <<< "${VALIDATOR_ACCOUNTS}"
+validator_index=0
 for account in "${validator_accounts[@]}"; do
   IFS=',' read -r address eth_public_key <<< "${account}"
+
+  # First validator stakes 10x more than the others
+  if [[ ${validator_index} -eq 0 ]]; then
+    stake_amount_eth=$((VALIDATOR_STAKE_AMOUNT_ETH * 10))
+    echo "First validator ${address} staking 10x amount: ${stake_amount_eth} ETH"
+  else
+    stake_amount_eth=${VALIDATOR_STAKE_AMOUNT_ETH}
+    echo "Validator ${address} staking regular amount: ${stake_amount_eth} ETH"
+  fi
+
   # Note: MaticStake requires the amount to be specified in wei, not in eth.
   forge script -vvvv --rpc-url "${L1_RPC_URL}" --broadcast \
     scripts/matic-cli-scripts/stake.s.sol:MaticStake \
     --sig "run(address,bytes,uint256,uint256)" \
-    "${address}" "${eth_public_key}" "${VALIDATOR_STAKE_AMOUNT_ETH}000000000000000000" "${VALIDATOR_TOP_UP_FEE_AMOUNT_ETH}000000000000000000"
+    "${address}" "${eth_public_key}" "${stake_amount_eth}000000000000000000" "${VALIDATOR_TOP_UP_FEE_AMOUNT_ETH}000000000000000000"

   # Update the validator config file.
-  jq --arg address "${address}" --arg stake "${VALIDATOR_STAKE_AMOUNT_ETH}" --arg balance "${VALIDATOR_BALANCE}" \
+  jq --arg address "${address}" --arg stake "${stake_amount_eth}" --arg balance "${VALIDATOR_BALANCE}" \
     '. += [{"address": $address, "stake": ($stake | tonumber), "balance": ($balance | tonumber)}]' \
     "${VALIDATORS_CONFIG_FILE}" > "${VALIDATORS_CONFIG_FILE}.tmp"
   mv "${VALIDATORS_CONFIG_FILE}.tmp" "${VALIDATORS_CONFIG_FILE}"
+
+  ((validator_index++))
 done
 echo "exports = module.exports = $(< ${VALIDATORS_CONFIG_FILE})" > "${VALIDATORS_CONFIG_FILE}"
```

Here is how to spin up the environment and trigger tests.

```bash
export ENCLAVE_NAME="pos-veblop-5"
./run.sh --env .env.scenario.5
bats -f "producer with more than 2/3 of the active power should produce all the blocks" tests/pos/veblop.bats
```
