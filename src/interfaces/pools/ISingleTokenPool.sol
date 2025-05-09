// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleTokenPool {
    error OnlyLocalToken(address expected, address actual);

    function getToken() external view returns (address localToken);

    function getRemoteToken(uint64 remoteChainSelector) external view returns (address remoteToken);
}
