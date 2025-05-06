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
}
