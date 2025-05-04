// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC721Mintable} from "src/interfaces/ext/IERC721Mintable.sol";
import {IExtStorage} from "src/interfaces/IExtStorage.sol";
import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";
import {CCIPCrossChainSenderReceiver} from "src/extensions/CCIPCrossChainSenderReceiver.sol";

contract ERC721TokenPool is CCIPCrossChainSenderReceiver, Ownable2Step, IERC721TokenPool {
    using EnumerableSet for EnumerableSet.UintSet;
    using RateLimiter for RateLimiter.TokenBucket;

    error Unauthorized(address sender);
    error NonExistentChain(uint64 chainSelector);
    error ExceedsTransferLimit(uint256 requested, uint256 limit);
    error ZeroIdsNotAllowed();
    error PoolAlreadyAdded(uint64 chainSelector, address pool);
    error NFTDeliveryFailed(address holder, uint256 id);

    event ExternalStorageUpdated(address indexed by, address indexed extStorage);
    event RouterUpdated(address indexed by, address indexed oldRouter, address indexed newRouter);
    event ChainConfigured(
        address indexed by,
        uint64 indexed chainSelector,
        RateLimiter.Config outboundConfig,
        RateLimiter.Config inboundConfig
    );

    struct RemoteChainConfig {
        address _pool;
        uint32 _transferLimitPerRequest;
        bytes _extraArgs;
        RateLimiter.TokenBucket _outboundRateLimiterConfig;
        RateLimiter.TokenBucket _inboundRateLimiterConfig;
    }

    uint256[50] private __gap;

    IERC721Mintable internal s_token;
    IExtStorage internal s_extStorage;
    address internal s_rateLimitAdmin;
    uint32 internal s_transferLimitPerRequest;
    uint256 internal s_fixedGas;
    uint256 internal s_dynamicGas;

    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => RemoteChainConfig remoteChainConfig) internal s_remoteChainConfigs;

    modifier onlyOtherChain(uint64 remoteChainSelector) {
        _requireOtherChain(remoteChainSelector);
        _;
    }

    modifier onlyEnabledChain(uint64 remoteChainSelector) {
        _requireEnabledChain(remoteChainSelector);
        _;
    }

    modifier onlyEnabledSender(uint64 remoteChainSelector, address srcSender) {
        _requireEnabledSender(remoteChainSelector, srcSender);
        _;
    }

    constructor() Ownable(address(0xdead)) {
        _disableInitializers();
    }

    function initialize(address owned, address router, address token, uint64 currentChainSelector)
        external
        initializer
        nonZero(router)
        nonZero(token)
    {
        _transferOwnership(owned);
        __CCIPCrossChainSenderReceiver_init(router, currentChainSelector);
        s_token = IERC721Mintable(token);
    }

    function setExternalStorage(address extStorage) external onlyOwner {
        s_extStorage = IExtStorage(extStorage);
        emit ExternalStorageUpdated(msg.sender, extStorage);
    }

    function setRateLimitAdmin(address rateLimitAdmin) external onlyOwner {
        s_rateLimitAdmin = rateLimitAdmin;
        emit RateLimitAdminSet(msg.sender, rateLimitAdmin);
    }

    function isSupportedChain(uint64 remoteChainSelector) public view returns (bool) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    /// @notice Gets the rate limiter admin address.
    function getRateLimitAdmin() external view returns (address) {
        return s_rateLimitAdmin;
    }

    /// @notice Gets the token bucket with its values for the block it was requested at.
    /// @return The token bucket.
    function getCurrentOutboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory)
    {
        return s_remoteChainConfigs[remoteChainSelector]._outboundRateLimiterConfig._currentTokenBucketState();
    }

    /// @notice Gets the token bucket with its values for the block it was requested at.
    /// @return The token bucket.
    function getCurrentInboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory)
    {
        return s_remoteChainConfigs[remoteChainSelector]._inboundRateLimiterConfig._currentTokenBucketState();
    }

    /// @notice Sets the chain rate limiter config.
    /// @param remoteChainSelector The remote chain selector for which the rate limits apply.
    /// @param outboundConfig The new outbound rate limiter config, meaning the onRamp rate limits for the given chain.
    /// @param inboundConfig The new inbound rate limiter config, meaning the offRamp rate limits for the given chain.
    function setChainRateLimiterConfig(
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) external {
        if (msg.sender != s_rateLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);

        _setRateLimitConfig(remoteChainSelector, outboundConfig, inboundConfig);
    }

    function _setRateLimitConfig(
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) internal onlyEnabledChain(remoteChainSelector) {
        RateLimiter._validateTokenBucketConfig(outboundConfig, false);
        s_remoteChainConfigs[remoteChainSelector]._outboundRateLimiterConfig._setTokenBucketConfig(outboundConfig);

        RateLimiter._validateTokenBucketConfig(inboundConfig, false);
        s_remoteChainConfigs[remoteChainSelector]._inboundRateLimiterConfig._setTokenBucketConfig(inboundConfig);

        emit ChainConfigured(msg.sender, remoteChainSelector, outboundConfig, inboundConfig);
    }

    function setTransferLimitPerRequest(uint64 chainSelector, uint32 limit) external onlyOwner {
        if (chainSelector == s_currentChainSelector) {
            s_transferLimitPerRequest = limit;
        } else {
            _requireEnabledChain(chainSelector);
            s_remoteChainConfigs[chainSelector]._transferLimitPerRequest = limit;
        }
    }

    function addRemotePool(uint64 remoteChainSelector, address pool, bytes calldata extraArgs)
        external
        onlyOwner
        nonZero(pool)
        onlyOtherChain(remoteChainSelector)
    {
        if (s_remoteChainConfigs[remoteChainSelector]._pool != address(0)) {
            revert PoolAlreadyAdded(remoteChainSelector, s_remoteChainConfigs[remoteChainSelector]._pool);
        }
        s_remoteChainConfigs[remoteChainSelector]._pool = pool;
        s_remoteChainConfigs[remoteChainSelector]._extraArgs = extraArgs;
        s_remoteChainSelectors.add(remoteChainSelector);

        emit ChainEnabled(remoteChainSelector, pool, extraArgs);
    }

    function removeRemotePool(uint64 remoteChainSelector)
        external
        onlyOwner
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
    {
        delete s_remoteChainConfigs[remoteChainSelector];
        s_remoteChainSelectors.remove(remoteChainSelector);

        emit ChainDisabled(remoteChainSelector);
    }

    function crossBatchTransfer(address to, uint256[] calldata ids, uint64 remoteChainSelector, IERC20 feeToken)
        external
        nonZero(to)
        onlyEnabledChain(remoteChainSelector)
        returns (bytes32 messageId)
    {
        uint256 limit =
            Math.min(s_transferLimitPerRequest, s_remoteChainConfigs[remoteChainSelector]._transferLimitPerRequest);
        if (ids.length > limit) revert ExceedsTransferLimit(ids.length, limit);
        if (ids.length == 0) revert ZeroIdsNotAllowed();

        _lock({from: msg.sender, ids: ids});
        _requireDelivered(address(this), ids);
        _consumeOutboundRateLimit(remoteChainSelector, ids.length);

        messageId = _sendDataPayFeeToken({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteChainConfigs[remoteChainSelector]._pool,
            feeToken: feeToken,
            gasLimit: s_fixedGas + s_dynamicGas * ids.length,
            data: abi.encode(msg.sender, to, ids)
        });

        emit CrossChainSent(msg.sender, to, ids, s_currentChainSelector, remoteChainSelector);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        virtual
        override
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        (address from, address to, uint256[] memory ids) = abi.decode(message.data, (address, address, uint256[]));
        if (ids.length == 0) revert ZeroIdsNotAllowed();
        if (ids.length > s_transferLimitPerRequest) revert ExceedsTransferLimit(ids.length, s_transferLimitPerRequest);

        _releaseOrMint(to, ids);
        _requireDelivered(to, ids);
        _consumeInboundRateLimit(message.sourceChainSelector, ids.length);

        emit CrossChainReceived(from, to, ids, message.sourceChainSelector, s_currentChainSelector);
    }

    function isSupportedToken(address token) public view returns (bool yes) {
        return token == address(s_token);
    }

    function getToken() external view returns (IERC721 token) {
        return s_token;
    }

    function getExternalStorage() external view returns (IExtStorage extStorage) {
        return s_extStorage;
    }

    function getSourcePool(uint64 remoteChainSelector)
        external
        view
        returns (address poolAddr, bytes memory extraArgs)
    {
        return (s_remoteChainConfigs[remoteChainSelector]._pool, s_remoteChainConfigs[remoteChainSelector]._extraArgs);
    }

    /// @notice Consumes outbound rate limiting capacity in this pool
    function _consumeOutboundRateLimit(uint64 remoteChainSelector, uint256 amount) internal {
        s_remoteChainConfigs[remoteChainSelector]._outboundRateLimiterConfig._consume(amount, address(s_token));
    }

    /// @notice Consumes inbound rate limiting capacity in this pool
    function _consumeInboundRateLimit(uint64 remoteChainSelector, uint256 amount) internal {
        s_remoteChainConfigs[remoteChainSelector]._inboundRateLimiterConfig._consume(amount, address(s_token));
    }

    function _lock(address from, uint256[] calldata ids) internal {
        for (uint256 i; i < ids.length; ++i) {
            s_token.safeTransferFrom(from, address(this), ids[i]);
        }
    }

    function _releaseOrMint(address to, uint256[] memory ids) internal {
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];

            address owned = _tryGetOwnerOf(id);
            if (owned == address(this)) {
                // Transfer the token to the recipient
                s_token.safeTransferFrom(address(this), to, id);
            } else if (owned == address(s_extStorage)) {
                s_token.safeTransferFrom(address(s_extStorage), to, id);
            } else {
                if (address(s_extStorage) == address(0)) {
                    s_token.mint(to, id);
                } else {
                    s_extStorage.mintFor(address(s_token), to, id);
                }
            }
        }
    }

    function _requireDelivered(address holder, uint256[] memory ids) internal view {
        for (uint256 i; i < ids.length; ++i) {
            if (_tryGetOwnerOf(ids[i]) != holder) revert NFTDeliveryFailed(holder, ids[i]);
        }
    }

    function _tryGetOwnerOf(uint256 id) private view returns (address ownedBy) {
        try s_token.ownerOf(id) returns (address by) {
            ownedBy = by;
        } catch {
            // Handle the case where the token does not exist or is not an ERC721
            ownedBy = address(0);
        }
    }

    function _requireOtherChain(uint64 remoteChainSelector) internal view {
        if (remoteChainSelector == s_currentChainSelector) revert OnlyOtherChain(remoteChainSelector);
    }

    function _requireEnabledSender(uint64 remoteChainSelector, address srcSender) internal view {
        if (s_remoteChainConfigs[remoteChainSelector]._pool != srcSender) {
            revert SenderNotEnabled(remoteChainSelector, srcSender);
        }
    }

    function _requireEnabledChain(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
    }
}
