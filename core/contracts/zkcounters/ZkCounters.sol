// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

contract ZkCounters {
    uint256 public count;

    function overflowGas(uint256 pace) public {
        count = 0;
        assembly {
            for {} gt(gas(), pace) {} {
                log4(0, 0, 0, 0, 0 ,0)
            }
        }
    }

    function useMaxGasPossible(uint256 pace) public {
        count = 0;
        assembly {
            for {} gt(gas(), pace) {} {
                log4(0, 0, 0, 0, 0 ,0)
            }
        }
    }

    function maxKeccakHashes(uint256 pace) public {
        count = 0;
        assembly {
            // In this case we want to do lots of keccak in order to push the limits of that particular counter
            for {} gt(gas(), pace) {} {
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

    function maxPoseidonHashes(uint256 pace) public {
        count = 0;
        assembly {
            for {} gt(gas(), pace) {} {
                sstore(0, extcodehash(sload(0)))
            }
        }
    }

    function maxPoseidonPaddings(uint256 pace) public {
        count = 0;
        assembly {
            mstore(0x0,0x2020)
            for {} gt(gas(), pace) {} {
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

    function maxMemAligns(uint256 pace) public {
        count = 0;
        assembly {
            // put a 1 way out in memory
            mstore(0x7000,1)
            let bigContract := create(0, 0x1000, 0x6000)
            for {} gt(gas(), pace) {} {
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

    function maxArithmetics(uint256 pace) public {
        count = 0;
        assembly {
            mstore(0x00, 0x2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d)
            mstore(0x20, 0x2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc228308)
            mstore(0x40, 0x19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a11)
            mstore(0x60, 0x172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba749)
            mstore(0x80, 0x1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a23)
            for {} gt(gas(), pace) {} {
                mstore(0xa0, staticcall(50000, 0x08, 0, 0xa0, 0xa0, 0x20))
            }
        }
    }

    function maxBinaries(uint256 pace) public {
        count = 0;
        assembly {
            for {} gt(gas(), pace) {} {
                mstore(0x00, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1,gas()))))))))))))))))))
            }
        }
    }

    function maxSteps(uint256 pace) public {
        count = 0;
        assembly {
            for {} gt(gas(), pace) {} {
                mstore(0x0, 1234)
            }
        }
    }

    function maxSHA256Hashes(uint256 pace) public {
        count = 0;
        assembly {
            mstore(0x00, 0x00)
            mstore(0x100, 0x1)
            for {} gt(gas(), pace) {} {
                // accumulate
                mstore(0x00, staticcall(gas(), 0x02, 0, 0x120, 0x0, 0x20))
            }
        }
    }
}