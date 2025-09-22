// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

contract Delegated {
    event DelegatedEvent(address indexed sender);

    function delegatedTest() external {
        emit DelegatedEvent(msg.sender);
    }
}
