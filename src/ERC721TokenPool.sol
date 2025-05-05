// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IERC721Mintable} from "src/interfaces/external/IERC721Mintable.sol";
import {IExtStorage} from "src/interfaces/external/IExtStorage.sol";
import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";
import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";

contract ERC721TokenPool is
    CCIPSenderReceiverUpgradeable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    IERC721TokenPool
{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using RateLimiter for RateLimiter.TokenBucket;

    uint256[50] private __gap;

    IERC721Mintable internal s_token;
    address internal s_rateLimitAdmin;
    uint64 internal s_fixedGas;
    uint64 internal s_dynamicGas;

    EnumerableSet.AddressSet internal s_extStorages;
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => RemoteChainConfig remoteChainConfig) internal s_remoteChainConfigs;

    modifier validLength(uint256[] calldata ids) {
        _requireValidLength(ids);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owned,
        address router,
        address rmnProxy,
        address token,
        uint64 currentChainSelector,
        uint64 fixedGas,
        uint64 dynamicGas
    ) external initializer nonZero(router) nonZero(token) {
        _transferOwnership(owned);
        __CCIPSenderReceiverUpgradeable_init(router, rmnProxy, currentChainSelector);

        if (!ERC165Checker.supportsInterface(token, type(IERC721).interfaceId)) revert TokenNotERC721();
        s_token = IERC721Mintable(token);

        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function setExternalStorage(address extStorage, bool shouldAdd) external nonZero(extStorage) onlyOwner {
        if (shouldAdd) {
            if (s_extStorages.contains(extStorage)) revert ExtStorageAlreadyAdded(extStorage);
            s_extStorages.add(extStorage);
        } else {
            if (!s_extStorages.contains(extStorage)) revert ExtStorageNotAdded(extStorage);
            s_extStorages.remove(extStorage);
        }

        emit ExternalStorageUpdated(msg.sender, extStorage, shouldAdd);
    }

    function setRateLimitAdmin(address rateLimitAdmin) external onlyOwner {
        s_rateLimitAdmin = rateLimitAdmin;
        emit RateLimitAdminSet(msg.sender, rateLimitAdmin);
    }

    function setGasLimitConfig(uint64 fixedGas, uint64 dynamicGas) external onlyOwner {
        _setGasLimitConfig(fixedGas, dynamicGas);
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
        validLength(ids)
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (bytes32 messageId)
    {
        _lock({from: msg.sender, ids: ids});
        _requireDelivered(address(this), ids);
        _consumeOutboundRateLimit(remoteChainSelector, ids.length);

        bytes memory data = abi.encode(msg.sender, to, ids);
        messageId = _sendDataPayFeeToken({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteChainConfigs[remoteChainSelector]._pool,
            feeToken: feeToken,
            gasLimit: estimateGasLimit(ids.length),
            allowOutOfOrderExecution: true,
            data: data
        });

        emit CrossChainSent(msg.sender, to, ids, s_currentChainSelector, remoteChainSelector);
    }

    function getSupportedChains() external view returns (uint64[] memory chains) {
        uint256[] memory values = s_remoteChainSelectors.values();
        assembly ("memory-safe") {
            chains := values
        }
    }

    function getRemotePools() external view returns (address[] memory pools) {
        uint256[] memory chainSelectors = s_remoteChainSelectors.values();
        pools = new address[](chainSelectors.length);
        for (uint256 i; i < chainSelectors.length; ++i) {
            pools[i] = s_remoteChainConfigs[uint64(chainSelectors[i])]._pool;
        }
    }

    function getFee(IERC20 feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee)
    {
        (fee,) = _getSendDataFee({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteChainConfigs[remoteChainSelector]._pool,
            feeToken: feeToken,
            gasLimit: estimateGasLimit(tokenCount),
            allowOutOfOrderExecution: true,
            data: abi.encode(address(0), address(0), new uint256[](tokenCount))
        });
    }

    function estimateGasLimit(uint256 tokenCount) public view returns (uint256 gasLimit) {
        return s_fixedGas + s_dynamicGas * tokenCount;
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

    function getExternalStorages() external view returns (address[] memory extStorages) {
        return s_extStorages.values();
    }

    function getSourcePool(uint64 remoteChainSelector) external view returns (address poolAddr) {
        return (s_remoteChainConfigs[remoteChainSelector]._pool);
    }

    function _setGasLimitConfig(uint64 fixedGas, uint64 dynamicGas) internal {
        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;

        emit GasLimitConfigUpdated(msg.sender, fixedGas, dynamicGas);
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

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override {
        (address from, address to, uint256[] memory ids) = abi.decode(message.data, (address, address, uint256[]));

        _requireValidLength(ids);
        _requireNonZero(from);
        _requireNonZero(to);

        _releaseOrMint(to, ids);
        _requireDelivered(to, ids);
        _consumeInboundRateLimit(message.sourceChainSelector, ids.length);

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
        IERC721 token = s_token;
        uint256 tokenCount = ids.length;

        for (uint256 i; i < tokenCount; ++i) {
            token.transferFrom(from, address(this), ids[i]);
        }
    }

    function _releaseOrMint(address to, uint256[] memory ids) internal {
        uint256 tokenCount = ids.length;
        address token = address(s_token);
        address[] memory extStorages = s_extStorages.values();
        uint256 extStorageCount = extStorages.length;

        for (uint256 i; i < tokenCount; ++i) {
            uint256 id = ids[i];
            address owned = _tryGetOwnerOf(IERC721(token), id);

            if (s_extStorages.contains(owned) || owned == address(this)) {
                IERC721(token).safeTransferFrom(owned, to, id);
            } else {
                try IERC721Mintable(token).mint(to, id) {}
                catch {
                    if (extStorageCount == 0) revert MintFailed(address(this), id, to);

                    for (uint256 j; j < extStorageCount; ++j) {
                        try IExtStorage(extStorages[i]).mintFor(token, to, id) {
                            break;
                        } catch {
                            if (j == extStorageCount - 1) revert MintFailed(extStorages[i], id, to);
                        }
                    }
                }
            }
        }
    }

    function _requireDelivered(address recipient, uint256[] memory ids) internal view {
        uint256 tokenCount = ids.length;
        IERC721 token = s_token;

        for (uint256 i; i < tokenCount; ++i) {
            if (_tryGetOwnerOf(token, ids[i]) != recipient) revert NFTDeliveryFailed(recipient, ids[i]);
        }
    }

    function _requireValidLength(uint256[] memory ids) internal pure {
        if (ids.length == 0) revert ZeroIdsNotAllowed();
    }

    function _tryGetOwnerOf(IERC721 token, uint256 id) internal view returns (address ownedBy) {
        try token.ownerOf(id) returns (address by) {
            return by;
        } catch {
            // Handle the case where the token does not exist or is not an ERC721
            return address(0);
        }
    }
}
