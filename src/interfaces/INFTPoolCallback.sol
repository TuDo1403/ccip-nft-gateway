// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INFTPoolCallback {
    function initialize(
        address initialOwner,
        address router,
        address rmnProxy,
        address token,
        uint64 currentChainSelector,
        uint32 fixedGas,
        uint32 dynamicGas
    ) external;

    function addRemotePool(uint64 remoteChainSelector, address remotePool, address remoteToken) external;
}
