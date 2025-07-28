# Source

These test vectors were collected from official EIP site:

- https://eips.ethereum.org/assets/eip-2537/test-vectors



## Modifications

In order to pass the tests, these small modifications had been done to test vectors to match exact error response:

- File fail-mul_G1_bls.json:
    - Test bls_g1mul_g1_not_in_correct_subgroup:
        - ExpectedError: "g1 point is not on correct subgroup"
- File fail-mul_G2_bls.json:
    - Test bls_g2mul_g2_not_in_correct_subgroup:
        - ExpectedError: "g2 point is not on correct subgroup"
