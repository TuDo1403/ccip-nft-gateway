// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IPausable} from "src/interfaces/external/IPausable.sol";

abstract contract PausableExtendedUpgradeable is PausableUpgradeable, AccessControlEnumerableUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256[50] private __gap1;

    address internal s_globalPauser;

    uint256[50] private __gap2;

    function __PausableExtendedUpgradeable_init(address globalPauser) internal onlyInitializing {
        __PausableExtendedUpgradeable_init_unchained(globalPauser);
    }

    function __PausableExtendedUpgradeable_init_unchained(address globalPauser) internal onlyInitializing {
        s_globalPauser = globalPauser;
        _grantRole(PAUSER_ROLE, globalPauser);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getGlobalPauser() external view returns (address) {
        return s_globalPauser;
    }

    function paused() public view virtual override returns (bool) {
        return
            (hasRole(PAUSER_ROLE, s_globalPauser) && IPausable(s_globalPauser).paused()) || PausableUpgradeable.paused();
    }
}
