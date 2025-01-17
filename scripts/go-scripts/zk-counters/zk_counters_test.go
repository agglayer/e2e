package main

import (
	"context"
	"os"
	"testing"

	"github.com/0xPolygonHermez/zkevm-node/test/operations"
	"github.com/stretchr/testify/require"
)

func TestZkCounters(t *testing.T) {
	rpcURL := os.Getenv("l2_rpc_url")

	// privateKeyHex := "0x" + os.Getenv("SENDER_PRIVATE_KEY")

	ctx := context.Background()
	client := operations.MustGetClient(rpcURL)

	blockNumber, err := client.BlockNumber(ctx)
	require.NoError(t, err)
	require.NotEqual(t, 0, blockNumber)

	// chainID, err := client.ChainID(ctx)
	// require.NoError(t, err)

	// auth := operations.MustGetAuth(privateKeyHex, chainID.Uint64())

	// _, scTx, _, err := zkcounters.DeployZkcounters(auth, client)
	// require.NoError(t, err)

	// log.Tx(t, scTx)
	// err = engine.WaitTxToBeMined(t, ctx, rpcURL, scTx.Hash(), operations.DefaultTimeoutTxToBeMined)
	// require.NoError(t, err)

	// tx, err := sc.F0001(auth)
	// require.NoError(t, err)

	// log.Tx(t, tx)
	// err = engine.WaitTxToBeMined(t, ctx, rpcURL, scTx.Hash(), operations.DefaultTimeoutTxToBeMined)
	// require.NoError(t, err)
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
