// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package zkcounters

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

// ZkcountersMetaData contains all meta data concerning the Zkcounters contract.
var ZkcountersMetaData = &bind.MetaData{
	ABI: "[{\"inputs\":[],\"name\":\"count\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersSteps\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
	Bin: "0x60806040525f8055348015610012575f80fd5b5061016e806100205f395ff3fe608060405234801561000f575f80fd5b5060043610610034575f3560e01c806306661abd146100385780638bd7b53814610052575b5f80fd5b6100405f5481565b60405190815260200160405180910390f35b61005a61005c565b005b5f8080555b60055a111561007c578061007481610114565b915050610061565b60405162461bcd60e51b815260206004820152605f60248201527f6661696c656420746f20657865637574652074686520756e7369676e6564207460448201527f72616e73616374696f6e3a206d61696e20657865637574696f6e20657863656560648201527f64656420746865206d6178696d756d206e756d626572206f6620737465707300608482015260a40160405180910390fd5b5f6001820161013157634e487b7160e01b5f52601160045260245ffd5b506001019056fea26469706673582212209a1fa5d1fd47361e7034c96f8d4efbc199abbf304763ae10b7cb1ec4cf0b0a0764736f6c63430008140033",
}

// ZkcountersABI is the input ABI used to generate the binding from.
// Deprecated: Use ZkcountersMetaData.ABI instead.
var ZkcountersABI = ZkcountersMetaData.ABI

// ZkcountersBin is the compiled bytecode used for deploying new contracts.
// Deprecated: Use ZkcountersMetaData.Bin instead.
var ZkcountersBin = ZkcountersMetaData.Bin

// DeployZkcounters deploys a new Ethereum contract, binding an instance of Zkcounters to it.
func DeployZkcounters(auth *bind.TransactOpts, backend bind.ContractBackend) (common.Address, *types.Transaction, *Zkcounters, error) {
	parsed, err := ZkcountersMetaData.GetAbi()
	if err != nil {
		return common.Address{}, nil, nil, err
	}
	if parsed == nil {
		return common.Address{}, nil, nil, errors.New("GetABI returned nil")
	}

	address, tx, contract, err := bind.DeployContract(auth, *parsed, common.FromHex(ZkcountersBin), backend)
	if err != nil {
		return common.Address{}, nil, nil, err
	}
	return address, tx, &Zkcounters{ZkcountersCaller: ZkcountersCaller{contract: contract}, ZkcountersTransactor: ZkcountersTransactor{contract: contract}, ZkcountersFilterer: ZkcountersFilterer{contract: contract}}, nil
}

// Zkcounters is an auto generated Go binding around an Ethereum contract.
type Zkcounters struct {
	ZkcountersCaller     // Read-only binding to the contract
	ZkcountersTransactor // Write-only binding to the contract
	ZkcountersFilterer   // Log filterer for contract events
}

// ZkcountersCaller is an auto generated read-only Go binding around an Ethereum contract.
type ZkcountersCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// ZkcountersTransactor is an auto generated write-only Go binding around an Ethereum contract.
type ZkcountersTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// ZkcountersFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type ZkcountersFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// ZkcountersSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type ZkcountersSession struct {
	Contract     *Zkcounters       // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// ZkcountersCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type ZkcountersCallerSession struct {
	Contract *ZkcountersCaller // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts     // Call options to use throughout this session
}

// ZkcountersTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type ZkcountersTransactorSession struct {
	Contract     *ZkcountersTransactor // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts     // Transaction auth options to use throughout this session
}

// ZkcountersRaw is an auto generated low-level Go binding around an Ethereum contract.
type ZkcountersRaw struct {
	Contract *Zkcounters // Generic contract binding to access the raw methods on
}

// ZkcountersCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type ZkcountersCallerRaw struct {
	Contract *ZkcountersCaller // Generic read-only contract binding to access the raw methods on
}

// ZkcountersTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type ZkcountersTransactorRaw struct {
	Contract *ZkcountersTransactor // Generic write-only contract binding to access the raw methods on
}

// NewZkcounters creates a new instance of Zkcounters, bound to a specific deployed contract.
func NewZkcounters(address common.Address, backend bind.ContractBackend) (*Zkcounters, error) {
	contract, err := bindZkcounters(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &Zkcounters{ZkcountersCaller: ZkcountersCaller{contract: contract}, ZkcountersTransactor: ZkcountersTransactor{contract: contract}, ZkcountersFilterer: ZkcountersFilterer{contract: contract}}, nil
}

// NewZkcountersCaller creates a new read-only instance of Zkcounters, bound to a specific deployed contract.
func NewZkcountersCaller(address common.Address, caller bind.ContractCaller) (*ZkcountersCaller, error) {
	contract, err := bindZkcounters(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &ZkcountersCaller{contract: contract}, nil
}

// NewZkcountersTransactor creates a new write-only instance of Zkcounters, bound to a specific deployed contract.
func NewZkcountersTransactor(address common.Address, transactor bind.ContractTransactor) (*ZkcountersTransactor, error) {
	contract, err := bindZkcounters(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &ZkcountersTransactor{contract: contract}, nil
}

// NewZkcountersFilterer creates a new log filterer instance of Zkcounters, bound to a specific deployed contract.
func NewZkcountersFilterer(address common.Address, filterer bind.ContractFilterer) (*ZkcountersFilterer, error) {
	contract, err := bindZkcounters(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &ZkcountersFilterer{contract: contract}, nil
}

// bindZkcounters binds a generic wrapper to an already deployed contract.
func bindZkcounters(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := ZkcountersMetaData.GetAbi()
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, *parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Zkcounters *ZkcountersRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Zkcounters.Contract.ZkcountersCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Zkcounters *ZkcountersRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.Contract.ZkcountersTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Zkcounters *ZkcountersRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Zkcounters.Contract.ZkcountersTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Zkcounters *ZkcountersCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Zkcounters.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Zkcounters *ZkcountersTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Zkcounters *ZkcountersTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Zkcounters.Contract.contract.Transact(opts, method, params...)
}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Zkcounters *ZkcountersCaller) Count(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "count")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Zkcounters *ZkcountersSession) Count() (*big.Int, error) {
	return _Zkcounters.Contract.Count(&_Zkcounters.CallOpts)
}

// Count is a free data retrieval call binding the contract method 0x06661abd.
//
// Solidity: function count() view returns(uint256)
func (_Zkcounters *ZkcountersCallerSession) Count() (*big.Int, error) {
	return _Zkcounters.Contract.Count(&_Zkcounters.CallOpts)
}

// OutOfCountersSteps is a paid mutator transaction binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() returns()
func (_Zkcounters *ZkcountersTransactor) OutOfCountersSteps(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "outOfCountersSteps")
}

// OutOfCountersSteps is a paid mutator transaction binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() returns()
func (_Zkcounters *ZkcountersSession) OutOfCountersSteps() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfCountersSteps(&_Zkcounters.TransactOpts)
}

// OutOfCountersSteps is a paid mutator transaction binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() returns()
func (_Zkcounters *ZkcountersTransactorSession) OutOfCountersSteps() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfCountersSteps(&_Zkcounters.TransactOpts)
}
