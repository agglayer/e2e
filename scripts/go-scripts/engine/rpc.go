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
	"github.com/0xPolygonHermez/zkevm-node/jsonrpc/types"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
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

func NewRequest(method string, parameters []any) types.Request {
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
