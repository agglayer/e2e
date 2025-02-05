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

	"github.com/agglayer/e2e/core/go/tools/hex"
	"github.com/agglayer/e2e/core/go/tools/log"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Request is a jsonrpc request
type Request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// Response is a jsonrpc  success response
type Response struct {
	JSONRPC string
	ID      interface{}
	Result  json.RawMessage
	Error   *ErrorObject
}

// RPCError represents an error returned by a JSON RPC endpoint.
type RPCError struct {
	err  string
	code int
	data []byte
}

// Error returns the error message.
func (e RPCError) Error() string {
	return e.err
}

// ErrorCode returns the error code.
func (e *RPCError) ErrorCode() int {
	return e.code
}

// ErrorData returns the error data.
func (e *RPCError) ErrorData() []byte {
	return e.data
}

// ErrorObject is a jsonrpc error
type ErrorObject struct {
	Code    int       `json:"code"`
	Message string    `json:"message"`
	Data    *ArgBytes `json:"data,omitempty"`
}

// RPCError returns an instance of RPCError from the
// data available in the ErrorObject instance
func (e *ErrorObject) RPCError() RPCError {
	var data []byte
	if e.Data != nil {
		data = *e.Data
	}
	rpcError := NewRPCErrorWithData(e.Code, e.Message, data)
	return *rpcError
}

// NewRPCError creates a new error instance to be returned by the RPC endpoints
func NewRPCError(code int, err string, args ...interface{}) *RPCError {
	return NewRPCErrorWithData(code, err, nil, args...)
}

// NewRPCErrorWithData creates a new error instance with data to be returned by the RPC endpoints
func NewRPCErrorWithData(code int, err string, data []byte, args ...interface{}) *RPCError {
	var errMessage string
	if len(args) > 0 {
		errMessage = fmt.Sprintf(err, args...)
	} else {
		errMessage = err
	}
	return &RPCError{code: code, err: errMessage, data: data}
}

// ArgBytes helps to marshal byte array values provided in the RPC requests
type ArgBytes []byte

// MarshalText marshals into text
func (b ArgBytes) MarshalText() ([]byte, error) {
	return encodeToHex(b), nil
}

func encodeToHex(b []byte) []byte {
	str := hex.EncodeToString(b)
	if len(str)%2 != 0 {
		str = "0" + str
	}
	return []byte("0x" + str)
}

func RPCCall(t *testing.T, url string, request Request) (Response, error) {
	input, err := json.Marshal(request)
	if err != nil {
		return Response{}, err
	}

	output, err := RawJSONRPCCall(t, url, input)
	if err != nil {
		return Response{}, err
	}

	var res Response
	err = json.Unmarshal(output, &res)
	if err != nil {
		return Response{}, err
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

func NewRequest(method string, parameters ...any) Request {
	params, _ := json.Marshal(parameters)
	return Request{
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
func GetSender(tx types.Transaction) (common.Address, error) {
	signer := types.NewEIP155Signer(tx.ChainId())
	sender, err := signer.Sender(&tx)
	if err != nil {
		return common.Address{}, err
	}
	return sender, nil
}

// TxToMsg converts a transaction to a call message
func TxToMsg(tx types.Transaction) ethereum.CallMsg {
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

func TxToTxArgs(tx types.Transaction) map[string]any {
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
