// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";

interface IEVM2EVMOnRamp {
    /// @dev Struct to contains the dynamic configuration
    struct DynamicConfig {
        address router; // ──────────────────────────╮ Router address
        uint16 maxNumberOfTokensPerMsg; //           │ Maximum number of distinct ERC20 token transferred per message
        uint32 destGasOverhead; //                   │ Gas charged on top of the gasLimit to cover destination chain costs
        uint16 destGasPerPayloadByte; //             │ Destination chain gas charged for passing each byte of `data` payload to receiver
        uint32 destDataAvailabilityOverheadGas; // ──╯ Extra data availability gas charged on top of the message, e.g. for OCR
        uint16 destGasPerDataAvailabilityByte; // ───╮ Amount of gas to charge per byte of message data that needs availability
        uint16 destDataAvailabilityMultiplierBps; // │ Multiplier for data availability gas, multiples of bps, or 0.0001
        IPriceRegistry priceRegistry; //                    │ Price registry address
        uint32 maxDataBytes; //                      │ Maximum payload data size in bytes
        uint32 maxPerMsgGasLimit; // ────────────────╯ Maximum gas limit for messages targeting EVMs
        //                                           │
        // The following three properties are defaults, they can be overridden by setting the TokenTransferFeeConfig for a token
        uint16 defaultTokenFeeUSDCents; // ──────────╮ Default token fee charged per token transfer
        uint32 defaultTokenDestGasOverhead; //       │ Default gas charged to execute the token transfer on the destination chain
        bool enforceOutOfOrder; // ──────────────────╯ Whether to enforce the allowOutOfOrderExecution extraArg value to be true.
    }

    function getDynamicConfig() external view returns (DynamicConfig memory dynamicConfig);
}
