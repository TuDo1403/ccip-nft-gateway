// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";

import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";
import {Pool} from "src/libraries/Pool.sol";

abstract contract TokenPool is AccessControlEnumerableUpgradeable, CCIPSenderReceiverUpgradeable, ITokenPool {
    bytes32 public constant TOKEN_POOL_OWNER_ROLE = keccak256("TOKEN_POOL_OWNER_ROLE");

    /// @dev Gap for future upgrades
    uint256[50] private __gap1;

    /// @dev Fixed gas for cross-chain message.
    uint32 private s_fixedGas;
    /// @dev Dynamic gas for cross-chain message. Multiplied by the number of tokens.
    uint32 private s_dynamicGas;

    /// @dev Gap for future upgrades
    uint256[50] private __gap2;

    modifier onlyLocalToken(address localToken) {
        _requireLocalToken(localToken);
        _;
    }

    function __TokenPool_init(
        address owner,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        uint64 currentChainSelector
    ) internal onlyInitializing {
        __TokenPool_init_unchained(owner, fixedGas, dynamicGas);
        __CCIPSenderReceiver_init(router, currentChainSelector);
    }

    function __TokenPool_init_unchained(address owner, uint32 fixedGas, uint32 dynamicGas) internal onlyInitializing {
        _grantRole(TOKEN_POOL_OWNER_ROLE, owner);
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function addRemotePool(uint64 remoteChainSelector, address remotePool) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _addRemoteChain(remoteChainSelector, remotePool);
        emit RemotePoolAdded(msg.sender, remoteChainSelector, remotePool);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function removeRemotePool(uint64 remoteChainSelector) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _removeRemoteChain(remoteChainSelector);
        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken)
        external
        onlyRole(TOKEN_POOL_OWNER_ROLE)
        nonZero(localToken)
        onlyEnabledChain(remoteChainSelector)
    {
        _requireNonZero(remoteToken);
        _mapRemoteToken(localToken, remoteChainSelector, remoteToken);
        emit RemoteTokenMapped(msg.sender, remoteChainSelector, localToken, remoteToken);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function unmapRemoteToken(address localToken, uint64 remoteChainSelector)
        external
        onlyRole(TOKEN_POOL_OWNER_ROLE)
        onlyEnabledChain(remoteChainSelector)
    {
        _unmapRemoteToken(localToken, remoteChainSelector);
        emit RemoteTokenUnmapped(msg.sender, remoteChainSelector, localToken);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function getRemotePool(uint64 remoteChainSelector) public view returns (address remotePool) {
        return _getRemoteSender(remoteChainSelector);
    }

    /**
     * @inheritdoc ITokenPool
     */
    function getRemotePools()
        external
        view
        returns (uint64[] memory remoteChainSelectors, address[] memory remotePools)
    {
        remoteChainSelectors = getSupportedChains();
        uint256 length = remoteChainSelectors.length;
        remotePools = new address[](length);

        for (uint256 i; i < length; ++i) {
            remotePools[i] = getRemotePool(remoteChainSelectors[i]);
        }
    }

    /**
     * @inheritdoc ITokenPool
     */
    function getGasLimitConfig() public view returns (uint32 fixedGas, uint32 dynamicGas) {
        return (s_fixedGas, s_dynamicGas);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, CCIPSenderReceiverUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ITypeAndVersion).interfaceId || interfaceId == type(ITokenPool).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Virtual function to be implemented by derived contracts to handle the lock or burn operation.
     */
    function _lockOrBurn(Pool.LockOrBurn memory lockOrBurn) internal virtual;

    /**
     * @dev Virtual function to be implemented by derived contracts to handle the release or mint operation.
     */
    function _releaseOrMint(Pool.ReleaseOrMint memory releaseOrMint) internal virtual;

    /**
     * @dev Virtual function to be implemented by derived contracts to handle the mapping of remote tokens.
     */
    function _mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken) internal virtual;

    /**
     * @dev Virtual function to be implemented by derived contracts to handle the unmapping of remote tokens.
     */
    function _unmapRemoteToken(address localToken, uint64 remoteChainSelector) internal virtual;

    /**
     * @dev Internal function to require that the local token is supported by the pool.
     */
    function _requireLocalToken(address localToken) internal view virtual;

    /**
     * @dev Internal function to set the gas limit configuration.
     * Requires that both fixedGas and dynamicGas are non-zero.
     * @param fixedGas The fixed gas limit.
     * @param dynamicGas The dynamic gas limit.
     */
    function _setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) internal {
        _requireNonZero(fixedGas);
        _requireNonZero(dynamicGas);

        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;

        emit GasLimitConfigured(msg.sender, fixedGas, dynamicGas);
    }
}
