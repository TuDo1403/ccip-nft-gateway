// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";
import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";

abstract contract TokenPoolUpgradeable is
    AccessControlEnumerableUpgradeable,
    CCIPSenderReceiverUpgradeable,
    ITokenPool
{
    bytes32 public constant TOKEN_POOL_OWNER = keccak256("TOKEN_POOL_OWNER");

    uint256[50] private __gap1;

    address internal s_token;
    uint32 internal s_fixedGas;
    uint32 internal s_dynamicGas;
    mapping(uint64 remoteChainSelector => address remoteToken) internal s_remoteTokens;

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
        _grantRole(TOKEN_POOL_OWNER, owner);
        __TokenPoolUpgradeable_init_unchained(token, fixedGas, dynamicGas);
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

    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external onlyRole(TOKEN_POOL_OWNER) {
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function addRemotePool(uint64 remoteChainSelector, address pool, address token)
        external
        onlyRole(TOKEN_POOL_OWNER)
    {
        _addRemoteChain(remoteChainSelector, abi.encode(pool));
        s_remoteTokens[remoteChainSelector] = token;
        emit RemotePoolAdded(msg.sender, remoteChainSelector, pool, token);
    }

    function removeRemotePool(uint64 remoteChainSelector) external onlyRole(TOKEN_POOL_OWNER) {
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

    function getRemotePool(uint64 remoteChainSelector) public view returns (address addr) {
        return abi.decode(s_remoteChainConfigs[remoteChainSelector]._addr, (address));
    }

    function getRemoteToken(uint64 remoteChainSelector) public view returns (address token) {
        return s_remoteTokens[remoteChainSelector];
    }

    function getRemotePools() external view returns (uint64[] memory remoteChainSelectors, address[] memory pools) {
        remoteChainSelectors = getSupportedChains();
        uint256 length = remoteChainSelectors.length;
        pools = new address[](length);

        for (uint256 i; i < length; ++i) {
            pools[i] = abi.decode(s_remoteChainConfigs[remoteChainSelectors[i]]._addr, (address));
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
        if (token != s_token) revert OnlyLocalToken(s_token, token);
    }
}
