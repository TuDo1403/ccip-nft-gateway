// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

interface IRateLimitConsumer {
    event RateLimitConfigured(
        address indexed by,
        uint64 indexed chainSelector,
        RateLimiter.Config outboundConfig,
        RateLimiter.Config inboundConfig
    );

    function RATE_LIMITER_ROLE() external view returns (bytes32);

    function setChainRateLimiterConfig(
        uint64 remoteChainSelector,
        RateLimiter.Config memory outboundConfig,
        RateLimiter.Config memory inboundConfig
    ) external;

    function getCurrentOutboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory state);

    function getCurrentInboundRateLimiterState(uint64 remoteChainSelector)
        external
        view
        returns (RateLimiter.TokenBucket memory state);
}
