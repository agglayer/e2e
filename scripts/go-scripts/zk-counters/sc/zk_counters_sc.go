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
	ABI: "[{\"inputs\":[],\"name\":\"count\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0001\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0002\",\"outputs\":[],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0003\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0004\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0005\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0006\",\"outputs\":[],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0007\",\"outputs\":[],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0008\",\"outputs\":[],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"f0009\",\"outputs\":[],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersKeccaks\",\"outputs\":[{\"internalType\":\"bytes32\",\"name\":\"test\",\"type\":\"bytes32\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersPoseidon\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfCountersSteps\",\"outputs\":[],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"outOfGas\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
	Bin: "0x60806040525f8055348015610012575f80fd5b5061048a806100205f395ff3fe608060405234801561000f575f80fd5b50600436106100e5575f3560e01c80634d15140e11610088578063c386184611610063578063c386184614610150578063c9dc3f5d14610158578063cb4e8cd114610160578063ceab8ada14610168575f80fd5b80634d15140e146101385780638bd7b53814610140578063a526fba914610148575f80fd5b806323f9ec13116100c357806323f9ec13146101155780632402eb191461011d5780632621002a1461012557806331fe52e814610130575f80fd5b806306661abd146100e95780630ee8394c1461010357806318891e8b1461010d575b5f80fd5b6100f15f5481565b60405190815260200160405180910390f35b61010b610170565b005b61010b61019a565b61010b610271565b61010b6102aa565b620f42405f206100f1565b61010b6102d3565b61010b6102f4565b61010b61032f565b61010b610353565b61010b610366565b61010b6103a7565b61010b6103f1565b61010b610413565b60016170005261600061100081815ff05b614e205a111561019557828283833c610181565b505050565b5f7f2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d815260207f2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc22830881527f19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a116040527f172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba7496060527f1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a236080525b61d6d85a111561026d5760a081818285600861c350fa9052610250565b5050565b5b60915a11156102a8575a600190811d811d811d811d811d811d811d811d811d811d811d811d811d811d811d811d901d5f52610272565b565b5f8081526001610100525b60af5a11156102d0576020816101208360025afa81526102b5565b50565b5f5b60648110156102d057805f5580806102ec90610430565b9150506102d5565b5b6101945a11156102a85760205f818120815281812081528181208152818120815281812081528181208152818120815290812090526102f5565b5f5b620186a08110156102d0576104d25f528061034b81610430565b915050610331565b5f5b60055a11156102d057600101610355565b5f61202081525b614ba45a11156102d0576002808283f050808283f050808283f050808283f050808283f050808283f050808283f050808283f0505061036d565b5b613b345a11156102a8575f808182838485a4808182838485a4808182838485a4808182838485a4808182838485a4808182838485a4808182838485a4808182838485a4506103a8565b5f5b61c3508110156102d057805f55808061040b90610430565b9150506103f3565b5b6109a45a11156102a8575f80543f3f3f3f3f3f3f3f9055610414565b5f6001820161044d57634e487b7160e01b5f52601160045260245ffd5b506001019056fea26469706673582212200cdc359059a8464fb57f4f47bca6bcdb601d0f8d341d9d5f003e6a1afb814eed64736f6c63430008140033",
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

// F0002 is a free data retrieval call binding the contract method 0x4d15140e.
//
// Solidity: function f0002() view returns()
func (_Zkcounters *ZkcountersCaller) F0002(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "f0002")

	if err != nil {
		return err
	}

	return err

}

// F0002 is a free data retrieval call binding the contract method 0x4d15140e.
//
// Solidity: function f0002() view returns()
func (_Zkcounters *ZkcountersSession) F0002() error {
	return _Zkcounters.Contract.F0002(&_Zkcounters.CallOpts)
}

// F0002 is a free data retrieval call binding the contract method 0x4d15140e.
//
// Solidity: function f0002() view returns()
func (_Zkcounters *ZkcountersCallerSession) F0002() error {
	return _Zkcounters.Contract.F0002(&_Zkcounters.CallOpts)
}

// F0006 is a free data retrieval call binding the contract method 0x18891e8b.
//
// Solidity: function f0006() view returns()
func (_Zkcounters *ZkcountersCaller) F0006(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "f0006")

	if err != nil {
		return err
	}

	return err

}

// F0006 is a free data retrieval call binding the contract method 0x18891e8b.
//
// Solidity: function f0006() view returns()
func (_Zkcounters *ZkcountersSession) F0006() error {
	return _Zkcounters.Contract.F0006(&_Zkcounters.CallOpts)
}

// F0006 is a free data retrieval call binding the contract method 0x18891e8b.
//
// Solidity: function f0006() view returns()
func (_Zkcounters *ZkcountersCallerSession) F0006() error {
	return _Zkcounters.Contract.F0006(&_Zkcounters.CallOpts)
}

// F0007 is a free data retrieval call binding the contract method 0x23f9ec13.
//
// Solidity: function f0007() view returns()
func (_Zkcounters *ZkcountersCaller) F0007(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "f0007")

	if err != nil {
		return err
	}

	return err

}

// F0007 is a free data retrieval call binding the contract method 0x23f9ec13.
//
// Solidity: function f0007() view returns()
func (_Zkcounters *ZkcountersSession) F0007() error {
	return _Zkcounters.Contract.F0007(&_Zkcounters.CallOpts)
}

// F0007 is a free data retrieval call binding the contract method 0x23f9ec13.
//
// Solidity: function f0007() view returns()
func (_Zkcounters *ZkcountersCallerSession) F0007() error {
	return _Zkcounters.Contract.F0007(&_Zkcounters.CallOpts)
}

// F0008 is a free data retrieval call binding the contract method 0xa526fba9.
//
// Solidity: function f0008() view returns()
func (_Zkcounters *ZkcountersCaller) F0008(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "f0008")

	if err != nil {
		return err
	}

	return err

}

// F0008 is a free data retrieval call binding the contract method 0xa526fba9.
//
// Solidity: function f0008() view returns()
func (_Zkcounters *ZkcountersSession) F0008() error {
	return _Zkcounters.Contract.F0008(&_Zkcounters.CallOpts)
}

// F0008 is a free data retrieval call binding the contract method 0xa526fba9.
//
// Solidity: function f0008() view returns()
func (_Zkcounters *ZkcountersCallerSession) F0008() error {
	return _Zkcounters.Contract.F0008(&_Zkcounters.CallOpts)
}

// F0009 is a free data retrieval call binding the contract method 0x2402eb19.
//
// Solidity: function f0009() view returns()
func (_Zkcounters *ZkcountersCaller) F0009(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "f0009")

	if err != nil {
		return err
	}

	return err

}

// F0009 is a free data retrieval call binding the contract method 0x2402eb19.
//
// Solidity: function f0009() view returns()
func (_Zkcounters *ZkcountersSession) F0009() error {
	return _Zkcounters.Contract.F0009(&_Zkcounters.CallOpts)
}

// F0009 is a free data retrieval call binding the contract method 0x2402eb19.
//
// Solidity: function f0009() view returns()
func (_Zkcounters *ZkcountersCallerSession) F0009() error {
	return _Zkcounters.Contract.F0009(&_Zkcounters.CallOpts)
}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Zkcounters *ZkcountersCaller) OutOfCountersKeccaks(opts *bind.CallOpts) ([32]byte, error) {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "outOfCountersKeccaks")

	if err != nil {
		return *new([32]byte), err
	}

	out0 := *abi.ConvertType(out[0], new([32]byte)).(*[32]byte)

	return out0, err

}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Zkcounters *ZkcountersSession) OutOfCountersKeccaks() ([32]byte, error) {
	return _Zkcounters.Contract.OutOfCountersKeccaks(&_Zkcounters.CallOpts)
}

// OutOfCountersKeccaks is a free data retrieval call binding the contract method 0x2621002a.
//
// Solidity: function outOfCountersKeccaks() pure returns(bytes32 test)
func (_Zkcounters *ZkcountersCallerSession) OutOfCountersKeccaks() ([32]byte, error) {
	return _Zkcounters.Contract.OutOfCountersKeccaks(&_Zkcounters.CallOpts)
}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Zkcounters *ZkcountersCaller) OutOfCountersSteps(opts *bind.CallOpts) error {
	var out []interface{}
	err := _Zkcounters.contract.Call(opts, &out, "outOfCountersSteps")

	if err != nil {
		return err
	}

	return err

}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Zkcounters *ZkcountersSession) OutOfCountersSteps() error {
	return _Zkcounters.Contract.OutOfCountersSteps(&_Zkcounters.CallOpts)
}

// OutOfCountersSteps is a free data retrieval call binding the contract method 0x8bd7b538.
//
// Solidity: function outOfCountersSteps() pure returns()
func (_Zkcounters *ZkcountersCallerSession) OutOfCountersSteps() error {
	return _Zkcounters.Contract.OutOfCountersSteps(&_Zkcounters.CallOpts)
}

// F0001 is a paid mutator transaction binding the contract method 0xc9dc3f5d.
//
// Solidity: function f0001() returns()
func (_Zkcounters *ZkcountersTransactor) F0001(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "f0001")
}

// F0001 is a paid mutator transaction binding the contract method 0xc9dc3f5d.
//
// Solidity: function f0001() returns()
func (_Zkcounters *ZkcountersSession) F0001() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0001(&_Zkcounters.TransactOpts)
}

// F0001 is a paid mutator transaction binding the contract method 0xc9dc3f5d.
//
// Solidity: function f0001() returns()
func (_Zkcounters *ZkcountersTransactorSession) F0001() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0001(&_Zkcounters.TransactOpts)
}

// F0003 is a paid mutator transaction binding the contract method 0xceab8ada.
//
// Solidity: function f0003() returns()
func (_Zkcounters *ZkcountersTransactor) F0003(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "f0003")
}

// F0003 is a paid mutator transaction binding the contract method 0xceab8ada.
//
// Solidity: function f0003() returns()
func (_Zkcounters *ZkcountersSession) F0003() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0003(&_Zkcounters.TransactOpts)
}

// F0003 is a paid mutator transaction binding the contract method 0xceab8ada.
//
// Solidity: function f0003() returns()
func (_Zkcounters *ZkcountersTransactorSession) F0003() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0003(&_Zkcounters.TransactOpts)
}

// F0004 is a paid mutator transaction binding the contract method 0xc3861846.
//
// Solidity: function f0004() returns()
func (_Zkcounters *ZkcountersTransactor) F0004(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "f0004")
}

// F0004 is a paid mutator transaction binding the contract method 0xc3861846.
//
// Solidity: function f0004() returns()
func (_Zkcounters *ZkcountersSession) F0004() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0004(&_Zkcounters.TransactOpts)
}

// F0004 is a paid mutator transaction binding the contract method 0xc3861846.
//
// Solidity: function f0004() returns()
func (_Zkcounters *ZkcountersTransactorSession) F0004() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0004(&_Zkcounters.TransactOpts)
}

// F0005 is a paid mutator transaction binding the contract method 0x0ee8394c.
//
// Solidity: function f0005() returns()
func (_Zkcounters *ZkcountersTransactor) F0005(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "f0005")
}

// F0005 is a paid mutator transaction binding the contract method 0x0ee8394c.
//
// Solidity: function f0005() returns()
func (_Zkcounters *ZkcountersSession) F0005() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0005(&_Zkcounters.TransactOpts)
}

// F0005 is a paid mutator transaction binding the contract method 0x0ee8394c.
//
// Solidity: function f0005() returns()
func (_Zkcounters *ZkcountersTransactorSession) F0005() (*types.Transaction, error) {
	return _Zkcounters.Contract.F0005(&_Zkcounters.TransactOpts)
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Zkcounters *ZkcountersTransactor) OutOfCountersPoseidon(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "outOfCountersPoseidon")
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Zkcounters *ZkcountersSession) OutOfCountersPoseidon() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfCountersPoseidon(&_Zkcounters.TransactOpts)
}

// OutOfCountersPoseidon is a paid mutator transaction binding the contract method 0xcb4e8cd1.
//
// Solidity: function outOfCountersPoseidon() returns()
func (_Zkcounters *ZkcountersTransactorSession) OutOfCountersPoseidon() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfCountersPoseidon(&_Zkcounters.TransactOpts)
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Zkcounters *ZkcountersTransactor) OutOfGas(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Zkcounters.contract.Transact(opts, "outOfGas")
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Zkcounters *ZkcountersSession) OutOfGas() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfGas(&_Zkcounters.TransactOpts)
}

// OutOfGas is a paid mutator transaction binding the contract method 0x31fe52e8.
//
// Solidity: function outOfGas() returns()
func (_Zkcounters *ZkcountersTransactorSession) OutOfGas() (*types.Transaction, error) {
	return _Zkcounters.Contract.OutOfGas(&_Zkcounters.TransactOpts)
}
