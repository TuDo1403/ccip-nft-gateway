// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";

import {ITokenPoolAbstract} from "src/interfaces/pools/ITokenPoolAbstract.sol";
import {Pool} from "src/libraries/Pool.sol";

abstract contract TokenPoolAbstractUpgradeable is
    AccessControlEnumerableUpgradeable,
    CCIPSenderReceiverUpgradeable,
    ITokenPoolAbstract
{
    bytes32 public constant TOKEN_POOL_OWNER_ROLE = keccak256("TOKEN_POOL_OWNER_ROLE");

    uint256[50] private __gap1;

    uint32 internal s_fixedGas;
    uint32 internal s_dynamicGas;

    uint256[50] private __gap2;

    modifier onlyLocalToken(address token) {
        _requireLocalToken(token);
        _;
    }

    function __TokenPoolAbstract_init(
        address owner,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        uint64 currentChainSelector
    ) internal onlyInitializing {
        __TokenPoolAbstract_init_unchained(owner, fixedGas, dynamicGas);
        __CCIPSenderReceiverUpgradeable_init(router, currentChainSelector);
    }

    function __TokenPoolAbstract_init_unchained(address owner, uint32 fixedGas, uint32 dynamicGas)
        internal
        onlyInitializing
    {
        _grantRole(TOKEN_POOL_OWNER_ROLE, owner);
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external onlyRole(TOKEN_POOL_OWNER_ROLE) {
        _setGasLimitConfig(fixedGas, dynamicGas);
    }

    function getGasLimitConfig() external view returns (uint32 fixedGas, uint32 dynamicGas) {
        return (s_fixedGas, s_dynamicGas);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, CCIPSenderReceiverUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ITokenPoolAbstract).interfaceId || super.supportsInterface(interfaceId);
    }

    function _lockOrBurn(Pool.LockOrBurn memory lockOrBurn) internal virtual;

    function _releaseOrMint(Pool.ReleaseOrMint memory releaseOrMint) internal virtual;

    function _setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) internal {
        s_fixedGas = fixedGas;
        s_dynamicGas = dynamicGas;

        emit GasLimitConfigured(msg.sender, fixedGas, dynamicGas);
    }

    function _requireLocalToken(address token) internal view virtual;
}
