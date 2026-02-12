# PoS Upgrade Scenario
Test a rolling upgrade of [kurtosis-pos](https://github.com/0xPolygon/kurtosis-pos) devnet nodes. Non-block-producing nodes are upgraded first, then block producers last to maintain network stability.

## Usage

1. Copy `.env.example` to `.env` and configure:
   - `ENCLAVE_NAME`: Name of the Kurtosis enclave
   - `KURTOSIS_POS_VERSION`: Initial kurtosis-pos package version
   - `NEW_BOR_IMAGE`: Target Bor client image
   - `NEW_HEIMDALL_IMAGE`: Target Heimdall client image
   - `NEW_ERIGON_IMAGE`: Target Erigon client image

2. (Optional) Customize `params.yml` for devnet configuration.

3. Run the scenario:
   ```bash
   sudo ./run.sh
   ```
