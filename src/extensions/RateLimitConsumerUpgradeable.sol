// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IRateLimitConsumer} from "src/interfaces/extensions/IRateLimitConsumer.sol";

abstract contract RateLimitConsumerUpgradeable is AccessControlEnumerableUpgradeable, IRateLimitConsumer {
    using RateLimiter for RateLimiter.Config;
    using RateLimiter for RateLimiter.TokenBucket;

    bytes32 public constant RATE_LIMITER_ROLE = keccak256("RATE_LIMITER_ROLE");

    uint256[50] private __gap1;

    mapping(uint64 remoteChainSelector => RateLimiter.TokenBucket) private s_outboundConfig;
    mapping(uint64 remoteChainSelector => RateLimiter.TokenBucket) private s_inboundConfig;

    uint256[50] private __gap2;

    function __RateLimitConsumer_init(address rateLimiter) internal onlyInitializing {
        __RateLimitConsumer_init_unchained(rateLimiter);
    }

    function __RateLimitConsumer_init_unchained(address rateLimiter) internal onlyInitializing {
        _grantRole(RATE_LIMITER_ROLE, rateLimiter);
    }

    /**
     * @notice Sets the chain rate limiter config.
     * @param remoteChainSelector The remote chain selector for which the rate limits apply.
     * @param outboundConfig The new outbound rate limiter config, meaning the onRamp rate limits for the given chain.
     * @param inboundConfig The new inbound rate limiter config, meaning the offRamp rate limits for the given chain.
     */
    function setChainRateLimiterConfig(
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) external onlyRole(RATE_LIMITER_ROLE) {
        _setRateLimitConfig(remoteChainSelector, outboundConfig, inboundConfig);
    }

    /**
     * @notice Gets the token bucket with its values for the block it was requested at.
     * @return state The token bucket.
     */
    function getCurrentOutboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory state)
    {
        return s_outboundConfig[remoteChainSelector]._currentTokenBucketState();
    }

    /**
     * @notice Gets the token bucket with its values for the block it was requested at.
     * @return state The token bucket.
     */
    function getCurrentInboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory state)
    {
        return s_inboundConfig[remoteChainSelector]._currentTokenBucketState();
    }

    /**
     * @notice Consumes outbound rate limiting capacity in this pool
     */
    function _consumeOutboundRateLimit(uint64 remoteChainSelector, address token, uint256 amount) internal {
        s_outboundConfig[remoteChainSelector]._consume(amount, token);
    }

    /**
     * @notice Consumes inbound rate limiting capacity in this pool
     */
    function _consumeInboundRateLimit(uint64 remoteChainSelector, address token, uint256 amount) internal {
        s_inboundConfig[remoteChainSelector]._consume(amount, token);
    }

    function _setRateLimitConfig(
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) internal {
        outboundConfig._validateTokenBucketConfig({mustBeDisabled: false});
        s_outboundConfig[remoteChainSelector]._setTokenBucketConfig(outboundConfig);

        inboundConfig._validateTokenBucketConfig({mustBeDisabled: false});
        s_inboundConfig[remoteChainSelector]._setTokenBucketConfig(inboundConfig);

        emit RateLimitConfigured(msg.sender, remoteChainSelector, outboundConfig, inboundConfig);
    }
}
