# pos-veblop

## Scenarios

<https://docs.google.com/spreadsheets/d/1XiEXlTpx24qiBgDbq9iijYts-04j-kutIF1cMdRaO0s/edit?gid=365332587#gid=365332587>

- [ ] 1. Single producer per span (TODO)
- [x] 2. No reorgs during rotation
- [x] 3. Candidate limit <= 3
- [x] 4. Equal slot distribution

## Testing

### Scenarios: 2 and 3

The script launches a Polygon PoS devnet with 5 validators and 4 rpc nodes. It waits until block 256 to ensure VEBloP is active, then simulates a failure by isolating the current block producer’s EL node from the rest of the EL nodes for 15 seconds. The remaining validators detect the producer’s inactivity and trigger a rotation, ending the current span and immediately starting the next one. The chain progresses smoothly without halting or reorgs.

Invariants checked:

- Each span has a minimum of one selected producer and a maximum of three selected producers.

```bash
./run.sh --env .env.default
```

### Scenario 4

The script starts a Polygon PoS devnet with 5 validators and 4 RPC nodes. It waits until block 1000 to ensure VEBloP is active and that multiple spans with producer rotations have occurred. It then verifies whether block producer slots are evenly distributed over the last 1000 blocks, allowing a tolerance of ±1 span (128 blocks).

Note: Waiting for more blocks, e.g., 10,000, would provide greater confidence in validating this invariant.

```bash
./run.sh --env .env.default.notests

echo "Waiting for block 1000..."
while true; do
  l2_rpc_url=$(kurtosis port print "pos-veblop" "l2-el-1-bor-heimdall-v2-validator" rpc)
  block_number=$(cast bn --rpc-url "$l2_rpc_url")
  echo "Block number: $block_number"

  if (( block_number > 1000 )); then
    echo "✅ Block number exceeded 1000"
    exit 0
  fi
  sleep 20
done

bats -f "enforce equal slot distribution between block producers" tests/pos/veblop.bats
```

```bash
veblop.bats
 ✓ enforce equal block distribution between block producers

1 test, 0 failures
```
