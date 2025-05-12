// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPool} from "src/pools/TokenPool.sol";
import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";
import {IMultiTokenPool} from "src/interfaces/pools/IMultiTokenPool.sol";

abstract contract MultiTokenPool is TokenPool, IMultiTokenPool {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Gap for future upgrades
    uint256[50] private __gap1;

    /// @dev The set of local tokens.
    EnumerableSet.AddressSet private s_localTokens;
    /// @dev The mapping of local token address => remote chain selector => remote token address.
    mapping(address local => mapping(uint64 remoteChainSelector => address)) private s_remoteTokens;

    /// @dev Gap for future upgrades
    uint256[50] private __gap2;

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IMultiTokenPool).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IMultiTokenPool
     */
    function getSupportedTokensForChain(uint64 remoteChainSelector)
        public
        view
        returns (address[] memory localTokens, address[] memory remoteTokens)
    {
        if (!isSupportedChain(remoteChainSelector)) return (new address[](0), new address[](0));

        uint256 tokenCount = s_localTokens.length();
        localTokens = new address[](tokenCount);
        remoteTokens = new address[](tokenCount);
        uint256 count;

        for (uint256 i; i < tokenCount; ++i) {
            address localToken = s_localTokens.at(i);
            address remoteToken = s_remoteTokens[localToken][remoteChainSelector];
            if (remoteToken != address(0)) {
                localTokens[count] = localToken;
                remoteTokens[count] = remoteToken;
                ++count;
            }
        }

        assembly ("memory-safe") {
            mstore(localTokens, count)
            mstore(remoteTokens, count)
        }
    }

    /**
     * @inheritdoc IMultiTokenPool
     */
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

    /**
     * @inheritdoc ITokenPool
     */
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

    /**
     * @inheritdoc IMultiTokenPool
     */
    function getRemoteToken(address localToken, uint64 remoteChainSelector) public view returns (address remoteToken) {
        if (!isSupportedChain(remoteChainSelector)) return address(0);
        return s_remoteTokens[localToken][remoteChainSelector];
    }

    /**
     * @dev See {ITokenPool-mapRemoteToken}.
     */
    function _mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken)
        internal
        virtual
        override
    {
        // Check if the remote token is already mapped to the local token
        (address[] memory existingLocalTokens, address[] memory existingRemoteTokens) =
            getSupportedTokensForChain(remoteChainSelector);
        if (existingRemoteTokens.length > 0) {
            for (uint256 i; i < existingRemoteTokens.length; ++i) {
                if (existingRemoteTokens[i] == remoteToken) {
                    revert TokenAlreadyMapped(existingLocalTokens[i], remoteToken);
                }
            }
        }

        s_localTokens.add(localToken);
        s_remoteTokens[localToken][remoteChainSelector] = remoteToken;
    }

    /**
     * @dev See {ITokenPool-unmapRemoteToken}.
     */
    function _unmapRemoteToken(address localToken, uint64 remoteChainSelector) internal virtual override {
        address remoteToken = s_remoteTokens[localToken][remoteChainSelector];
        if (remoteToken == address(0)) revert TokenNotMapped(localToken, remoteChainSelector);
        delete s_remoteTokens[localToken][remoteChainSelector];

        // If the token is not mapped to any other chain, remove it from the set
        if (!isSupportedToken(localToken)) s_localTokens.remove(localToken);
    }
    
    /**
     * @dev See {TokenPool-requireLocalToken}.
     */
    function _requireLocalToken(address localToken) internal view virtual override {
        if (!isSupportedToken(localToken)) revert OnlyLocalToken();
    }

    /**
     * @dev Checks if the two arrays have the same length.
     */
    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }
}
