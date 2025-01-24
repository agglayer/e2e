package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/engine"
	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/tools/log"
	zkcounters "github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/zk-counters/sc"
	"github.com/0xPolygonHermez/zkevm-node/hex"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestZkCounters(t *testing.T) {
	rpcURL := os.Getenv("l2_rpc_url")
	privateKeyHex := "0x" + os.Getenv("SENDER_PRIVATE_KEY")

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

	estimateCounters := func(args map[string]any, counter string) (uint64, uint64, string) {
		req := engine.NewRequest("zkevm_estimateCounters", args)
		res, err := engine.RPCCall(t, rpcURL, req)
		require.NoError(t, err)
		require.Nil(t, res.Error)
		require.NotNil(t, res.Result)

		resMap := map[string]any{}
		err = json.Unmarshal(res.Result, &resMap)
		require.NoError(t, err)

		countersUsedKey := "countersUsed"
		countersLimitsKey := "countersLimits"

		usedCounterKey := counter
		maxCounterKey := counter

		// TODO: remove this switch when the counters are fixed on erigon.
		// This switch makes the code compatible with legacy node response
		// because erigon is using a different way to return the counters.
		countersLimitsKey = "countersLimit"
		switch counter {
		case "gas":
			usedCounterKey = "gasUsed"
			maxCounterKey = "maxGasUsed"
		case "keccakHashes":
			usedCounterKey = "usedKeccakHashes"
			maxCounterKey = "maxKeccakHashes"
		case "poseidonhashes":
			usedCounterKey = "usedPoseidonHashes"
			maxCounterKey = "maxPoseidonHashes"
		case "poseidonPaddings":
			usedCounterKey = "usedPoseidonPaddings"
			maxCounterKey = "maxPoseidonPaddings"
		case "memAligns":
			usedCounterKey = "usedMemAligns"
			maxCounterKey = "maxMemAligns"
		case "arithmetics":
			usedCounterKey = "usedArithmetics"
			maxCounterKey = "maxArithmetics"
		case "binaries":
			usedCounterKey = "usedBinaries"
			maxCounterKey = "maxBinaries"
		case "steps":
			usedCounterKey = "usedSteps"
			maxCounterKey = "maxSteps"
		case "SHA256hashes":
			usedCounterKey = "usedSHA256Hashes"
			maxCounterKey = "maxSHA256Hashes"
		}

		countersUsed := resMap[countersUsedKey].(map[string]any)
		countersLimits := resMap[countersLimitsKey].(map[string]any)
		oocError := resMap["oocError"].(string)

		usedHex := countersUsed[usedCounterKey].(string)
		used := hex.DecodeUint64(usedHex)
		maxHex := countersLimits[maxCounterKey].(string)
		max := hex.DecodeUint64(maxHex)
		return used, max, oocError
	}

	testCases := []testCase{
		// {
		// 	name:          "call OOC gas",
		// 	gasLimit:      29999999,
		// 	counter:       "gas",
		// 	expectedError: "gas required exceeds allowance (50000)",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxGasUsed(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC keccaks",
		// 	gasLimit:      494719,
		// 	counter:       "keccakHashes",
		// 	expectedError: "not enough keccak counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxKeccakHashes(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC poseidon hashes",
		// 	gasLimit:      1488485,
		// 	counter:       "poseidonhashes",
		// 	expectedError: "not enough poseidon counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxPoseidonHashes(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC poseidon paddings",
		// 	gasLimit:      30000000,
		// 	counter:       "poseidonPaddings",
		// 	expectedError: "not enough poseidon paddings counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxPoseidonPaddings(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC mem aligns",
		// 	gasLimit:      115644,
		// 	counter:       "memAligns",
		// 	expectedError: "not enough mem aligns counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxMemAligns(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC Arithmetics",
		// 	gasLimit:      3386851,
		// 	counter:       "arithmetics",
		// 	expectedError: "not enough arithmetics counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxArithmetics(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC binaries",
		// 	gasLimit:      1643884,
		// 	counter:       "binaries",
		// 	expectedError: "not enough binaries counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxBinaries(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC steps",
		// 	gasLimit:      5345981,
		// 	counter:       "steps",
		// 	expectedError: "not enough step counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxSteps(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
		// {
		// 	name:          "call OOC SHA256Hashes",
		// 	gasLimit:      498636,
		// 	counter:       "SHA256hashes",
		// 	expectedError: "not enough SHA256 Hashes counters to continue the execution",
		// 	createTxToEstimateCounters: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) *types.Transaction {
		// 		tx, err := sc.MaxSHA256Hashes(&a)
		// 		require.NoError(t, err)
		// 		return tx
		// 	},
		// },
	}

	addr := "0xFB054898a55bB49513D1BA8e0FB949Ea3D9B4153"
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
			a := *auth
			a.GasLimit = testCase.gasLimit
			a.NoSend = true
			tx := testCase.createTxToEstimateCounters(t, context.Background(), sc, client, a)
			args := engine.TxToTxArgs(*tx)
			used, max, counterError := estimateCounters(args, testCase.counter)
			if len(testCase.expectedError) == 0 {
				assert.GreaterOrEqual(t, max, used)
			} else {
				assert.Greater(t, used, max)
			}
			assert.Equal(t, testCase.expectedError, counterError)
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
