// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ITokenAdminRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/ITokenAdminRegistry.sol";

interface ITokenAdminRegistryExtended is ITokenAdminRegistry {
    struct TokenConfig {
        address administrator; // the current administrator of the token
        address pendingAdministrator; // the address that is pending to become the new administrator
        address tokenPool; // the token pool for this token. Can be address(0) if not deployed or not configured.
    }

    /// @notice Returns the configuration for a token.
    /// @param token The token to get the configuration for.
    /// @return config The configuration for the token.
    function getTokenConfig(address token) external view returns (TokenConfig memory);
}
