// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPool} from "src/pools/TokenPool.sol";
import {IMultiTokenPool} from "src/interfaces/pools/IMultiTokenPool.sol";

abstract contract MultiTokenPool is TokenPool, IMultiTokenPool {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256[50] private __gap1;

    EnumerableSet.AddressSet private s_localTokens;
    mapping(address local => mapping(uint64 remoteChainSelector => address)) private s_remoteTokens;

    uint256[50] private __gap2;

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IMultiTokenPool).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Get all supported local localTokens that have a remote mapping for the given chain
    function getSupportedTokensForChain(uint64 remoteChainSelector)
        external
        view
        returns (address[] memory localTokens)
    {
        uint256 tokenCount = s_localTokens.length();
        localTokens = new address[](tokenCount);
        uint256 count;

        for (uint256 i; i < tokenCount; ++i) {
            address localToken = s_localTokens.at(i);
            if (s_remoteTokens[localToken][remoteChainSelector] != address(0)) {
                localTokens[count++] = localToken;
            }
        }

        assembly ("memory-safe") {
            mstore(localTokens, count)
        }
    }

    function getTokens() public view returns (address[] memory localTokens) {
        address[] memory tokenSet = s_localTokens.values();
        uint256 tokenCount = tokenSet.length;

        localTokens = new address[](tokenCount);
        uint256 count;
        for (uint256 i; i < tokenCount; ++i) {
            if (isSupportedToken(tokenSet[i])) {
                localTokens[count++] = tokenSet[i];
            }
        }

        assembly ("memory-safe") {
            mstore(localTokens, count)
        }
    }

    function isSupportedToken(address localToken) public view virtual override returns (bool yes) {
        // Short circuit if the token is not in the set
        if (!s_localTokens.contains(localToken)) return false;

        // Check if the token has a mapping on any enabled chain
        uint64[] memory supportedChains = getSupportedChains();
        uint256 chainCount = supportedChains.length;

        for (uint256 i; i < chainCount; ++i) {
            if (getRemoteToken(localToken, supportedChains[i]) != address(0)) {
                return true;
            }
        }

        return false;
    }

    function getRemoteToken(address localToken, uint64 remoteChainSelector) public view returns (address remoteToken) {
        if (!isSupportedChain(remoteChainSelector)) return address(0);
        return s_remoteTokens[localToken][remoteChainSelector];
    }

    function _mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken)
        internal
        virtual
        override
    {
        s_localTokens.add(localToken);
        s_remoteTokens[localToken][remoteChainSelector] = remoteToken;
    }

    function _unmapRemoteToken(address localToken, uint64 remoteChainSelector) internal virtual override {
        delete s_remoteTokens[localToken][remoteChainSelector];

        // If the token is not mapped to any other chain, remove it from the set
        if (!isSupportedToken(localToken)) s_localTokens.remove(localToken);
    }

    function _requireLocalToken(address localToken) internal view virtual override {
        if (!isSupportedToken(localToken)) revert OnlyLocalToken();
    }

    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }
}
