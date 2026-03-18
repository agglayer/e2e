package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/agglayer/e2e/core/golang/tools/log"
	"github.com/ethereum/go-ethereum/common"
)

const (
	TimeoutTxToBeMined    = 30 * time.Second
	TimeoutTxToDisappear = 5 * time.Minute

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

