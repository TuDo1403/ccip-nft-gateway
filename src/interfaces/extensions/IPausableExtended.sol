// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPausableExtended {
    function PAUSER_ROLE() external view returns (bytes32);

    function getGlobalPauser() external view returns (address globalPauser);

    function pause() external;

    function unpause() external;
}
