// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

contract Delegated {
    event DelegatedEvent(address indexed sender);

    function delegatedTest() external {
        (bool success, ) = address(0).call{value: 1 ether}("");
        require(success, "ETH burn failed");

        emit DelegatedEvent(msg.sender);
    }
}
