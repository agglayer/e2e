# Veblop Tests Suite

Tests are divided into three categories:

- **invariants**: Tests that enforce protocol properties that must always hold
(e.g. fairness, producer set size). A failure here means the protocol is violating a core guarantee and must be investigated immediately.

- **faults**: Tests that deliberately inject faults
(e.g. isolating producers, spamming consensus messages) to ensure the system remains live and stable under stress. A failure here usually indicates degraded fault tolerance or liveness, not a permanent invariant violation.

- **scenarios**: Tests that target a specific environment or configuration. For example, running with a misconfigured validator, a devnet with a validator holding an outsized share of power, or other special network setups.
These are useful for reproducing edge cases or validating behavior under custom setups.

## Invariants

Run all invariants:

```bash
bats tests/pos/veblop/invariants.bats
```

Run only fairness invariants:

```bash
bats tests/pos/veblop/invariants.bats --filter-tags fairness
```

## Faults

Run all faults:

```bash
bats tests/pos/veblop/faults.bats
```

Run only liveness-related faults:

```bash
bats tests/pos/veblop/faults.bats --filter-tags liveness
```

## Scenarios

TODO

## Tips

You can list all tests along with their description and tags using this single command:

```bash
grep -B 3 "@test" veblop/*.bats
```
