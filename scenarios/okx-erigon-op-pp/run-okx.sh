rm -rf agglayer-contracts anvil.log
okx_rpc="https://testrpc.xlayer.tech/terigon"
PORT=8545
anvil --block-time 1 --port $PORT --fork-url $okx_rpc --fork-block-number 12493009 > anvil.log 2>&1 &
ANVIL_PID=$!

cleanup() {
  if kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "Stopping anvil (pid $ANVIL_PID)..."
    kill "$ANVIL_PID" 2>/dev/null || true
    for i in {1..10}; do
      kill -0 "$ANVIL_PID" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$ANVIL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Wait for the rpc to be ready (máx ~30s)
for i in {1..60}; do
  if curl -fsS -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
    "http://127.0.0.1:$PORT" >/dev/null; then
    echo "anvil ready in :$PORT (pid $ANVIL_PID)"
    break
  fi
  # abort if anvil crashed
  kill -0 "$ANVIL_PID" 2>/dev/null || { echo "anvil crashed; check anvil.log"; exit 1; }
  sleep 0.5
  [ "$i" -eq 60 ] && { echo "waiting anvil timeout"; exit 1; }
done

rpc_url="http://127.0.0.1:$PORT"

git clone https://github.com/agglayer/agglayer-contracts.git
cd agglayer-contracts || exit 1
git checkout feature/upgrade-etrog-sovereign #v12.1.1
npm install
npx hardhat compile

# private_key=$(curl -fsSL https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/main/input_parser.star | sed -nE 's/.*"zkevm_l2_admin_private_key"[[:space:]]*:[[:space:]]*"(0x[0-9a-fA-F]{64})".*/\1/p')
from="0xff6250d0E86A2465B0C1bF8e36409503d6a26963"
cast rpc anvil_impersonateAccount $from --rpc-url $rpc_url
cast rpc anvil_setBalance $from 0x56bc75e2d63100000 --rpc-url $rpc_url
# Find the slot of the delay variable
# SLOT_TARGET=$(cast call $TIMELOCK "getMinDelay()(uint256)" --rpc-url $rpc_url | cast to-dec)
# for i in $(seq 0 200); do
#   v_hex=$(cast storage $TIMELOCK $i --rpc-url $rpc_url)
#   v_dec=$(cast to-dec $v_hex 2>/dev/null || echo -1)
#   if [ "$v_dec" = "$SLOT_TARGET" ]; then
#     echo "Posible slot: $i  (valor=$v_dec / $v_hex)"
#   fi
# done


# cast rpc anvil_stopImpersonatingAccount 0xImpersonatedAddress --rpc-url http://127.0.0.1:8545

# cast send 0xContract "approve(address,uint256)" 0xSpender 1000000000000000000 --from $from --unlocked --rpc-url http://127.0.0.1:8545

# Deploy new L2 smc implementation
l2_GER_proxy_addr="0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa"
l2_bridge_proxy_addr=$(cast call $l2_GER_proxy_addr "bridgeAddress()(address)" --rpc-url $rpc_url)
IMPL_SLOT=0x360894A13ba1a3210667c828492db98DCA3E2076CC3735A920A3CA505D382BBC
ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103

nonce=$(cast nonce $from --rpc-url "$rpc_url" --block pending)
target_nonce=$nonce

bridge_smc_bytecode=$(cat artifacts/contracts/sovereignChains/AgglayerBridgeL2FromEtrog.sol/AgglayerBridgeL2FromEtrog.json | jq -r '.bytecode')
new_bridge_impl_addr=$(cast compute-address --nonce "$target_nonce" "$from" | grep -Eo '0x[0-9a-fA-F]{40}')
echo "new_bridge_impl_addr deploy address: $new_bridge_impl_addr"
cast send --legacy -r "$rpc_url" --from $from --unlocked --nonce "$target_nonce" --create "$bridge_smc_bytecode"

target_nonce=$((nonce + 1)) # We need to skip the proxy admin deployment tx
ger_smc_bytecode=$(cat artifacts/contracts/sovereignChains/AgglayerGERL2.sol/AgglayerGERL2.json | jq -r '.bytecode')
ger_constructor_args=$(cast abi-encode 'constructor(address)' $l2_bridge_proxy_addr | sed 's/0x//')
new_ger_impl_addr=$(cast compute-address --nonce "$target_nonce" "$from" | grep -Eo '0x[0-9a-fA-F]{40}')
echo "new_ger_impl_addr deploy address: $new_ger_impl_addr"
cast send --legacy -r "$rpc_url" --from $from --unlocked --nonce "$target_nonce" --create "$ger_smc_bytecode$ger_constructor_args"

CURRENT_BRIDGE_IMPL=$(cast storage "$l2_bridge_proxy_addr" $IMPL_SLOT --rpc-url "$rpc_url" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -c 41 | sed 's/^/0x/')
BRIDGE_ADMIN=$(cast storage "$l2_bridge_proxy_addr" $ADMIN_SLOT --rpc-url "$rpc_url" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -c 41 | sed 's/^/0x/')
echo "l2_bridge_proxy_addr: $l2_bridge_proxy_addr"
echo "BRIDGE_ADMIN (ProxyAdmin): $BRIDGE_ADMIN"
echo "Current Bridge Impl: $CURRENT_BRIDGE_IMPL"
echo "New bridge impl: $new_bridge_impl_addr"

CURRENT_GER_IMPL=$(cast storage "$l2_GER_proxy_addr" $IMPL_SLOT --rpc-url "$rpc_url" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -c 41 | sed 's/^/0x/')
GER_ADMIN=$(cast storage "$l2_GER_proxy_addr" $ADMIN_SLOT --rpc-url "$rpc_url" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -c 41 | sed 's/^/0x/')
echo "l2_GER_proxy_addr: $l2_GER_proxy_addr"
echo "GER_ADMIN (ProxyAdmin): $GER_ADMIN"
echo "Current GER Impl: $CURRENT_GER_IMPL"
echo "New GER impl: $new_ger_impl_addr"

TIMELOCK=$(cast call $GER_ADMIN "owner()(address)" --rpc-url $rpc_url)

if [ "$TIMELOCK" != "$(cast call $BRIDGE_ADMIN "owner()(address)" --rpc-url $rpc_url)" ]; then
  echo "The L2Bridge admin owner must be the same to the L2GerManager admin owner"
  exit 1
fi

# Set lower timelock delay for testing
MIN_DELAY_SLOT=2
NEW_DELAY=0
VALUE_HEX=0x$(printf "%064x" $NEW_DELAY)
cast rpc anvil_setStorageAt "$TIMELOCK" "0x$(printf '%x' "$MIN_DELAY_SLOT")" "$VALUE_HEX" --rpc-url "$rpc_url"
TIMELOCK_DELAY=$(cast call $TIMELOCK "getMinDelay()(uint256)" --rpc-url $rpc_url)
if [ "$TIMELOCK" -ne "$NEW_DELAY" ]; then
  echo "error setting new timelock delay, got $TIMELOCK_DELAY expected $NEW_DELAY"
  exit 1
fi

GER_INIT_DATA=$(cast calldata "initialize(address,address)" "0x0b68058E5b2592b1f472AdFe106305295A332A7C" $from)
DATA_GER=$(cast calldata "upgradeAndCall(address,address,bytes)" $l2_GER_proxy_addr $new_ger_impl_addr $GER_INIT_DATA)
# Get the balancetree to initialize the bridge smc
sed -i.bak -E "/localhost:/,/^[[:space:]]*},/ s#(url:[[:space:]]*)['\"][^'\"]*['\"]#\1'$okx_rpc'#" hardhat.config.ts

# mv tools/getLBT/parameters.json.example tools/getLBT/parameters.json
# jq --arg c "$l2_bridge_proxy_addr" '.contractAddress = $c' tools/getLBT/parameters.json > tools/getLBT/parameters.json.tmp && mv tools/getLBT/parameters.json.tmp tools/getLBT/parameters.json
# jq --arg b "100" '.blockRange = $b' tools/getLBT/parameters.json > tools/getLBT/parameters.json.tmp && mv tools/getLBT/parameters.json.tmp tools/getLBT/parameters.json
# npx hardhat run ./tools/getLBT/getLBT.ts --network localhost
# FILE="$(ls -1t tools/getLBT/initializeLBT-*.json 2>/dev/null | head -n1)" || true
# [ -n "$FILE" ] || { echo "No se encontró initializeLBT-*.json"; exit 1; }

# originNetworkArray="$(jq -c '.originNetwork' "$FILE")"
# originTokenAddressArray="$(jq -c '.originTokenAddress' "$FILE")"
# amountArray="$(jq -c '.totalSupply' "$FILE")"

originNetworkArray='[0]'
originTokenAddressArray='[0x3f4b6664338f23d2397c953f2ab4ce8031663f80]'
amountArray='[9999999999999999999999]'

BRIDGE_INIT_DATA=$(cast calldata \
  "initializeFromEtrog(address,address,address,address,uint32[],address[],uint256[])" \
  $from \
  $from \
  $from \
  $from \
  $originNetworkArray \
  $originTokenAddressArray \
  $amountArray)

# DATA_BRIDGE=$(cast calldata "upgrade(address,address)" $l2_bridge_proxy_addr $new_bridge_impl_addr)
DATA_BRIDGE=$(cast calldata "upgradeAndCall(address,address,bytes)" $l2_bridge_proxy_addr $new_bridge_impl_addr $BRIDGE_INIT_DATA)

SALT="0x0000000000000000000000000000000000000000000000000000000000000000"
cast send $TIMELOCK "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)" "[$GER_ADMIN,$BRIDGE_ADMIN]" "[0,0]" "[$DATA_GER,$DATA_BRIDGE]" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $SALT \
  $TIMELOCK_DELAY \
  --rpc-url $rpc_url --from $from --unlocked --legacy

sleep $(($TIMELOCK_DELAY + 15))

cast send $TIMELOCK \
  "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)" \
  "[$GER_ADMIN,$BRIDGE_ADMIN]" \
  "[0,0]" \
  "[$DATA_GER,$DATA_BRIDGE]" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $SALT \
  --rpc-url $rpc_url --from $from --unlocked

# cast send $l2_bridge_proxy_addr $BRIDGE_INIT_DATA --from $from --unlocked --rpc-url $rpc_url || exit 1
# echo $(cast call $l2_bridge_proxy_addr $BRIDGE_INIT_DATA --from $from --rpc-url $rpc_url) || exit 1

PK=0x$(openssl rand -hex 32)
ADDR=$(cast wallet address --private-key "$PK")
echo "ADDRESS=$ADDR"
echo "PRIVATE_KEY=$PK"
cast rpc anvil_setBalance $ADDR 0x56bc75e2d63100000 --rpc-url $rpc_url

polycli ulxly bridge asset \
    --value 1 \
    --gas-limit 1250000 \
    --bridge-address "$l2_bridge_proxy_addr" \
    --destination-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --destination-network 0 \
    --rpc-url $rpc_url \
    --private-key "$PK" || exit 1

echo "✅ GER SOVEREIGN VERSION DEPLOYED: $(cast call --rpc-url $rpc_url $l2_GER_proxy_addr 'GER_SOVEREIGN_VERSION()(string)' || exit 1)"
echo "✅ BRIDGE SOVEREIGN VERSION DEPLOYED: $(cast call --rpc-url $rpc_url $l2_bridge_proxy_addr 'BRIDGE_SOVEREIGN_VERSION()(string)' || exit 1)"
echo "✅ L2 GER updated successfully. L2GERUpdater: $(cast call $l2_GER_proxy_addr 'globalExitRootUpdater()(address)' --rpc-url $rpc_url)"
