// https://github.com/0xPolygonHermez/zkevm-rom/blob/main/docs/opcode-cost-zk-counters.md
{

        let action := calldataload(0)

        mstore(0, action)
        switch action

        // maxGasUsed - NOTE: I CAN'T GO BEYOND 30M GAS
        // cast send --gas-price 1gwei --gas-limit 29999999 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 1)
        case 0x0001 {
                // The goal here is to see how much GAS we can consume. LOG4 seems to be expensive for GAS but cheap for counters
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

        // maxKeccakHashes
        // cast send --gas-price 2gwei --gas-limit 476227 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 2)
        case 0x0002 {
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

        // maxPoseidonHashes
        // cast send --gas-price 2gwei --gas-limit 1386006 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 3)
        case 0x0003 {
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

        // maxPoseidonPaddings - NOTE: I CAN'T HIT THIS LIMIT.... yet
        // cast send --gas-price 2gwei --gas-limit 29999999 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 4)
        case 0x0004 {
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

        // maxMemAligns
        // cast send --gas-price 2gwei --gas-limit 96913 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 5)
        case 0x0005 {
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

        // maxArithmetics
        // cast send --gas-price 2gwei --gas-limit 1430649 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 6)
        case 0x0006 {
                mstore(0x00, 0x2850da2e46aa5dd9f61ffcd946950739259152db7c0da19f5dca5bc9ef9aab8d)
                mstore(0x20, 0x2f1aa883281df6c54504da443fed2bfd3d40d52403dfd8ca2ee32396bc228308)
                mstore(0x40, 0x19d1c096fea0c11845a724cfc1b8c136c9b02c5c5a15e5d47226e1ab7e0c7a11)
                mstore(0x60, 0x172ace8be0f28d72e4fd5a6acc400c1986815b492c611e850a922155431ba749)
                mstore(0x80, 0x1521ead02326d5115ff3fd009ddae7895d9cc538579dd89d334f446265c74a23)
                for {} gt(gas(), 55000) {} {
                        mstore(0xa0, staticcall(50000, 0x08, 0, 0xa0, 0xa0, 0x20))
                }
        }

        // maxBinaries
        // cast send --gas-price 2gwei --gas-limit 563779 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 7)
        case 0x0007 {
                for {} gt(gas(), 145) {} {
                        mstore(0x00, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1, sar(1,gas()))))))))))))))))))
                }
        }

        // maxSteps
        // cast send --gas-price 2gwei --gas-limit 1625164 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 8)
        case 0x0008 {
                let i := 0
                for {} gt(gas(),5) {} {
                        i := add(i,1)
                }
        }

        // maxSHA256Hashes
        // cast send --gas-price 2gwei --gas-limit 479069 --legacy --private-key $private_key --rpc-url $rpc_url 0x24C4Fac6751991a93eD237770a6725a99e540Ee0 $(cast abi-encode 'f(uint256)' 9)
        case 0x0009 {
                mstore(0x00, 0x00)
                mstore(0x100, 0x1)
                for {} gt(gas(), 175) {} {
                        // accumulate
                        mstore(0x00, staticcall(gas(), 0x02, 0, 0x120, 0x0, 0x20))
                }
        }

        default {
                mstore(0, 0x4641494c21)
                revert(0,0x20)
        }
}
