# PoS Upgrade Scenario

Test a rolling upgrade of [kurtosis-pos](https://github.com/0xPolygon/kurtosis-pos) devnet nodes. Non-block-producing nodes are upgraded first, then block producers last to maintain network stability.

## Usage

1. Copy `.env.example` to `.env` and configure:
   - `ENCLAVE_NAME`: Name of the Kurtosis enclave
   - `KURTOSIS_POS_VERSION`: Initial kurtosis-pos package version (branch, tag, or commit)
   - `RIO_HF`: Block number for Rio hard fork activation (default: `128`)
   - `RIO_HF_TIMEOUT`: Timeout in seconds waiting for Rio HF block (default: `300`)
   - `NEW_BOR_IMAGE`: Target Bor client image
   - `NEW_HEIMDALL_V2_IMAGE`: Target Heimdall v2 client image
   - `NEW_ERIGON_IMAGE`: Target Erigon client image

2. (Optional) Customize `params.yml` for devnet configuration.

3. Run the scenario:

   ```bash
   sudo bash run.sh
   ```

## Cleanup

Remove the enclave, orphaned containers, and temporary data before re-running:

```bash
kurtosis enclave rm --force pos
docker ps --all --format '{{.Names}}' | grep -E '^l2-(e|c)l-.*-.*-' | xargs docker rm --force
sudo rm -rf ./tmp
```
