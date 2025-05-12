// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMultiTokenPool {
    /// @dev Revert if the given token is not supported by the pool.
    error OnlyLocalToken();
    /// @dev Revert if array lengths do not match.
    error LengthMismatch(uint256 expected, uint256 actual);
    /// @dev Revert if the local token does not have remote token mapped given the remote chain.
    error TokenNotMapped(address localToken, uint64 remoteChainSelector);
    /// @dev Revert if the local token already has remote token mapped given the remote chain.
    error TokenAlreadyMapped(address localToken, address remoteToken);

    /**
     * @dev Get all supported token pair for a given chain.
     * Requirements:
     * - The remote chain is be enabled by the pool.
     * @param remoteChainSelector The selector of the remote chain.
     * @return localTokens The list of local tokens supported by the pool.
     * @return remoteTokens The list of remote tokens supported by the pool.
     */
    function getSupportedTokensForChain(uint64 remoteChainSelector)
        external
        view
        returns (address[] memory localTokens, address[] memory remoteTokens);

    /**
     * @dev Get all supported local tokens.
     * @return localTokens The list of local tokens supported by the pool.
     */
    function getTokens() external view returns (address[] memory localTokens);

    /**
     * @dev Get remote token address for a given local token and remote chain.
     * Requirements:
     * - The local token must be supported by the pool.
     * - The remote chain must be enabled by the pool.
     */
    function getRemoteToken(address localToken, uint64 remoteChainSelector)
        external
        view
        returns (address remoteToken);
}
