package engine

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/tools/log"
	"github.com/0xPolygonHermez/zkevm-node/hex"
	"github.com/0xPolygonHermez/zkevm-node/jsonrpc/types"
	"github.com/ethereum/go-ethereum/common"
)

const (
	TimeoutTxToBeMined    = 1 * time.Minute
	TimeoutTxToBeFound    = 1 * time.Minute
	TimeoutBlockToBeFound = 1 * time.Minute
	TimeoutBatchToBeFound = 1 * time.Minute

	jsonRPC_Version = "2.0"
	jsonRPC_ID      = 1
)

// WaitTxToBeMined waits until a tx has been mined or the given timeout expires.
func WaitTxToBeMined(t *testing.T, ctx context.Context, url string, txHash common.Hash, timeout time.Duration) error {
	log.Msgf(t, "waiting tx %v to be mined", txHash.String())

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{txHash.String()}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := types.Request{
			JSONRPC: jsonRPC_Version,
			ID:      jsonRPC_ID,
			Method:  "eth_getTransactionReceipt",
			Params:  bParams,
		}
		res, err := RPCCall(t, url, req)
		if err != nil {
			return err
		}

		if res.Error != nil {
			return res.Error.RPCError()
		}

		b, err := json.Marshal(res.Result)
		if err != nil {
			return err
		}
		result := string(b)

		if result == "null" {
			log.Msgf(t, "tx %v not mined yet", txHash.String())
		} else {
			log.Msg(t, "transaction found: ", txHash)
			return nil
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if err != nil {
				log.Msgf(t, "error waiting tx %v to be mined: %v", txHash, err)
				return err
			}
			log.Msgf(t, "stopped waiting tx %v to be mined, the context is done without errors", txHash)
			return err
		case <-queryTicker.C:
		}
	}
}

func WaitTxToBeFoundByHash(ctx context.Context, t *testing.T, url string, txHash common.Hash, timeout time.Duration) error {
	log.Msgf(t, "waiting tx %v to be found", txHash.String())

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{txHash.String()}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := types.Request{
			JSONRPC: jsonRPC_Version,
			ID:      jsonRPC_ID,
			Method:  "eth_getTransactionByHash",
			Params:  bParams,
		}
		res, err := RPCCall(t, url, req)
		if err != nil {
			return err
		}

		if res.Error != nil {
			return res.Error.RPCError()
		}

		b, err := json.Marshal(res.Result)
		if err != nil {
			return err
		}
		result := string(b)

		if result == "null" {
			log.Msgf(t, "tx %v not mined yet", txHash.String())
		} else {
			log.Msg(t, "transaction found: ", txHash)
			return nil
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				return err
			} else if err != nil {
				log.Msgf(t, "error waiting tx %v to be found: %v", txHash, err)
				return err
			}
			log.Msgf(t, "stopped waiting tx %v to be found, the context is done without errors", txHash)
			return err
		case <-queryTicker.C:
		}
	}
}

func WaitTxToDisappearByHash(ctx context.Context, t *testing.T, url string, txHash common.Hash, timeout time.Duration) error {
	log.Msgf(t, "waiting tx %v to disappear", txHash.String())

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{txHash.String()}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := types.Request{
			JSONRPC: jsonRPC_Version,
			ID:      jsonRPC_ID,
			Method:  "eth_getTransactionByHash",
			Params:  bParams,
		}
		res, err := RPCCall(t, url, req)
		if err != nil {
			return err
		}

		if res.Error != nil {
			return res.Error.RPCError()
		}

		b, err := json.Marshal(res.Result)
		if err != nil {
			return err
		}
		result := string(b)

		if result == "null" {
			log.Msg(t, "transaction disappeared: ", txHash)
			return nil
		} else {
			log.Msgf(t, "tx %v still exists", txHash.String())
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				return err
			} else if err != nil {
				log.Msgf(t, "error waiting tx %v to disappear: %v", txHash, err)
				return err
			}
			log.Msgf(t, "stopped waiting tx %v to disappear, the context is done without errors", txHash)
			return err
		case <-queryTicker.C:
		}
	}
}

func WaitForBlockToBeFoundByNumber(ctx context.Context, t *testing.T, url string, blockNumber uint64, timeout time.Duration) error {
	log.Msgf(t, "waiting block %v to be found", blockNumber)

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{hex.EncodeUint64(blockNumber), false}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := types.Request{
			JSONRPC: jsonRPC_Version,
			ID:      jsonRPC_ID,
			Method:  "eth_getBlockByNumber",
			Params:  bParams,
		}
		res, err := RPCCall(t, url, req)
		if err != nil {
			return err
		}

		if res.Error != nil {
			return res.Error.RPCError()
		}

		b, err := json.Marshal(res.Result)
		if err != nil {
			return err
		}
		result := string(b)

		if result == "null" {
			log.Msgf(t, "block %v not found yet", blockNumber)
		} else {
			log.Msg(t, "block found: ", blockNumber)
			return nil
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				return err
			} else if err != nil {
				log.Msgf(t, "error waiting block %v to be found: %v", blockNumber, err)
				return err
			}
			log.Msgf(t, "stopped waiting block %v to be found, the context is done without errors", blockNumber)
			return err
		case <-queryTicker.C:
		}
	}
}

func WaitForBatchToBeFoundByNumber(ctx context.Context, t *testing.T, url string, batchNumber uint64, timeout time.Duration) error {
	log.Msgf(t, "waiting batch %v to be found", batchNumber)

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{hex.EncodeUint64(batchNumber), false}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := types.Request{
			JSONRPC: jsonRPC_Version,
			ID:      jsonRPC_ID,
			Method:  "zkevm_getBatchByNumber",
			Params:  bParams,
		}
		res, err := RPCCall(t, url, req)
		if err != nil {
			return err
		}

		if res.Error != nil {
			return res.Error.RPCError()
		}

		b, err := json.Marshal(res.Result)
		if err != nil {
			return err
		}
		result := string(b)

		if result == "null" {
			log.Msgf(t, "batch %v not found yet", batchNumber)
		} else {
			log.Msg(t, "batch found: ", batchNumber)
			return nil
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				return err
			} else if err != nil {
				log.Msgf(t, "error waiting batch %v to be found: %v", batchNumber, err)
				return err
			}
			log.Msgf(t, "stopped waiting batch %v to be found, the context is done without errors", batchNumber)
			return err
		case <-queryTicker.C:
		}
	}
}
