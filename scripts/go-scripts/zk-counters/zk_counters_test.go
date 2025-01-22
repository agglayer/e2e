package main

import (
	"context"
	"os"
	"testing"

	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/engine"
	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/tools/log"
	zkcounters "github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/zk-counters/sc"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
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
		name          string
		execute       func(*testing.T, context.Context, *zkcounters.Zkcounters, *ethclient.Client, bind.TransactOpts) string
		expectedError string
	}

	testCases := []testCase{
		{
			name: "call OOC steps",
			execute: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) string {
				a.GasLimit = 30000000
				a.NoSend = true
				tx, err := sc.OutOfCountersSteps(&a)
				require.NoError(t, err)

				// estimate / call tx to get ooc error
				// estimate counters to check usage is bigger than the limit
				// send tx, wait it to be found, check there is no receipt, wait tx to disappear from pool

				err = c.SendTransaction(ctx, tx)
				require.Nil(t, err)

				log.Tx(t, tx)
				err = engine.WaitTxToBeFoundByHash(ctx, t, rpcURL, tx.Hash(), engine.TimeoutTxToBeFound)
				require.NoError(t, err)

				receipt, err := c.TransactionReceipt(ctx, tx.Hash())
				require.NoError(t, err)
				require.Nil(t, receipt)

				err = engine.WaitTxToDisappearByHash(ctx, t, rpcURL, tx.Hash(), engine.TimeoutTxToBeFound)
				require.NoError(t, err)

				return err.Error()
			},
			expectedError: "failed to execute the unsigned transaction: main execution exceeded the maximum number of steps",
		},
		// {
		// 	name: "call OOC keccaks",
		// 	execute: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) string {
		// 		_, err := sc.OutOfCountersKeccaks(nil)
		// 		require.NotNil(t, err)
		// 		return err.Error()
		// 	},
		// 	expectedError: "failed to execute the unsigned transaction: not enough keccak counters to continue the execution",
		// },
		// {
		// 	name: "call OOC poseidon",
		// 	execute: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) string {
		// 		a.GasLimit = 30000000
		// 		a.NoSend = true
		// 		tx, err := sc.OutOfCountersPoseidon(&a)
		// 		require.NoError(t, err)

		// 		err = c.SendTransaction(ctx, tx)
		// 		require.NotNil(t, err)
		// 		return err.Error()
		// 	},
		// 	expectedError: "failed to add tx to the pool: not enough poseidon counters to continue the execution",
		// },
		// {
		// 	name: "estimate gas OOC poseidon",
		// 	execute: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) string {
		// 		a.GasLimit = 30000000
		// 		a.NoSend = true
		// 		tx, err := sc.OutOfCountersPoseidon(&a)
		// 		require.NoError(t, err)

		// 		_, err = c.EstimateGas(ctx, ethereum.CallMsg{
		// 			From:     a.From,
		// 			To:       tx.To(),
		// 			Gas:      tx.Gas(),
		// 			GasPrice: tx.GasPrice(),
		// 			Value:    tx.Value(),
		// 			Data:     tx.Data(),
		// 		})
		// 		require.NotNil(t, err)
		// 		return err.Error()
		// 	},
		// 	expectedError: "not enough poseidon counters to continue the execution",
		// },
		// {
		// 	name: "estimate gas OOG",
		// 	execute: func(t *testing.T, ctx context.Context, sc *zkcounters.Zkcounters, c *ethclient.Client, a bind.TransactOpts) string {
		// 		a.GasLimit = 50000
		// 		a.NoSend = true
		// 		tx, err := sc.OutOfCountersPoseidon(&a)
		// 		require.NoError(t, err)

		// 		_, err = c.EstimateGas(ctx, ethereum.CallMsg{
		// 			From:     a.From,
		// 			To:       tx.To(),
		// 			Gas:      tx.Gas(),
		// 			GasPrice: tx.GasPrice(),
		// 			Value:    tx.Value(),
		// 			Data:     tx.Data(),
		// 		})
		// 		require.NotNil(t, err)
		// 		return err.Error()
		// 	},
		// 	expectedError: "gas required exceeds allowance (50000)",
		// },
	}

	_, scTx, sc, err := zkcounters.DeployZkcounters(auth, client)
	require.NoError(t, err)

	log.Tx(t, scTx)
	err = engine.WaitTxToBeMined(t, ctx, rpcURL, scTx.Hash(), engine.TimeoutTxToBeMined)
	require.NoError(t, err)

	// create TX that cause an OOC
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			err := testCase.execute(t, context.Background(), sc, client, *auth)
			assert.Equal(t, testCase.expectedError, err)
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
