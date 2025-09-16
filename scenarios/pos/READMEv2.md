# pos-veblop

## Ensure the candidate list has a maximum of 3 entries and is normalized

Scenario name: `candidate-list-normalization`

- Clone kurtosis-pos
- Modify `static_files/cl/heimdall_v2/app.toml` to specify 10 producer votes:

Note that some producers must be empty or duplicated

```toml
producer_votes="1,2,3,3,4,,5,6,7,7,7,7,8,9,9,9,10,,,,,"
```

- Start the node and verify that the list is trimmed to 3 first entries.

## Big Validator

Scenario name: `big-validator`

- Start kurtosis-pos
- Update the stake of the first validator so that he always gets more than 2/3 of the weighted votes
    - Do the simulation with the quint specification to compute exactly how much stake is needed given that all validators have 1000 eth
