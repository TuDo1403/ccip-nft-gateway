// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleTokenPool {
    /// @dev Revert if the given token is not supported by the pool.
    error OnlyLocalToken(address expected, address actual);

    /**
     * @dev Get supported local token.
     */
    function getToken() external view returns (address localToken);

    /**
     * @dev Get remote token address for a given local token and remote chain.
     * Requirements:
     * - The remote chain must be enabled by the pool.
     */
    function getRemoteToken(uint64 remoteChainSelector) external view returns (address remoteToken);
}
