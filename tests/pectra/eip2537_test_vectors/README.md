# Source
These test vectors were collected from official EIP site:
- https://eips.ethereum.org/assets/eip-2537/test-vectors

## Modifications

In order to pass the tests, all test vectors for fails had been to be modified.
All expected errors in the format:

    - gX point is not in the correct subgroup

Had been to be reformated to:

    - gX point is not on correct subgroup

To match tha answer given by op-geth
