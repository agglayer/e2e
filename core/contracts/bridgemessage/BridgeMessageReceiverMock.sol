// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;
import "./Interfaces.sol";

contract BridgeMessageReceiverMock is IBridgeMessageReceiver {
    uint256 internal constant _DEPOSIT_CONTRACT_TREE_DEPTH = 32;

    event MessageReceived(address destinationAddress);
    event UpdateParameters();

    IPolygonZkEVMBridgeV2 public immutable bridgeAddress;
    bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] smtProofLocalExitRoot;
    bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] smtProofRollupExitRoot;
    uint256 globalIndex;
    bytes32 mainnetExitRoot;
    bytes32 rollupExitRoot;
    bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] smtProofLocalExitRoot1;
    bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] smtProofRollupExitRoot1;
    uint256 globalIndex1;
    bytes32 mainnetExitRoot1;
    bytes32 rollupExitRoot1;
    uint32 originNetwork;
    address originAddress;
    uint32 destinationNetwork;
    address destinationAddress;
    uint256 amount;
    bytes metadata;
    bytes data;

    constructor(IPolygonZkEVMBridgeV2 _bridgeAddress) {
        bridgeAddress = _bridgeAddress;
    }

    function updateParameters(
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata msmtProofLocalExitRoot,
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata msmtProofRollupExitRoot,
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata msmtProofLocalExitRoot1,
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata msmtProofRollupExitRoot1,
        uint256 mglobalIndex,
        bytes32 mmainnetExitRoot,
        bytes32 mrollupExitRoot,
        uint256 mglobalIndex1,
        bytes32 mmainnetExitRoot1,
        bytes32 mrollupExitRoot1,
        uint32 moriginNetwork,
        address moriginAddress,
        uint32 mdestinationNetwork,
        address mdestinationAddress,
        uint256 mamount,
        bytes calldata mmetadata
    ) public {
        smtProofLocalExitRoot = msmtProofLocalExitRoot;
        smtProofRollupExitRoot = msmtProofRollupExitRoot;
        smtProofLocalExitRoot1 = msmtProofLocalExitRoot1;
        smtProofRollupExitRoot1 = msmtProofRollupExitRoot1;
        globalIndex = mglobalIndex;
        mainnetExitRoot = mmainnetExitRoot;
        rollupExitRoot = mrollupExitRoot;
        globalIndex1 = mglobalIndex1;
        mainnetExitRoot1 = mmainnetExitRoot1;
        rollupExitRoot1 = mrollupExitRoot1;
        originNetwork = moriginNetwork;
        originAddress = moriginAddress;
        destinationNetwork = mdestinationNetwork;
        destinationAddress = mdestinationAddress;
        amount = mamount;
        metadata = mmetadata;

        emit UpdateParameters();
    }

    /// @inheritdoc IBridgeMessageReceiver
    function onMessageReceived(
        address originAddress1,
        uint32 originNetwork1,
        bytes memory data1
    ) external payable {
        data = data1;
        
        // First claim with first set of parameters
        bridgeAddress.claimMessage(
            smtProofLocalExitRoot,
            smtProofRollupExitRoot,
            globalIndex,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork1,
            originAddress1,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
        
        // Second claim with second set of parameters
        bridgeAddress.claimMessage(
            smtProofLocalExitRoot1,
            smtProofRollupExitRoot1,
            globalIndex1,
            mainnetExitRoot1,
            rollupExitRoot1,
            originNetwork1,
            originAddress1,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
    }
}
