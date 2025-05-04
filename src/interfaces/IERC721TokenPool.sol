// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

interface IERC721TokenPool is IAny2EVMMessageReceiver {
    error Unauthorized(address sender);
    error ExceedsTransferLimit(uint256 requested, uint256 limit);
    error ZeroIdsNotAllowed();
    error PoolAlreadyAdded(uint64 chainSelector, address pool);
    error NFTDeliveryFailed(address holder, uint256 id);
    error MintFailed(uint256 id);
    error TokenNotERC721();

    event ExternalStorageUpdated(address indexed by, address indexed extStorage);
    event ChainConfigured(
        address indexed by,
        uint64 indexed chainSelector,
        RateLimiter.Config outboundConfig,
        RateLimiter.Config inboundConfig
    );
    event ChainDisabled(uint64 indexed chainSelector);
    event ChainEnabled(uint64 indexed chainSelector, address indexed pool);
    event RateLimitAdminSet(address indexed by, address rateLimitAdmin);
    event CrossChainReceived(
        address indexed from, address indexed to, uint256[] ids, uint64 srcChainSelector, uint64 dstChainSelector
    );
    event CrossChainSent(
        address indexed from, address indexed to, uint256[] ids, uint64 srcChainSelector, uint64 dstChainSelector
    );

    struct RemoteChainConfig {
        address _pool;
        uint32 _transferLimitPerRequest;
        RateLimiter.TokenBucket _outboundRateLimiterConfig;
        RateLimiter.TokenBucket _inboundRateLimiterConfig;
    }

    function initialize(
        address owned,
        address router,
        address token,
        uint64 currentChainSelector,
        uint64 fixedGas,
        uint64 dynamicGas
    ) external;

    function addRemotePool(uint64 remoteChainSelector, address pool) external;

    function setRateLimitAdmin(address rateLimitAdmin) external;

    function setExternalStorage(address extStorage) external;

    function setTransferLimitPerRequest(uint64 chainSelector, uint16 limit) external;

    // function crossChainTransfer(
    //     address to,
    //     uint256 tokenId,
    //     uint256 quantity,
    //     uint64 dstChainSelector,
    //     PayFeesIn payFeesIn
    // ) external payable returns (bytes32 messageId);
    // function enableChain(uint64 srcChainSelector, address pool, bytes calldata extraArgs) external;
    // function disableChain(uint64 srcChainSelector) external;
    // function getCCIPRouter() external view returns (address);
    // function getCurrentChainSelector() external view returns (uint64);
    // function getNFTAddress() external view returns (address);
    // function getRoninGateway() external view returns (address);
    // function getLinkToken() external view returns (address);
    // function getSourcePool(uint64 srcChainSelector) external view returns (address, bytes memory);
}
