#!/usr/bin/env bash

for c in op-deployer external-op-node external-op-geth-sequencer aggkit-bridge aggkit; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done
sudo rm -rf aggkit aggkit-bridge chaindata jwt.txt op-deployer-output opgeth-data regenesis.json rollup.json regenesis.json.tmp rollup.json.tmp regenesisTool op-deployer-work
kurtosis clean --all

kurtosis run --enclave=cdk --args-file=https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/main/.github/tests/cdk-erigon/sovereign.yml github.com/0xPolygon/kurtosis-cdk

sleep 60 # Wait for the bridge spammer to generate some traffic
kurtosis service stop cdk bridge-spammer-001
sleep 30

docker cp "$(docker ps --filter "name=cdk-erigon-sequencer-001" --format "{{.ID}}")":/home/erigon/data/dynamic-kurtosis-sequencer/chaindata .
kurtosis service stop cdk cdk-erigon-sequencer-001
wget https://github.com/ARR552/regenesisTool/releases/download/v0.0.1/regenesisTool
chmod +x regenesisTool
./regenesisTool --action=regenesis --chaindata="./chaindata" --output=./

jq '.config = {
  chainId: 2151908,
  homesteadBlock: 0,
  eip150Block: 0,
  eip155Block: 0,
  eip158Block: 0,
  byzantiumBlock: 0,
  constantinopleBlock: 0,
  petersburgBlock: 0,
  istanbulBlock: 0,
  muirGlacierBlock: 0,
  berlinBlock: 0,
  londonBlock: 0,
  arrowGlacierBlock: 0,
  grayGlacierBlock: 0,
  mergeNetsplitBlock: 0,
  shanghaiTime: 0,
  cancunTime: 0,
  pragueTime: 0,
  bedrockBlock: 0,
  regolithTime: 0,
  canyonTime: 0,
  ecotoneTime: 0,
  fjordTime: 0,
  graniteTime: 0,
  holoceneTime: 0,
  isthmusTime: 0,
  terminalTotalDifficulty: 0,
  depositContractAddress: "0x0000000000000000000000000000000000000000",
  optimism: {
    eip1559Elasticity: 6,
    eip1559Denominator: 50,
    eip1559DenominatorCanyon: 250
  }
}' regenesis.json > genesis.new.json && mv genesis.new.json regenesis.json

###################### Deploy OP smc and create the rollup.json file ######################
# Run op-deployer container and keep it running
docker run -d \
  --name op-deployer \
  --restart unless-stopped \
  -u root \
  -v ./op-deployer-work:/work \
  -w /work \
  --entrypoint sh \
  europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/op-deployer:v0.4.0-rc.2 \
  -c "tail -f /dev/null"

docker cp op-deployer:. ./op-deployer-output

cd op-deployer-output || exit 1

# Init op-deployer env
./op-deployer init --intent-config-type custom --l1-chain-id 271828 --l2-chain-ids 2151908 --workdir ./

# Create intent file
cat > intent.toml << 'EOF'
configType = 'custom'
fundDevAccounts = false
l1ChainID = 271828
l1ContractsLocator = 'https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz'
l2ContractsLocator = 'https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz'
useInterop = false
[[chains]]
  baseFeeVaultRecipient = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
  eip1559Denominator = 50
  eip1559DenominatorCanyon = 250
  eip1559Elasticity = 6
  id = '0x000000000000000000000000000000000000000000000000000000000020d5e5'
  l1FeeVaultRecipient = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
  operatorFeeConstant = 0
  operatorFeeScalar = 0
  sequencerFeeVaultRecipient = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
  [[chains.dangerousAdditionalDisputeGames]]
    dangerouslyAllowCustomDisputeParameters = true
    faultGameClockExtension = 10800
    faultGameMaxClockDuration = 302400
    faultGameMaxDepth = 73
    faultGameSplitDepth = 30
    makeRespected = false
    oracleChallengePeriodSeconds = 0
    oracleMinProposalSize = 0
    respectedGameType = 0
    useCustomOracle = false
    vmType = 'CANNON'
  [chains.dangerousAltDAConfig]
    daBondSize = 0
    daChallengeWindow = 100
    daCommitmentType = 'KeccakCommitment'
    daResolveWindow = 100
    useAltDA = false
  [chains.deployOverrides]
    fundDevAccounts = true
    l2BlockTime = 1
    l2GenesisFjordTimeOffset = '0x0'
    l2GenesisGraniteTimeOffset = '0x0'
    l2GenesisIsthmusTimeOffset = '0x0'
  [chains.roles]
    batcher = '0x6bd90c2a1AE00384AD9F4BcD76310F54A9CcdA11'
    challenger = '0xAF4186A3A3cE26558CbD335AD0c616D6F997072d'
    l1ProxyAdminOwner = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
    l2ProxyAdminOwner = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
    proposer = '0xDFfA3C478Be83a91286c04721d2e5DF9A133b93F'
    systemConfigOwner = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
    unsafeBlockSigner = '0x8545C053457e96305221aF08d14B4eF641D0ab18'
[superchainRoles]
  protocolVersionsOwner = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
  superchainGuardian = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
  superchainProxyAdminOwner = '0x8943545177806ED17B9F23F0a21ee5948eCaa776'
EOF

# Apply chain state
./op-deployer apply --l1-rpc-url "http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)" --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --workdir ./

# Generate genesis.json
./op-deployer inspect genesis 2151909 --workdir ./ > genesis.json

# Generate rollup.json
./op-deployer inspect rollup 2151909 --workdir ./ > rollup.json

mv rollup.json ../rollup.json

cd .. || exit 1

# Fix the l2_chain_id in rollup.json
jq '.l2_chain_id = 2151908' rollup.json > rollup.json.tmp && mv rollup.json.tmp rollup.json

# Fix the timestamp in regenesis.json to match the one in rollup.json
jq --slurpfile r rollup.json '.timestamp = $r[0].genesis.l2_time' regenesis.json > regenesis.json.tmp && mv regenesis.json.tmp regenesis.json

#######################################################################################

# Load genesis in op-geth
docker run --rm \
  -v ./regenesis.json:/genesis.json \
  -v ./opgeth-data:/datadir \
  us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101602.3 \
  init --state.scheme=hash --datadir=/datadir /genesis.json

# Generate JWT secret
openssl rand -hex 32 | tr -d '\n' > jwt.txt

# Run op-geth
docker run -d \
  --name external-op-geth-sequencer \
  --network kt-cdk \
  -p 8545:8545 \
  -p 8546:8546 \
  -p 30303:30303 \
  -v ./regenesis.json:/genesis.json \
  -v ./opgeth-data:/datadir \
  -v ./jwt.txt:/jwt.txt \
  us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101602.3 \
  --datadir=/datadir \
  --rollup.sequencerhttp=http://external-op-node:8547 \
  --unlock=0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed \
  --password=/dev/null \
  --allow-insecure-unlock \
  --keystore=/tmp \
  --mine \
  --miner.etherbase=0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed \
  --http \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=web3,debug,eth,txpool,net,engine \
  --http.vhosts="*" \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/jwt.txt \
  --authrpc.vhosts="*" \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.api=debug,eth,txpool,net,engine \
  --syncmode=full \
  --gcmode=archive \
  --log.format=json

sleep 10

# Update the L2 genesis hash in rollup.json before running the op-node
L2_GENESIS_HASH=$(cast rpc --rpc-url http://localhost:8545 eth_getBlockByNumber 0x0 true | jq -r '.hash')
jq --arg h "$L2_GENESIS_HASH" '.genesis.l2.hash = $h' rollup.json > rollup.tmp && mv rollup.tmp rollup.json

# Run op-node
BEACON="$(kurtosis port print cdk cl-1-lighthouse-geth http | sed 's/127\.0\.0\.1/host.docker.internal/')"
RPC="http://$(kurtosis port print cdk el-1-geth-lighthouse rpc | sed -e 's#^http://##' -e 's#127\.0\.0\.1#host.docker.internal#')"
docker run -d --name external-op-node \
  --network kt-cdk \
  --add-host=host.docker.internal:host-gateway \
  -p 8547:8547 \
  -v ./rollup.json:/rollup.json \
  -v ./jwt.txt:/jwt.txt \
  us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.13.5 \
  op-node \
    --l1="$RPC" \
    --l1.beacon="$BEACON" \
    --l2=http://external-op-geth-sequencer:8551 \
    --l2.jwt-secret=/jwt.txt \
    --rollup.config=/rollup.json \
    --sequencer.enabled=true \
    --sequencer.stopped=false \
    --p2p.disable=true \
    --rpc.addr=0.0.0.0 \
    --rpc.port=8547

# Extract the aggkit files and dbs
mkdir -p aggkit aggkit-bridge
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001--' | awk '{print $1}' | head -n1)":/etc/aggkit/config.toml ./aggkit/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001--' | awk '{print $1}' | head -n1)":/etc/aggkit/sequencer.keystore ./aggkit/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001--' | awk '{print $1}' | head -n1)":/etc/aggkit/aggoracle.keystore ./aggkit/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001--' | awk '{print $1}' | head -n1)":/tmp ./aggkit/
chmod 777 aggkit/tmp/*

kurtosis service stop cdk aggkit-001

docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001-bridge--' | awk '{print $1}' | head -n1)":/etc/aggkit/config.toml ./aggkit-bridge/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001-bridge--' | awk '{print $1}' | head -n1)":/etc/aggkit/sequencer.keystore ./aggkit-bridge/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001-bridge--' | awk '{print $1}' | head -n1)":/etc/aggkit/aggoracle.keystore ./aggkit-bridge/
docker cp "$(docker ps --format '{{.ID}} {{.Names}}' | grep ' aggkit-001-bridge--' | awk '{print $1}' | head -n1)":/tmp ./aggkit-bridge/
chmod 777 aggkit-bridge/tmp/*

kurtosis service stop cdk aggkit-001-bridge

# Edit config file to point to the new op instances
sed -i.bak 's|http://cdk-erigon-rpc-001:8123|http://external-op-geth-sequencer:8545|g' ./aggkit/config.toml
sed -i.bak 's|http://cdk-erigon-rpc-001:8123|http://external-op-geth-sequencer:8545|g' ./aggkit-bridge/config.toml
L1_RPC="$(kurtosis port print cdk el-1-geth-lighthouse rpc | sed -e 's#^http://##' -e 's#127\.0\.0\.1#host.docker.internal#')"
[ -n "$L1_RPC" ] || { echo "Could not resolve kurtosis L1_RPC"; exit 1; }
sed -i.bak "s|http://el-1-geth-lighthouse:8545|http://$L1_RPC|g" ./aggkit/config.toml
sed -i.bak "s|http://el-1-geth-lighthouse:8545|http://$L1_RPC|g" ./aggkit-bridge/config.toml
AGGLAYER_GRPC="$(kurtosis port print cdk agglayer aglr-grpc | sed -E 's/127\.0\.0\.1/host.docker.internal/; s#^[a-z][a-z0-9+.-]*://#http://#')"
[ -n "$AGGLAYER_GRPC" ] || { echo "Could not resolve kurtosis AGGLAYER_GRPC"; exit 1; }
sed -i.bak "s|http://agglayer:4443|$AGGLAYER_GRPC|g" ./aggkit/config.toml
sed -i.bak "s|http://agglayer:4443|$AGGLAYER_GRPC|g" ./aggkit-bridge/config.toml

sleep 120

# Run aggkit-aggsender+bridge
docker run -d --name aggkit \
  --network kt-cdk \
  --add-host=host.docker.internal:host-gateway \
  --restart=unless-stopped \
  -v "./aggkit/config.toml:/config/aggkit.toml:ro" \
  -v "./aggkit/aggkit-data:/data" \
  -v "./aggkit/sequencer.keystore:/etc/aggkit/sequencer.keystore" \
  -v "./aggkit/aggoracle.keystore:/etc/aggkit/aggoracle.keystore" \
  -v "./aggkit/tmp:/tmp:rw" \
  ghcr.io/agglayer/aggkit:0.5.4 \
  run -cfg /config/aggkit.toml -components aggsender,bridge

# Run aggkit-bridge only
docker run -d --name aggkit-bridge \
  --network kt-cdk \
  --add-host=host.docker.internal:host-gateway \
  --restart=unless-stopped \
  -v "./aggkit-bridge/config.toml:/config/aggkit.toml:ro" \
  -v "./aggkit-bridge/aggkit-data:/data" \
  -v "./aggkit-bridge/sequencer.keystore:/etc/aggkit/sequencer.keystore" \
  -v "./aggkit-bridge/aggoracle.keystore:/etc/aggkit/aggoracle.keystore" \
  -v "./aggkit-bridge/tmp:/tmp:rw" \
  ghcr.io/agglayer/aggkit:0.5.4 \
  run -cfg /config/aggkit.toml -components bridge

# Send an L2 deposit to for a new certificate.
polycli ulxly bridge asset \
    --value 1 \
    --gas-limit 1250000 \
    --bridge-address "$(kurtosis service exec cdk contracts-001 'cat /opt/zkevm/combined.json' | jq | grep "polygonZkEVML2BridgeAddress" | awk -F'"' '{print $4}')" \
    --destination-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --destination-network 0 \
    --rpc-url "http://localhost:8545" \
    --private-key "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"

### Wait for the cert to be settled
CONTAINER="aggkit"
TIMEOUT_SECS="60"
SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # only watch fresh logs

# Try JSON-aware path first (handles mixed lines with fromjson?)
MATCH_JSON=$(
  timeout "${TIMEOUT_SECS}s" bash -c '
    docker logs -f --since "'"$SINCE"'" "'"$CONTAINER"'" 2>&1 \
    | stdbuf -oL -eL jq -Rr --unbuffered "
        fromjson?                                                  # parse if JSON; pass null if not
        | select(. != null and .module == \"aggsender\")           # only aggsender JSON entries
        | select(.msg | test(\"changed status from \\\\[Candidate\\\\] to \\\\[Settled\\\\]\")) 
        | {
            time:   (.ts? // now | tostring),
            height: ((.msg|capture(\"certificate (?<h>[0-9]+)/\").h) // \"\"),
            cert:   ((.msg|capture(\"certificate [0-9]+/(?<c>0x[0-9a-fA-F]+)\").c) // \"\"),
            tx:     ((.msg|capture(\"SettlementTxnHash: (?<tx>0x[0-9a-fA-F]+)\").tx) // \"\")
          }
        | @json
      " \
    | head -n 1
  ' || true
)

if [[ -n "${MATCH_JSON}" ]]; then
  echo "✅ Settled cert in JSON format: ${MATCH_JSON}"
  exit 0
fi

# Fallback: plain-text grep in case logs weren’t JSON-formatted
MATCH_TXT=$(
  timeout "${TIMEOUT_SECS}s" bash -c '
    docker logs -f --since "'"$SINCE"'" "'"$CONTAINER"'" 2>&1 \
    | stdbuf -oL -eL grep -m1 -E "changed status from \[Candidate\] to \[Settled\]" \
    | sed -E "s/.*certificate ([0-9]+)\/(0x[0-9a-fA-F]+).*SettlementTxnHash: (0x[0-9a-fA-F]+).*/{\"height\":\"\1\",\"cert\":\"\2\",\"tx\":\"\3\"}/"
  ' || true
)

if [[ -n "${MATCH_TXT}" ]]; then
  echo "✅ Settled cert in TXT format: ${MATCH_TXT}"
  exit 0
fi

echo "❌ No Settled cert found in ${TIMEOUT_SECS}s (container=${CONTAINER})"
exit 1
