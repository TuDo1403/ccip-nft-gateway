// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TokenPool} from "src/pools/TokenPool.sol";
import {ISingleTokenPool} from "src/interfaces/pools/ISingleTokenPool.sol";

abstract contract SingleTokenPool is TokenPool, ISingleTokenPool {
    uint256[50] private __gap1;

    address private s_localToken;
    mapping(uint64 remoteChainSelector => address) private s_remoteTokens;

    uint256[50] private __gap2;

    function getToken() public view returns (address localToken) {
        return s_localToken;
    }

    function isSupportedToken(address localToken) public view virtual override returns (bool yes) {
        return localToken == s_localToken;
    }

    function getRemoteToken(uint64 remoteChainSelector) public view returns (address remoteToken) {
        return s_remoteTokens[remoteChainSelector];
    }

    function _mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken)
        internal
        virtual
        override
    {
        s_localToken = localToken;
        s_remoteTokens[remoteChainSelector] = remoteToken;
    }

    function _unmapRemoteToken(address, /* localToken */ uint64 remoteChainSelector) internal virtual override {
        delete s_remoteTokens[remoteChainSelector];
    }

    function _requireLocalToken(address localToken) internal view virtual override {
        if (!isSupportedToken(localToken)) revert OnlyLocalToken(s_localToken, localToken);
    }
}
