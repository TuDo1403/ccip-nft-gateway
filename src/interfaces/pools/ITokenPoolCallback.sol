// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenPoolCallback {
    function initialize(
        address admin,
        address token,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        address rmnProxy,
        uint64 currentChainSelector
    ) external;

    function addRemotePool(uint64 remoteChainSelector, address remotePool, address token) external;
}
