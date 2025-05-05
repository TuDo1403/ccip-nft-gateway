// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IExtStorage {
    function mintFor(address token, address to, uint256 id) external;
}
