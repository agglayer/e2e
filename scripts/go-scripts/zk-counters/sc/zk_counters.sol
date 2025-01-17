// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract ZkCounters {
    uint256 public count = 0;

    // set gasLimit = 50000 & steps = 100
    function outOfGas() public {
        for (uint256 i = 0; i < 100; i++) {
            assembly {
                sstore(0x00, i)
            }
        }
    }

    // set gasLimit = 30000000 & steps = 50000
    function outOfCountersPoseidon() public {
        for (uint256 i = 0; i < 50000; i++) {
            assembly {
                sstore(0x00, i)
            }
        }
    }

    // gasLimit = 50000 & bytesKeccak = 1000000
    function outOfCountersKeccaks() pure public returns (bytes32 test) {
        assembly {
            test := keccak256(0, 1000000)
        }
        return test;
    }

    // set number and gas limit
    // gasLimit = 50000 & iterations = 100000
    function outOfCountersSteps() pure public {
        for (uint i = 0; i < 100000; i++) {
            assembly {
                mstore(0x0, 1234)
            }
        }
    }

    // maxGasUsed - NOTE: I CAN'T GO BEYOND 30M GAS
    // cast send --gas-price 1gwei --gas-limit 29999999 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000001
    function f0001() public {
        assembly {
                // The goal here is to see how much GAS we can consume. LOG4 seems to be expensive for GAS but cheap for counters?
            for {} gt(gas(), 15156) {} {
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
                log4(0, 0, 0, 0, 0 ,0)
            }
        }
    }

    // maxKeccakHashes
    // cast send --gas-price 2gwei --gas-limit 494719 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000002
    function f0002() view public {
        assembly {
            // In this case we want to do lots of keccak in order to push the limits of that particular counter
            for {} gt(gas(), 404) {} {
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
                mstore(0, keccak256(0, 32))
            }
        }
    }

    // maxPoseidonHashes
    // cast send --gas-price 2gwei --gas-limit 1488485 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000003
    function f0003() public {
        assembly {
            for {} gt(gas(), 2468) {} {
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
                sstore(0, extcodehash(sload(0)))
            }
        }
    }

    // maxPoseidonPaddings - NOTE: I CAN'T HIT THIS LIMIT.... yet
    // cast send --gas-price 2gwei --gas-limit 29999999 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000004
    function f0004() public {
        assembly {
            mstore(0x0,0x2020)
            for {} gt(gas(), 19364) {} {
                pop(create(0, 0x0, 0x2)) // this should require 54 bytes of padding (I think)
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
                pop(create(0, 0x0, 0x2))
            }
        }
    }

    // maxMemAligns
    // cast send --gas-price 2gwei --gas-limit 115644 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000005
    function f0005() public {
            assembly {
            // put a 1 way out in memory
            mstore(0x7000,1)
            let bigContract := create(0, 0x1000, 0x6000)
            for {} gt(gas(), 20000) {} {
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
                    extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
            }
        }
    }

    // maxArithmetics
    // cast send --gas-price 2gwei --gas-limit 3386851 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000006
    function f0006() view public {
            assembly {
            mstore(0x00, 0x2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d)
            mstore(0x20, 0x2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc228308)
            mstore(0x40, 0x19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a11)
            mstore(0x60, 0x172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba749)
            mstore(0x80, 0x1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a23)
            for {} gt(gas(), 55000) {} {
                    mstore(0xa0, staticcall(50000, 0x08, 0, 0xa0, 0xa0, 0x20))
            }
        }
    }

    // maxBinaries
    // cast send --gas-price 2gwei --gas-limit 1643884 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000007
    function f0007() view public {
            assembly {
            for {} gt(gas(), 145) {} {
                    mstore(0x00, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1,gas()))))))))))))))))))
            }
        }
    }

    // maxSteps
    // cast send --gas-price 2gwei --gas-limit 5345981 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000008
    function f0008() view public {
            assembly {
            let i := 0
            for {} gt(gas(),5) {} {
                    i := add(i,1)
            }
        }
    }

    // maxSHA256Hashes
    // cast send --gas-price 2gwei --gas-limit 498636 --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://127.0.0.1:33882 $(jq -r '.contractAddress' zkevm-counters.json) 0000000000000000000000000000000000000000000000000000000000000009
    function f0009() view public {
            assembly {
            mstore(0x00, 0x00)
            mstore(0x100, 0x1)
            for {} gt(gas(), 175) {} {
                    // accumulate
                    mstore(0x00, staticcall(gas(), 0x02, 0, 0x120, 0x0, 0x20))
            }
        }
    }
}