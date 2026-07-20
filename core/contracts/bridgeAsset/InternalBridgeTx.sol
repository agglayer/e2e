// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;
import "./Interfaces.sol";

contract InternalBridgeTx {
    event MessageReceived(address destinationAddress);
    event BridgeTransactionExecuted(uint32 destinationNetwork, address destinationAddress, uint256 amount);
    event UpdateBridgeParameters();

    IPolygonZkEVMBridgeV2 public immutable bridgeAddress;

    // First bridge transaction parameters
    uint32 destinationNetwork1;
    address destinationAddress1;
    uint256 amount1;
    address token1;
    bool forceUpdateGlobalExitRoot1;
    bytes permitData1;

    // Second bridge transaction parameters
    uint32 destinationNetwork2;
    address destinationAddress2;
    uint256 amount2;
    address token2;
    bool forceUpdateGlobalExitRoot2;
    bytes permitData2;

    bytes data;

    constructor(IPolygonZkEVMBridgeV2 _bridgeAddress) {
        bridgeAddress = _bridgeAddress;
    }

    function updateBridgeParameters(
        // First bridge transaction parameters
        uint32 _destinationNetwork1,
        address _destinationAddress1,
        uint256 _amount1,
        address _token1,
        bool _forceUpdateGlobalExitRoot1,
        bytes calldata _permitData1,
        // Second bridge transaction parameters
        uint32 _destinationNetwork2,
        address _destinationAddress2,
        uint256 _amount2,
        address _token2,
        bool _forceUpdateGlobalExitRoot2,
        bytes calldata _permitData2
    ) public {
        // Set first bridge transaction parameters
        destinationNetwork1 = _destinationNetwork1;
        destinationAddress1 = _destinationAddress1;
        amount1 = _amount1;
        token1 = _token1;
        forceUpdateGlobalExitRoot1 = _forceUpdateGlobalExitRoot1;
        permitData1 = _permitData1;

        // Set second bridge transaction parameters
        destinationNetwork2 = _destinationNetwork2;
        destinationAddress2 = _destinationAddress2;
        amount2 = _amount2;
        token2 = _token2;
        forceUpdateGlobalExitRoot2 = _forceUpdateGlobalExitRoot2;
        permitData2 = _permitData2;

        emit UpdateBridgeParameters();
    }

    function onMessageReceived(
        bytes memory data1
    ) external payable {
        data = data1;

        // First bridge transaction
        try bridgeAddress.bridgeAsset{value: amount1}(
            destinationNetwork1,
            destinationAddress1,
            amount1,
            token1,
            forceUpdateGlobalExitRoot1,
            permitData1
        ) {
            emit BridgeTransactionExecuted(destinationNetwork1, destinationAddress1, amount1);
        } catch {
            // First bridge transaction failed, continue with second transaction
        }

        // Second bridge transaction
        try bridgeAddress.bridgeAsset{value: amount2}(
            destinationNetwork2,
            destinationAddress2,
            amount2,
            token2,
            forceUpdateGlobalExitRoot2,
            permitData2
        ) {
            emit BridgeTransactionExecuted(destinationNetwork2, destinationAddress2, amount2);
        } catch {
            // Second bridge transaction failed, transaction continues
        }

        emit MessageReceived(msg.sender);
    }

    // Function to receive ETH
    receive() external payable {}

    // Fallback function
    fallback() external payable {}
}
