// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package main

import (
	"errors"
	"math/big"
	"strings"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = ethereum.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
	_ = abi.ConvertType
)

// MainMetaData contains all meta data concerning the Main contract.
var MainMetaData = &bind.MetaData{
	ABI: "[{\"inputs\":[],\"name\":\"count\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersKeccaks\",\"outputs\":[{\"internalType\":\"bytes32\",\"name\":\"test\",\"type\":\"bytes32\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersPoseidon\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersSteps\",\"outputs\":[],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfGas\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
	Bin: "0x60806040525f8055348015610012575f80fd5b5061015c806100205f395ff3fe608060405234801561000f575f80fd5b5060043610610055575f3560e01c806306661abd146100595780632621002a1461007357806331fe52e81461007e5780638bd7b53814610088578063cb4e8cd114610090575b5f80fd5b6100615f5481565b60405190815260200160405180910390f35b620f42405f20610061565b610086610098565b005b6100866100bc565b6100866100e0565b5f5b60648110156100b957805f5580806100b190610102565b91505061009a565b50565b5f5b620186a08110156100b9576104d25f52806100d881610102565b9150506100be565b5f5b61c3508110156100b957805f5580806100fa90610102565b9150506100e2565b5f6001820161011f57634e487b7160e01b5f52601160045260245ffd5b506001019056fea264697066735822122053688c9ee4acb3ef944a6de3bfde9bbadc9d5a3296a62b664838d32858526e5f64736f6c63430008140033",
}

// MainABI is the input ABI used to generate the binding from.
// Deprecated: Use MainMetaData.ABI instead.
var MainABI = MainMetaData.ABI

// MainBin is the compiled bytecode used for deploying new contracts.
// Deprecated: Use MainMetaData.Bin instead.
var MainBin = MainMetaData.Bin

// DeployMain deploys a new Ethereum contract, binding an instance of Main to it.
func DeployMain(auth *bind.TransactOpts, backend bind.ContractBackend) (common.Address, *types.Transaction, *Main, error) {
	parsed, err := MainMetaData.GetAbi()
	if err != nil {
		return common.Address{}, nil, nil, err
	}
	if parsed == nil {
		return common.Address{}, nil, nil, errors.New("GetABI returned nil")
	}

	address, tx, contract, err := bind.DeployContract(auth, *parsed, common.FromHex(MainBin), backend)
	if err != nil {
		return common.Address{}, nil, nil, err
	}
	return address, tx, &Main{MainCaller: MainCaller{contract: contract}, MainTransactor: MainTransactor{contract: contract}, MainFilterer: MainFilterer{contract: contract}}, nil
}

// Main is an auto generated Go binding around an Ethereum contract.
type Main struct {
	MainCaller     // Read-only binding to the contract
	MainTransactor // Write-only binding to the contract
	MainFilterer   // Log filterer for contract events
}

// MainCaller is an auto generated read-only Go binding around an Ethereum contract.
type MainCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// MainTransactor is an auto generated write-only Go binding around an Ethereum contract.
type MainTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// MainFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type MainFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// MainSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type MainSession struct {
	Contract     *Main             // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// MainCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type MainCallerSession struct {
	Contract *MainCaller   // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts // Call options to use throughout this session
}

// MainTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type MainTransactorSession struct {
	Contract     *MainTransactor   // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// MainRaw is an auto generated low-level Go binding around an Ethereum contract.
type MainRaw struct {
	Contract *Main // Generic contract binding to access the raw methods on
}

// MainCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type MainCallerRaw struct {
	Contract *MainCaller // Generic read-only contract binding to access the raw methods on
}

// MainTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type MainTransactorRaw struct {
	Contract *MainTransactor // Generic write-only contract binding to access the raw methods on
}

// NewMain creates a new instance of Main, bound to a specific deployed contract.
func NewMain(address common.Address, backend bind.ContractBackend) (*Main, error) {
	contract, err := bindMain(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &Main{MainCaller: MainCaller{contract: contract}, MainTransactor: MainTransactor{contract: contract}, MainFilterer: MainFilterer{contract: contract}}, nil
}

// NewMainCaller creates a new read-only instance of Main, bound to a specific deployed contract.
func NewMainCaller(address common.Address, caller bind.ContractCaller) (*MainCaller, error) {
	contract, err := bindMain(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &MainCaller{contract: contract}, nil
}

// NewMainTransactor creates a new write-only instance of Main, bound to a specific deployed contract.
func NewMainTransactor(address common.Address, transactor bind.ContractTransactor) (*MainTransactor, error) {
	contract, err := bindMain(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &MainTransactor{contract: contract}, nil
}

// NewMainFilterer creates a new log filterer instance of Main, bound to a specific deployed contract.
func NewMainFilterer(address common.Address, filterer bind.ContractFilterer) (*MainFilterer, error) {
	contract, err := bindMain(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &MainFilterer{contract: contract}, nil
}

// bindMain binds a generic wrapper to an already deployed contract.
func bindMain(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := MainMetaData.GetAbi()
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, *parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Main *MainRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Main.Contract.MainCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Main *MainRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Main.Contract.MainTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Main *MainRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Main.Contract.MainTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Main *MainCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Main.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Main *MainTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Main.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Main *MainTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Main.Contract.contract.Transact(opts, method, params...)
}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Main *MainCaller) Count(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _Main.contract.Call(opts, &out, "count")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Main *MainSession) Count() (*big.Int, error) {
	return _Main.Contract.Count(&_Main.CallOpts)
}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Main *MainCallerSession) Count() (*big.Int, error) {
	return _Main.Contract.Count(&_Main.CallOpts)
}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Main *MainCaller) OutOfCountersKeccaks(opts *bind.CallOpts) ([32]byte, error) {
	var out []interface{}
	err := _Main.contract.Call(opts, &out, "outOfCountersKeccaks")

	if err != nil {
		return *new([32]byte), err
	}

	out0 := *abi.ConvertType(out[0], new([32]byte)).(*[32]byte)

	return out0, err

}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Main *MainSession) OutOfCountersKeccaks() ([32]byte, error) {
	return _Main.Contract.OutOfCountersKeccaks(&_Main.CallOpts)
}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Main *MainCallerSession) OutOfCountersKeccaks() ([32]byte, error) {
	return _Main.Contract.OutOfCountersKeccaks(&_Main.CallOpts)
}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Main *MainCaller) OutOfCountersSteps(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Main.contract.Call(opts, &out, "outOfCountersSteps")

	if err != nil {
		return err
	}

	return err

}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Main *MainSession) OutOfCountersSteps() error {
	return _Main.Contract.OutOfCountersSteps(&_Main.CallOpts)
}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Main *MainCallerSession) OutOfCountersSteps() error {
	return _Main.Contract.OutOfCountersSteps(&_Main.CallOpts)
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Main *MainTransactor) OutOfCountersPoseidon(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Main.contract.Transact(opts, "outOfCountersPoseidon")
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Main *MainSession) OutOfCountersPoseidon() (*types.Transaction, error) {
	return _Main.Contract.OutOfCountersPoseidon(&_Main.TransactOpts)
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Main *MainTransactorSession) OutOfCountersPoseidon() (*types.Transaction, error) {
	return _Main.Contract.OutOfCountersPoseidon(&_Main.TransactOpts)
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Main *MainTransactor) OutOfGas(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Main.contract.Transact(opts, "outOfGas")
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Main *MainSession) OutOfGas() (*types.Transaction, error) {
	return _Main.Contract.OutOfGas(&_Main.TransactOpts)
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Main *MainTransactorSession) OutOfGas() (*types.Transaction, error) {
	return _Main.Contract.OutOfGas(&_Main.TransactOpts)
}
