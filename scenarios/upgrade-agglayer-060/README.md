# upgrade-agglayer-060

Verifies an **agglayer node upgrade** from the current latest stable
(`ghcr.io/agglayer/agglayer:0.5.1`) to a `0.6.0-rc.x` release candidate on a live Kurtosis-CDK
**PP (pessimistic)** devnet, checking that bridging and certificate settlement work **both before
and after** the upgrade.

This exercises the real `0.5.x -> 0.6` storage-schema migration (the settlement column families
are created on first open of the 0.5.x RocksDB) while keeping the rest of the network running.

## The settlement gate (`QUIESCE_BEFORE_UPGRADE`)

A 0.5.x agglayer node does not record settlement **job-ids** (those columns are new in 0.6). When
you swap a 0.5.1 node to 0.6.0-rc.4 while a certificate is **mid-settlement** (state `Candidate`
with a settlement tx already submitted), rc.4's startup recovery scan finds no job-id to resume and
the certificate orchestrator hard-errors — `"Candidate certificate has no settlement job id"` — so
that certificate is parked in `InError` and settlement stalls at that height. (Verified on rc.4:
the DB schema migration and the *backlog* resume fine; only an actively-settling carry-over cert
breaks.)

The scenario therefore **quiesces settlement before the swap by default**
(`QUIESCE_BEFORE_UPGRADE=true`): it stops the aggsender (`aggkit-001`) so no new certificates are
produced, then blocks until the latest pending certificate is `null`, refusing to upgrade if it
cannot drain within `QUIESCE_TIMEOUT`. This is the safe, supported 0.5.1 → 0.6.0-rc.4 path.

Set `QUIESCE_BEFORE_UPGRADE=false` to swap **with settlement in-flight** (aggsender/spammer keep
running, and the scenario waits for a non-null pending certificate first). This is an opt-in path:
it is **expected to fail for a 0.5.x → 0.6 upgrade** on rc.4 (the job-id limitation above) and is
retained to (a) reproduce that limitation and (b) cover 0.6.x → 0.6.y upgrades, where job-ids
already exist so the in-flight settlement can be resumed.

## Run

```bash
cd scenarios/upgrade-agglayer-060
cp env.example .env    # optional; edit as needed
./run.sh
```

The scenario tears down its enclave on exit. Set `KEEP_ENCLAVE=true` to keep it for debugging.

## Requirements

- **Docker** running, plus `kurtosis`, `cast` (foundry), `bats`, `jq`, `yq`.
- **polycli must match CI** (`POLYCLI_VERSION`, currently `v0.1.90`). A different polycli changes
  `ulxly bridge/claim` flags and can silently break claims. Install the release binary (not a dev
  build) and ensure it is on `PATH` (`run.sh` adds `~/go/bin`):
  ```bash
  curl -sL "https://github.com/0xPolygon/polygon-cli/releases/download/v0.1.90/polycli_v0.1.90_linux_amd64.tar.gz" \
    | tar xz -C ~/go/bin/ && mv ~/go/bin/polycli_* ~/go/bin/polycli
  ```

## Configuration

See `env.example`. Key knobs: `ENCLAVE_NAME`, `KURTOSIS_CDK` (defaults to the local
`~/kurtosis-cdk` checkout; can pin `github.com/0xPolygon/kurtosis-cdk@<hash>`),
`AGGLAYER_IMAGE_STABLE`, `AGGLAYER_IMAGE_RC`, `AGGLAYER_READRPC_HOST_PORT`, and the
settlement/quiesce timeouts.

## Known limitations / local-run notes

- **reth L1 requires `reth_image`.** `chain.yml` sets `l1_el_type: reth` (to match the agglayer
  CI matrix and enable the reth-specific `rpc-tests.bats`). Current kurtosis-cdk HEAD has **no
  `reth_image` default**, so `reth_image` MUST be set in the args (already done here) or Starlark
  crashes with `el_image=None`. If reth-as-L1 proves incomplete on your kurtosis-cdk HEAD, either
  pin `KURTOSIS_CDK=github.com/0xPolygon/kurtosis-cdk@6f5c0f0c...` (where the reth-L1 matrix is
  CI-proven) or fall back to the default geth L1 (drop `l1_el_type`/`reth_image` — note the
  reth-only rpc-tests will then not apply, so run only `bridges.bats`).
- **Apple Silicon (arm64) hosts.** Several required polygonlabs images (e.g.
  `agglayer-contracts:v12.2.3`) are published `linux/amd64` only. Contract deployment is
  mandatory, so the devnet cannot come up on a native arm64 host — use an amd64 machine, force
  amd64 emulation, or run in CI.
- **GCP Artifact Registry.** `~/.docker/config.json` may route `europe-west2-docker.pkg.dev`
  through a `gcloud` cred helper; if gcloud is not authenticated, either `gcloud auth login` or
  rely on the images being public.

## How the node swap works

The agglayer node stores its config, keystore(s) and RocksDB in a single `/etc/agglayer`
bind-mount. A bare `kurtosis service update` would drop the runtime `storage/`, so `run.sh`
instead: stops the Kurtosis-managed node, `docker inspect`s its `/etc/agglayer` mount source, and
relaunches the RC image on the same enclave network (`kt-<enclave>`) with `--name agglayer`,
reusing that mount. Because the container then leaves Kurtosis's control, its read-RPC is
published on `AGGLAYER_READRPC_HOST_PORT` and the tests/helpers are pointed at it via
`AGGLAYER_RPC_URL` / `AGGLAYER_READRPC_URL`.

> Note: current kurtosis-cdk has no standalone `agglayer-prover` service — the node runs its
> prover inline — so only the `agglayer` container is swapped.
