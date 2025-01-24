package engine

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"

	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/tools/log"
	"github.com/0xPolygonHermez/zkevm-node/hex"
	"github.com/0xPolygonHermez/zkevm-node/jsonrpc/types"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	ethTypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

func RPCCall(t *testing.T, url string, request types.Request) (types.Response, error) {
	input, err := json.Marshal(request)
	if err != nil {
		return types.Response{}, err
	}

	output, err := RawJSONRPCCall(t, url, input)
	if err != nil {
		return types.Response{}, err
	}

	var res types.Response
	err = json.Unmarshal(output, &res)
	if err != nil {
		return types.Response{}, err
	}

	return res, nil
}

func RawJSONRPCCall(t *testing.T, url string, input json.RawMessage) (json.RawMessage, error) {
	reqBodyReader := bytes.NewReader(input)
	httpReq, err := http.NewRequest(http.MethodPost, url, reqBodyReader)
	if err != nil {
		return nil, err
	}

	httpReq.Header.Add("Content-type", "application/json")

	httpRes, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, err
	}

	output, err := io.ReadAll(httpRes.Body)
	if err != nil {
		return nil, err
	}
	defer httpRes.Body.Close()

	if httpRes.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%v - %v", httpRes.StatusCode, string(output))
	}

	// removes output suffix trailing newline
	if len(output) > 0 && output[len(output)-1] == 10 {
		output = output[:len(output)-1]
	}

	log.Msgf(t, "RPC call to %v", url)
	log.Complements(t, fmt.Sprintf("request: %v", string(input)), fmt.Sprintf("response: %v", string(output)))
	return output, nil
}

const (
	requestVersion = "2.0"
	requestId      = float64(1)
)

func NewRequest(method string, parameters ...any) types.Request {
	params, _ := json.Marshal(parameters)
	return types.Request{
		JSONRPC: requestVersion,
		ID:      requestId,
		Method:  method,
		Params:  params,
	}
}

// GetClient returns an ethereum client to the provided URL
func GetClient(URL string) (*ethclient.Client, error) {
	client, err := ethclient.Dial(URL)
	if err != nil {
		return nil, err
	}
	return client, nil
}

// MustGetClient GetClient but panic if err
func MustGetClient(URL string) *ethclient.Client {
	client, err := GetClient(URL)
	if err != nil {
		panic(err)
	}
	return client
}

// GetAuth configures and returns an auth object.
func GetAuth(privateKeyStr string, chainID uint64) (*bind.TransactOpts, error) {
	privateKey, err := crypto.HexToECDSA(strings.TrimPrefix(privateKeyStr, "0x"))
	if err != nil {
		return nil, err
	}

	return bind.NewKeyedTransactorWithChainID(privateKey, big.NewInt(0).SetUint64(chainID))
}

// MustGetAuth GetAuth but panics if err
func MustGetAuth(privateKeyStr string, chainID uint64) *bind.TransactOpts {
	auth, err := GetAuth(privateKeyStr, chainID)
	if err != nil {
		panic(err)
	}
	return auth
}

// GetSender gets the sender from the transaction's signature
func GetSender(tx ethTypes.Transaction) (common.Address, error) {
	signer := ethTypes.NewEIP155Signer(tx.ChainId())
	sender, err := signer.Sender(&tx)
	if err != nil {
		return common.Address{}, err
	}
	return sender, nil
}

// TxToMsg converts a transaction to a call message
func TxToMsg(tx ethTypes.Transaction) ethereum.CallMsg {
	sender, err := GetSender(tx)
	if err != nil {
		sender = common.Address{}
	}

	return ethereum.CallMsg{
		From:     sender,
		To:       tx.To(),
		Gas:      tx.Gas(),
		GasPrice: tx.GasPrice(),
		Value:    tx.Value(),
		Data:     tx.Data(),
	}
}

func TxToTxArgs(tx ethTypes.Transaction) map[string]any {
	sender, err := GetSender(tx)
	if err != nil {
		sender = common.Address{}
	}

	return map[string]any{
		"From":     sender.String(),
		"To":       tx.To().String(),
		"Gas":      hex.EncodeUint64(tx.Gas()),
		"GasPrice": hex.EncodeBig(tx.GasPrice()),
		"Value":    hex.EncodeBig(tx.Value()),
		"Input":    hex.EncodeToHex(tx.Data()),
	}
}
