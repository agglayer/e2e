# Veblop Tests Suite

Tests are divided into three categories:

- **invariants**: Tests that enforce protocol properties that must always hold (e.g. fairness, producer set size). A failure here means the protocol is violating a core guarantee and must be investigated immediately.

- **faults**: Tests that deliberately inject faults (e.g. isolating producers, spamming consensus messages) to ensure the system remains live and stable under stress. A failure here usually indicates degraded fault tolerance or liveness, not a permanent invariant violation.

- **scenarios**: Tests that target a specific environment or configuration. For example, running with a misconfigured validator, a devnet with a validator holding an outsized share of power, or other special network setups. These are useful for reproducing edge cases or validating behavior under custom setups.

## Invariants

Each invariant test is tagged to indicate whether it applies to any devnet or only to equal-stake devnets.

- **stake-agnostic**: Invariants that hold under any stake distribution. These include structural properties that must always be true, regardless of how validator weights differ.

- **equal-stake**: Invariants that only hold when all producers have the same stake. These are useful for catching allocation or rotation bugs. They will fail on heterogeneous networks.

Run all invariants:

```bash
bats invariants.bats
```

Run only stake-agnostic invariants:

```bash
bats invariants.bats --filter-tags stake-agnostic
```

Run only equal-stake invariants:

```bash
bats invariants.bats --filter-tags equal-stake
```

## Faults

Run all faults:

```bash
bats faults.bats
```

Run only liveness-related faults:

```bash
bats faults.bats --filter-tags liveness
```

## Scenarios

TODO

## Tips

You can list all tests along with their description and tags using this single command:

```bash
grep -B 3 "@test" *.bats
```
