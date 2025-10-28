// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

interface IBasePolygonZkEVMGlobalExitRoot {
    /**
     * @dev Thrown when the caller is not the allowed contracts
     */
    error OnlyAllowedContracts();

    /**
     * @dev Thrown when the caller is not the coinbase neither the globalExitRootUpdater
     */
    error OnlyGlobalExitRootUpdater();

    /**
     * @dev Thrown when trying to call a function that only the pending GlobalExitRootUpdater can call.
     */
    error OnlyPendingGlobalExitRootUpdater();

    /**
     * @dev Thrown when the caller is not the globalExitRootRemover
     */
    error OnlyGlobalExitRootRemover();

    /**
     * @dev Thrown when trying to call a function that only the pending GlobalExitRootRemover can call.
     */
    error OnlyPendingGlobalExitRootRemover();

    /**
     * @dev Thrown when trying to insert a global exit root that is already set
     */
    error GlobalExitRootAlreadySet();

    /**
     * @dev Thrown when trying to remove a ger that doesn't exist
     */
    error GlobalExitRootNotFound();

    /**
     * @dev Thrown when trying to call a function with an input zero address
     */
    error InvalidZeroAddress();

    function updateExitRoot(bytes32 newRollupExitRoot) external;

    function globalExitRootMap(
        bytes32 globalExitRootNum
    ) external returns (uint256);
}

interface IPolygonZkEVMBridgeV2 {
    /**
     * @dev Thrown when the destination network is invalid
     */
    error DestinationNetworkInvalid();

    /**
     * @dev Thrown when the amount does not match msg.value
     */
    error AmountDoesNotMatchMsgValue();

    /**
     * @dev Thrown when user is bridging tokens and is also sending a value
     */
    error MsgValueNotZero();

    /**
     * @dev Thrown when the Ether transfer on claimAsset fails
     */
    error EtherTransferFailed();

    /**
     * @dev Thrown when the message transaction on claimMessage fails
     */
    error MessageFailed();

    /**
     * @dev Thrown when the global exit root does not exist
     */
    error GlobalExitRootInvalid();

    /**
     * @dev Thrown when the smt proof does not match
     */
    error InvalidSmtProof();

    /**
     * @dev Thrown when an index is already claimed
     */
    error AlreadyClaimed();

    /**
     * @dev Thrown when the owner of permit does not match the sender
     */
    error NotValidOwner();

    /**
     * @dev Thrown when the spender of the permit does not match this contract address
     */
    error NotValidSpender();

    /**
     * @dev Thrown when the amount of the permit does not match
     */
    error NotValidAmount();

    /**
     * @dev Thrown when the permit data contains an invalid signature
     */
    error NotValidSignature();

    /**
     * @dev Thrown when sender is not the rollup manager
     */
    error OnlyRollupManager();

    /**
     * @dev Thrown when the permit data contains an invalid signature
     */
    error NativeTokenIsEther();

    /**
     * @dev Thrown when the permit data contains an invalid signature
     */
    error NoValueInMessagesOnGasTokenNetworks();

    /**
     * @dev Thrown when the permit data contains an invalid signature
     */
    error GasTokenNetworkMustBeZeroOnEther();

    /**
     * @dev Thrown when the wrapped token proxy deployment fails
     */
    error FailedProxyDeployment();

    /**
     * @dev Thrown when try to set a zero address to a non valid zero address field
     */
    error InvalidZeroAddress();

    /**
     * @dev Thrown when sender is not the proxied tokens manager
     */
    error OnlyProxiedTokensManager();

    /**
     * @dev Thrown when trying to call a function that only the pending ProxiedTokensManager can call.
     */
    error OnlyPendingProxiedTokensManager();

    /**
     * @dev Thrown when trying to set bridgeAddress to as proxied tokens manager role.
     */
    error BridgeAddressNotAllowed();

    /**
     * @dev Thrown when trying to initialize the incorrect initialize function
     */
    error InvalidInitializeFunction();

    /**
     * @dev Thrown when failing to retrieve the owner from proxyAdmin
     */
    error InvalidProxyAdmin(address proxyAdmin);

    /**
     * @dev Thrown when the owner of a proxyAdmin is zero address
     */
    error InvalidZeroProxyAdminOwner(address proxyAdmin);

    function wrappedTokenToTokenInfo(
        address destinationAddress
    ) external view returns (uint32, address);

    function updateGlobalExitRoot() external;

    function activateEmergencyState() external;

    function deactivateEmergencyState() external;

    function bridgeAsset(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        address token,
        bool forceUpdateGlobalExitRoot,
        bytes calldata permitData
    ) external payable;

    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external payable;

    function bridgeMessageWETH(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amountWETH,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external;

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

    function claimMessage(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;

    function initialize(
        uint32 _networkID,
        address _gasTokenAddress,
        uint32 _gasTokenNetwork,
        IBasePolygonZkEVMGlobalExitRoot _globalExitRootManager,
        address _polygonRollupManager,
        bytes memory _gasTokenMetadata
    ) external;

    function getTokenMetadata(
        address token
    ) external view returns (bytes memory);

    function getWrappedTokenBridgeImplementation()
        external
        view
        returns (address);

    function getProxiedTokensManager() external view returns (address);
}

/**
 * @dev Define interface for PolygonZkEVM Bridge message receiver
 */
interface IInternalClaims {
    function onMessageReceived(
    ) external payable;
}

/**
 * @dev Define interface for PolygonZkEVM Bridge message receiver
 */
interface IBridgeMessageReceiver {
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes memory data
    ) external payable;
}
