// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TokenPool} from "src/pools/TokenPool.sol";
import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";
import {ISingleTokenPool} from "src/interfaces/pools/ISingleTokenPool.sol";

abstract contract SingleTokenPool is TokenPool, ISingleTokenPool {
    /// @dev Gap for future upgrades
    uint256[50] private __gap1;

    /// @dev The local token address.
    address private s_localToken;
    /// @dev The mapping of remote chain selector => remote token address.
    mapping(uint64 remoteChainSelector => address) private s_remoteTokens;

    /// @dev Gap for future upgrades
    uint256[50] private __gap2;

    /**
     * @inheritdoc ISingleTokenPool
     */
    function getToken() public view returns (address localToken) {
        return s_localToken;
    }

    /**
     * @inheritdoc ITokenPool
     */
    function isSupportedToken(address localToken) public view virtual override returns (bool yes) {
        return localToken == s_localToken;
    }

    /**
     * @inheritdoc ISingleTokenPool
     */
    function getRemoteToken(uint64 remoteChainSelector) public view returns (address remoteToken) {
        return s_remoteTokens[remoteChainSelector];
    }

    /**
     * @dev See {ITokenPool-mapRemoteToken}.
     */
    function _mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken)
        internal
        virtual
        override
    {
        s_localToken = localToken;
        s_remoteTokens[remoteChainSelector] = remoteToken;
    }

    /**
     * @dev See {ITokenPool-unmapRemoteToken}.
     */
    function _unmapRemoteToken(address, /* localToken */ uint64 remoteChainSelector) internal virtual override {
        delete s_remoteTokens[remoteChainSelector];
    }

    /**
     * @dev See {TokenPool-unmapRemoteToken}.
     */
    function _requireLocalToken(address localToken) internal view virtual override {
        if (!isSupportedToken(localToken)) revert OnlyLocalToken(s_localToken, localToken);
    }
}
