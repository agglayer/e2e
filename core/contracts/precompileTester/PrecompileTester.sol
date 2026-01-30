// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Precompile probe harness.
 *
 * - Executes a fixed, deterministic set of calls to the given precompiles in the constructor.
 * - Uses low-level .call for every precompile and NEVER reverts; it logs per-case success/failure.
 * - Emits one standardized event per test case in deterministic order.
 * - outputHash = keccak256(returndata) when success == true, else bytes32(0).
 *
 * IMPORTANT:
 * - For complex precompiles (KZG, BLS12-381 family, P-256), placeholder inputs are included to ensure
 *   the call path is exercised and logged. Replace those with your real test vectors to validate correctness.
 * - The precompile order matches exactly the list provided in the prompt.
 */
contract PrecompileTester {
    event PrecompileTestResult(
        uint256 id,
        address precompile,
        bool success,
        bytes32 outputHash
    );

    // ---- Ordered precompile list (exact order preserved) ----
    address private constant PC_ECRECOVER = address(uint160(0x01));
    address private constant PC_SHA256 = address(uint160(0x02));
    address private constant PC_RIPEMD160 = address(uint160(0x03));
    address private constant PC_IDENTITY = address(uint160(0x04));
    address private constant PC_MODEXP = address(uint160(0x05));
    address private constant PC_BN256_ADD = address(uint160(0x06));
    address private constant PC_BN256_MUL = address(uint160(0x07));
    address private constant PC_BN256_PAIRING = address(uint160(0x08));
    address private constant PC_BLAKE2F = address(uint160(0x09));
    address private constant PC_KZG_POINT_EVAL = address(uint160(0x0a));
    address private constant PC_BLS12_G1_ADD = address(uint160(0x0b));
    address private constant PC_BLS12_G1_MULTIEXP = address(uint160(0x0c));
    address private constant PC_BLS12_G2_ADD = address(uint160(0x0d));
    address private constant PC_BLS12_G2_MULTIEXP = address(uint160(0x0e));
    address private constant PC_BLS12_PAIRING = address(uint160(0x0f));
    address private constant PC_BLS12_MAP_G1 = address(uint160(0x10));
    address private constant PC_BLS12_MAP_G2 = address(uint160(0x11));
    address private constant PC_P256_VERIFY = address(uint160(0x0100)); // 256

    constructor() {
        // We advance through precompiles in this exact sequence; IDs are deterministic.
        uint256 p = 0;

        // 1) ecrecover (0x01) — 128-byte input: h(32) | v(32) | r(32) | s(32).
        unchecked {
            ++p;
        }
        _callAndLog(
            _id(p, 1),
            PC_ECRECOVER,
            _encECRecover(
                bytes32(
                    uint256(
                        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
                    )
                ),
                27,
                bytes32(uint256(1)),
                bytes32(uint256(2))
            )
        );
        _callAndLog(
            _id(p, 2),
            PC_ECRECOVER,
            _encECRecover(
                bytes32(
                    uint256(
                        0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
                    )
                ),
                28,
                bytes32(uint256(3)),
                bytes32(uint256(4))
            )
        );

        // 2) sha256 (0x02) — returns SHA-256 digest of input.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_SHA256, bytes("abc"));
        _callAndLog(_id(p, 2), PC_SHA256, hex"");

        // 3) ripemd160 (0x03) — returns 20 bytes (we hash the return in logs).
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_RIPEMD160, bytes("abc"));

        // 4) identity / datacopy (0x04) — echoes the input.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_IDENTITY, hex"deadbeef");
        _callAndLog(_id(p, 2), PC_IDENTITY, hex"");

        // 5) bigModExp (0x05) — EIP-198-compatible encoding: 32|32|32 len headers + base|exp|mod.
        //    Using small, deterministic values to keep gas low.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_MODEXP, _encModExp(2, 5, 97)); // 2^5 mod 97 = 32
        _callAndLog(_id(p, 2), PC_MODEXP, _encModExp(1234567, 891011, 7919));

        // 6) bn256Add (0x06) — EIP-196, input = (x1,y1,x2,y2) each 32 bytes, values < p.
        //    Use the classic on-curve point (1,2) twice.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BN256_ADD, _encU256x4(1, 2, 1, 2));

        // 7) bn256ScalarMul (0x07) — input = (x,y,scalar).
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BN256_MUL, _encU256x3(1, 2, 3));

        // 8) bn256Pairing (0x08) — EIP-197.
        //    Empty input is a valid "0-pair" which evaluates to true on spec-compliant impls; cheap & deterministic.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BN256_PAIRING, hex"");

        // 9) blake2F (0x09) — EIP-152, 213 bytes input. We'll use 12 rounds, zero state/message, final=1.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLAKE2F, _blake2f_12rounds_zero_final1());

        // 10) KZG point evaluation (0x0a) — EIP-4844. Placeholder input.
        //     Replace with a real 192-byte vector (commitment/proof/eval) when available.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_KZG_POINT_EVAL, _kzgVector());

        // 11) BLS12-381 G1 add (0x0b) — Placeholder; replace with real EIP-2537 vector (compressed points).
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_G1_ADD, _zeros(256)); // likely 2*48 compressed

        // 12) BLS12-381 G1 multiexp (0x0c) — Placeholder; replace with real (point,scalar) pairs.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_G1_MULTIEXP, _zeros(160)); // variable-length; 0 to trigger deterministic fail/success

        // 13) BLS12-381 G2 add (0x0d) — Placeholder; replace with 2*96 compressed.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_G2_ADD, _zeros(512));

        // 14) BLS12-381 G2 multiexp (0x0e) — Placeholder.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_G2_MULTIEXP, _zeros(288));

        // 15) BLS12-381 pairing (0x0f) — Placeholder; replace with k*(48 + 96) bytes for k pairs (compressed).
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_PAIRING, _zeros(384));

        // 16) BLS12-381 map-to-G1 (0x10) — Placeholder; replace with proper field encoding.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_MAP_G1, _zeros(64)); // typical field size placeholder

        // 17) BLS12-381 map-to-G2 (0x11) — Placeholder.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_BLS12_MAP_G2, _zeros(128));

        // 18) P-256 verify (0x0100) — Placeholder signature tuple; replace with real (msg, pk, sig) encoding per your spec.
        unchecked {
            ++p;
        }
        _callAndLog(_id(p, 1), PC_P256_VERIFY, _zeros(128));
    }

    // ------------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------------

    function _id(
        uint256 precompileIndex,
        uint256 caseIndex
    ) private pure returns (uint256) {
        unchecked {
            return precompileIndex * 1000 + caseIndex;
        }
    }

    function _callAndLog(uint256 id, address pc, bytes memory input) private {
        // NOTE: requirement asked for .call; we keep it exactly that.
        (bool ok, bytes memory out) = pc.call(input);
        emit PrecompileTestResult(id, pc, ok, ok ? keccak256(out) : bytes32(0));
    }

    // --- ecrecover encoding: 128 bytes = h(32) | v(32) | r(32) | s(32) ---
    function _encECRecover(
        bytes32 h,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private pure returns (bytes memory) {
        // v is read from the lowest byte of a 32-byte word by the precompile.
        return bytes.concat(h, bytes32(uint256(v)), r, s);
    }

    // --- bigModExp (EIP-198): [lenB(32), lenE(32), lenM(32)] | base | exp | mod ---
    // For simplicity we always use 32-byte limbs.
    function _encModExp(
        uint256 base,
        uint256 exponent,
        uint256 modulus
    ) private pure returns (bytes memory) {
        return
            bytes.concat(
                bytes32(uint256(32)), // base length
                bytes32(uint256(32)), // exp length
                bytes32(uint256(32)), // mod length
                bytes32(base),
                bytes32(exponent),
                bytes32(modulus)
            );
    }

    // --- bn256 helpers: pack uint256s to 32-byte big-endian words in sequence ---
    function _encU256x4(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) private pure returns (bytes memory) {
        return bytes.concat(bytes32(a), bytes32(b), bytes32(c), bytes32(d));
    }

    function _encU256x3(
        uint256 a,
        uint256 b,
        uint256 c
    ) private pure returns (bytes memory) {
        return bytes.concat(bytes32(a), bytes32(b), bytes32(c));
    }

    // --- blake2F (EIP-152) 213-byte input builder: 12 rounds, zero state & message, final=1 ---
    function _blake2f_12rounds_zero_final1()
        private
        pure
        returns (bytes memory input)
    {
        input = new bytes(213);
        // rounds: BIG-endian uint32 => 12 == 0x00 0x00 0x00 0x0c
        input[0] = 0x00;
        input[1] = 0x00;
        input[2] = 0x00;
        input[3] = 0x0c;
        // h[0..7] 64-bit words (8*8 = 64 bytes) -> already zero
        // m[0..15] 64-bit words (16*8 = 128 bytes) -> already zero
        // t (offset) 16 bytes -> already zero
        // final block flag (1 byte) at the end:
        input[212] = 0x01;
    }

    // --- simple zero-filled buffer ---
    function _zeros(uint256 len) private pure returns (bytes memory b) {
        b = new bytes(len);
        // bytes are zero-initialized by default in Solidity, so nothing else to do
    }

    function _kzgVector() private pure returns (bytes memory) {
    return bytes.concat(
        // versionedHash (32 bytes)
        hex"013cb9810630b811b199f0e62870e6f5db2ace0b5645e436ad7092c3544fc30d",
        // point (32 bytes)
        hex"0000000000000000000000000000000000000000000000000000000000000005",
        // claim (32 bytes)
        hex"2d49f6b7e4749dbd3c95dc2674f80d988626b6d1c22bbd1ad56f9d6a3c306bb4",
        // commitment (48 bytes)
        hex"9869b5669003ce14283e97370073773f8f1d3821f0d27beaedfb310cacf08ccc84114065d20200475f7ee2606a777ea4",
        // proof (48 bytes)
        hex"8c9bd0478fc7e81c03dfa87160ede0188f7ae822aa4f93e684caeaa15cd1f1bbd22cf1275dabc37a78778f1dffd8647e"
    );
}
}
