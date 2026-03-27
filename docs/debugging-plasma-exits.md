# Debugging Polygon PoS Plasma Exits

This guide documents how to debug L2→L1 Plasma exit operations on the Polygon PoS bridge.
It covers the full flow, what can go wrong at each step, and how to investigate issues.

## Overview: The Plasma Exit Flow

```
L2: burn tokens (withdraw(uint256) on 0x1010)
        ↓
    wait for checkpoint (Heimdall submits block range to L1 RootChain)
        ↓
    generate exit payload (polycli pos exit-proof)
        ↓
L1: startExitWithBurntTokens(bytes) on ERC20Predicate
        ↓
    wait for HALF_EXIT_PERIOD (1s on devnet, ~7 days on mainnet)
        ↓
L1: processExits(MATIC) on WithdrawManagerProxy
        ↓
    POL balance increases
```

## Key Contracts

| Contract | Address (devnet) | Role |
|---|---|---|
| ERC20Predicate | `0x1D4b8c4d...CA35` | Verifies burn proof, queues exit |
| WithdrawManagerProxy | `0x862ff216...10` | Manages exit queue, processes exits |
| WithdrawManager (impl) | `0x489E1b7F...73` | WithdrawManager logic (behind proxy) |
| RootChainProxy | `0x39b4be5a...68` | Stores checkpoint data |
| ExitNFT | `0xF2dd130f...A4` | NFT minted when exit is queued |

Get addresses from the enclave:
```bash
kurtosis files inspect pos matic-contract-addresses contractAddresses.json | jq '.root.predicates, .root.WithdrawManagerProxy'
```

## Step-by-Step Debugging

### Step 1: Burn on L2

```bash
# Send the burn transaction
withdraw_receipt=$(cast send \
  --rpc-url "${L2_RPC_URL}" \
  --private-key "${PRIVATE_KEY}" \
  --value "1000000000000000000" \
  --json \
  "0x0000000000000000000000000000000000001010" \
  "withdraw(uint256)" "1000000000000000000")

withdraw_tx_hash=$(echo "${withdraw_receipt}" | jq -r '.transactionHash')
withdraw_block=$(echo "${withdraw_receipt}" | jq -r '.blockNumber' | xargs printf "%d")
echo "Burn tx: ${withdraw_tx_hash} at block ${withdraw_block}"
```

**What to check:**
- `status: 1` — if status 0, the burn failed. The 0x1010 contract requires the amount to be bridge-backed. You must run a bridge (deposit) test first.
- Check log index 1 is `Withdraw` event: `cast receipt --rpc-url "${L2_RPC_URL}" --json "${withdraw_tx_hash}" | jq '.logs[1].topics[0]'` should be `0xebff2602...`

**Common issue:** Burn reverts because no bridge-backed balance exists. Run the bridge POL test first.

### Step 2: Wait for Checkpoint

```bash
# Poll Heimdall for checkpoint count
curl -s "${L2_CL_API_URL}/checkpoints/latest" | jq '.checkpoint.id'

# A new checkpoint should appear covering withdraw_block
# This can take ~1-2 minutes on devnet
```

**What to check:**
- The checkpoint ID should increment, and the checkpoint's `end_block` should be >= `withdraw_block`
- Query a specific checkpoint: `curl -s "${L2_CL_API_URL}/checkpoints/${CHECKPOINT_ID}" | jq .`

### Step 3: Generate Exit Payload

```bash
# The native token burn is at log index 1 (LogTransfer=0, Withdraw=1, LogFeeTransfer=2)
payload=$(polycli pos exit-proof \
  --l1-rpc-url "${L1_RPC_URL}" \
  --l2-rpc-url "${L2_RPC_URL}" \
  --root-chain-address "${L1_ROOT_CHAIN_PROXY_ADDRESS}" \
  --tx-hash "${withdraw_tx_hash}" \
  --log-index 1 2>/dev/null)
echo "Payload length: ${#payload}"
echo "First byte: 0x${payload:2:2}"  # Should be 0xf9 (RLP long list prefix)
```

**What to check:**
- First byte `0xf9` or `0xf8` or anything `>= 0xc0` = RLP list (correct)
- First byte `0x00` = ABI encoding (wrong — polycli bug)
- If polycli fails: checkpoint not yet indexed, retry in a few seconds

**Debugging payload format (RLP decode):**
```bash
# Check the branchMask field (field[8] in the RLP list)
# It should start with 0x00 (extension HP encoding)
# The branchMask for tx at index 0 should be 0x0080
python3 -c "
import rlp
data = bytes.fromhex('${payload[2:]}')
fields = rlp.decode(data)
print('branchMask:', fields[8].hex())  # Should be 0080 for txIndex=0
print('logIndex:', int.from_bytes(fields[9], 'big'))  # Should be 1
"
```

### Step 4: Simulate startExitWithBurntTokens

Always simulate before sending:
```bash
address=$(cast wallet address --private-key "${PRIVATE_KEY}")
cast call \
  --rpc-url "${L1_RPC_URL}" \
  --from "${address}" \
  "${L1_ERC20_PREDICATE_ADDRESS}" \
  "startExitWithBurntTokens(bytes)" \
  "${payload}" 2>&1
```

**Expected:** `0x` (empty return, no revert)

**Common revert messages and their causes:**

| Error | Cause | Fix |
|---|---|---|
| `incorrect mask` | branchMask[0] != 0 (HP leaf encoding used instead of extension) | polycli bug: don't include terminator in hexToCompact |
| `INVALID_RECEIPT_MERKLE_PROOF` | Proof nodes encoded as byte strings, not RLP lists | polycli bug: use `rlp.RawValue` for proof nodes |
| `WITHDRAW_BLOCK_NOT_A_PART_OF_SUBMITTED_HEADER` | Block Merkle leaf is wrong (using block hash instead of keccak256(n,ts,txRoot,receiptsRoot)) | polycli bug: compute correct leaf |
| `Not a withdraw event signature` | Wrong log index — pointed to LogTransfer instead of Withdraw | Use `--log-index 1` for native token |
| `Withdrawer and burn exit tx do not match` | `msg.sender` != topic[2] (from address in Withdraw event) | Send from the same address that did the burn |

### Step 5: Send startExitWithBurntTokens

```bash
cast send \
  --rpc-url "${L1_RPC_URL}" \
  --private-key "${PRIVATE_KEY}" \
  --gas-limit 500000 \
  "${L1_ERC20_PREDICATE_ADDRESS}" \
  "startExitWithBurntTokens(bytes)" \
  "${payload}"
```

**What to check after:**
```bash
# Verify ExitStarted event was emitted on WithdrawManager
# The tx receipt should have 2 logs:
# - Log 0: ExitNFT Transfer (minted to user)
# - Log 1: WithdrawManager ExitStarted
cast receipt --rpc-url "${L1_RPC_URL}" --json "${TX_HASH}" | jq '.logs | length'

# Get the exit ID
cast receipt --rpc-url "${L1_RPC_URL}" --json "${TX_HASH}" | jq '.logs[1].topics[2]'

# Verify queue has 1 exit under MATIC
queue=$(cast call --rpc-url "${L1_RPC_URL}" "${WITHDRAW_MANAGER}" "exitsQueues(address)(address)" "${MATIC}")
cast call --rpc-url "${L1_RPC_URL}" "${queue}" "currentSize()(uint256)"
# Should return 1
```

### Step 6: Check Exit is Processable

```bash
WITHDRAW_MANAGER="0x862ff216d822fBF2F381812627D4216d2150e810"
MATIC="0x8E1700577B7aE261753c67e1B93Fe60Dd3e205fa"
queue=$(cast call --rpc-url "${L1_RPC_URL}" "${WITHDRAW_MANAGER}" "exitsQueues(address)(address)" "${MATIC}")

# Get exitableAt from the queue
cast call --rpc-url "${L1_RPC_URL}" "${queue}" "getMin()(uint256,uint256)"
# First return value = exitableAt (unix timestamp)

# Get current block timestamp
curl -s -X POST "${L1_RPC_URL}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
  | jq -r '.result.timestamp' | xargs printf "%d\n"

# Exit is processable when: exitableAt <= block.timestamp
```

**Key insight:** `exitableAt = Math.max(checkpoint_createdAt + 2*HALF_EXIT_PERIOD, now_at_startExit + HALF_EXIT_PERIOD)`. With `HALF_EXIT_PERIOD=1`, the exit may not be processable for 1 second. On a fast devnet, `processExits` called in the very next block might still be too early. Retry in a loop.

### Step 7: Process Exit

```bash
cast send \
  --rpc-url "${L1_RPC_URL}" \
  --private-key "${PRIVATE_KEY}" \
  "${WITHDRAW_MANAGER}" \
  "processExits(address)" \
  "${MATIC}"
```

**What to check:**
- If `logs: []` — either exit not yet processable (retry) or already processed (queue empty now)
- If `Withdraw` event emitted — exit was processed
- The `Withdraw` event is on WithdrawManagerProxy (0x862ff2...)

**Check if POL balance increased:**
```bash
cast call --rpc-url "${L1_RPC_URL}" --json \
  "${L1_POL_TOKEN_ADDRESS}" "balanceOf(address)(uint)" "${address}" | jq -r '.[0]'
```

## Advanced Debugging: Tracing Transactions

### Trace a failed transaction
```bash
# Requires archive node or recent block
cast run --rpc-url "${L1_RPC_URL}" "${TX_HASH}"

# Or use debug_traceCall to simulate at latest block
curl -s -X POST "${L1_RPC_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"debug_traceCall",
    "params":[{
      "from":"YOUR_ADDRESS",
      "to":"CONTRACT_ADDRESS",
      "data":"CALLDATA",
      "gas":"0x1E8480"
    },"latest",{"tracer":"callTracer","tracerConfig":{"withLog":true}}],
    "id":1
  }' | jq '.result'
```

### Get revert reason from a failed call
```bash
cast call --rpc-url "${L1_RPC_URL}" \
  --from "${address}" \
  "${CONTRACT}" "FUNCTION_SIG" "ARGS" 2>&1
# Error: execution reverted: REVERT_REASON
```

### Inspect the exit queue state
```bash
# Check queue size
queue=$(cast call --rpc-url "${L1_RPC_URL}" "${WITHDRAW_MANAGER}" "exitsQueues(address)(address)" "${TOKEN}")
cast call --rpc-url "${L1_RPC_URL}" "${queue}" "currentSize()(uint256)"

# Get minimum priority (exitableAt) and value (lower exitId bits)
cast call --rpc-url "${L1_RPC_URL}" "${queue}" "getMin()(uint256,uint256)"

# Reconstruct the exitId
python3 -c "
exit_at = EXITABLE_AT
lower = LOWER_VALUE
exit_id = (exit_at << 128) | lower
print('exitId:', exit_id)
print('exitId hex:', hex(exit_id))
"

# Check exits[exitId] storage (amount, txHash, exitor, token, isRegularExit, predicate)
cast call --rpc-url "${L1_RPC_URL}" "${WITHDRAW_MANAGER}" \
  "exits(uint256)(uint256,bytes32,address,address,bool,address)" "${EXIT_ID}"

# Check ExitNFT ownership
EXIT_NFT="0xF2dd130f8dfA4f55c6CCABB48f385c100c37D8A4"
cast call --rpc-url "${L1_RPC_URL}" "${EXIT_NFT}" "exists(uint256)(bool)" "${EXIT_ID}"
cast call --rpc-url "${L1_RPC_URL}" "${EXIT_NFT}" "ownerOf(uint256)(address)" "${EXIT_ID}"
```

## Understanding the Exit Payload Format

The payload is an **RLP-encoded list** of 10 fields:

```
RLP([
  headerNumber,       // uint: checkpoint ID × stride (e.g., checkpoint 2 → 20000)
  blockProof,         // bytes: binary Merkle proof of the block within the checkpoint
  blockNumber,        // uint: L2 block number containing the burn tx
  blockTimestamp,     // uint: timestamp of that L2 block
  txRoot,             // bytes32: transactions root of that L2 block
  receiptRoot,        // bytes32: receipts root of that L2 block
  receipt,            // bytes: RLP-encoded burn transaction receipt
  receiptParentNodes, // bytes: RLP-encoded list of MPT proof nodes (root-to-leaf)
  branchMask,         // bytes: HP-encoded path through receipt MPT (e.g., [0x00, 0x80] for txIndex=0)
  logIndex            // uint: which log in the receipt is the Withdraw event (1 for native token)
])
```

**branchMask explained:**
- The receipt MPT uses `rlp(txIndex)` as the key (e.g., txIndex=0 → key=`0x80`)
- The key nibbles are `[8, 0]` for key `0x80`
- HP encoding without terminator: `[0x00, 0x80]` (extension prefix 0x00 = even length)
- `verifyInclusion` requires `branchMaskBytes[0] == 0` — this is satisfied by extension encoding

**blockProof (checkpoint Merkle proof) explained:**
- The checkpoint stores a Merkle root of all blocks in the range
- Each leaf is: `keccak256(abi.encodePacked(blockNum_32, blockTime_32, txRoot_32, receiptsRoot_32))`
- This is NOT the Ethereum block hash — it's a hash of specific fields
- The proof is an array of sibling hashes concatenated (32 bytes each)

## Why MATIC and not POL for processExits?

The 0x1010 contract on L2 emits:
```solidity
event Withdraw(address indexed token, address indexed from, uint256 amount, uint256 input1, uint256 output1)
```

where `token` = the L1 root token = MATIC (the original mapping before POL migration).

`ERC20Predicate.startExitWithBurntTokens` reads `rootToken = topics[1] = MATIC` and calls `addExitToQueue(..., rootToken=MATIC, ...)`.

`WithdrawManager` indexes exits under `exitsQueues[rootToken]` = `exitsQueues[MATIC]`.

So `processExits(MATIC)` is correct. Internally, `onFinalizeExit` converts MATIC→POL via the registry and transfers POL to the user.

## Proxy vs Implementation

`WithdrawManagerProxy` delegates most calls to `WithdrawManager` (impl). BUT some functions are implemented DIRECTLY in the proxy (don't delegate):
- `exitsQueues(address)` — reads proxy storage directly
- `exits(uint256)` — reads proxy storage directly
- `exitNft()` — reads proxy storage

When debugging, ensure you compute the **correct function selector**:
```bash
cast keccak "processExits(address)" | head -c 10
# → 0x0f6795f2

cast keccak "startExitWithBurntTokens(bytes)" | head -c 10
# → 0x6f7c1f04
```

The wrong selector might accidentally hit a proxy-direct function (e.g., `0x72d8d524` is not `processExits`).
