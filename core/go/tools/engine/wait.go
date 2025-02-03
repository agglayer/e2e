package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/agglayer/e2e/core/go/tools/hex"
	"github.com/agglayer/e2e/core/go/tools/log"
	"github.com/ethereum/go-ethereum/common"
)

const (
	TimeoutTxToBeMined    = 1 * time.Minute
	TimeoutTxToBeFound    = 1 * time.Minute
	TimeoutBlockToBeFound = 1 * time.Minute
	TimeoutBatchToBeFound = 1 * time.Minute
	TimeoutTxToDisappear  = 5 * time.Minute

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
		req := Request{
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
			var m map[string]any
			err := json.Unmarshal(b, &m)
			if err != nil {
				log.Msgf(t, "error checking if tx %v was mined or not: %v", txHash.String(), err.Error())
				return err
			}
			if m["blockHash"] != nil {
				log.Msgf(t, "tx %v was mined", txHash.String())
				return nil
			} else {
				log.Msgf(t, "tx %v not mined yet", txHash.String())
			}
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				log.Msgf(t, "stopped waiting tx %v to be mined, timeout expired", txHash)
				return err
			} else if err != nil {
				log.Msgf(t, "error waiting tx %v to be mined: %v", txHash, err)
				return err
			}
			log.Msgf(t, "stopped waiting tx %v to be mined, the context is done without errors", txHash)
			return err
		case <-queryTicker.C:
		}
	}
}

func WaitTxToBeFoundByHash(t *testing.T, ctx context.Context, url string, txHash common.Hash, timeout time.Duration) error {
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
		req := Request{
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
				log.Msgf(t, "stopped waiting tx %v to be found, timeout expired", txHash)
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

// WaitTxToDisappearByHash waits until a not mined TX that was sent to the network and is still in the pool to disappear
// from the pool after being discarded during the selection phase. This is mainly used to test zkCounter offenders.
func WaitTxToDisappearByHash(t *testing.T, ctx context.Context, url string, txHash common.Hash, timeout time.Duration) error {
	log.Msgf(t, "waiting tx %v to disappear", txHash.String())

	innerCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	queryTicker := time.NewTicker(10 * time.Second)
	defer queryTicker.Stop()

	for {
		params := []interface{}{txHash.String()}
		bParams, err := json.Marshal(params)
		if err != nil {
			return err
		}
		req := Request{
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
			var m map[string]any
			err := json.Unmarshal(b, &m)
			if err != nil {
				log.Msgf(t, "error checking if tx %v was mined or not: %v", txHash.String(), err.Error())
				return err
			}
			if m["blockHash"] != nil {
				eMsg := fmt.Sprintf("tx %v was mined and will never disappear", txHash.String())
				log.Msgf(t, eMsg)
				return fmt.Errorf(eMsg)
			}

			log.Msgf(t, "tx %v still exists", txHash.String())
		}

		select {
		case <-innerCtx.Done():
			err := innerCtx.Err()
			if errors.Is(err, context.DeadlineExceeded) {
				log.Msgf(t, "stopped waiting tx %v to disappear, timeout expired", txHash)
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

func WaitForBlockToBeFoundByNumber(t *testing.T, ctx context.Context, url string, blockNumber uint64, timeout time.Duration) error {
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
		req := Request{
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

func WaitForBatchToBeFoundByNumber(t *testing.T, ctx context.Context, url string, batchNumber uint64, timeout time.Duration) error {
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
		req := Request{
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
