// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

// forge build --root . --out out-json eip7823-modexp.sol && mv out-json/eip7823-modexp.sol/PreModExp.json . && rm -fr cache/ out-json/

contract PreModExp {
    // Original tiny test: base=0x08, exp=0x09, mod=0x0a (all 1-byte)
    function modexp_test_0() public returns (bytes32) {
        bytes32 result;
        assembly {
            let p := mload(0x40)

            // lengths (big-endian 32-byte integers)
            mstore(p, 1)            // baseLen
            mstore(add(p, 0x20), 1) // expLen
            mstore(add(p, 0x40), 1) // modLen

            // payload
            mstore8(add(p, 0x60), 0x08) // base
            mstore8(add(p, 0x61), 0x09) // exp
            mstore8(add(p, 0x62), 0x0a) // mod

            let inSize := add(0x60, 3)  // 96 + 3
            // call precompile 0x05
            let ok := call(gas(), 0x05, 0x00, p, inSize, p, 1)
            // ignore ok; EIP-198 returns empty on mod=0; here mod=0x0a so fine.
            result := mload(p) // first 32 bytes of output; here output is 1 byte padded
        }
        return result; // expected: 0x08...001
    }

    // ---- helpers ----------------------------------------------------------

    // Fill `len` bytes at `dst` with repeated 0x11 bytes (all ones in hex-nibble terms).
    function _fill_0x11(uint dst, uint len) private pure {
        assembly {
            // write word-by-word with 0x11 repeated (32 bytes)
            // 0x1111... repeated 32 times
            let word := 0x1111111111111111111111111111111111111111111111111111111111111111
            let end := add(dst, len)
            // write 32-byte chunks
            for { } lt(add(dst, 0x20), end) { dst := add(dst, 0x20) } {
                mstore(dst, word)
            }
            // tail bytes
            for { } lt(dst, end) { dst := add(dst, 1) } {
                mstore8(dst, 0x11)
            }
        }
    }

    // Core builder: sets lengths and writes base/exp/mod slices, then calls 0x05.
    // Returns first 32 bytes of the output.
    function _modexp_build_and_call(uint baseLen, uint expLen, uint modLen, bool baseIs11, bool expIs11, bool modIs11) private returns (bytes32) {
        bytes32 outFirst32;
        assembly {
            let p := mload(0x40)

            // header: 3 x 32-byte big-endian lengths
            mstore(p, baseLen)
            mstore(add(p, 0x20), expLen)
            mstore(add(p, 0x40), modLen)

            // compute pointers for base/exp/mod blobs
            let basePtr := add(p, 0x60)
            let expPtr  := add(basePtr, baseLen)
            let modPtr  := add(expPtr,  expLen)

            // initialize all to zero; we only need to zero the first/last words if we write exact bytes,
            // but writing exact bytes below makes it unnecessary to pre-zero.
            // fill base
            // we call back into Solidity helper via function selector, so do it inline instead:
        }
        // fill base/exp/mod from Solidity to keep the assembly tight
        if (baseIs11) {
            _fill_0x11(uint(unsafeMemoryPtr()) + 0x60, baseLen);
        } else {
            assembly { if gt(baseLen, 0) { mstore8(add(add(mload(0x40), 0x60), 0x00), 0x01) } }
        }

        if (expIs11) {
            assembly {
                let p := mload(0x40)
                let basePtr := add(p, 0x60)
                let expPtr := add(basePtr, baseLen)
                // fill
                // jump back to Solidity helper
            }
            _fill_0x11(uint(unsafeMemoryPtr()) + 0x60 + baseLen, expLen);
        } else {
            assembly {
                let p := mload(0x40)
                let basePtr := add(p, 0x60)
                let expPtr := add(basePtr, baseLen)
                if gt(expLen, 0) { mstore8(expPtr, 0x01) }
            }
        }

        if (modIs11) {
            assembly {
                let p := mload(0x40)
                let basePtr := add(p, 0x60)
                let expPtr := add(basePtr, baseLen)
                let modPtr := add(expPtr,  expLen)
                // fill
            }
            _fill_0x11(uint(unsafeMemoryPtr()) + 0x60 + baseLen + expLen, modLen);
        } else {
            assembly {
                let p := mload(0x40)
                let basePtr := add(p, 0x60)
                let expPtr := add(basePtr, baseLen)
                let modPtr := add(expPtr,  expLen)
                if gt(modLen, 0) { mstore8(modPtr, 0x01) }
            }
        }

        // call precompile
        assembly {
            let p := mload(0x40)
            let inSize := add(0x60, add(baseLen, add(expLen, modLen))) // 96 + sum
            let ok := call(gas(), 0x05, 0x00, p, inSize, p, modLen)
            if iszero(ok) {
                // Propagate revert data if any (precompile likely returns none on failure, but be correct)
                let rds := returndatasize()
                let rptr := mload(0x40)
                returndatacopy(rptr, 0, rds)
                revert(rptr, rds)
            }
            outFirst32 := mload(p) // first 32 bytes of output (or zero if modLen==0)
        }
        return outFirst32;
    }

    // unsafeMemoryPtr(): helper to read current free mem pointer for offset math in Solidity
    function unsafeMemoryPtr() private pure returns (uint ptr) {
        assembly { ptr := mload(0x40) }
    }

    // ---- tests ------------------------------------------------------------

    // Test 1: 1024-byte base of 0x11, exp=0x01, mod=0x01
    function modexp_test_1_base_1024() public returns (bytes32) {
        return _modexp_build_and_call(1024, 1, 1, true, false, false);
    }

    // Test 2: 1024-byte exponent of 0x11, base=0x01, mod=0x01
    function modexp_test_2_exp_1024() public returns (bytes32) {
        return _modexp_build_and_call(1, 1024, 1, false, true, false);
    }

    // Test 3: 1024-byte modulus of 0x11, base=0x01, exp=0x01
    function modexp_test_3_mod_1024() public returns (bytes32) {
        return _modexp_build_and_call(1, 1, 1024, false, false, true);
    }

    // Test 4: 1025-byte base of 0x11, exp=0x01, mod=0x01
    function modexp_test_4_base_1025() public returns (bytes32) {
        return _modexp_build_and_call(1025, 1, 1, true, false, false);
    }

    // Test 5: 1025-byte exponent of 0x11, base=0x01, mod=0x01
    function modexp_test_5_exp_1025() public returns (bytes32) {
        return _modexp_build_and_call(1, 1025, 1, false, true, false);
    }

    // Test 6: 1025-byte modulus of 0x11, base=0x01, exp=0x01
    function modexp_test_6_mod_1025() public returns (bytes32) {
        return _modexp_build_and_call(1, 1, 1025, false, false, true);
    }
}
