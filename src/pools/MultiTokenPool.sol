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
        return s_localTokens.values();
    }

    function isSupportedToken(address localToken) public view virtual override returns (bool yes) {
        return s_localTokens.contains(localToken);
    }

    function getRemoteToken(address localToken, uint64 remoteChainSelector) public view returns (address remoteToken) {
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

        address[] memory localTokens = getTokens();
        uint256 tokenCount = localTokens.length;

        // Prune any localTokens that no longer have mappings on any enabled chain
        uint64[] memory chains = getSupportedChains();
        uint256 chainCount = chains.length;

        for (uint256 i; i < tokenCount; ++i) {
            bool hasMapping = false;
            for (uint256 j; j < chainCount; ++j) {
                if (s_remoteTokens[localTokens[i]][chains[j]] != address(0)) {
                    hasMapping = true;
                    break;
                }
            }
            if (!hasMapping) {
                s_localTokens.remove(localTokens[i]);
            }
        }
    }

    function _requireLocalToken(address localToken) internal view virtual override {
        if (!isSupportedToken(localToken)) revert OnlyLocalToken();
    }

    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }
}
