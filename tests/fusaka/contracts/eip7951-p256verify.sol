// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// forge build --root . --out out-json eip7951-p256verify.sol && mv out-json/eip7951-p256verify.sol/P256Harness.json . && rm -fr cache/ out-json/

contract P256Harness {
    // last==1 if the last verify succeeded, else 0
    bytes32 public last;

    function verify(bytes memory input160) external {
        require(input160.length == 160, "bad len");
        bool ok;
        bytes32 result;
        assembly {
            let outPtr := mload(0x40)
            result := 99
            ok := staticcall(gas(), 0x0100, add(input160, 0x20), 160, outPtr, 0x20)
            // per spec, success means 32-byte 0x...01 returned
            if ok {
                result := mload(outPtr)
            }
        }
        last = result;
    }
}
