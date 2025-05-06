// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {PausableExtendedUpgradeable} from "src/extensions/PausableExtendedUpgradeable.sol";
import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";
import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

abstract contract TokenPoolUpgradeable is
    AccessControlEnumerableUpgradeable,
    PausableExtendedUpgradeable,
    CCIPSenderReceiverUpgradeable,
    ITokenPool
{
    bytes32 public constant TOKEN_POOL_OWNER_ROLE = keccak256("TOKEN_POOL_OWNER_ROLE");

    uint256[50] private __gap1;

    address internal s_token;
    uint32 internal s_fixedGas;
    uint32 internal s_dynamicGas;
    mapping(uint64 remoteChainSelector => Any2EVMAddress remoteToken) internal s_remoteTokens;

    uint256[50] private __gap2;

    modifier onlyLocalToken(address token) {
        _requireLocalToken(token);
        _;
    }

    function __TokenPoolUpgradeable_init(
        address owner,
        address token,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        address rmnProxy,
        uint64 currentChainSelector
    ) internal onlyInitializing {
        _grantRole(TOKEN_POOL_OWNER_ROLE, owner);
        __TokenPoolUpgradeable_init_unchained(token, fixedGas, dynamicGas);
        __PausableExtendedUpgradeable_init(owner);
        __CCIPSenderReceiverUpgradeable_init(router, rmnProxy, currentChainSelector);
    }

    function __TokenPoolUpgradeable_init_unchained(address token, uint32 fixedGas, uint32 dynamicGas)
        internal
        onlyInitializing
        nonZero(token)
    {
        s_token = token;
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function addRemotePool(uint64 remoteChainSelector, Any2EVMAddress calldata pool, Any2EVMAddress calldata token)
        external
        onlyRole(TOKEN_POOL_OWNER_ROLE)
    {
        _addRemoteChain(remoteChainSelector, pool);
        s_remoteTokens[remoteChainSelector] = token;
        emit RemotePoolAdded(msg.sender, remoteChainSelector, pool, token);
    }

    function removeRemotePool(uint64 remoteChainSelector) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _removeRemoteChain(remoteChainSelector);
        delete s_remoteTokens[remoteChainSelector];
        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, CCIPSenderReceiverUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ITokenPool).interfaceId || super.supportsInterface(interfaceId);
    }

    function getGasLimitConfig() external view returns (uint32 fixedGas, uint32 dynamicGas) {
        return (s_fixedGas, s_dynamicGas);
    }

    function getToken() external view returns (address token) {
        return s_token;
    }

    function isSupportedToken(address token) public view returns (bool yes) {
        return token == address(s_token);
    }

    function getRemotePool(uint64 remoteChainSelector) public view returns (Any2EVMAddress memory pool) {
        return s_remoteChainConfigs[remoteChainSelector]._addr;
    }

    function getRemoteToken(uint64 remoteChainSelector) public view returns (Any2EVMAddress memory token) {
        return s_remoteTokens[remoteChainSelector];
    }

    function getRemotePools() external view returns (RemoteChainConfig[] memory pools) {
        uint64[] memory remoteChainSelectors = getSupportedChains();
        uint256 length = remoteChainSelectors.length;
        pools = new RemoteChainConfig[](length);

        for (uint256 i; i < length; ++i) {
            pools[i] = s_remoteChainConfigs[remoteChainSelectors[i]];
        }
    }

    function _lockOrBurn(LockOrBurn memory lockOrBurn) internal virtual;

    function _releaseOrMint(ReleaseOrMint memory releaseOrMint) internal virtual;

    function _setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) internal {
        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;

        emit GasLimitConfigured(msg.sender, fixedGas, dynamicGas);
    }

    function _requireLocalToken(address token) internal view {
        if (!isSupportedToken(token)) revert OnlyLocalToken(s_token, token);
    }
}
