package test

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/agglayer/e2e/test/contracts/zkcounters"
	"github.com/agglayer/e2e/test/engine"
	"github.com/agglayer/e2e/test/tools/log"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const addr = ""

func TestZkCounters(t *testing.T) {
	rpcURL := os.Getenv("L2_RPC_URL")
	privateKeyHex := os.Getenv("L2_SENDER_PRIVATE_KEY")

	fmt.Println("rpcURL", rpcURL)
	fmt.Println("privateKeyHex", privateKeyHex)

	ctx := context.Background()
	client := engine.MustGetClient(rpcURL)

	blockNumber, err := client.BlockNumber(ctx)
	require.NoError(t, err)
	require.NotEqual(t, 0, blockNumber)

	chainID, err := client.ChainID(ctx)
	require.NoError(t, err)

	auth := engine.MustGetAuth(privateKeyHex, chainID.Uint64())

	type testCase struct {
		name                       string
		gasLimit                   uint64
		counter                    string
		expectedError              string
		createTxToEstimateCounters func(*testing.T, context.Context, *zkcounters.Zkcounters, *ethclient.Client, bind.TransactOpts) *types.Transaction
	}

	// THIS COMMENTED CODE BLOCK IS WAITING ERIGON TO FIX ESTIMATE COUNTERS
	{
		// estimateCounters := func(args map[string]any, counter string) (uint64, uint64, string) {
		// 	req := engine.NewRequest("zkevm_estimateCounters", args)
		// 	res, err := engine.RPCCall(t, rpcURL, req)
		// 	require.NoError(t, err)
		// 	require.Nil(t, res.Error)
		// 	require.NotNil(t, res.Result)

		// 	resMap := map[string]any{}
		// 	err = json.Unmarshal(res.Result, &resMap)
		// 	require.NoError(t, err)

		// 	countersUsedKey := "countersUsed"
		// 	countersLimitsKey := "countersLimits"

		// 	usedCounterKey := counter
		// 	maxCounterKey := counter

		// 	countersUsed := resMap[countersUsedKey].(map[string]any)
		// 	countersLimits := resMap[countersLimitsKey].(map[string]any)
		// 	oocError := ""
		// 	if v, found := resMap["oocError"]; found {
		// 		oocError = v.(string)
		// 	}

		// 	if v, found := resMap["revertInfo"]; found {
		// 		if v, found := v.(map[string]any)["message"]; found {
		// 			oocError = v.(string)
		// 		}
		// 	}

		// 	// print counters
		// 	const logColumnWidth = 30
		// 	headerSeparator := strings.Repeat("-", logColumnWidth)
		// 	columnSeparator := "|"
		// 	pad := func(s string) string {
		// 		startPos := logColumnWidth - len(s)
		// 		return strings.Repeat(" ", startPos) + s
		// 	}

		// 	log.Msg(t, columnSeparator, headerSeparator, "-", headerSeparator, "-", headerSeparator, columnSeparator)
		// 	log.Msg(t, columnSeparator, strings.Repeat(" ", 42), "zkCounters", strings.Repeat(" ", 42), columnSeparator)
		// 	log.Msg(t, columnSeparator, headerSeparator, "-", headerSeparator, "-", headerSeparator, columnSeparator)
		// 	log.Msg(t, columnSeparator, pad("counter name"), columnSeparator, pad("used"), columnSeparator, pad("limits"), columnSeparator)
		// 	log.Msg(t, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator)
		// 	for k, u := range countersUsed {
		// 		keyCounter := pad(k)
		// 		usedCounter := pad(fmt.Sprintf("%v", u))
		// 		maxCounter := pad(fmt.Sprintf("%v", countersLimits[k]))

		// 		target := ""
		// 		if k == usedCounterKey {
		// 			log.Msg(t, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator)
		// 			target = " <== target counter"
		// 		}

		// 		log.Msg(t, columnSeparator, keyCounter, columnSeparator, usedCounter, columnSeparator, maxCounter, columnSeparator, target)

		// 		if k == usedCounterKey {
		// 			log.Msg(t, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator)
		// 		}
		// 	}
		// 	log.Msg(t, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator, headerSeparator, columnSeparator)

		// 	used := uint64(countersUsed[usedCounterKey].(float64))
		// 	max := uint64(countersLimits[maxCounterKey].(float64))
		// 	return used, max, oocError
		// }
	}

	testCases := []testCase{
		{
			name: "max gas - tx discarded", counter: "gas", expectedError: "out of gas",
			gasLimit: 30000000, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.OverflowGas(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max gas - tx mined", counter: "gas", expectedError: "",
			gasLimit: 30000000, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.UseMaxGasPossible(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max keccaks - tx discarded", counter: "keccakHashes", expectedError: "not enough keccak counters to continue the execution",
			gasLimit: 499133, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxKeccakHashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max keccaks - tx mined", counter: "keccakHashes", expectedError: "",
			gasLimit: 496133, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxKeccakHashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max poseidon hashes - tx discarded", counter: "poseidonhashes", expectedError: "not enough poseidon counters to continue the execution",
			gasLimit: 1599010, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxPoseidonHashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max poseidon hashes - tx mined", counter: "poseidonhashes", expectedError: "",
			gasLimit: 1589010, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxPoseidonHashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
		// // TODO: We can't reach this counter yet
		// // {
		// // 	name: "max poseidon paddings - tx discarded", counter: "poseidonPaddings", expectedError: "not enough poseidon paddings counters to continue the execution",
		// // 	gasLimit: 30000000, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// // 		tx, err := sc.MaxPoseidonPaddings(&a)
		// // 		require.NoError(t, err)
		// // 		return tx
		// // 	},
		// // },
		// // {
		// // 	name: "max poseidon paddings - tx mined", counter: "poseidonPaddings", expectedError: "not enough poseidon paddings counters to continue the execution",
		// // 	gasLimit: 30000000, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// // 		tx, err := sc.MaxPoseidonPaddings(&a)
		// // 		require.NoError(t, err)
		// // 		return tx
		// // 	},
		// // },
		{
			name: "max mem aligns - tx discarded", counter: "memAligns", expectedError: "not enough mem aligns counters to continue the execution",
			gasLimit: 119305, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxMemAligns(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max mem aligns - tx mined", counter: "memAligns", expectedError: "",
			gasLimit: 118305, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxMemAligns(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max Arithmetics - tx discarded", counter: "arithmetics", expectedError: "not enough arithmetics counters to continue the execution",
			gasLimit: 2995828, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxArithmetics(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max Arithmetics - tx mined", counter: "arithmetics", expectedError: "",
			gasLimit: 2985828, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxArithmetics(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max binaries - tx discarded", counter: "binaries", expectedError: "not enough binary counters to continue the execution",
			gasLimit: 1654654, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxBinaries(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max binaries - tx mined", counter: "binaries", expectedError: "",
			gasLimit: 1644654, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxBinaries(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max steps - tx discarded", counter: "steps", expectedError: "not enough step counters to continue the execution",
			gasLimit: 3456200, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSteps(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max steps - tx mined", counter: "steps", expectedError: "",
			gasLimit: 3406200, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSteps(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max SHA256Hashes - tx discarded", counter: "SHA256hashes", expectedError: "not enough sha256 counters to continue the execution",
			gasLimit: 501000, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSHA256Hashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max SHA256Hashes - tx mined", counter: "SHA256hashes", expectedError: "",
			gasLimit: 500500, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSHA256Hashes(&a)
				require.NoError(t, err)
				return tx
			},
		},
	}

	var sc *zkcounters.Zkcounters
	if addr == "" {
		var scAddr common.Address
		var scTx *types.Transaction
		scAddr, scTx, sc, err = zkcounters.DeployZkcounters(auth, client)
		require.NoError(t, err)

		fmt.Println(scAddr)

		log.Tx(t, scTx)
		err = engine.WaitTxToBeMined(t, ctx, rpcURL, scTx.Hash(), engine.TimeoutTxToBeMined)
		require.NoError(t, err)
	} else {
		sc, err = zkcounters.NewZkcounters(common.HexToAddress(addr), client)
		require.NoError(t, err)
	}

	// create TX that cause an OOC
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			// define if the tx in this test case must get mined or not
			txMustGetMined := len(testCase.expectedError) == 0

			gasPrice, err := client.SuggestGasPrice(ctx)
			require.NoError(t, err)

			// create TX to validate counters
			a := *auth
			a.GasLimit = testCase.gasLimit
			a.GasPrice = gasPrice
			a.NoSend = true
			tx := testCase.createTxToEstimateCounters(t, context.Background(), sc, client, a)

			// send the tx
			err = client.SendTransaction(ctx, tx)
			require.NoError(t, err)

			// check tx is in the pool
			poolTx, pending, err := client.TransactionByHash(ctx, tx.Hash())
			assert.NoError(t, err)
			assert.True(t, pending)
			assert.NotNil(t, poolTx)

			// wait for tx
			if txMustGetMined {
				err = engine.WaitTxToBeMined(t, ctx, rpcURL, tx.Hash(), engine.TimeoutTxToBeMined)
				assert.NoError(t, err)

				receipt, err := client.TransactionReceipt(ctx, tx.Hash())
				assert.NoError(t, err)
				assert.Equal(t, uint64(types.ReceiptStatusSuccessful), receipt.Status)
			} else {
				err = engine.WaitTxToDisappearByHash(t, ctx, rpcURL, tx.Hash(), engine.TimeoutTxToDisappear)
				if err != nil && strings.Contains(err.Error(), "was mined and will never disappear") {
					receipt, err := client.TransactionReceipt(ctx, tx.Hash())
					assert.NoError(t, err)
					assert.Equal(t, uint64(types.ReceiptStatusFailed), receipt.Status)
				}
			}

			// THIS COMMENTED CODE BLOCK IS WAITING ERIGON TO FIX ESTIMATE COUNTERS
			{
				// // estimate counters
				// args := engine.TxToTxArgs(*tx)
				// used, max, counterError := estimateCounters(args, testCase.counter)

				// // check target counter against limit
				// if txMustGetMined {
				// 	assert.GreaterOrEqual(t, max, used)
				// } else {
				// 	assert.GreaterOrEqual(t, used, max)
				// }

				// // check OOC error message
				// assert.Equal(t, testCase.expectedError, counterError)
			}
		})
	}
}

func NoError(t *testing.T, err error) {
	if err != nil {
		if t == nil {
			panic(err)
		} else {
			require.NoError(t, err)
		}
	}
}
