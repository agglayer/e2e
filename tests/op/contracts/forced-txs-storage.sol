// SPDX-License-Identifier: MIT
// forge build forced-txs-storage.sol
// cp ../../../compiled-contracts/forced-txs-storage.sol/SimpleStorage.json .
pragma solidity ^0.8.0;

contract SimpleStorage {
    uint256 public value;

    constructor() {
        value = 43981;
    }

    // Fallback for any tx with data that doesn’t match a function selector
    fallback() external payable {
        // Expect msg.data to be 32 bytes, representing uint256
        if (msg.data.length == 32) {
            value = abi.decode(msg.data, (uint256));
        } else {
            value = 1337;
        }
    }

    function getValue() public view returns (uint256) {
        return value;
    }
}
