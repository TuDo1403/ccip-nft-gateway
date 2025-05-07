// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TokenPoolAbstractUpgradeable} from "src/pools/TokenPoolAbstractUpgradeable.sol";
import {ISingleTokenPool} from "src/interfaces/pools/ISingleTokenPool.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

abstract contract SingleTokenPoolUpgradeable is TokenPoolAbstractUpgradeable, ISingleTokenPool {
    uint256[50] private __gap1;

    address internal s_token;
    mapping(uint64 remoteChainSelector => Any2EVMAddress remoteToken) internal s_remoteTokens;

    uint256[50] private __gap2;

    function __SingleTokenPoolUpgradeable_init(
        address owner,
        address token,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        uint64 currentChainSelector
    ) internal onlyInitializing {
        __SingleTokenPoolUpgradeable_init_unchained(token);
        __TokenPoolAbstract_init(owner, fixedGas, dynamicGas, router, currentChainSelector);
    }

    function __SingleTokenPoolUpgradeable_init_unchained(address token) internal onlyInitializing nonZero(token) {
        s_token = token;
    }

    function addRemotePool(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata remotePool,
        Any2EVMAddress calldata remoteToken
    ) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _addRemoteChain(remoteChainSelector, remotePool);
        s_remoteTokens[remoteChainSelector] = remoteToken;
        emit RemotePoolAdded(msg.sender, remoteChainSelector, remotePool, remoteToken);
    }

    function removeRemotePool(uint64 remoteChainSelector) external virtual override onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _removeRemoteChain(remoteChainSelector);
        delete s_remoteTokens[remoteChainSelector];
        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    function getToken() external view returns (address token) {
        return s_token;
    }

    function isSupportedToken(address token) public view virtual override returns (bool yes) {
        return token == address(s_token);
    }

    function getRemotePool(uint64 remoteChainSelector)
        public
        view
        virtual
        override
        returns (Any2EVMAddress memory remotePool)
    {
        return s_remoteChainConfigs[remoteChainSelector]._addr;
    }

    function getRemoteToken(uint64 remoteChainSelector) public view returns (Any2EVMAddress memory remoteToken) {
        return s_remoteTokens[remoteChainSelector];
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
        if (!isSupportedToken(token)) revert OnlyLocalToken(s_token, token);
    }
}
