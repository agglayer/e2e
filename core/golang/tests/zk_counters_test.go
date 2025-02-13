package test

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"strings"
	"testing"

	"github.com/agglayer/e2e/core/golang/contracts/zkcounters"
	"github.com/agglayer/e2e/core/golang/tools/engine"
	"github.com/agglayer/e2e/core/golang/tools/hex"
	"github.com/agglayer/e2e/core/golang/tools/log"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestZkCounters(t *testing.T) {
	// the test is able to deploy the SC for each run, but
	// addr can be used during the development to avoid deploying
	// SC every time, this should be left empty when pushing to
	// the repository
	const addr = ""

	rpcURL := os.Getenv("L2_SEQUENCER_RPC_URL")
	privateKeyHex := os.Getenv("L2_SENDER_PRIVATE_KEY")

	ctx := context.Background()
	client := engine.MustGetClient(rpcURL)

	forkIdResponse, err := engine.RPCCall(t, rpcURL, engine.NewRequest("zkevm_getForkId"))
	require.NoError(t, err)
	require.Nil(t, forkIdResponse.Error)
	require.NotNil(t, forkIdResponse.Result)

	var forkIdHex string
	err = json.Unmarshal(forkIdResponse.Result, &forkIdHex)
	require.NoError(t, err)
	require.NotEmpty(t, forkIdHex)

	forkId := hex.DecodeUint64(forkIdHex)

	blockNumber, err := client.BlockNumber(ctx)
	require.NoError(t, err)
	require.NotEqual(t, 0, blockNumber)

	chainID, err := client.ChainID(ctx)
	require.NoError(t, err)

	auth := engine.MustGetAuth(privateKeyHex, chainID.Uint64())

	type testCase struct {
		name                       string
		gasLimitByForkID           map[uint64]uint64
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
			gasLimitByForkID: map[uint64]uint64{9: 30000000, 11: 30000000, 12: 30000000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.OverflowGas(&a, big.NewInt(200))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max gas - tx mined", counter: "gas", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 18000000, 11: 30000000, 12: 30000000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.UseMaxGasPossible(&a, big.NewInt(1900))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max keccaks - tx discarded", counter: "keccakHashes", expectedError: "not enough keccak counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 138000, 11: 499133, 12: 499133}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxKeccakHashes(&a, big.NewInt(404))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max keccaks - tx mined", counter: "keccakHashes", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 137333, 11: 476133, 12: 476133}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxKeccakHashes(&a, big.NewInt(404))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max poseidon hashes - tx discarded", counter: "poseidonhashes", expectedError: "not enough poseidon counters to continue the execution",
<<<<<<< HEAD
			gasLimitByForkID: map[uint64]uint64{9: 450000, 11: 1599010, 12: 1549010},
=======
			gasLimitByForkID: map[uint64]uint64{9: 450000, 11: 1699010, 12: 1599010},
>>>>>>> main
			createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxPoseidonHashes(&a, big.NewInt(10000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max poseidon hashes - tx mined", counter: "poseidonhashes", expectedError: "",
<<<<<<< HEAD
			gasLimitByForkID: map[uint64]uint64{9: 400000, 11: 1549010, 12: 1499010}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
=======
			gasLimitByForkID: map[uint64]uint64{9: 400000, 11: 1599010, 12: 1549010}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
>>>>>>> main
				tx, err := sc.MaxPoseidonHashes(&a, big.NewInt(10000))
				require.NoError(t, err)
				return tx
			},
		},
		// TODO: We can't reach this counter yet
		// {
		// 	name: "max poseidon paddings - tx discarded", counter: "poseidonPaddings", expectedError: "not enough poseidon paddings counters to continue the execution",
		// map[uint64uint64]	gasLimitByForkID: {9:0,11: 30000000,12:30000000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxPoseidonPaddings(&a, big.NewInt(19364))
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name: "max poseidon paddings - tx mined", counter: "poseidonPaddings", expectedError: "not enough poseidon paddings counters to continue the execution",
		// map[uint64uint64]	gasLimitByForkID: {9:0,11: 30000000,12:30000000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxPoseidonPaddings(&a, big.NewInt(19364))
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		{
			name: "max mem aligns - tx discarded", counter: "memAligns", expectedError: "not enough mem aligns counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 81000, 11: 119305, 12: 119305}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxMemAligns(&a, big.NewInt(20000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max mem aligns - tx mined", counter: "memAligns", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 80000, 11: 118305, 12: 118305}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxMemAligns(&a, big.NewInt(20000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max Arithmetics - tx discarded", counter: "arithmetics", expectedError: "not enough arithmetics counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 790000, 11: 2995828, 12: 2995828}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxArithmetics(&a, big.NewInt(55000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max Arithmetics - tx mined", counter: "arithmetics", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 780000, 11: 2795828, 12: 2795828}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxArithmetics(&a, big.NewInt(55000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max binaries - tx discarded", counter: "binaries", expectedError: "not enough binary counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 415000, 11: 1654654, 12: 1654654}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxBinaries(&a, big.NewInt(145))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max binaries - tx mined", counter: "binaries", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 410000, 11: 1544654, 12: 1544654}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxBinaries(&a, big.NewInt(145))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max steps - tx discarded", counter: "steps", expectedError: "not enough step counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 870000, 11: 3556200, 12: 3456200}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSteps(&a, big.NewInt(10000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max steps - tx mined", counter: "steps", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 860000, 11: 3206200, 12: 3206200}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSteps(&a, big.NewInt(10000))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max SHA256Hashes - tx discarded", counter: "SHA256hashes", expectedError: "not enough sha256 counters to continue the execution",
			gasLimitByForkID: map[uint64]uint64{9: 100000, 11: 100000, 12: 100000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSHA256Hashes(&a, big.NewInt(175))
				require.NoError(t, err)
				return tx
			},
		},
		{
			name: "max SHA256Hashes - tx mined", counter: "SHA256hashes", expectedError: "",
			gasLimitByForkID: map[uint64]uint64{9: 90000, 11: 90000, 12: 90000}, createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
				tx, err := sc.MaxSHA256Hashes(&a, big.NewInt(175))
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

		log.Tx(t, scTx)
		err = engine.WaitTxToBeMined(t, ctx, rpcURL, scTx.Hash(), engine.TimeoutTxToBeMined)
		require.NoError(t, err)
		fmt.Println(scAddr)
	} else {
		sc, err = zkcounters.NewZkcounters(common.HexToAddress(addr), client)
		require.NoError(t, err)
	}

	// create TX that cause an OOC
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			// fund a random account to avoid nonce issues
			privateKey, err := crypto.GenerateKey()
			require.NoError(t, err)
			tcAuth, err := bind.NewKeyedTransactorWithChainID(privateKey, chainID)
			require.NoError(t, err)

			nonce, err := client.PendingNonceAt(ctx, auth.From)
			require.NoError(t, err)

			gasPrice, err := client.SuggestGasPrice(ctx)
			require.NoError(t, err)

			value, _ := big.NewInt(0).SetString("1000000000000000000", 10) // 1 ETH

			gas, err := client.EstimateGas(ctx, ethereum.CallMsg{
				From:     auth.From,
				To:       &tcAuth.From,
				GasPrice: gasPrice,
				Value:    value,
			})
			require.NoError(t, err)

			tx := types.NewTx(&types.LegacyTx{
				To:       &tcAuth.From,
				Nonce:    nonce,
				GasPrice: gasPrice,
				Value:    value,
				Gas:      gas,
			})

			signedTx, err := auth.Signer(auth.From, tx)
			require.NoError(t, err)

			err = client.SendTransaction(ctx, signedTx)
			require.NoError(t, err)

			err = engine.WaitTxToBeMined(t, ctx, rpcURL, signedTx.Hash(), engine.TimeoutTxToBeMined)
			require.NoError(t, err)

			// define if the tx in this test case must get mined or not
			txMustGetMined := len(testCase.expectedError) == 0

			gasLimit, found := testCase.gasLimitByForkID[forkId]
			if !found {
				t.Fatalf("gas limit not found for fork id %d", forkId)
			}

			// create TX to validate counters
			a := *tcAuth
			a.GasLimit = gasLimit
			a.GasPrice = gasPrice
			a.NoSend = true
			tx = testCase.createTxToEstimateCounters(t, context.Background(), sc, client, a)
			log.Tx(t, tx)

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
				require.NoError(t, err)

				receipt, err := client.TransactionReceipt(ctx, tx.Hash())
				require.NoError(t, err)
				require.Equal(t, uint64(types.ReceiptStatusSuccessful), receipt.Status)
			} else {
				err = engine.WaitTxToDisappearByHash(t, ctx, rpcURL, tx.Hash(), engine.TimeoutTxToDisappear)
				if err != nil && strings.Contains(err.Error(), "was mined and will never disappear") {
					receipt, err := client.TransactionReceipt(ctx, tx.Hash())
					require.NoError(t, err)
					require.Equal(t, uint64(types.ReceiptStatusFailed), receipt.Status)
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
