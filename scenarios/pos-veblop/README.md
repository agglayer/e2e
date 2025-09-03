# pos-veblop

<https://docs.google.com/spreadsheets/d/1XiEXlTpx24qiBgDbq9iijYts-04j-kutIF1cMdRaO0s/edit?gid=365332587#gid=365332587>

1. Single producer per span (TODO)
2. No reorgs during rotation
3. Candidate limit <= 3

Scenarios: 2, 3

The script launches a Polygon PoS devnet with 5 validators and 4 rpc nodes. It waits until block 256 to ensure VEBloP is active, then simulates a failure by isolating the current block producer’s EL node from the rest of the EL nodes for 15 seconds. The remaining validators detect the producer’s inactivity and trigger a rotation, ending the current span and immediately starting the next one. The chain progresses smoothly without halting or reorgs.

Invariants checked:

- Each span has a minimum of one selected producer and a maximum of three selected producers.

```bash
./run.sh --env .env.default
```
