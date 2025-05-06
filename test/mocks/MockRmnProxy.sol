// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockRmnProxy {
    mapping(uint64 => bool) public isCursed;

    function setCursed(uint64 chainSelector, bool cursed) external {
        isCursed[chainSelector] = cursed;
    }
}
