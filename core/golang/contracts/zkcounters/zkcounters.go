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
	ABI: "[{\"inputs\":[],\"name\":\"count\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxArithmetics\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxBinaries\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxKeccakHashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxMemAligns\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxPoseidonHashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxPoseidonPaddings\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxSHA256Hashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"maxSteps\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"overflowGas\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"pace\",\"type\":\"uint256\"}],\"name\":\"useMaxGasPossible\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
	Bin: "0x608060405234801561000f575f80fd5b5061056e8061001d5f395ff3fe608060405234801561000f575f80fd5b50600436106100a7575f3560e01c80633be355131161006f5780633be3551314610139578063739cce1f146101555780638c3181bc146101715780639ab20bad1461018d578063a1511934146101a9578063e9480707146101c5576100a7565b806304749cc7146100ab57806306661abd146100c757806311b2f2eb146100e5578063138b0cfa146101015780631b5998b41461011d575b5f80fd5b6100c560048036038101906100c091906104e5565b6101e1565b005b6100cf61020e565b6040516100dc919061051f565b60405180910390f35b6100ff60048036038101906100fa91906104e5565b610213565b005b61011b600480360381019061011691906104e5565b61022f565b005b610137600480360381019061013291906104e5565b61027b565b005b610153600480360381019061014e91906104e5565b610354565b005b61016f600480360381019061016a91906104e5565b61039b565b005b61018b600480360381019061018691906104e5565b6103b9565b005b6101a760048036038101906101a291906104e5565b6103d7565b005b6101c360048036038101906101be91906104e5565b610445565b005b6101df60048036038101906101da91906104e5565b610492565b005b5f80819055505f80526001610100525b805a111561020b5760205f6101205f60025afa5f526101f1565b50565b5f5481565b5f80819055505b805a111561022c575f543f5f5561021a565b50565b5f80819055506120205f525b805a11156102785760025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f05061023b565b50565b5f80819055507f2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d5f527f2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc2283086020527f19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a116040527f172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba7496060527f1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a236080525b805a111561035157602060a0805f600861c350fa60a052610335565b50565b5f80819055505b805a11156103985760205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f5261035b565b50565b5f80819055505b805a11156103b6575f805f805f80a46103a2565b50565b5f80819055505b805a11156103d4575f805f805f80a46103c0565b50565b5f80819055506001617000526160006110005ff05b815a11156104415761600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c6103ec565b5050565b5f80819055505b805a111561048f575a60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d5f5261044c565b50565b5f80819055505b805a11156104ab576104d25f52610499565b50565b5f80fd5b5f819050919050565b6104c4816104b2565b81146104ce575f80fd5b50565b5f813590506104df816104bb565b92915050565b5f602082840312156104fa576104f96104ae565b5b5f610507848285016104d1565b91505092915050565b610519816104b2565b82525050565b5f6020820190506105325f830184610510565b9291505056fea2646970667358221220503f8e21dbbe46e46531807f72bf66b9585748f1d57f12908c0d0f8344bda85764736f6c63430008140033",
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

// MaxArithmetics is a paid mutator transaction binding the contract method 0x1b5998b4.
//
// Solidity: function maxArithmetics(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxArithmetics(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxArithmetics", pace)
}

// MaxArithmetics is a paid mutator transaction binding the contract method 0x1b5998b4.
//
// Solidity: function maxArithmetics(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxArithmetics(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxArithmetics(&_Zkcounters.TransactOpts, pace)
}

// MaxArithmetics is a paid mutator transaction binding the contract method 0x1b5998b4.
//
// Solidity: function maxArithmetics(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxArithmetics(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxArithmetics(&_Zkcounters.TransactOpts, pace)
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xa1511934.
//
// Solidity: function maxBinaries(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxBinaries(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxBinaries", pace)
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xa1511934.
//
// Solidity: function maxBinaries(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxBinaries(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxBinaries(&_Zkcounters.TransactOpts, pace)
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xa1511934.
//
// Solidity: function maxBinaries(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxBinaries(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxBinaries(&_Zkcounters.TransactOpts, pace)
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0x3be35513.
//
// Solidity: function maxKeccakHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxKeccakHashes(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxKeccakHashes", pace)
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0x3be35513.
//
// Solidity: function maxKeccakHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxKeccakHashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxKeccakHashes(&_Zkcounters.TransactOpts, pace)
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0x3be35513.
//
// Solidity: function maxKeccakHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxKeccakHashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxKeccakHashes(&_Zkcounters.TransactOpts, pace)
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x9ab20bad.
//
// Solidity: function maxMemAligns(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxMemAligns(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxMemAligns", pace)
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x9ab20bad.
//
// Solidity: function maxMemAligns(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxMemAligns(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxMemAligns(&_Zkcounters.TransactOpts, pace)
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x9ab20bad.
//
// Solidity: function maxMemAligns(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxMemAligns(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxMemAligns(&_Zkcounters.TransactOpts, pace)
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x11b2f2eb.
//
// Solidity: function maxPoseidonHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxPoseidonHashes(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxPoseidonHashes", pace)
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x11b2f2eb.
//
// Solidity: function maxPoseidonHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxPoseidonHashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonHashes(&_Zkcounters.TransactOpts, pace)
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x11b2f2eb.
//
// Solidity: function maxPoseidonHashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxPoseidonHashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonHashes(&_Zkcounters.TransactOpts, pace)
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x138b0cfa.
//
// Solidity: function maxPoseidonPaddings(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxPoseidonPaddings(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxPoseidonPaddings", pace)
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x138b0cfa.
//
// Solidity: function maxPoseidonPaddings(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxPoseidonPaddings(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonPaddings(&_Zkcounters.TransactOpts, pace)
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x138b0cfa.
//
// Solidity: function maxPoseidonPaddings(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxPoseidonPaddings(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonPaddings(&_Zkcounters.TransactOpts, pace)
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x04749cc7.
//
// Solidity: function maxSHA256Hashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxSHA256Hashes(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxSHA256Hashes", pace)
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x04749cc7.
//
// Solidity: function maxSHA256Hashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxSHA256Hashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSHA256Hashes(&_Zkcounters.TransactOpts, pace)
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x04749cc7.
//
// Solidity: function maxSHA256Hashes(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxSHA256Hashes(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSHA256Hashes(&_Zkcounters.TransactOpts, pace)
}

// MaxSteps is a paid mutator transaction binding the contract method 0xe9480707.
//
// Solidity: function maxSteps(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) MaxSteps(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxSteps", pace)
}

// MaxSteps is a paid mutator transaction binding the contract method 0xe9480707.
//
// Solidity: function maxSteps(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) MaxSteps(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSteps(&_Zkcounters.TransactOpts, pace)
}

// MaxSteps is a paid mutator transaction binding the contract method 0xe9480707.
//
// Solidity: function maxSteps(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxSteps(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSteps(&_Zkcounters.TransactOpts, pace)
}

// OverflowGas is a paid mutator transaction binding the contract method 0x739cce1f.
//
// Solidity: function overflowGas(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) OverflowGas(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "overflowGas", pace)
}

// OverflowGas is a paid mutator transaction binding the contract method 0x739cce1f.
//
// Solidity: function overflowGas(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) OverflowGas(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.OverflowGas(&_Zkcounters.TransactOpts, pace)
}

// OverflowGas is a paid mutator transaction binding the contract method 0x739cce1f.
//
// Solidity: function overflowGas(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) OverflowGas(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.OverflowGas(&_Zkcounters.TransactOpts, pace)
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0x8c3181bc.
//
// Solidity: function useMaxGasPossible(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactor) UseMaxGasPossible(opts *bind.TransactOpts, pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "useMaxGasPossible", pace)
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0x8c3181bc.
//
// Solidity: function useMaxGasPossible(uint256 pace) returns()
func (_Zkcounters *ZkcountersSession) UseMaxGasPossible(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.UseMaxGasPossible(&_Zkcounters.TransactOpts, pace)
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0x8c3181bc.
//
// Solidity: function useMaxGasPossible(uint256 pace) returns()
func (_Zkcounters *ZkcountersTransactorSession) UseMaxGasPossible(pace *big.Int) (*types.Transaction, error) {
	return _Zkcounters.Contract.UseMaxGasPossible(&_Zkcounters.TransactOpts, pace)
}
