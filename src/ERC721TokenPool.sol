// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IERC721Mintable} from "src/interfaces/ext/IERC721Mintable.sol";
import {IExtStorage} from "src/interfaces/ext/IExtStorage.sol";
import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";
import {CCIPCrossChainSenderReceiver} from "src/extensions/CCIPCrossChainSenderReceiver.sol";

contract ERC721TokenPool is CCIPCrossChainSenderReceiver, Pausable, Ownable2Step, IERC721TokenPool {
    using EnumerableSet for EnumerableSet.UintSet;
    using RateLimiter for RateLimiter.TokenBucket;

    uint256[50] private __gap;

    IERC721Mintable internal s_token;
    IExtStorage internal s_extStorage;
    address internal s_rateLimitAdmin;
    uint64 internal s_fixedGas;
    uint64 internal s_dynamicGas;

    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => RemoteChainConfig remoteChainConfig) internal s_remoteChainConfigs;

    constructor() Ownable(address(0xdead)) {
        _disableInitializers();
    }

    function initialize(
        address owned,
        address router,
        address token,
        uint64 currentChainSelector,
        uint64 fixedGas,
        uint64 dynamicGas
    ) external initializer nonZero(router) nonZero(token) {
        _transferOwnership(owned);
        __CCIPCrossChainSenderReceiver_init(router, currentChainSelector);
        if (!ERC165Checker.supportsInterface(token, type(IERC721).interfaceId)) revert TokenNotERC721();

        s_token = IERC721Mintable(token);
        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;
    }

    function setExternalStorage(address extStorage) external onlyOwner {
        s_extStorage = IExtStorage(extStorage);
        emit ExternalStorageUpdated(msg.sender, extStorage);
    }

    function setRateLimitAdmin(address rateLimitAdmin) external onlyOwner {
        s_rateLimitAdmin = rateLimitAdmin;
        emit RateLimitAdminSet(msg.sender, rateLimitAdmin);
    }

    function setGasLimitConfig(uint64 fixedGas, uint64 dynamicGas) external onlyOwner {
        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;
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

    function setTransferLimitPerRequest(uint64 remoteChainSelector, uint16 limit)
        external
        onlyOwner
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
    {
        s_remoteChainConfigs[remoteChainSelector]._transferLimitPerRequest = limit;
    }

    function addRemotePool(uint64 remoteChainSelector, address pool)
        external
        onlyOwner
        nonZero(pool)
        onlyOtherChain(remoteChainSelector)
    {
        if (s_remoteChainConfigs[remoteChainSelector]._pool != address(0)) {
            revert PoolAlreadyAdded(remoteChainSelector, s_remoteChainConfigs[remoteChainSelector]._pool);
        }
        s_remoteChainConfigs[remoteChainSelector]._pool = pool;
        s_remoteChainSelectors.add(remoteChainSelector);

        emit ChainEnabled(remoteChainSelector, pool);
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
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (bytes32 messageId)
    {
        uint256 tokenCount = ids.length;
        uint256 limit = s_remoteChainConfigs[remoteChainSelector]._transferLimitPerRequest;
        if (tokenCount > limit) revert ExceedsTransferLimit(tokenCount, limit);

        if (tokenCount == 0) revert ZeroIdsNotAllowed();

        _lock({from: msg.sender, ids: ids});
        _requireDelivered(address(this), ids);
        _consumeOutboundRateLimit(remoteChainSelector, tokenCount);

        bytes memory data = abi.encode(msg.sender, to, ids);
        messageId = _sendDataPayFeeToken({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteChainConfigs[remoteChainSelector]._pool,
            feeToken: feeToken,
            gasLimit: s_fixedGas + s_dynamicGas * tokenCount,
            data: data
        });

        emit CrossChainSent(msg.sender, to, ids, s_currentChainSelector, remoteChainSelector);
    }

    function getFee(IERC20 feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee)
    {
        if (tokenCount == 0) revert ZeroIdsNotAllowed();
        uint256[] memory ids = new uint256[](tokenCount);

        (fee,) = _getSendDataFee({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteChainConfigs[remoteChainSelector]._pool,
            feeToken: feeToken,
            gasLimit: s_fixedGas + s_dynamicGas * tokenCount,
            data: abi.encode(address(0), address(0), ids)
        });
    }

    function isSupportedChain(uint64 remoteChainSelector) public view override returns (bool) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    function getGasLimitConfig() external view returns (uint256 fixedGas, uint256 dynamicGas) {
        return (s_fixedGas, s_dynamicGas);
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

    function isSupportedToken(address token) public view returns (bool yes) {
        return token == address(s_token);
    }

    function isSenderEnabled(uint64 remoteChainSelector, address srcSender)
        public
        view
        virtual
        override
        returns (bool yes)
    {
        return s_remoteChainConfigs[remoteChainSelector]._pool == srcSender;
    }

    function getToken() external view returns (IERC721 token) {
        return s_token;
    }

    function getExternalStorage() external view returns (IExtStorage extStorage) {
        return s_extStorage;
    }

    function getSourcePool(uint64 remoteChainSelector) external view returns (address poolAddr) {
        return (s_remoteChainConfigs[remoteChainSelector]._pool);
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

    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual override {
        (address from, address to, uint256[] memory ids) = abi.decode(message.data, (address, address, uint256[]));
        uint256 tokenCount = ids.length;
        if (tokenCount == 0) revert ZeroIdsNotAllowed();

        _releaseOrMint(to, ids);
        _requireDelivered(to, ids);
        _consumeInboundRateLimit(message.sourceChainSelector, tokenCount);

        emit CrossChainReceived(from, to, ids, message.sourceChainSelector, s_currentChainSelector);
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
            s_token.transferFrom(from, address(this), ids[i]);
        }
    }

    function _releaseOrMint(address to, uint256[] memory ids) internal {
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];

            address owned = _tryGetOwnerOf(id);
            if (owned == address(this)) {
                // Transfer the token to the recipient
                s_token.safeTransferFrom(address(this), to, id);
            } else if (owned != address(0) && owned == address(s_extStorage)) {
                s_token.safeTransferFrom(address(s_extStorage), to, id);
            } else {
                try s_token.mint(to, id) {}
                catch {
                    if (address(s_extStorage) == address(0)) revert MintFailed(id);
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
}
