// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.28;

/**
 * @title IBridge
 * @dev Interface for the bridge contract
 */
interface IBridge {
    function claimAsset(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;
}

/**
 * @title TestDoubleClaim
 * @dev Contract that provides functionality to claim assets from the bridge
 */
contract TestDoubleClaim {
    // Bridge contract interface
    IBridge public immutable bridge;

    // Events
    event AssetClaimed(
        uint256 indexed globalIndex,
        uint32 originNetwork,
        address originTokenAddress,
        address destinationAddress,
        uint256 amount
    );

    event ClaimFailed(
        uint256 indexed globalIndex,
        string reason
    );

    /**
     * @dev Constructor that sets the bridge contract address
     * @param _bridge Address of the deployed bridge contract
     */
    constructor(address _bridge) {
        require(_bridge != address(0), "Bridge address cannot be zero");
        bridge = IBridge(_bridge);
    }

    /**
     * @dev Normal claim function that takes individual parameters
     */
    function normalClaim(
        bytes32[32] calldata proofLocalExitRoot,
        bytes32[32] calldata proofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external {
        try bridge.claimAsset(
            proofLocalExitRoot,
            proofRollupExitRoot,
            globalIndex,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork,
            originTokenAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        ) {
            emit AssetClaimed(
                globalIndex,
                originNetwork,
                originTokenAddress,
                destinationAddress,
                amount
            );
        } catch Error(string memory reason) {
            // Catch revert with reason string
            emit ClaimFailed(globalIndex, reason);
        } catch (bytes memory) {
            // Catch low-level revert (e.g., out of gas, invalid opcode)
            emit ClaimFailed(globalIndex, "Low-level revert - possible gas limit or invalid data");
        }
    }

    function attemptTwoClaims(
        bytes32[32] calldata firstProofLocalExitRoot,
        bytes32[32] calldata firstProofRollupExitRoot,
        uint256 firstGlobalIndex,
        bytes32 firstMainnetExitRoot,
        bytes32 firstRollupExitRoot,
        uint32 firstOriginNetwork,
        address firstOriginTokenAddress,
        uint32 firstDestinationNetwork,
        address firstDestinationAddress,
        uint256 firstAmount,
        bytes calldata firstMetadata,
        bytes32[32] calldata secondProofLocalExitRoot,
        bytes32[32] calldata secondProofRollupExitRoot,
        uint256 secondGlobalIndex,
        bytes32 secondMainnetExitRoot,
        bytes32 secondRollupExitRoot,
        uint32 secondOriginNetwork,
        address secondOriginTokenAddress,
        uint32 secondDestinationNetwork,
        address secondDestinationAddress,
        uint256 secondAmount,
        bytes calldata secondMetadata
    ) external {
        // First claim attempt
        try bridge.claimAsset(
            firstProofLocalExitRoot,
            firstProofRollupExitRoot,
            firstGlobalIndex,
            firstMainnetExitRoot,
            firstRollupExitRoot,
            firstOriginNetwork,
            firstOriginTokenAddress,
            firstDestinationNetwork,
            firstDestinationAddress,
            firstAmount,
            firstMetadata
        ) {
            emit AssetClaimed(
                firstGlobalIndex,
                firstOriginNetwork,
                firstOriginTokenAddress,
                firstDestinationAddress,
                firstAmount
            );
        } catch Error(string memory reason) {
            // Catch revert with reason string
            emit ClaimFailed(firstGlobalIndex, reason);
        } catch (bytes memory) {
            // Catch low-level revert (e.g., out of gas, invalid opcode)
            emit ClaimFailed(firstGlobalIndex, "First claim: Low-level revert");
        }

        // Second claim attempt
        try bridge.claimAsset(
            secondProofLocalExitRoot,
            secondProofRollupExitRoot,
            secondGlobalIndex,
            secondMainnetExitRoot,
            secondRollupExitRoot,
            secondOriginNetwork,
            secondOriginTokenAddress,
            secondDestinationNetwork,
            secondDestinationAddress,
            secondAmount,
            secondMetadata
        ) {
            emit AssetClaimed(
                secondGlobalIndex,
                secondOriginNetwork,
                secondOriginTokenAddress,
                secondDestinationAddress,
                secondAmount
            );
        } catch Error(string memory reason) {
            // Catch revert with reason string
            emit ClaimFailed(secondGlobalIndex, reason);
        } catch (bytes memory) {
            // Catch low-level revert (e.g., out of gas, invalid opcode)
            emit ClaimFailed(secondGlobalIndex, "Second claim: Low-level revert");
        }
    }

    /**
     * @dev Debug function to test both claim methods with the same data
     */
    function debugCompareClaims(
        bytes32[32] calldata proofLocalExitRoot,
        bytes32[32] calldata proofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external {
        // Try normalClaim first
        try bridge.claimAsset(
            proofLocalExitRoot,
            proofRollupExitRoot,
            globalIndex,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork,
            originTokenAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        ) {
            emit AssetClaimed(
                globalIndex,
                originNetwork,
                originTokenAddress,
                destinationAddress,
                amount
            );
            emit ClaimFailed(globalIndex, "normalClaim succeeded");
        } catch Error(string memory reason) {
            emit ClaimFailed(globalIndex, string(abi.encodePacked("normalClaim failed: ", reason)));
        } catch (bytes memory) {
            emit ClaimFailed(globalIndex, "normalClaim failed: Low-level revert");
        }
        
        // Try the same claim again (simulating attemptTwoClaims behavior)
        try bridge.claimAsset(
            proofLocalExitRoot,
            proofRollupExitRoot,
            globalIndex,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork,
            originTokenAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        ) {
            emit AssetClaimed(
                globalIndex,
                originNetwork,
                originTokenAddress,
                destinationAddress,
                amount
            );
            emit ClaimFailed(globalIndex, "second attempt succeeded");
        } catch Error(string memory reason) {
            emit ClaimFailed(globalIndex, string(abi.encodePacked("second attempt failed: ", reason)));
        } catch (bytes memory) {
            emit ClaimFailed(globalIndex, "second attempt failed: Low-level revert");
        }
    }
} 