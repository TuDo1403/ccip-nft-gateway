// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPoolAbstractUpgradeable} from "src/pools/TokenPoolAbstractUpgradeable.sol";
import {IMultiTokensPool} from "src/interfaces/pools/IMultiTokensPool.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

abstract contract MultiTokensPoolUpgradeable is TokenPoolAbstractUpgradeable, IMultiTokensPool {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256[50] private __gap1;

    EnumerableSet.AddressSet internal s_supportedTokens;
    mapping(uint64 remoteChainSelector => mapping(address local => Any2EVMAddress remote)) internal s_remoteTokens;

    uint256[50] private __gap2;

    function addRemotePool(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata remotePool,
        Any2EVMAddress[] calldata remoteTokens,
        address[] calldata localTokens
    ) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _requireEqualLength(remoteTokens.length, localTokens.length);
        _addRemoteChain(remoteChainSelector, remotePool);

        uint256 length = remoteTokens.length;
        for (uint256 i; i < length; ++i) {
            s_remoteTokens[remoteChainSelector][localTokens[i]] = remoteTokens[i];
        }

        emit RemotePoolAdded(msg.sender, remoteChainSelector, remotePool, remoteTokens, localTokens);
    }

    function removeRemotePool(uint64 remoteChainSelector) external virtual override onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _removeRemoteChain(remoteChainSelector);

        address[] memory localTokens = getTokens();
        uint256 length = localTokens.length;
        for (uint256 i; i < length; ++i) {
            delete s_remoteTokens[remoteChainSelector][localTokens[i]];
        }

        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    function getTokens() public view returns (address[] memory tokens) {
        return s_supportedTokens.values();
    }

    function isSupportedToken(address token) public view virtual override returns (bool yes) {
        return s_supportedTokens.contains(token);
    }

    function getRemotePool(uint64 remoteChainSelector)
        public
        view
        virtual
        override
        returns (Any2EVMAddress memory pool)
    {
        return s_remoteChainConfigs[remoteChainSelector]._addr;
    }

    function getRemoteToken(uint64 remoteChainSelector, address localToken)
        public
        view
        returns (Any2EVMAddress memory remoteToken)
    {
        return s_remoteTokens[remoteChainSelector][localToken];
    }

    function getRemotePools() external view virtual override returns (RemoteChainConfig[] memory pools) {
        uint64[] memory remoteChainSelectors = getSupportedChains();
        uint256 length = remoteChainSelectors.length;
        pools = new RemoteChainConfig[](length);

        for (uint256 i; i < length; ++i) {
            pools[i] = s_remoteChainConfigs[remoteChainSelectors[i]];
        }
    }

    function _requireLocalToken(address token) internal view virtual override {
        if (!isSupportedToken(token)) revert OnlyLocalToken();
    }

    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }
}
