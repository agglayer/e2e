# pos-veblop

## Scenarios

<https://docs.google.com/spreadsheets/d/1XiEXlTpx24qiBgDbq9iijYts-04j-kutIF1cMdRaO0s/edit?gid=365332587#gid=365332587>

1. Single producer per span (TODO)
2. No reorgs during rotation
3. Candidate limit <= 3
4. Equal slot distribution

## Testing

### Scenarios: 2, 3

The script launches a Polygon PoS devnet with 5 validators and 4 rpc nodes. It waits until block 256 to ensure VEBloP is active, then simulates a failure by isolating the current block producer’s EL node from the rest of the EL nodes for 15 seconds. The remaining validators detect the producer’s inactivity and trigger a rotation, ending the current span and immediately starting the next one. The chain progresses smoothly without halting or reorgs.

Invariants checked:

- Each span has a minimum of one selected producer and a maximum of three selected producers.

```bash
./run.sh --env .env.default
```

### Scenario 4

The script launches a Polygon PoS devnet with 5 validators and 4 rpc nodes. It waits until block 1000 to ensure VeBloP is active and different spans happened with producer rotations. It then checks if there is an equal slot distribution between block producers.

Note: We could even wait more blocks, e.g. 10 000 blocks to validate the invariant with more confidence.

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
