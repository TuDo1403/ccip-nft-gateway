// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockRmnProxy {
    mapping(bytes16 => bool) public isCursed;

    function setCursed(uint64 chainSelector, bool cursed) external {
        isCursed[bytes16(uint128(chainSelector))] = cursed;
    }
}
