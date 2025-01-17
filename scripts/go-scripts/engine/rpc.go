package engine

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"

	"github.com/0xPolygon/evm-regression-tests/scripts/go-scripts/tools/log"
	"github.com/0xPolygonHermez/zkevm-node/jsonrpc/types"
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
