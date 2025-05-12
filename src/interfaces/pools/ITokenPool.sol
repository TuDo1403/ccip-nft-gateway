// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";

interface ITokenPool is ITypeAndVersion {
    /// @dev emit when gas config for cross-chain message is set.
    event GasLimitConfigured(address indexed by, uint32 fixedGas, uint32 dynamicGas);
    /// @dev emit when remote pool is added.
    event RemotePoolAdded(address indexed by, uint64 indexed remoteChainSelector, address indexed remotePool);
    /// @dev emit when remote pool is removed.
    event RemotePoolRemoved(address indexed by, uint64 indexed remoteChainSelector);
    /// @dev emit when remote token is mapped.
    event RemoteTokenMapped(
        address indexed by, uint64 indexed remoteChainSelector, address indexed localToken, address remoteToken
    );
    /// @dev emit when remote token is unmapped.
    event RemoteTokenUnmapped(address indexed by, uint64 indexed remoteChainSelector, address indexed localToken);

    /**
     * @dev Token pool owner role.
     * Value is equal to keccak256("TOKEN_POOL_OWNER_ROLE").
     */
    function TOKEN_POOL_OWNER_ROLE() external view returns (bytes32);

    /**
     * @dev Enabled `remotePool` to interact with this pool.
     * Requirements:
     * - `remotePool` is not null.
     * - `remoteChainSelector` is not null.
     * - `remoteChainSelector` != `currentChainSelector`.
     * - Caller must have `TOKEN_POOL_OWNER_ROLE`.
     * - `remoteChainSelector` must be supported by CCIP router.
     */
    function addRemotePool(uint64 remoteChainSelector, address remotePool) external;

    /**
     * @dev Disable `remotePool` to interact with this pool.
     * Requirements:
     * - `remoteChainSelector` is not null.
     * - `remoteChainSelector` != `currentChainSelector`.
     * - Caller must have `TOKEN_POOL_OWNER_ROLE`.
     * - Remote pool must be added before.
     *
    * Removing a remote pool does not delete the token mappings for the specified remote chain.
    * However, all tokens mapped to the removed remote pool will be deactivated.
     */
    function removeRemotePool(uint64 remoteChainSelector) external;

    /**
     * @dev Map local token to remote token for a given remote chain.
     * Requirements:
     * - `localToken` is not null.
     * - `remoteChainSelector` must be enabled.
     * - `remoteToken` is not null.
     * - Caller must have `TOKEN_POOL_OWNER_ROLE`.
     */
    function mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken) external;

    /**
     * @dev Unmap local token to remote token for a given remote chain.
     * Requirements:
     * - `localToken` must be added before.
     * - `remoteChainSelector` must be enabled.
     * - Caller must have `TOKEN_POOL_OWNER_ROLE`.
    * - If `remoteChainSelector` is not enabled in this pool or no remote token is mapped to `localToken`, `localToken` will be removed from the set.
     */
    function unmapRemoteToken(address localToken, uint64 remoteChainSelector) external;

    /**
     * @dev Set gas limit config for cross-chain message.
     * Requirements:
     * - `fixedGas` is not null.
     * - `dynamicGas` is not null.
     * - Caller must have `TOKEN_POOL_OWNER_ROLE`.
     */
    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external;

    /**
     * @dev Get all supported chain selectors along with their remote pools pair for this pool/
     * @return remoteChainSelectors The list of remote chain selectors.
     * @return remotePools The list of enabled sender pools for the given remote chain.
     */
    function getRemotePools()
        external
        view
        returns (uint64[] memory remoteChainSelectors, address[] memory remotePools);

    /**
     * @dev Get remote token address for a given local token and remote chain.
     * Returns zero address if the token is not mapped or `remoteChainSelector` is disabled.
     */
    function getRemotePool(uint64 remoteChainSelector) external view returns (address remotePool);

    /**
     * @dev Returns whether the token is supported by the pool.
     */
    function isSupportedToken(address token) external view returns (bool yes);

    /**
     * @dev Get gas limit config for cross-chain message.
     * @return fixedGas The fixed gas limit for cross-chain message.
     * @return dynamicGas The dynamic gas use for multiply with calldata size or costs based by user inputs.
     */
    function getGasLimitConfig() external view returns (uint32 fixedGas, uint32 dynamicGas);
}
