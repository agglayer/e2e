#!/usr/bin/env bats
# bats file_tags=pos,evm

setup() {
  # Load libraries.
  load "../../../core/helpers/pos-setup.bash"
  pos_setup
}

# bats test_tags=precompilers
@test "push and validate all available precompilers" {
  # BIN_PATH="core/contracts/bin/precompiletester.bin"
  # BYTECODE="0x$(tr -d '\n' < "$BIN_PATH")"

  # txhash=$(cast send --create "$BYTECODE" \
  #   --rpc-url "$L2_RPC_URL" \
  #   --private-key "$PRIVATE_KEY" \
  #   --json | jq -r '.transactionHash')
  txhash=$(forge create core/contracts/precompileTester/PrecompileTester.sol:PrecompileTester \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$L2_RPC_URL" \
    --broadcast \
    --priority-gas-price 35gwei \
    --gas-price 35gwei \
    --json | jq -r '.transactionHash')
  
  echo "${txhash}"

  SIG=$(cast keccak "PrecompileTestResult(uint256,address,bool,bytes32)")
  RECEIPT=$(cast receipt "${txhash}" --rpc-url "$L2_RPC_URL" --json)

  FAIL=0

  while read -r DATA; do
    OUT=$(cast abi-decode -i --json \
      "PrecompileTestResult(uint256 id,address precompile,bool success,bytes32 outputHash)" \
      "$DATA")

    ID=$(echo "$OUT" | jq -r '.[0]')
    PRE=$(echo "$OUT" | jq -r '.[1]')
    SUCCESS=$(echo "$OUT" | jq -r '.[2]')

    if [ "$SUCCESS" = "true" ]; then
      echo "✔ id=$ID precompile=$PRE success=true"
    else
      echo "❌ id=$ID precompile=$PRE success=false"
      FAIL=1
    fi
  done < <(
    echo "$RECEIPT" \
      | jq -r --arg sig "$SIG" '.logs[] | select(.topics[0] == $sig) | .data'
  )

  if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All precompiles passed!"
  else
    echo "💥 Some precompiles failed!"
  fi

}