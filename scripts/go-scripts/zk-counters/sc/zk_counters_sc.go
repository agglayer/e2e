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
	ABI: "[{\"inputs\":[],\"name\":\"count\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxArithmetics\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxBinaries\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxKeccakHashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxMemAligns\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxPoseidonHashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxPoseidonPaddings\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxSHA256Hashes\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"maxSteps\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"overflowGas\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"useMaxGasPossible\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
	Bin: "0x608060405234801561000f575f80fd5b506104688061001d5f395ff3fe608060405234801561000f575f80fd5b50600436106100a7575f3560e01c8063a7c19bb81161006f578063a7c19bb8146100f1578063a8a61c71146100fb578063d076c38914610105578063d15382671461010f578063e050f2bd14610119578063e7ff720214610123576100a7565b806306661abd146100ab578063138070c4146100c95780632f3bd8bf146100d35780639a077793146100dd5780639c94a61e146100e7575b5f80fd5b6100b361012d565b6040516100c09190610419565b60405180910390f35b6100d1610132565b005b6100db6101a1565b005b6100e56101ee565b005b6100ef61020b565b005b6100f9610238565b005b610103610312565b005b61010d610331565b005b61011761034e565b005b61012161039b565b005b61012b6103e3565b005b5f5481565b5f80819055506001617000526160006110005ff05b614e205a111561019e5761600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c61600061100080833c610147565b50565b5f80819055506120205f525b614ba45a11156101ec5760025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f05060025f80f0506101ad565b565b5f80819055505b6127105a1115610209575f543f5f556101f5565b565b5f80819055505f80526001610100525b60af5a11156102365760205f6101205f60025afa5f5261021b565b565b5f80819055507f2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d5f527f2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc2283086020527f19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a116040527f172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba7496060527f1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a236080525b61d6d85a111561031057602060a0805f600861c350fa60a0526102f2565b565b5f80819055505b61076c5a111561032f575f805f805f80a4610319565b565b5f80819055505b6127105a111561034c576104d25f52610338565b565b5f80819055505b60915a1115610399575a60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d60011d5f52610355565b565b5f80819055505b6101945a11156103e15760205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f5260205f205f526103a2565b565b5f80819055505b60c85a11156103ff575f805f805f80a46103ea565b565b5f819050919050565b61041381610401565b82525050565b5f60208201905061042c5f83018461040a565b9291505056fea26469706673582212205515c8621501e7448e7814910864face53e1b9169c1da9176fd4ab70777b966064736f6c63430008140033",
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

// MaxArithmetics is a paid mutator transaction binding the contract method 0xa7c19bb8.
//
// Solidity: function maxArithmetics() returns()
func (_Zkcounters *ZkcountersTransactor) MaxArithmetics(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxArithmetics")
}

// MaxArithmetics is a paid mutator transaction binding the contract method 0xa7c19bb8.
//
// Solidity: function maxArithmetics() returns()
func (_Zkcounters *ZkcountersSession) MaxArithmetics() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxArithmetics(&_Zkcounters.TransactOpts)
}

// MaxArithmetics is a paid mutator transaction binding the contract method 0xa7c19bb8.
//
// Solidity: function maxArithmetics() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxArithmetics() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxArithmetics(&_Zkcounters.TransactOpts)
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xd1538267.
//
// Solidity: function maxBinaries() returns()
func (_Zkcounters *ZkcountersTransactor) MaxBinaries(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxBinaries")
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xd1538267.
//
// Solidity: function maxBinaries() returns()
func (_Zkcounters *ZkcountersSession) MaxBinaries() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxBinaries(&_Zkcounters.TransactOpts)
}

// MaxBinaries is a paid mutator transaction binding the contract method 0xd1538267.
//
// Solidity: function maxBinaries() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxBinaries() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxBinaries(&_Zkcounters.TransactOpts)
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0xe050f2bd.
//
// Solidity: function maxKeccakHashes() returns()
func (_Zkcounters *ZkcountersTransactor) MaxKeccakHashes(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxKeccakHashes")
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0xe050f2bd.
//
// Solidity: function maxKeccakHashes() returns()
func (_Zkcounters *ZkcountersSession) MaxKeccakHashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxKeccakHashes(&_Zkcounters.TransactOpts)
}

// MaxKeccakHashes is a paid mutator transaction binding the contract method 0xe050f2bd.
//
// Solidity: function maxKeccakHashes() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxKeccakHashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxKeccakHashes(&_Zkcounters.TransactOpts)
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x138070c4.
//
// Solidity: function maxMemAligns() returns()
func (_Zkcounters *ZkcountersTransactor) MaxMemAligns(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxMemAligns")
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x138070c4.
//
// Solidity: function maxMemAligns() returns()
func (_Zkcounters *ZkcountersSession) MaxMemAligns() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxMemAligns(&_Zkcounters.TransactOpts)
}

// MaxMemAligns is a paid mutator transaction binding the contract method 0x138070c4.
//
// Solidity: function maxMemAligns() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxMemAligns() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxMemAligns(&_Zkcounters.TransactOpts)
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x9a077793.
//
// Solidity: function maxPoseidonHashes() returns()
func (_Zkcounters *ZkcountersTransactor) MaxPoseidonHashes(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxPoseidonHashes")
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x9a077793.
//
// Solidity: function maxPoseidonHashes() returns()
func (_Zkcounters *ZkcountersSession) MaxPoseidonHashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonHashes(&_Zkcounters.TransactOpts)
}

// MaxPoseidonHashes is a paid mutator transaction binding the contract method 0x9a077793.
//
// Solidity: function maxPoseidonHashes() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxPoseidonHashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonHashes(&_Zkcounters.TransactOpts)
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x2f3bd8bf.
//
// Solidity: function maxPoseidonPaddings() returns()
func (_Zkcounters *ZkcountersTransactor) MaxPoseidonPaddings(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxPoseidonPaddings")
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x2f3bd8bf.
//
// Solidity: function maxPoseidonPaddings() returns()
func (_Zkcounters *ZkcountersSession) MaxPoseidonPaddings() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonPaddings(&_Zkcounters.TransactOpts)
}

// MaxPoseidonPaddings is a paid mutator transaction binding the contract method 0x2f3bd8bf.
//
// Solidity: function maxPoseidonPaddings() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxPoseidonPaddings() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxPoseidonPaddings(&_Zkcounters.TransactOpts)
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x9c94a61e.
//
// Solidity: function maxSHA256Hashes() returns()
func (_Zkcounters *ZkcountersTransactor) MaxSHA256Hashes(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxSHA256Hashes")
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x9c94a61e.
//
// Solidity: function maxSHA256Hashes() returns()
func (_Zkcounters *ZkcountersSession) MaxSHA256Hashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSHA256Hashes(&_Zkcounters.TransactOpts)
}

// MaxSHA256Hashes is a paid mutator transaction binding the contract method 0x9c94a61e.
//
// Solidity: function maxSHA256Hashes() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxSHA256Hashes() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSHA256Hashes(&_Zkcounters.TransactOpts)
}

// MaxSteps is a paid mutator transaction binding the contract method 0xd076c389.
//
// Solidity: function maxSteps() returns()
func (_Zkcounters *ZkcountersTransactor) MaxSteps(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "maxSteps")
}

// MaxSteps is a paid mutator transaction binding the contract method 0xd076c389.
//
// Solidity: function maxSteps() returns()
func (_Zkcounters *ZkcountersSession) MaxSteps() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSteps(&_Zkcounters.TransactOpts)
}

// MaxSteps is a paid mutator transaction binding the contract method 0xd076c389.
//
// Solidity: function maxSteps() returns()
func (_Zkcounters *ZkcountersTransactorSession) MaxSteps() (*types.Transaction, error) {
	return _Zkcounters.Contract.MaxSteps(&_Zkcounters.TransactOpts)
}

// OverflowGas is a paid mutator transaction binding the contract method 0xe7ff7202.
//
// Solidity: function overflowGas() returns()
func (_Zkcounters *ZkcountersTransactor) OverflowGas(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "overflowGas")
}

// OverflowGas is a paid mutator transaction binding the contract method 0xe7ff7202.
//
// Solidity: function overflowGas() returns()
func (_Zkcounters *ZkcountersSession) OverflowGas() (*types.Transaction, error) {
	return _Zkcounters.Contract.OverflowGas(&_Zkcounters.TransactOpts)
}

// OverflowGas is a paid mutator transaction binding the contract method 0xe7ff7202.
//
// Solidity: function overflowGas() returns()
func (_Zkcounters *ZkcountersTransactorSession) OverflowGas() (*types.Transaction, error) {
	return _Zkcounters.Contract.OverflowGas(&_Zkcounters.TransactOpts)
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0xa8a61c71.
//
// Solidity: function useMaxGasPossible() returns()
func (_Zkcounters *ZkcountersTransactor) UseMaxGasPossible(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "useMaxGasPossible")
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0xa8a61c71.
//
// Solidity: function useMaxGasPossible() returns()
func (_Zkcounters *ZkcountersSession) UseMaxGasPossible() (*types.Transaction, error) {
	return _Zkcounters.Contract.UseMaxGasPossible(&_Zkcounters.TransactOpts)
}

// UseMaxGasPossible is a paid mutator transaction binding the contract method 0xa8a61c71.
//
// Solidity: function useMaxGasPossible() returns()
func (_Zkcounters *ZkcountersTransactorSession) UseMaxGasPossible() (*types.Transaction, error) {
	return _Zkcounters.Contract.UseMaxGasPossible(&_Zkcounters.TransactOpts)
}
