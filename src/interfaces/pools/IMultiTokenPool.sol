// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMultiTokenPool {
    error OnlyLocalToken();
    error LengthMismatch(uint256 expected, uint256 actual);
    error TokenAlreadyAdded(address localToken);
    error TokenNotAdded(address localToken);

    function getSupportedTokensForChain(uint64 remoteChainSelector)
        external
        view
        returns (address[] memory localTokens);

    function getTokens() external view returns (address[] memory localTokens);

    function getRemoteToken(address localToken, uint64 remoteChainSelector)
        external
        view
        returns (address remoteToken);
}
